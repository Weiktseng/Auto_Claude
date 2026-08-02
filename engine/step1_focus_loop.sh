#!/bin/bash
#
# Auto_Claude Stage 1 — Focus Loop (Dev ↔ dumb NLP Trigger)
#
# Purpose:
#   Keep Dev's context window on one thing: finishing every item in phase_plan.md.
#   The "other AI" is NOT a reviewer. It's a bash function that returns a canned
#   "繼續 / 好 / 下一項" string. Zero tokens, zero critique, zero interruption.
#
# Single-side stop: only Dev can end Stage 1 by emitting <!JOB_STOP_NOTHINGS_CAN_DO!>
# (when every phase_plan item is checked). Trigger never signals stop.
#
# Flow:
#   1. Dev reads phase_plan.md + initial prompt, works on item 1.1
#   2. Trigger says "繼續。" (pure bash, no LLM call)
#   3. Dev picks next item, works again
#   4. Repeat until Dev emits stop signal OR max-rounds hit
#   5. On exit: run Curator to compress → progress.md
#   6. If --chain-stage2: auto-exec step2_rev_loop.sh
#
# Usage:
#   engine/step1_focus_loop.sh --project-dir <path> --initial-prompt "..." [options]
#
# Options:
#   --project-dir <path>        Target project (must have .auto_claude/ structure)
#   --initial-prompt <text>     First-round prompt (usually "讀 phase_plan.md 開始做 Phase 1")
#   --max-rounds N              Hard cap (default 40 — phase should finish well before this)
#   --phase-plan <path>         Override phase_plan path (default: .auto_claude/agent/phase_plan.md)
#   --model-dev <name>          Dev model (default: opus)
#   --chain-stage2              After stop, auto-exec step2_rev_loop.sh
#   --chain-stage3              Implies --chain-stage2, and forwards --chain-stage3 to step2
#                               (full 3-stage pipeline: step1 → step2 → attack, attack waits for human)
#   --no-curator                Skip Curator at end (debug only)
#   --help | -h                 Show this help

STEP1_VERSION="1.0"

set -uo pipefail
trap 'rm -f "${_session_ref:-}" 2>/dev/null' EXIT
trap 'rm -f "${_session_ref:-}" 2>/dev/null; kill 0 2>/dev/null' SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"

