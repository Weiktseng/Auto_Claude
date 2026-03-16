#!/bin/bash
#
# Auto_Claude Agent Loop
# 全自動 Dev ↔ Agent 對話迴圈
#
# Usage:
#   ./agent/loop.sh --project-dir <path> --spec <path> [options]
#
# Quick start (交通部):
#   ./agent/motc_loop.sh
#
# Flow:
#   1. Extract dev's latest output
#   2. Agent reviews → produces feedback
#   3. Inject feedback into dev session → dev continues working
#   4. Repeat from 1
#

set -uo pipefail
# NOTE: 不用 set -e，因為 main loop 內的 grep/claude 指令可能回傳非 0，
# 不應該讓整個腳本因此死掉。關鍵錯誤靠明確的 || exit 處理。

# Ensure child processes are killed when this script exits
trap 'kill 0 2>/dev/null' EXIT SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"

# ── Defaults ──
MODEL_AGENT="opus"
MODEL_DEV="opus"
PROJECT_DIR=""
SPEC_PATH=""
PROMPT_TEMPLATE=""
MAX_ROUNDS=10
DEV_SESSION_ID=""
INITIAL_PROMPT=""

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)      PROJECT_DIR="$2";       shift 2 ;;
        --spec)             SPEC_PATH="$2";          shift 2 ;;
        --prompt-template)  PROMPT_TEMPLATE="$2";    shift 2 ;;
        --model-agent)      MODEL_AGENT="$2";        shift 2 ;;
        --model-dev)        MODEL_DEV="$2";          shift 2 ;;
        --max-rounds)       MAX_ROUNDS="$2";         shift 2 ;;
        --resume-session)   DEV_SESSION_ID="$2";     shift 2 ;;
        --initial-prompt)   INITIAL_PROMPT="$2";     shift 2 ;;
        --help|-h)
            head -16 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ── Validate ──
if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: --project-dir is required" >&2; exit 1
fi
if [[ -z "$SPEC_PATH" ]]; then
    echo "Error: --spec is required" >&2; exit 1
fi

# Defaults
PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$SCRIPT_DIR/prompts/motc_agent.prompt.md}"
TEMPLATE_PROMPT=$(cat "$PROMPT_TEMPLATE")
SPEC_CONTENT=$(cat "$SPEC_PATH")

# ── Log setup ──
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
LOOP_LOG="$LOG_DIR/${TIMESTAMP}_loop.md"

cat > "$LOOP_LOG" <<EOF
# Agent Loop Log

- **Start**: $(date +"%Y-%m-%d %H:%M:%S")
- **Agent model**: $MODEL_AGENT
- **Dev model**: $MODEL_DEV
- **Project**: $PROJECT_DIR
- **Max rounds**: $MAX_ROUNDS

---

EOF

echo "🔄 Auto_Claude Agent Loop"
echo "   Agent: $MODEL_AGENT | Dev: $MODEL_DEV"
echo "   Project: $PROJECT_DIR"
echo "   Max rounds: $MAX_ROUNDS"
echo "   Log: $LOOP_LOG"
echo ""

# ── Helper: wait for rate limit reset ──
RATE_LIMIT_PATTERN="rate.limit\|overloaded\|529\|too many\|capacity\|hit your limit\|resets.*am\|throttl"

