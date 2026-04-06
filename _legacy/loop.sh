#!/bin/bash
#
# Auto_Claude Dev ↔ Reviewer Loop
# 全自動 Dev ↔ Reviewer 對話迴圈
#
# Usage:
#   ./agent/loop.sh --project-dir <path> --spec <path> [options]
#
# Quick start (交通部):
#   ./agent/motc_loop.sh
#
# Flow:
#   1. Extract dev's latest output
#   2. Reviewer reviews → produces feedback
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
MODEL_REVIEWER="opus"
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
        --model-reviewer)      MODEL_REVIEWER="$2";        shift 2 ;;
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
PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$SCRIPT_DIR/prompts/motc_reviewer.prompt.md}"
TEMPLATE_PROMPT=$(cat "$PROMPT_TEMPLATE")
SPEC_CONTENT=$(cat "$SPEC_PATH")

# ── Log setup ──
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
LOOP_LOG="$LOG_DIR/${TIMESTAMP}_loop.md"

cat > "$LOOP_LOG" <<EOF
# Dev ↔ Reviewer Loop Log

- **Start**: $(date +"%Y-%m-%d %H:%M:%S")
- **Reviewer model**: $MODEL_REVIEWER
- **Dev model**: $MODEL_DEV
- **Project**: $PROJECT_DIR
- **Max rounds**: $MAX_ROUNDS

---

EOF

echo "🔄 Auto_Claude Dev ↔ Reviewer Loop"
echo "   Reviewer: $MODEL_REVIEWER | Dev: $MODEL_DEV"
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