# ── Defaults ──
PROJECT_DIR=""
INITIAL_PROMPT=""
MAX_ROUNDS=40
PHASE_PLAN_PATH=""
MODEL_DEV="opus"
CHAIN_STAGE2=false
CHAIN_STAGE3=false
RUN_CURATOR=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)     PROJECT_DIR="$2";     shift 2 ;;
        --initial-prompt)  INITIAL_PROMPT="$2";  shift 2 ;;
        --max-rounds)      MAX_ROUNDS="$2";      shift 2 ;;
        --phase-plan)      PHASE_PLAN_PATH="$2"; shift 2 ;;
        --model-dev)       MODEL_DEV="$2";       shift 2 ;;
        --chain-stage2)    CHAIN_STAGE2=true;    shift ;;
        --chain-stage3)    CHAIN_STAGE2=true; CHAIN_STAGE3=true; shift ;;
        --no-curator)      RUN_CURATOR=false;    shift ;;
        --help|-h)
            awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/,""); print; next} {exit}' "$0"
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Validate ──
[[ -z "$PROJECT_DIR" ]] && { echo "Error: --project-dir is required" >&2; exit 1; }
[[ ! -d "$PROJECT_DIR" ]] && { echo "Error: $PROJECT_DIR is not a directory" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

AUTO_CLAUDE_DIR="$PROJECT_DIR/.auto_claude"
AGENT_DIR="$AUTO_CLAUDE_DIR/agent"
[[ ! -d "$AGENT_DIR" ]] && { echo "Error: $AGENT_DIR not found" >&2; exit 1; }

touch "$AUTO_CLAUDE_DIR/.metadata_never_index" 2>/dev/null  # Spotlight prevention

PHASE_PLAN_PATH="${PHASE_PLAN_PATH:-$AGENT_DIR/phase_plan.md}"
if [[ ! -f "$PHASE_PLAN_PATH" ]]; then
    echo "❌ phase_plan.md not found at $PHASE_PLAN_PATH" >&2
    echo "   Stage 1 needs a human-written phase plan before it can start." >&2
    echo "   Copy the template: cp $SCRIPT_DIR/../templates/agent/phase_plan_template.md $PHASE_PLAN_PATH" >&2
    echo "   Then fill it in and re-run." >&2
    exit 1
fi

# Sanity check: phase_plan must not be the unfilled template
if grep -q '⚠️ 這是 Phase Plan 模板' "$PHASE_PLAN_PATH"; then
    echo "❌ $PHASE_PLAN_PATH still contains the template warning header." >&2
    echo "   Fill in real phases and items before running Stage 1." >&2
    exit 1
fi
if grep -qE '<[a-z_]+>|<\.\.\.>' "$PHASE_PLAN_PATH"; then
    echo "⚠️  $PHASE_PLAN_PATH still has <...> placeholders. Dev will be confused." >&2
    read -p "Continue anyway? [y/N] " _confirm
    [[ "$_confirm" != "y" && "$_confirm" != "Y" ]] && exit 0
fi

[[ -z "$INITIAL_PROMPT" ]] && INITIAL_PROMPT="讀 agent/phase_plan.md，從 Phase 1 第一個未勾選的 item 開始做。按照 Stage 1 focus 模式的規則工作。"

# ── Load .env if present ──
_load_env() {
    local env_file="$AUTO_CLAUDE_DIR/.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
            export ANTHROPIC_API_KEY
            echo "🔑 Using API key from .auto_claude/.env"
            return
        fi
    fi
    unset ANTHROPIC_API_KEY
    echo "🔓 Using OAuth (no API key)"
}
_load_env

# ── Prompts ──
STAGE1_PROMPT_FILE=""
if [[ -f "$AGENT_DIR/dev/stage1_prompt.md" ]]; then
    STAGE1_PROMPT_FILE="$AGENT_DIR/dev/stage1_prompt.md"
elif [[ -f "$SCRIPT_DIR/../templates/agent/dev/stage1_prompt.md" ]]; then
    STAGE1_PROMPT_FILE="$SCRIPT_DIR/../templates/agent/dev/stage1_prompt.md"
else
    echo "Error: stage1_prompt.md not found" >&2
    exit 1
fi
STAGE1_PROMPT=$(cat "$STAGE1_PROMPT_FILE")

# ── Shared dev rules (optional) ──
# common_rules.md holds the discipline shared by every mode; the stage prompt holds
# only what's specific to this stage. Prepended when present. Absent is FINE — older
# projects still carry the full rule list inline in their stage prompt, so skipping
# here leaves them working exactly as before.
COMMON_RULES_FILE=""
if [[ -f "$AGENT_DIR/dev/common_rules.md" ]]; then
    COMMON_RULES_FILE="$AGENT_DIR/dev/common_rules.md"
elif [[ -f "$SCRIPT_DIR/../templates/pipeline/agent/dev/common_rules.md" ]]; then
    COMMON_RULES_FILE="$SCRIPT_DIR/../templates/pipeline/agent/dev/common_rules.md"
fi
if [[ -n "$COMMON_RULES_FILE" ]]; then
    STAGE1_PROMPT="$(cat "$COMMON_RULES_FILE")

---

$STAGE1_PROMPT"
    echo "   Common rules: $COMMON_RULES_FILE"
fi

PHASE_PLAN_CONTENT=$(cat "$PHASE_PLAN_PATH")

CONTEXT_PATH="$AGENT_DIR/context.md"
CONTEXT_CONTENT=""
[[ -f "$CONTEXT_PATH" ]] && CONTEXT_CONTENT=$(cat "$CONTEXT_PATH")

SPEC_PATH="$AGENT_DIR/spec.txt"
SPEC_EXISTS=false
[[ -f "$SPEC_PATH" ]] && SPEC_EXISTS=true

COMMS_DIR="$AGENT_DIR/comms"
mkdir -p "$COMMS_DIR" "$AGENT_DIR/dev"

# ── Log setup ──
LOG_DIR="$AUTO_CLAUDE_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
STAGE1_LOG="$LOG_DIR/${TIMESTAMP}_stage1.md"
SESSION_CSV="$LOG_DIR/${TIMESTAMP}_stage1_sessions.csv"

echo "round,role,session_uuid,project_folder,timestamp" > "$SESSION_CSV"

cat > "$STAGE1_LOG" <<EOF
# Stage 1 Focus Loop — $(date +"%Y-%m-%d %H:%M:%S")

- **Version**: $STEP1_VERSION
- **Project**: $PROJECT_DIR
- **Phase plan**: $PHASE_PLAN_PATH
- **Dev model**: $MODEL_DEV
- **Max rounds**: $MAX_ROUNDS
- **Chain to Stage 2**: $CHAIN_STAGE2

---

EOF

_session_ref=$(mktemp /tmp/stage1_session_ref.XXXXXX)

capture_session() {
    local role="$1"
    local round_num="$2"
    local newest
    newest=$(find ~/.claude/projects -name "*.jsonl" -newer "$_session_ref" -type f 2>/dev/null | head -1)
    if [[ -n "$newest" ]]; then
        local uuid
        uuid=$(basename "$newest" .jsonl)
        local folder
        folder=$(basename "$(dirname "$newest")")
        echo "$round_num,$role,$uuid,$folder,$(date +%Y-%m-%dT%H:%M:%S)" >> "$SESSION_CSV"
    fi
    touch "$_session_ref"
}

echo "🎯 Stage 1 Focus Loop v${STEP1_VERSION}"
echo "   Project:     $PROJECT_DIR"
echo "   Phase plan:  $PHASE_PLAN_PATH"
echo "   Dev model:   $MODEL_DEV"
echo "   Max rounds:  $MAX_ROUNDS"
echo "   Log:         $STAGE1_LOG"
echo "   Trigger:     dumb NLP bot (pure bash, zero tokens)"
echo ""

# ── Dumb Trigger (pure bash, no LLM) ──
# Rotates through canned responses. Dev is told upfront that this is dumb.
TRIGGER_RESPONSES=(
    "好，繼續 phase_plan.md 的下一項。"
    "繼續。"
    "好，下一個 item。"
    "繼續推進。"
    "好。下一步。"
    "繼續工作。"
    "OK。下一項。"
)

dumb_trigger() {
    local round_num="$1"
    local idx=$((round_num % ${#TRIGGER_RESPONSES[@]}))
    echo "${TRIGGER_RESPONSES[$idx]}"
}

# ── Rate limit helper (copied from loop.sh) ──
RATE_LIMIT_PATTERN="rate.limit\|overloaded\|529\|too many\|capacity\|hit your limit\|resets.*am\|throttl"

wait_for_rate_limit() {
    local label="$1"
    local result="$2"
    local reset_hour
    reset_hour=$(echo "$result" | grep -oi "resets [0-9]*am" | grep -o "[0-9]*" | head -1)
    if [[ -n "$reset_hour" ]]; then
        local target_hour=$reset_hour
        [[ $target_hour -eq 12 ]] && target_hour=0
        local now_epoch today_reset reset_epoch wait_secs
        now_epoch=$(date +%s)
        today_reset=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $(printf '%02d' $target_hour):00:00" +%s 2>/dev/null)
        reset_epoch=$today_reset
        [[ $reset_epoch -le $now_epoch ]] && reset_epoch=$((reset_epoch + 86400))
        wait_secs=$((reset_epoch - now_epoch + 60))
        echo "⏳ $label: rate limit hit. Sleeping ${wait_secs}s..." >&2
        sleep "$wait_secs"
    else
        echo "⏳ $label: rate limit hit. Waiting 300s..." >&2
        sleep 300
    fi
}

# ── Build Dev prompt (Stage 1 variant) ──
build_dev_prompt() {
    local main_content="$1"
    local prompt_file
    prompt_file=$(mktemp /tmp/stage1_dev_prompt.XXXXXX)

    cat > "$prompt_file" <<DEVPROMPT
$STAGE1_PROMPT

$main_content
DEVPROMPT

    if [[ "$SPEC_EXISTS" == true ]]; then
        printf '\n規範書路徑：%s — 需要細節時用 Read 工具去看。\n' "$SPEC_PATH" >> "$prompt_file"
    fi

    # Phase plan — the single most important injection
    printf '\n\n---\n# 📋 Phase Plan（你的工作清單 — 一項一項勾完）\n\n' >> "$prompt_file"
    printf '檔案路徑：%s\n' "$PHASE_PLAN_PATH"  >> "$prompt_file"
    printf '**做完一項就用 Edit 工具把對應的 `- [ ]` 改成 `- [x]` 並 commit。**\n\n' >> "$prompt_file"
    echo "$PHASE_PLAN_CONTENT" >> "$prompt_file"

    # Dev memory
    local _dev_mem_file="$AGENT_DIR/dev/memory.md"
    if [[ -f "$_dev_mem_file" ]]; then
        local _mem_size
        _mem_size=$(wc -c < "$_dev_mem_file" | tr -d ' ')
        if [[ $_mem_size -gt 50 ]]; then
            printf '\n---\n# 你的筆記（dev/memory.md — 只有你看到）\n' >> "$prompt_file"
            printf '路徑：%s，append 到檔尾。只注入最後 80 行。\n\n' "$_dev_mem_file" >> "$prompt_file"
            tail -80 "$_dev_mem_file" >> "$prompt_file"
        fi
    fi

    # ── Except-hook findings (post-dev anti-pattern scan; copied from loop.sh) ──
    local _except_file="$LOG_DIR/except_violations_latest.txt"
    if [[ -s "$_except_file" ]]; then
        printf '\n\n---\n# ⚠️ 上一輪你新增的 except 區塊違反規則（loop hook 自動掃描）\n' >> "$prompt_file"
        printf '這些 pattern 會讓失敗靜默降級成「看起來 OK 的 DB 狀態」，defeat 所有測試閘門。\n' >> "$prompt_file"
        printf '請本輪先修完下列項目再繼續新工作：\n\n' >> "$prompt_file"
        cat "$_except_file" >> "$prompt_file"
        printf '\n' >> "$prompt_file"
        rm -f "$_except_file"
    fi

    # Human hotline (same mechanism as loop.sh)
    local _hmsg_file="$COMMS_DIR/human_message.md"
    local _hreply_file="$COMMS_DIR/human_reply.md"
    if [[ -f "$_hmsg_file" ]]; then
        local _hmsg_content
        _hmsg_content=$(cat "$_hmsg_file")
        if [[ "$_hmsg_content" != *"目前沒有人類插話"* && -n "$_hmsg_content" ]]; then
            printf '\n\n⚠️ 人類即時插話（最高優先）：\n' >> "$prompt_file"
            printf '讀完後用 Bash 把回覆 append 到 %s\n\n' "$_hreply_file" >> "$prompt_file"
            echo "$_hmsg_content" >> "$prompt_file"
            printf '\n---\n[%s] Stage 1 Round %s\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${round:-?}" "$_hmsg_content" >> "$COMMS_DIR/human_message_history.log"
            echo "（目前沒有人類插話）" > "$_hmsg_file"
        fi
    fi

    # Context
    if [[ -n "$CONTEXT_CONTENT" ]]; then
        printf '\n\n---\n# 專案背景\n\n' >> "$prompt_file"
        echo "$CONTEXT_CONTENT" >> "$prompt_file"
    fi

    cat "$prompt_file"
    rm -f "$prompt_file"
}

# ── Dev session (reused across rounds via --resume) ──
DEV_SESSION_ID=""
DEV_LIVE_LOG=""

run_dev() {
    local message="$1"
    local _output_file
    _output_file=$(mktemp /tmp/stage1_dev_output.XXXXXX)

    touch "$_session_ref"
    while true; do
        if [[ -n "$DEV_SESSION_ID" ]]; then
            (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --resume "$DEV_SESSION_ID" \
                "$message" 2>&1) | tee "$_output_file" > "${DEV_LIVE_LOG:-/dev/null}"
        else
            DEV_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
            (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --session-id "$DEV_SESSION_ID" \
                "$message" 2>&1) | tee "$_output_file" > "${DEV_LIVE_LOG:-/dev/null}"
        fi
        if grep -qi "$RATE_LIMIT_PATTERN" "$_output_file" 2>/dev/null; then
            wait_for_rate_limit "Stage1 Dev" "$(cat "$_output_file")"
            > "$_output_file"
        else
            break
        fi
    done
    capture_session "dev" "${round:-0}"
    sync 2>/dev/null; sleep 1
    cat "$_output_file"
    rm -f "$_output_file"
}

# ── Curator (copied from loop.sh, only runs at Stage 1 exit) ──
PROGRESS_FILE="$AGENT_DIR/dev/progress.md"
CURATOR_PROMPT_FILE="$AGENT_DIR/curator/prompt.md"
[[ ! -f "$CURATOR_PROMPT_FILE" ]] && CURATOR_PROMPT_FILE="$SCRIPT_DIR/../templates/agent/curator/prompt.md"
CURATOR_PROMPT="Compress tool call outputs to one-line logs keeping key content."
[[ -f "$CURATOR_PROMPT_FILE" ]] && CURATOR_PROMPT=$(cat "$CURATOR_PROMPT_FILE")

run_curator_final() {
    local dev_output="$1"
    local round_num="$2"

    echo "🧹 Curator (sonnet) compressing Stage 1 context..."

    local curator_input="Stage 1 focus loop 結束時的最終狀態。請壓縮所有 tool call 輸出，保留：
1. 每個已完成 phase_plan item 對應的關鍵檔案和函數
2. 哪些 item 已勾選、哪些還沒
3. Blocked items 的 blocker 原因
4. 任何 Stage 2 Reviewer 會需要知道的 known issue / technical debt

輸出會寫進 dev/progress.md，Stage 2 Dev 啟動時會讀到。

$dev_output"

    local response
    touch "$_session_ref"
    while true; do
        response=$(echo "$curator_input" | "$CLAUDE_BIN" \
            --print \
            --model sonnet \
            --append-system-prompt "$CURATOR_PROMPT" \
            --disallowed-tools "Bash Write Edit Glob Grep WebFetch WebSearch NotebookEdit Agent" \
            - 2>&1)
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Stage1 Curator" "$response"
        else
            break
        fi
    done
    capture_session "curator" "$round_num"

    cat > "$PROGRESS_FILE" <<PROGRESS
# Stage 1 結束進度（Curator 壓縮於 $(date +"%Y-%m-%d %H:%M:%S")，Round $round_num）

$response

---

## Phase Plan 當前勾選狀態

$(cat "$PHASE_PLAN_PATH")
PROGRESS

    echo "   ✅ Progress saved → $PROGRESS_FILE"
}

# ── Heartbeat ──
HEARTBEAT_FILE="$LOG_DIR/heartbeat"

# ── Main loop ──
STOP_SIGNAL="<!JOB_STOP_NOTHINGS_CAN_DO!>"
DEV_OUTPUT=""
FINAL_ROUND=0
STOPPED_BY_DEV=false

for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Stage 1 · Round $round / $MAX_ROUNDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    printf '{"pid":%d,"stage":1,"round":%d,"max":%d,"time":"%s","log":"%s","sessions":"%s"}\n' \
        $$ $round $MAX_ROUNDS "$(date +"%Y-%m-%d %H:%M:%S")" "$STAGE1_LOG" "$SESSION_CSV" > "$HEARTBEAT_FILE"

    DEV_LIVE_LOG="$LOG_DIR/stage1_dev_live_round${round}.log"
    > "$DEV_LIVE_LOG"
    echo "   📡 Dev live log: tail -f $DEV_LIVE_LOG"

    # Round 1 uses initial prompt; subsequent rounds use trigger canned text
    if [[ $round -eq 1 ]]; then
        echo "🔨 Dev: initial prompt..."
        DEV_MESSAGE=$(build_dev_prompt "$INITIAL_PROMPT")
    else
        TRIGGER_TEXT=$(dumb_trigger "$round")
        echo "🤖 Trigger (dumb bot): $TRIGGER_TEXT"
        cat >> "$STAGE1_LOG" <<TRIG
### Round $round · Trigger
\`$TRIGGER_TEXT\` (pure bash, 0 tokens)

TRIG
        DEV_MESSAGE=$(build_dev_prompt "$TRIGGER_TEXT")
    fi

    # Snapshot HEAD so the post-dev except scan only looks at this round's diff
    _round_start_sha=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")

    DEV_START=$(date +%s)
    DEV_OUTPUT=$(run_dev "$DEV_MESSAGE")
    DEV_END=$(date +%s)
    DEV_DURATION=$((DEV_END - DEV_START))
    DEV_CHARS=${#DEV_OUTPUT}

    if echo "$DEV_OUTPUT" | grep -qi "$RATE_LIMIT_PATTERN"; then
        echo "🛡️ Rate limit caught, waiting..."
        wait_for_rate_limit "Stage1 main" "$DEV_OUTPUT"
        ((round--))
        continue
    fi
    if [[ $DEV_CHARS -lt 10 ]]; then
        echo "⚠️ Dev output too short (${DEV_CHARS} chars), retrying in 5s..."
        sleep 5
        ((round--))
        continue
    fi

    echo "   Dev: ${DEV_CHARS} chars (${DEV_DURATION}s)"
    echo ""
    echo "$DEV_OUTPUT"
    echo ""

    # ── Post-Dev hook: scan for exception anti-patterns in this round's diff ──
    # Stage 1 is the only stage with no Reviewer, so this hook is the ONLY quality
    # gate here. It was missing until 2026-07-31 — same class of omission as
    # KNOWN_PITFALLS.md #12 (new loop copied loop.sh but dropped a guard).
    _except_violations="$LOG_DIR/except_violations_latest.txt"
    if [[ -x "$SCRIPT_DIR/check_except_patterns.py" ]]; then
        if python3 "$SCRIPT_DIR/check_except_patterns.py" \
                "$PROJECT_DIR" --since "$_round_start_sha" > "$_except_violations" 2>&1; then
            rm -f "$_except_violations"
        else
            _viol_count=$(grep -c '\[silent_swallow\]\|\[bare_except\]' "$_except_violations" 2>/dev/null || echo 0)
            echo "⚠️  except-hook: $_viol_count anti-pattern(s) flagged — will inject into next Dev prompt"
        fi
    fi

    cat >> "$STAGE1_LOG" <<EOF
## Round $round — $(date +"%H:%M:%S") — Dev (${DEV_CHARS} chars, ${DEV_DURATION}s)

$DEV_OUTPUT

---

EOF

    FINAL_ROUND=$round

    # Single-side stop: only Dev can stop Stage 1
    if echo "$DEV_OUTPUT" | grep -qF "$STOP_SIGNAL"; then
        echo "🏁 Dev signaled stop. Stage 1 complete."
        STOPPED_BY_DEV=true
        cat >> "$STAGE1_LOG" <<EOF
### 🏁 Dev single-side stop at Round $round

EOF
        break
    fi
done

if [[ "$STOPPED_BY_DEV" != true ]]; then
    echo "⏰ Max rounds ($MAX_ROUNDS) reached without Dev stop signal."
    echo "   Stage 1 may have unfinished phase_plan items. Check $PHASE_PLAN_PATH before proceeding."
    cat >> "$STAGE1_LOG" <<EOF
### ⏰ Stage 1 max rounds reached (no stop signal)

EOF
fi

# ── Curator at exit ──
if [[ "$RUN_CURATOR" == true ]]; then
    run_curator_final "$DEV_OUTPUT" "$FINAL_ROUND"
else
    echo "⏭️  Curator skipped (--no-curator)"
fi

echo ""
echo "🏁 Stage 1 finished at Round $FINAL_ROUND"
echo "   Log: $STAGE1_LOG"
echo "   Progress: $PROGRESS_FILE"

# ── Chain to Stage 2 ──
if [[ "$CHAIN_STAGE2" == true ]]; then
    STEP2="$SCRIPT_DIR/step2_rev_loop.sh"
    if [[ ! -x "$STEP2" ]]; then
        echo "⚠️  --chain-stage2 set but $STEP2 not executable. Exiting Stage 1 only." >&2
        exit 0
    fi
    echo ""
    echo "🔗 Chaining to Stage 2 (step2_rev_loop.sh)..."
    STAGE2_INITIAL="Stage 1 已結束。讀 agent/dev/progress.md 了解 Stage 1 做了什麼，然後開始 Stage 2 review/fix 工作：跑測試、修 bug、把 Reviewer 找到的問題一項一項解掉。"
    STAGE2_ARGS=(
        --project-dir "$PROJECT_DIR"
        --initial-prompt "$STAGE2_INITIAL"
        --model-dev "$MODEL_DEV"
    )
    [[ "$CHAIN_STAGE3" == true ]] && STAGE2_ARGS+=(--chain-stage3)
    exec "$STEP2" "${STAGE2_ARGS[@]}"
fi