wait_for_rate_limit() {
    local label="$1"
    local result="$2"

    # Extract reset time if mentioned (e.g. "resets 12am", "resets 5am")
    local reset_hour
    reset_hour=$(echo "$result" | grep -oi "resets [0-9]*am" | grep -o "[0-9]*" | head -1)

    if [[ -n "$reset_hour" ]]; then
        # Convert 12am→0, 1am→1, etc.
        local target_hour=$reset_hour
        if [[ $target_hour -eq 12 ]]; then
            target_hour=0
        fi

        local now_epoch
        now_epoch=$(date +%s)

        # Build today's reset time (e.g. today at 00:00:00 for 12am)
        local today_reset
        today_reset=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $(printf '%02d' $target_hour):00:00" +%s 2>/dev/null)

        # If that time already passed, it's tomorrow
        local reset_epoch=$today_reset
        if [[ $reset_epoch -le $now_epoch ]]; then
            reset_epoch=$((reset_epoch + 86400))
        fi

        local wait_secs=$((reset_epoch - now_epoch + 60))  # +60s buffer
        echo "⏳ $label: rate limit hit. Resets at ${reset_hour}am (hour=$target_hour). Sleeping ${wait_secs}s (~$((wait_secs/60))min)..." >&2
        cat >> "$LOOP_LOG" <<RATELIMIT
### ⏳ Rate limit — $label — $(date +"%H:%M:%S"), sleeping ${wait_secs}s until $(printf '%02d' $target_hour):00 (+60s buffer)

RATELIMIT
        sleep "$wait_secs"
    else
        # Unknown reset time, wait 5 min
        echo "⏳ $label: rate limit hit. Waiting 300s..." >&2
        sleep 300
    fi
}

# ── Helper: run curator (compress tool outputs) ──
CURATOR_PROMPT=$(cat "$SCRIPT_DIR/prompts/curator.prompt.md" 2>/dev/null || echo "Compress tool call outputs to one-line logs keeping key content.")
CURATOR_INTERVAL=8
PROGRESS_FILE="$PROJECT_DIR/progress.md"

run_curator() {
    local dev_output="$1"
    local round_num="$2"

    echo "🧹 Curator (sonnet) compressing context..."

    local curator_input="以下是開發者第 $round_num 輪結束時的累積輸出。請壓縮 tool call 輸出，保留關鍵內容本身。

$dev_output"

    local response
    while true; do
        response=$(echo "$curator_input" | env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
            --print \
            --model sonnet \
            --append-system-prompt "$CURATOR_PROMPT" \
            --disallowed-tools "Bash Write Edit Glob Grep WebFetch WebSearch NotebookEdit Agent" \
            - 2>&1)
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Curator" "$response"
        else
            break
        fi
    done

    # Write compressed progress
    cat > "$PROGRESS_FILE" <<PROGRESS_EOF
# 開發進度（Curator 壓縮於 $(date +"%Y-%m-%d %H:%M:%S")，Round $round_num 後）

$response
PROGRESS_EOF

    echo "   Curator done. Progress saved to $PROGRESS_FILE"
    echo "$response"
}

# ── Helper: run agent ──
run_agent() {
    local dev_output="$1"

    local prompt_file
    prompt_file=$(mktemp /tmp/agent_prompt_XXXXXX.txt)

    cat > "$prompt_file" <<AGENT_EOF
你是 AI 決策代理。根據以下規範書與開發原則，對開發者輸出做出判斷。

# 招標規範書（精簡版）

$SPEC_CONTENT

---

# 開發者最新輸出

$dev_output

---

請根據你的角色定義和開發原則，對以上內容做出回覆。
AGENT_EOF

    local response
    while true; do
        response=$(cat "$prompt_file" | env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
            --print \
            --model "$MODEL_AGENT" \
            --append-system-prompt "$TEMPLATE_PROMPT" \
            --disallowed-tools "Write Edit NotebookEdit Agent" --allowedTools "WebFetch WebSearch Read Glob Grep mcp__entropyshield__*" \
            - 2>&1)
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Agent" "$response"
        else
            break
        fi
    done

    rm -f "$prompt_file"
    echo "$response"
}

# ── Helper: run dev ──
run_dev() {
    local message="$1"
    local response

    while true; do
        if [[ -n "$DEV_SESSION_ID" ]]; then
            response=$(env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --resume "$DEV_SESSION_ID" \
                "$message" 2>&1)
        else
            DEV_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
            local full_message="$message"
            if [[ -f "$PROGRESS_FILE" ]]; then
                local progress_content
                progress_content=$(cat "$PROGRESS_FILE")
                full_message="你是接手的開發者。以下是前一輪的壓縮進度紀錄，讀完後繼續工作：

$progress_content

---

$message"
            fi
            response=$(cd "$PROJECT_DIR" && env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --session-id "$DEV_SESSION_ID" \
                "$full_message" 2>&1)
        fi
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Dev" "$response"
        else
            break
        fi
    done

    echo "$response"
}