# ── Helper: run reviewer ──
run_reviewer() {
    local dev_output="$1"

    local prompt_file
    prompt_file=$(mktemp /tmp/reviewer_prompt_XXXXXX.txt)

    # Read human's messages — both original and dev's reply
    local human_section=""
    local human_msg_file="$PROJECT_DIR/human_message.md"
    local human_reply_file="$PROJECT_DIR/human_reply.md"
    local has_human=false

    # Original human message (if not cleared yet)
    if [[ -f "$human_msg_file" ]]; then
        local msg_content
        msg_content=$(cat "$human_msg_file")
        if [[ "$msg_content" != *"目前沒有人類插話"* && -n "$msg_content" ]]; then
            human_section="
---

# ⚠️ 人類主管的原話（最高優先，你的建議必須符合這個方向）

$msg_content
"
            has_human=true
        fi
    fi

    # Dev's reply to human (persistent record of human instructions)
    if [[ -f "$human_reply_file" ]]; then
        local reply_content
        reply_content=$(cat "$human_reply_file")
        if [[ -n "$reply_content" ]]; then
            human_section="$human_section
---

# 開發者對人類指示的回覆紀錄

$reply_content
"
        fi
    fi

    # Read reviewer's own past memory
    local reviewer_memory_section=""
    local reviewer_mem_file="$PROJECT_DIR/reviewer_memory.md"
    if [[ -f "$reviewer_mem_file" ]]; then
        local mem_content
        mem_content=$(tail -100 "$reviewer_mem_file")  # 最近 100 行，防 context 爆
        reviewer_memory_section="
---

# 你過去的審查紀錄（已經問過/確認過的事不要再問！）

$mem_content
"
    fi

    cat > "$prompt_file" <<AGENT_EOF
你是 AI 審查者（Reviewer）。根據以下規範書與開發原則，對開發者輸出做出判斷。

# 招標規範書（精簡版）

$SPEC_CONTENT
$human_section$reviewer_memory_section
---

# 開發者最新輸出

$dev_output

---

請根據你的角色定義和開發原則，對以上內容做出回覆。
重要規則：
1. 查看「你過去的審查紀錄」，已經問過且 Dev 已回答的問題，不要再問。往前推進，不要原地踏步。
2. 如果上面有「人類主管的原話」或「開發者對人類指示的回覆紀錄」，你的回覆第一行必須寫「📌 已讀人類指示：」加一句摘要，然後你的建議必須符合該方向。人類主管的指示優先於你自己的判斷。

你有一個專用工具可以讀寫你自己的 prompt 檔案（motc_reviewer.prompt.md）：
- 讀取：bash $SCRIPT_DIR/tools/prompt_rw.sh read
- 覆寫：echo "新內容" | bash $SCRIPT_DIR/tools/prompt_rw.sh write
- 追加：echo "追加內容" | bash $SCRIPT_DIR/tools/prompt_rw.sh append
這是你唯一可以寫入的檔案。用它來更新你的任務清單狀態或修正你的行為規則。
AGENT_EOF

    local response
    while true; do
        response=$(cat "$prompt_file" | env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
            --print \
            --model "$MODEL_REVIEWER" \
            --append-system-prompt "$TEMPLATE_PROMPT" \
            --disallowed-tools "Write Edit NotebookEdit Agent" --allowedTools "WebFetch WebSearch Read Glob Grep mcp__entropyshield__*" \
            - 2>&1)
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Reviewer" "$response"
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
            response=$(cd "$PROJECT_DIR" && env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" \
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

# ── Heartbeat file ──
HEARTBEAT_FILE="$LOG_DIR/heartbeat"

# ── Main loop ──
for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Round $round / $MAX_ROUNDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Heartbeat — quick way to check if loop is alive
    printf '{"pid":%d,"round":%d,"max":%d,"time":"%s","log":"%s"}\n' \
        $$ $round $MAX_ROUNDS "$(date +"%Y-%m-%d %H:%M:%S")" "$LOOP_LOG" > "$HEARTBEAT_FILE"

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

    # ── Step B: Reviewer reviews ──
    echo "🧠 Reviewer ($MODEL_REVIEWER) reviewing..."
    REVIEWER_START=$(date +%s)
    REVIEWER_RESPONSE=$(run_reviewer "$DEV_OUTPUT")
    REVIEWER_END=$(date +%s)
    REVIEWER_DURATION=$((REVIEWER_END - REVIEWER_START))
    # Rate limit guard for reviewer
    if echo "$REVIEWER_RESPONSE" | grep -qi "$RATE_LIMIT_PATTERN"; then
        echo "🛡️ Main loop caught rate limit in reviewer response, waiting..."
        wait_for_rate_limit "Reviewer (main loop)" "$REVIEWER_RESPONSE"
        ((round--))
        continue
    fi

    REVIEWER_CHARS=${#REVIEWER_RESPONSE}

    # Empty response guard
    if [[ $REVIEWER_CHARS -lt 5 ]]; then
        echo "⚠️ Reviewer returned empty/near-empty response, substituting fallback"
        REVIEWER_RESPONSE="reviewer agent 連線有問題 這一輪先繼續能做的"
        REVIEWER_CHARS=${#REVIEWER_RESPONSE}
    fi

    echo "   Reviewer response: ${REVIEWER_CHARS} chars (${REVIEWER_DURATION}s)"
    echo ""
    echo "$REVIEWER_RESPONSE"
    echo ""

    # Log reviewer response
    cat >> "$LOOP_LOG" <<EOF
### Reviewer Response (${REVIEWER_CHARS} chars, ${REVIEWER_DURATION}s)

$REVIEWER_RESPONSE

EOF

    # ── Append to reviewer memory (persistent across rounds) ──
    REVIEWER_MEMORY_FILE="$PROJECT_DIR/reviewer_memory.md"
    if [[ ! -f "$REVIEWER_MEMORY_FILE" ]]; then
        echo "# Reviewer 審查記憶（自動累積，勿手動刪除）" > "$REVIEWER_MEMORY_FILE"
        echo "" >> "$REVIEWER_MEMORY_FILE"
        echo "每一條是 reviewer 過去某一輪的回覆摘要。已經問過/確認過的事不要再問。" >> "$REVIEWER_MEMORY_FILE"
        echo "" >> "$REVIEWER_MEMORY_FILE"
    fi
    cat >> "$REVIEWER_MEMORY_FILE" <<AMEOF
## Round $round ($(date +"%H:%M"))
$REVIEWER_RESPONSE

---
AMEOF

    # ── Step C: Dev continues with reviewer feedback ──
    echo "🔨 Dev ($MODEL_DEV) continuing with reviewer feedback..."
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
5. 停止協議：如果你確認所有剩餘工作都需要人類才能繼續，且 reviewer 也同意，在回覆中輸出 <!JOB_STOP_NOTHINGS_CAN_DO!>。不要輕易用——先想想有沒有任何能做的事。

以下是 AI 審查者（Reviewer）的回饋：

DEVPROMPT_STATIC

    echo "$REVIEWER_RESPONSE" >> "$DEV_PROMPT_FILE"

    # ── Human hotline: inject human_message.md if present ──
    HUMAN_MSG_FILE="$PROJECT_DIR/human_message.md"
    HUMAN_REPLY_FILE="$PROJECT_DIR/human_reply.md"
    if [[ -f "$HUMAN_MSG_FILE" ]]; then
        HUMAN_MSG_CONTENT=$(cat "$HUMAN_MSG_FILE")
        if [[ "$HUMAN_MSG_CONTENT" != *"目前沒有人類插話"* && -n "$HUMAN_MSG_CONTENT" ]]; then
            printf '\n\n⚠️ 人類即時插話（最高優先，讀完後把回覆寫到 %s，然後清空 %s 寫入「（目前沒有人類插話）」）：\n\n' "$HUMAN_REPLY_FILE" "$HUMAN_MSG_FILE" >> "$DEV_PROMPT_FILE"
            echo "$HUMAN_MSG_CONTENT" >> "$DEV_PROMPT_FILE"
        fi
    fi

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

    echo "📄 Round $round complete. Total: Reviewer ${REVIEWER_DURATION}s + Dev ${DEV_DURATION}s"
    echo ""

    # ── Step D-0: Check for graceful stop signal ──
    STOP_SIGNAL="<!JOB_STOP_NOTHINGS_CAN_DO!>"
    REVIEWER_WANTS_STOP=false
    DEV_WANTS_STOP=false

    if echo "$REVIEWER_RESPONSE" | grep -qF "$STOP_SIGNAL"; then
        REVIEWER_WANTS_STOP=true
        echo "🛑 Reviewer signaled: nothing more to do"
    fi
    if echo "$DEV_OUTPUT" | grep -qF "$STOP_SIGNAL"; then
        DEV_WANTS_STOP=true
        echo "🛑 Dev signaled: nothing more to do"
    fi

    if [[ "$REVIEWER_WANTS_STOP" == true && "$DEV_WANTS_STOP" == true ]]; then
        echo ""
        echo "🏁 Both Reviewer and Dev agree: nothing more can be done without human input."
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