# ── Main loop ──
for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Round $round / $MAX_ROUNDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # ── Step A: Get dev output ──
    if [[ $round -eq 1 ]]; then
        if [[ -n "$INITIAL_PROMPT" ]]; then
            echo "🔨 Dev: running initial prompt..."
            DEV_OUTPUT=$(run_dev "$INITIAL_PROMPT")
        else
            echo "📥 Extracting latest dev session output..."
            DEV_OUTPUT=$(python3 "$SCRIPT_DIR/extract_session.py" \
                "$PROJECT_DIR" --lines 3 --memory --format prompt 2>&1) || {
                echo "❌ Could not extract dev output. Exiting."
                exit 1
            }
        fi
    fi

    # ── Guards: rate limit and empty output ──
    if echo "$DEV_OUTPUT" | grep -qi "$RATE_LIMIT_PATTERN"; then
        echo "🛡️ Main loop caught rate limit in dev output, waiting..."
        wait_for_rate_limit "Dev (main loop)" "$DEV_OUTPUT"
        ((round--))
        continue
    fi
    if [[ ${#DEV_OUTPUT} -lt 10 ]]; then
        echo "⚠️ Dev output too short (${#DEV_OUTPUT} chars), retrying in 30s..."
        sleep 30
        ((round--))
        continue
    fi

    DEV_CHARS=${#DEV_OUTPUT}
    echo "   Dev output: ${DEV_CHARS} chars"

    # Log dev output
    cat >> "$LOOP_LOG" <<EOF
## Round $round — $(date +"%H:%M:%S")

### Dev Output (${DEV_CHARS} chars)

$DEV_OUTPUT

EOF

    # ── Step B: Agent reviews ──
    echo "🧠 Agent ($MODEL_AGENT) reviewing..."
    AGENT_START=$(date +%s)
    AGENT_RESPONSE=$(run_agent "$DEV_OUTPUT")
    AGENT_END=$(date +%s)
    AGENT_DURATION=$((AGENT_END - AGENT_START))
    # Rate limit guard for agent
    if echo "$AGENT_RESPONSE" | grep -qi "$RATE_LIMIT_PATTERN"; then
        echo "🛡️ Main loop caught rate limit in agent response, waiting..."
        wait_for_rate_limit "Agent (main loop)" "$AGENT_RESPONSE"
        ((round--))
        continue
    fi

    AGENT_CHARS=${#AGENT_RESPONSE}

    echo "   Agent response: ${AGENT_CHARS} chars (${AGENT_DURATION}s)"
    echo ""
    echo "$AGENT_RESPONSE"
    echo ""

    # Log agent response
    cat >> "$LOOP_LOG" <<EOF
### Agent Response (${AGENT_CHARS} chars, ${AGENT_DURATION}s)

$AGENT_RESPONSE

EOF

    # ── Step C: Dev continues with agent feedback ──
    echo "🔨 Dev ($MODEL_DEV) continuing with agent feedback..."
    DEV_START=$(date +%s)
    # Build dev prompt via temp file to avoid shell expansion issues
    QUESTIONS_FILE="$SCRIPT_DIR/questions_for_human.md"
    DEV_PROMPT_FILE=$(mktemp /tmp/dev_prompt_XXXXXX.txt)

    cat > "$DEV_PROMPT_FILE" <<'DEVPROMPT_STATIC'
規則：
1. 直接動手做事，不要問問題。你是 RD，寫程式是你的工作。
2. 如果有問題只有人類能回答，把問題追加寫到 questions_for_human.md，然後繼續做你能做的部分。
3. 每輪結束時報告：做了什麼（具體檔案/功能）、下一步打算做什麼。
4. 目標：3/31 在另一台乾淨電腦上能展示給政府官員看。
5. 停止協議：如果你確認所有剩餘工作都需要人類才能繼續，且 agent 也同意，在回覆中輸出 <!JOB_STOP_NOTHINGS_CAN_DO!>。不要輕易用——先想想有沒有任何能做的事。

以下是 AI 審查代理的回饋：

DEVPROMPT_STATIC

    echo "$AGENT_RESPONSE" >> "$DEV_PROMPT_FILE"

    printf '\n\n已知背景（不需要再問）：\n\n' >> "$DEV_PROMPT_FILE"
    if [[ -f "$SCRIPT_DIR/human_context.md" ]]; then
        cat "$SCRIPT_DIR/human_context.md" >> "$DEV_PROMPT_FILE"
    fi

    DEV_MESSAGE=$(cat "$DEV_PROMPT_FILE")
    rm -f "$DEV_PROMPT_FILE"

    DEV_OUTPUT=$(run_dev "$DEV_MESSAGE")

    # Rate limit guard for dev Step C
    if echo "$DEV_OUTPUT" | grep -qi "$RATE_LIMIT_PATTERN"; then
        echo "🛡️ Main loop caught rate limit in dev Step C, waiting..."
        wait_for_rate_limit "Dev Step C (main loop)" "$DEV_OUTPUT"
        ((round--))
        continue
    fi

    DEV_END=$(date +%s)
    DEV_DURATION=$((DEV_END - DEV_START))
    DEV_CHARS=${#DEV_OUTPUT}

    echo "   Dev response: ${DEV_CHARS} chars (${DEV_DURATION}s)"
    echo ""
    echo "$DEV_OUTPUT"
    echo ""

    # Log dev response
    cat >> "$LOOP_LOG" <<EOF
### Dev Response (${DEV_CHARS} chars, ${DEV_DURATION}s)

$DEV_OUTPUT

---

EOF

    echo "📄 Round $round complete. Total: Agent ${AGENT_DURATION}s + Dev ${DEV_DURATION}s"
    echo ""

    # ── Step D-0: Check for graceful stop signal ──
    STOP_SIGNAL="<!JOB_STOP_NOTHINGS_CAN_DO!>"
    AGENT_WANTS_STOP=false
    DEV_WANTS_STOP=false

    if echo "$AGENT_RESPONSE" | grep -qF "$STOP_SIGNAL"; then
        AGENT_WANTS_STOP=true
        echo "🛑 Agent signaled: nothing more to do"
    fi
    if echo "$DEV_OUTPUT" | grep -qF "$STOP_SIGNAL"; then
        DEV_WANTS_STOP=true
        echo "🛑 Dev signaled: nothing more to do"
    fi

    if [[ "$AGENT_WANTS_STOP" == true && "$DEV_WANTS_STOP" == true ]]; then
        echo ""
        echo "🏁 Both Agent and Dev agree: nothing more can be done without human input."
        echo "   Stopping loop at Round $round."
        cat >> "$LOOP_LOG" <<EOF
### 🏁 Graceful stop — both sides signaled $STOP_SIGNAL at Round $round

EOF
        break
    fi

    # ── Step D-1: Curator — every N rounds, compress context and start fresh session ──
    if [[ $((round % CURATOR_INTERVAL)) -eq 0 && $round -lt $MAX_ROUNDS ]]; then
        echo "🧹 Round $round: Curator triggered (every ${CURATOR_INTERVAL} rounds)"

        CURATOR_START=$(date +%s)
        CURATOR_RESPONSE=$(run_curator "$DEV_OUTPUT" "$round")
        CURATOR_END=$(date +%s)
        CURATOR_DURATION=$((CURATOR_END - CURATOR_START))

        cat >> "$LOOP_LOG" <<EOF
### 🧹 Curator (Round $round, ${CURATOR_DURATION}s)

$CURATOR_RESPONSE

EOF

        # Reset dev session — next round starts fresh with progress.md
        echo "🔄 Resetting dev session (old: $DEV_SESSION_ID)"
        DEV_SESSION_ID=""

        echo "   New session will start with progress.md context"
        echo ""
    fi
done

echo "🏁 Loop finished ($MAX_ROUNDS rounds)."
echo "📄 Full log: $LOOP_LOG"
