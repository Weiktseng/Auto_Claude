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

LOOP_VERSION="3.1"

set -uo pipefail
# NOTE: 不用 set -e，因為 main loop 內的 grep/claude 指令可能回傳非 0，
# 不應該讓整個腳本因此死掉。關鍵錯誤靠明確的 || exit 處理。

# Ensure child processes are killed when this script exits
trap 'kill 0 2>/dev/null' EXIT SIGINT SIGTERM

# ── PID lock: prevent duplicate loop instances ──
# Lock file 放在 LOG_DIR，但此時還沒 parse args，所以先用暫存位置，
# parse 完後再搬到正確的 LOG_DIR（見下方 "Relocate lock file"）。
_EARLY_LOCK_FILE="/tmp/auto_claude_loop.pid"
if [[ -f "$_EARLY_LOCK_FILE" ]]; then
    _EXISTING_PID=$(cat "$_EARLY_LOCK_FILE")
    if kill -0 "$_EXISTING_PID" 2>/dev/null; then
        echo "❌ Loop already running (PID $_EXISTING_PID). Exiting." >&2
        echo "   如果確定沒在跑，刪除 $_EARLY_LOCK_FILE 再試。" >&2
        exit 1
    else
        echo "⚠️ Stale lock file found (PID $_EXISTING_PID not running), removing."
        rm -f "$_EARLY_LOCK_FILE"
    fi
fi
echo $$ > "$_EARLY_LOCK_FILE"
trap 'rm -f "$_EARLY_LOCK_FILE" "${LOCK_FILE:-}" 2>/dev/null; kill 0 2>/dev/null' EXIT SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"

# ── CLI version check (soft warning, no longer blocks) ──
MIN_CLI_VERSION="2.1.84"
ACTUAL_CLI_VERSION=$("$CLAUDE_BIN" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
if [[ -n "$ACTUAL_CLI_VERSION" ]]; then
    echo "ℹ️  CLI version: $ACTUAL_CLI_VERSION"
else
    echo "⚠️  Could not detect CLI version"
fi

# ── Load .env if exists (for API key) ──
# API key / OAuth handled by _load_env() after PROJECT_DIR is set
_load_env() {
    local env_file="$PROJECT_DIR/.auto_claude/.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
            export ANTHROPIC_API_KEY
            echo "🔑 Using API key from .auto_claude/.env"
            return
        fi
    fi
    # No API key found — strip any inherited key to force OAuth
    unset ANTHROPIC_API_KEY
    echo "🔓 Using OAuth (no API key)"
}

# ── Defaults ──
MODEL_REVIEWER="opus"
MODEL_DEV="opus"
PROJECT_DIR=""
SPEC_PATH=""
PROMPT_TEMPLATE=""
CONTEXT_PATH=""
COMMS_DIR=""
LOG_DIR_OVERRIDE=""
MAX_ROUNDS=10
DEV_SESSION_ID=""
INITIAL_PROMPT=""
# ⚠️ KNOWN PITFALL #11: 新啟動時不帶 --initial-prompt 會導致 Round 1 嘗試
#    extract 上次 session 的輸出，若 session 不存在則立刻 exit。
#    除非確定要 resume 上次中斷的 session，否則一律帶 --initial-prompt。
#    詳見 KNOWN_PITFALLS.md #11。

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)      PROJECT_DIR="$2";       shift 2 ;;
        --spec)             SPEC_PATH="$2";          shift 2 ;;
        --prompt-template)  PROMPT_TEMPLATE="$2";    shift 2 ;;
        --context)          CONTEXT_PATH="$2";       shift 2 ;;
        --comms-dir)        COMMS_DIR="$2";          shift 2 ;;
        --log-dir)          LOG_DIR_OVERRIDE="$2";   shift 2 ;;
        --model-reviewer)   MODEL_REVIEWER="$2";     shift 2 ;;
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

# ── Auto-detect .auto_claude/ in project dir ──
AUTO_CLAUDE_DIR="$PROJECT_DIR/.auto_claude"
AGENT_DIR=""  # Set below if .auto_claude/ exists
if [[ -d "$AUTO_CLAUDE_DIR" ]]; then
    echo "📁 Found .auto_claude/ in project dir"
    AGENT_DIR="$AUTO_CLAUDE_DIR/agent"
    # Prevent macOS Spotlight from indexing (causes mds_stores CPU spike)
    touch "$AUTO_CLAUDE_DIR/.metadata_never_index" 2>/dev/null
    # Load API key if available
    _load_env
    # Ensure agent subdirectories exist
    mkdir -p "$AGENT_DIR/reviewer" "$AGENT_DIR/curator" "$AGENT_DIR/dev" "$AGENT_DIR/comms"
    PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$AGENT_DIR/reviewer/prompt.md}"
    CONTEXT_PATH="${CONTEXT_PATH:-$AGENT_DIR/context.md}"
    COMMS_DIR="${COMMS_DIR:-$AGENT_DIR/comms}"
    LOG_DIR_OVERRIDE="${LOG_DIR_OVERRIDE:-$AUTO_CLAUDE_DIR/logs}"
    SPEC_PATH="${SPEC_PATH:-$AGENT_DIR/spec.txt}"
else
    # Fallback — 向後相容舊路徑
    PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-$SCRIPT_DIR/prompts/motc_reviewer.prompt.md}"
    CONTEXT_PATH="${CONTEXT_PATH:-$SCRIPT_DIR/human_context.md}"
    COMMS_DIR="${COMMS_DIR:-$PROJECT_DIR}"
fi
if [[ -z "$SPEC_PATH" ]]; then
    echo "Error: --spec is required (or place spec.txt in .auto_claude/)" >&2; exit 1
fi
TEMPLATE_PROMPT=$(cat "$PROMPT_TEMPLATE")
SPEC_CONTENT=$(cat "$SPEC_PATH")

# ── Log setup ──
LOG_DIR="${LOG_DIR_OVERRIDE:-$SCRIPT_DIR/logs}"
mkdir -p "$LOG_DIR"

# ── Relocate lock file to project-specific LOG_DIR ──
LOCK_FILE="$LOG_DIR/.loop.pid"
if [[ -f "$LOCK_FILE" ]]; then
    _EXISTING_PID=$(cat "$LOCK_FILE")
    if kill -0 "$_EXISTING_PID" 2>/dev/null && [[ "$_EXISTING_PID" != "$$" ]]; then
        echo "❌ Loop already running for this project (PID $_EXISTING_PID). Exiting." >&2
        rm -f "$_EARLY_LOCK_FILE"
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"
rm -f "$_EARLY_LOCK_FILE"  # early lock 任務完成，改用 project-specific lock

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

# ── Session index CSV (maps rounds → .jsonl session files) ──
SESSION_CSV="$LOG_DIR/${TIMESTAMP}_sessions.csv"
echo "round,role,session_uuid,project_folder,timestamp" > "$SESSION_CSV"

# Helper: capture the session UUID created by a --print call
# Usage: touch "$ref_file" BEFORE the call, then call this AFTER
_session_ref=$(mktemp /tmp/session_ref_XXXXXX)

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
    touch "$_session_ref"  # reset for next call
}

echo "🔄 Auto_Claude Dev ↔ Reviewer Loop (v${LOOP_VERSION})"
echo "   Reviewer: $MODEL_REVIEWER | Dev: $MODEL_DEV"
echo "   Project: $PROJECT_DIR"
echo "   Max rounds: $MAX_ROUNDS"
echo "   Log: $LOOP_LOG"
echo ""

# ── Dev server management (auto-reload mode) ──
DEV_SERVER_PID=""
DEV_SERVER_PORT=$(grep "^PORT" "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d ' "' || echo "8001")
DEV_SERVER_PORT=${DEV_SERVER_PORT:-8001}

start_dev_server() {
    # Kill anything on the port
    local old_pids
    old_pids=$(lsof -ti:"$DEV_SERVER_PORT" 2>/dev/null || true)
    if [[ -n "$old_pids" ]]; then
        echo "🔪 Killing stale processes on port $DEV_SERVER_PORT: $old_pids"
        echo "$old_pids" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi

    # Start uvicorn with --reload in dev mode
    echo "🚀 Starting dev server on port $DEV_SERVER_PORT (auto-reload)..."
    (cd "$PROJECT_DIR" && python3 run.py --dev > /dev/null 2>&1) &
    DEV_SERVER_PID=$!

    # Wait for server to be ready (max 60s)
    local waited=0
    while [[ $waited -lt 60 ]]; do
        if curl -sf "http://localhost:$DEV_SERVER_PORT/health" > /dev/null 2>&1; then
            echo "   ✅ Dev server ready (${waited}s, PID $DEV_SERVER_PID, auto-reload on)"
            return 0
        fi
        sleep 1
        ((waited++))
    done
    echo "   ⚠️ Dev server did not become ready in 60s, continuing anyway"
}

# Start server before entering main loop
if [[ "${SKIP_DEV_SERVER:-}" != "1" ]]; then
    start_dev_server
else
    echo "⏭️  SKIP_DEV_SERVER=1, skipping dev server startup"
fi

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
CURATOR_PROMPT=$(cat "${AGENT_DIR:+$AGENT_DIR/curator/prompt.md}" 2>/dev/null || cat "$SCRIPT_DIR/prompts/curator.prompt.md" 2>/dev/null || echo "Compress tool call outputs to one-line logs keeping key content.")
CURATOR_INTERVAL=8
PROGRESS_FILE="${AGENT_DIR:-$PROJECT_DIR}/dev/progress.md"

run_curator() {
    local dev_output="$1"
    local round_num="$2"

    echo "🧹 Curator (sonnet) compressing context..."

    local curator_input="以下是開發者第 $round_num 輪結束時的累積輸出。請壓縮 tool call 輸出，保留關鍵內容本身。

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
            wait_for_rate_limit "Curator" "$response"
        else
            break
        fi
    done
    capture_session "curator" "$round_num"

    # Write compressed progress
    cat > "$PROGRESS_FILE" <<PROGRESS_EOF
# 開發進度（Curator 壓縮於 $(date +"%Y-%m-%d %H:%M:%S")，Round $round_num 後）

$response
PROGRESS_EOF

    echo "   Curator done. Progress saved to $PROGRESS_FILE"
    echo "$response"
}

# ── Helper: summarize reviewer memory ──
REVIEWER_MEMORY_SUMMARIZER_INTERVAL=12  # 每 N 輪壓縮一次

summarize_reviewer_memory() {
    local mem_file="${AGENT_DIR:-$COMMS_DIR}/reviewer/memory.md"
    if [[ ! -f "$mem_file" ]]; then return; fi

    local mem_size
    mem_size=$(wc -l < "$mem_file" | tr -d ' ')
    if [[ $mem_size -lt 60 ]]; then
        echo "   Reviewer memory only ${mem_size} lines, skip summarize"
        return
    fi

    echo "📝 Summarizing reviewer memory (${mem_size} lines)..."

    local mem_content
    mem_content=$(cat "$mem_file")

    local summarizer_prompt
    summarizer_prompt="你是 Reviewer Memory Summarizer。你的任務是壓縮審查記憶，保留重要資訊，刪除垃圾。

輸入是 reviewer 累積的審查記憶。請輸出壓縮版，遵守以下規則：

## 必須保留（保留原文，不改寫）
1. **每一個質疑（Reviewer 問的問題）和對應的答案（Dev 怎麼回的）** — 這是最重要的，用 Q/A 格式保留原文
2. **人類主管的指示** — 原文保留，標記 📌
3. **關鍵決策和結論** — 例如「確認 OK」「這個方案接受」
4. **未解決的問題** — 標記 ⚠️

## 必須刪除
1. \`Error: Input must be provided\` 等系統錯誤訊息 — 全刪
2. \`Prompt 已送出\` \`好 繼續\` 等無實質內容的確認訊息 — 全刪
3. \`Reviewer 連線失敗。Dev 先做這些：\` 的 fallback 訊息 — 全刪
4. 重複的任務狀態回報（同一件事報告多次，只留最終結果）
5. 重複的 Playwright 測試報告（17/17 通過重複出現，只留最新一次）

## 輸出格式
\`\`\`
# Reviewer 審查記憶（摘要版 — YYYY-MM-DD HH:MM 壓縮）

每一條是 reviewer 過去某一輪的回覆摘要。已經問過/確認過的事不要再問。

## 關鍵 Q&A 紀錄
（按時間序列出每個質疑和答案）

## 📌 人類指示摘要
（所有人類主管的指示）

## 當前狀態
（最新的任務狀態、測試結果）

## ⚠️ 未解決
（還沒解決的問題）
\`\`\`

以下是要壓縮的內容：

$mem_content"

    local response
    touch "$_session_ref"
    while true; do
        response=$(echo "$summarizer_prompt" | "$CLAUDE_BIN" \
            --print \
            --model sonnet \
            --disallowed-tools "Bash Write Edit Glob Grep WebFetch WebSearch NotebookEdit Agent" \
            - 2>&1)
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "MemorySummarizer" "$response"
        else
            break
        fi
    done
    capture_session "memory_summarizer" "${_dev_round:-0}"

    # Validate: response should be non-empty and not an error
    local resp_len=${#response}
    if [[ $resp_len -lt 50 ]] || echo "$response" | grep -qi "^Error:"; then
        echo "   ⚠️ Summarizer failed (${resp_len} chars), keeping original memory"
        return
    fi

    # Backup then replace
    cp "$mem_file" "${mem_file}.bak"
    echo "$response" > "$mem_file"
    local new_lines
    new_lines=$(wc -l < "$mem_file" | tr -d ' ')
    echo "   ✅ Reviewer memory: ${mem_size} → ${new_lines} lines (backup: reviewer_memory.md.bak)"
}

# ── Helper: run reviewer ──
run_reviewer() {
    local dev_output="$1"

    local prompt_file
    prompt_file=$(mktemp /tmp/reviewer_prompt_XXXXXX)

    # Read human's messages — both original and dev's reply
    local human_section=""
    local human_msg_file="$COMMS_DIR/human_message.md"
    local human_reply_file="$COMMS_DIR/human_reply.md"
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
    local reviewer_mem_file="${AGENT_DIR:-$COMMS_DIR}/reviewer/memory.md"
    if [[ -f "$reviewer_mem_file" ]]; then
        local mem_content
        mem_content=$(tail -100 "$reviewer_mem_file")  # 最近 100 行，防 context 爆
        reviewer_memory_section="
---

# 你過去的審查紀錄（已經問過/確認過的事不要再問！）

$mem_content
"
    fi

    # Read todo list
    local todo_section=""
    local todo_file="$COMMS_DIR/todo.md"
    if [[ -f "$todo_file" ]]; then
        local todo_content
        todo_content=$(cat "$todo_file")
        todo_section="
---

# 任務清單（Dev + Reviewer 共用，你可以更新狀態）

$todo_content
"
    fi

    # Find tools directory
    local proj_tools_dir
    proj_tools_dir="${AUTO_CLAUDE_DIR:-$(dirname "$COMMS_DIR")}/tools"

    cat > "$prompt_file" <<AGENT_EOF
你是 AI 審查者（Reviewer）。根據以下規範書與開發原則，對開發者輸出做出判斷。

# 招標規範書（精簡版）

$SPEC_CONTENT
$human_section$reviewer_memory_section$todo_section
---

# 開發者最新輸出

$dev_output

---

請根據你的角色定義和開發原則，對以上內容做出回覆。
重要規則：
1. 查看「你過去的審查紀錄」，已經問過且 Dev 已回答的問題，不要再問。往前推進，不要原地踏步。
2. 如果上面有「人類主管的原話」或「開發者對人類指示的回覆紀錄」，你的回覆第一行必須寫「📌 已讀人類指示：」加一句摘要，然後你的建議必須符合該方向。人類主管的指示優先於你自己的判斷。
3. 查看「任務清單」，從中挑下一個該做的任務指派給 Dev。

你的工具：
- 讀寫 todo：bash $(dirname "$SCRIPT_DIR")/tools/todo_rw.sh $COMMS_DIR read|write|append
- 讀寫 prompt：bash $SCRIPT_DIR/tools/prompt_rw.sh read|write|append
AGENT_EOF

    local response
    local _reviewer_timeout=600  # 10 minutes max for reviewer
    touch "$_session_ref"
    while true; do
        local _rev_output_file
        _rev_output_file=$(mktemp /tmp/auto_claude_rev.XXXXXX)
        (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
            --print \
            --model "$MODEL_REVIEWER" \
            --append-system-prompt "$TEMPLATE_PROMPT" \
            --disallowed-tools "Write Edit NotebookEdit Agent mcp__playwright__*" --allowedTools "WebFetch WebSearch Read Glob Grep mcp__entropyshield__*" \
            - < "$prompt_file" > "$_rev_output_file" 2>&1) &
        local _rev_pid=$!
        local _waited=0
        while kill -0 "$_rev_pid" 2>/dev/null; do
            sleep 5
            _waited=$((_waited + 5))
            if [[ $_waited -ge $_reviewer_timeout ]]; then
                echo "⏰ Reviewer timed out after ${_reviewer_timeout}s, killing PID $_rev_pid..."
                kill "$_rev_pid" 2>/dev/null; sleep 2; kill -9 "$_rev_pid" 2>/dev/null
                break
            fi
        done
        wait "$_rev_pid" 2>/dev/null
        response=$(cat "$_rev_output_file")
        rm -f "$_rev_output_file"
        if [[ $_waited -ge $_reviewer_timeout ]]; then
            echo "⏰ Retrying reviewer..."
            continue
        fi
        if echo "$response" | grep -qi "$RATE_LIMIT_PATTERN"; then
            wait_for_rate_limit "Reviewer" "$response"
        else
            break
        fi
    done
    capture_session "reviewer" "${_dev_round:-0}"

    rm -f "$prompt_file"
    echo "$response"
}

# ── Helper: run dev ──
# Dev output streams to a live log file so you can tail -f it
DEV_LIVE_LOG=""  # Set per-round in main loop

run_dev() {
    local message="$1"
    local _dev_output_file
    _dev_output_file=$(mktemp /tmp/auto_claude_dev_output.XXXXXX)

    touch "$_session_ref"
    while true; do
        if [[ -n "$DEV_SESSION_ID" ]]; then
            (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --resume "$DEV_SESSION_ID" \
                "$message" 2>&1) | tee "$_dev_output_file" > "${DEV_LIVE_LOG:-/dev/null}" &
            local _dev_pid=$!
            wait $_dev_pid
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
            (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
                --print \
                --model "$MODEL_DEV" \
                --session-id "$DEV_SESSION_ID" \
                "$full_message" 2>&1) | tee "$_dev_output_file" > "${DEV_LIVE_LOG:-/dev/null}" &
            local _dev_pid=$!
            wait $_dev_pid
        fi
        if grep -qi "$RATE_LIMIT_PATTERN" "$_dev_output_file" 2>/dev/null; then
            local _rl_content
            _rl_content=$(cat "$_dev_output_file")
            wait_for_rate_limit "Dev" "$_rl_content"
            > "$_dev_output_file"  # clear for retry
        else
            break
        fi
    done
    capture_session "dev" "${_dev_round:-0}"

    # Belt-and-suspenders: wait a beat for tee to flush
    sync 2>/dev/null
    sleep 1
    cat "$_dev_output_file"
    rm -f "$_dev_output_file"
}

# ── Heartbeat file ──
HEARTBEAT_FILE="$LOG_DIR/heartbeat"

# ── Main loop ──
_INJECT_DETAIL_UPGRADE=false  # Set true when Reviewer triggers detail upgrade phase
for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Round $round / $MAX_ROUNDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Heartbeat — quick way to check if loop is alive
    printf '{"pid":%d,"round":%d,"max":%d,"time":"%s","log":"%s","sessions":"%s"}\n' \
        $$ $round $MAX_ROUNDS "$(date +"%Y-%m-%d %H:%M:%S")" "$LOOP_LOG" "$SESSION_CSV" > "$HEARTBEAT_FILE"

    # ── Step A: Get dev output ──
    # ⚠️ KNOWN PITFALL #11: Round 1 的兩種模式
    #    有 --initial-prompt → 直接餵 Dev，適合新啟動（大部分場景）
    #    沒有              → extract 上次 session，適合中斷後 resume（session 必須還在）
    #    新啟動忘了帶 --initial-prompt 是最常見的啟動失敗原因。
    _dev_round=$round  # expose to run_dev for CSV capture
    if [[ $round -eq 1 ]]; then
        if [[ -n "$INITIAL_PROMPT" ]]; then
            echo "🔨 Dev: running initial prompt..."
            DEV_OUTPUT=$(run_dev "$INITIAL_PROMPT")
        else
            echo "📥 Extracting latest dev session output..."
            echo "   💡 如果這步失敗，請加 --initial-prompt 重新啟動（詳見 KNOWN_PITFALLS.md #11）"
            DEV_OUTPUT=$(python3 "$SCRIPT_DIR/extract_session.py" \
                "$PROJECT_DIR" --lines 3 --memory --format prompt 2>&1) || {
                echo "❌ Could not extract dev output. Exiting."
                echo "💡 提示：新啟動請用 --initial-prompt \"你的指令\"。只有 resume 中斷的 loop 才不需要。"
                exit 1
            }
            # Round 1 抓到的可能是上次 loop 的 reviewer 殘留，加標註
            DEV_OUTPUT="⚠️ 以下是 loop 重啟時從上次 session 擷取的輸出。可能是 Dev 或 Reviewer 的最後回應，請根據內容判斷。

${DEV_OUTPUT}"
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
        echo "⚠️ Dev output too short (${#DEV_OUTPUT} chars), retrying in 5s... (cache race condition)"
        sleep 5
        ((round--))
        continue
    fi

    DEV_CHARS=${#DEV_OUTPUT}
    echo "   Dev output: ${DEV_CHARS} chars"

    # Log dev output (Round 1 可能是上次 session 殘留)
    _output_label="Dev Output"
    if [[ $round -eq 1 && -z "${INITIAL_PROMPT:-}" ]]; then
        _output_label="Previous Session Output (may be Dev or Reviewer)"
    fi
    cat >> "$LOOP_LOG" <<EOF
## Round $round — $(date +"%H:%M:%S")

### ${_output_label} (${DEV_CHARS} chars)

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

    # Error/empty response guard
    if [[ $REVIEWER_CHARS -lt 5 ]] || echo "$REVIEWER_RESPONSE" | grep -qi "^Error:"; then
        echo "⚠️ Reviewer error or empty response (${REVIEWER_CHARS} chars), retrying once..."
        echo "   Response was: $(echo "$REVIEWER_RESPONSE" | head -1)"
        # Retry once
        REVIEWER_RESPONSE=$(run_reviewer "$DEV_OUTPUT")
        REVIEWER_CHARS=${#REVIEWER_RESPONSE}
        if [[ $REVIEWER_CHARS -lt 5 ]] || echo "$REVIEWER_RESPONSE" | grep -qi "^Error:"; then
            echo "⚠️ Reviewer retry also failed, using fallback"
            REVIEWER_RESPONSE="Reviewer 連線失敗。Dev 先做這些：用 Playwright 逐頁檢查所有按鈕是否正常、所有表單是否能送出、所有頁面是否有 JS error。修完一輪 commit。"
            REVIEWER_CHARS=${#REVIEWER_RESPONSE}
        fi
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
    REVIEWER_MEMORY_FILE="${AGENT_DIR:-$COMMS_DIR}/reviewer/memory.md"
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
    DEV_PROMPT_FILE=$(mktemp /tmp/dev_prompt_XXXXXX)

    cat > "$DEV_PROMPT_FILE" <<'DEVPROMPT_STATIC'
規則：
1. 直接動手做事，不要問問題。你是 RD，寫程式是你的工作。
2. 如果有問題只有人類能回答，把問題追加寫到 questions_for_human.md，然後繼續做你能做的部分。
3. 每輪結束時報告：做了什麼（具體檔案/功能）、下一步打算做什麼。
4. 目標：3/31 在另一台乾淨電腦上能展示給政府官員看。
5. 停止協議：如果你確認所有剩餘工作都需要人類才能繼續，且 reviewer 也同意，在回覆中輸出 <!JOB_STOP_NOTHINGS_CAN_DO!>。不要輕易用——先想想有沒有任何能做的事。
6. 不要為了讓測試通過而 hard-code 值。測試驗證正確性，不定義解法。如果測試本身有問題，回報而不是繞過。
7. 如果過程中建了暫存檔（test_*.py、debug_*.sh、tmp_*），做完後刪掉。

以下是 AI 審查者（Reviewer）的回饋：

DEVPROMPT_STATIC

    echo "$REVIEWER_RESPONSE" >> "$DEV_PROMPT_FILE"

    # ── Spec path hint for dev ──
    printf '\n規範書路徑：%s — 不確定需求細節時自己用 Read 工具去看。\n' "$SPEC_PATH" >> "$DEV_PROMPT_FILE"

    # ── Dev memory injection ──
    DEV_MEMORY_FILE="$COMMS_DIR/dev_memory.md"
    if [[ -f "$DEV_MEMORY_FILE" ]]; then
        mem_size=$(wc -c < "$DEV_MEMORY_FILE" | tr -d ' ')
        if [[ $mem_size -gt 50 ]]; then  # skip if only header/placeholder
            printf '\n---\n# 你的筆記（dev_memory.md — 只有你會看到，Reviewer 看不到）\n' >> "$DEV_PROMPT_FILE"
            printf '重要：每輪結束前把關鍵發現寫回這個檔案（用 Bash append）。\n' >> "$DEV_PROMPT_FILE"
            printf '記：已測過哪些頁面/功能、發現的 workaround、待修的技術債、API 行為觀察。\n' >> "$DEV_PROMPT_FILE"
            printf '⚠️ 注意：系統只注入此檔案的最後 80 行。新內容請 append 到檔尾，不要寫在開頭。過時的筆記可以刪掉以節省空間。\n' >> "$DEV_PROMPT_FILE"
            printf '路徑：%s\n\n' "$DEV_MEMORY_FILE" >> "$DEV_PROMPT_FILE"
            tail -80 "$DEV_MEMORY_FILE" >> "$DEV_PROMPT_FILE"  # 最近 80 行，防 context 爆
        fi
    fi

    # ── Todo list injection for dev ──
    if [[ -f "$COMMS_DIR/todo.md" ]]; then
        printf '\n---\n# 任務清單（你和 Reviewer 共用）\n做完一項用 Bash 更新狀態：echo "✅" 追加到 %s/todo.md 對應行\n\n' "$COMMS_DIR" >> "$DEV_PROMPT_FILE"
        cat "$COMMS_DIR/todo.md" >> "$DEV_PROMPT_FILE"
    fi

    # ── Human hotline: inject human_message.md if present ──
    HUMAN_MSG_FILE="$COMMS_DIR/human_message.md"
    HUMAN_REPLY_FILE="$COMMS_DIR/human_reply.md"
    if [[ -f "$HUMAN_MSG_FILE" ]]; then
        HUMAN_MSG_CONTENT=$(cat "$HUMAN_MSG_FILE")
        if [[ "$HUMAN_MSG_CONTENT" != *"目前沒有人類插話"* && -n "$HUMAN_MSG_CONTENT" ]]; then
            printf '\n\n⚠️ 人類即時插話（最高優先）：\n讀完後用 Bash 把回覆寫到 %s\n\n' "$HUMAN_REPLY_FILE" >> "$DEV_PROMPT_FILE"
            echo "$HUMAN_MSG_CONTENT" >> "$DEV_PROMPT_FILE"
            # ── 永久記錄 human message（不給任何 agent 讀，純歷史） ──
            printf '\n---\n[%s] Round %s\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$round" "$HUMAN_MSG_CONTENT" >> "$COMMS_DIR/human_message_history.log"
            echo "📝 Human message archived to human_message_history.log"

            # Loop 自動清除，dev 不需要手動清
            echo "（目前沒有人類插話）" > "$HUMAN_MSG_FILE"
        fi
    fi

    # ── Detail upgrade guide injection (triggered by Reviewer signal) ──
    UPGRADE_GUIDES_DIR="$PROJECT_DIR/detail_upgrade_guides"
    if [[ "$_INJECT_DETAIL_UPGRADE" == true ]]; then
        _guide_count=0
        if [[ -d "$UPGRADE_GUIDES_DIR" ]]; then
            for _guide_file in "$UPGRADE_GUIDES_DIR"/*.md; do
                [[ -f "$_guide_file" ]] || continue
                _guide_name=$(basename "$_guide_file" .md)
                printf '\n\n---\n# 📦 Detail Upgrade Guide: %s\n\n' "$_guide_name" >> "$DEV_PROMPT_FILE"
                cat "$_guide_file" >> "$DEV_PROMPT_FILE"
                echo "📦 Injected guide: $_guide_name"
                ((_guide_count++))
            done
        fi
        if [[ $_guide_count -eq 0 ]]; then
            printf '\n\n---\n# 📦 Detail Upgrade — 資料夾是空的，人類尚未放入升級指南。先做你能做的打磨。\n' >> "$DEV_PROMPT_FILE"
            echo "⚠️ No guides found in $UPGRADE_GUIDES_DIR"
        else
            echo "📦 Injected $_guide_count guide(s) total"
        fi
        _INJECT_DETAIL_UPGRADE=false
    fi

    printf '\n\n已知背景（不需要再問）：\n\n' >> "$DEV_PROMPT_FILE"
    if [[ -f "$CONTEXT_PATH" ]]; then
        cat "$CONTEXT_PATH" >> "$DEV_PROMPT_FILE"
    fi

    DEV_MESSAGE=$(cat "$DEV_PROMPT_FILE")
    rm -f "$DEV_PROMPT_FILE"

    DEV_LIVE_LOG="$LOG_DIR/dev_live_round${round}.log"
    > "$DEV_LIVE_LOG"  # clear
    echo "   📡 Dev live log: tail -f $DEV_LIVE_LOG"
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

    # ── Detail upgrade phase: Reviewer triggers, human controls content ──
    # Reviewer sends <!PHASE_DETAIL_UPGRADE!> (or legacy <!PHASE_UI_POLISH!>)
    # Loop injects ALL .md files in references/detail_upgrade_guides/
    # Human manages what's in that folder — add/remove files to control what dev sees
    if echo "$REVIEWER_RESPONSE" | grep -qF '<!PHASE_DETAIL_UPGRADE!>'; then
        _INJECT_DETAIL_UPGRADE=true
        echo "📦 Reviewer triggered detail upgrade phase"
    elif echo "$REVIEWER_RESPONSE" | grep -qF '<!PHASE_UI_POLISH!>'; then
        _INJECT_DETAIL_UPGRADE=true
        echo "📦 Reviewer triggered detail upgrade phase (legacy UI_POLISH signal)"
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

    # ── Step D-2: Reviewer memory summarizer — periodic compression ──
    if [[ $((round % REVIEWER_MEMORY_SUMMARIZER_INTERVAL)) -eq 0 && $round -lt $MAX_ROUNDS ]]; then
        summarize_reviewer_memory
    fi
done

echo "🏁 Loop finished ($MAX_ROUNDS rounds)."
echo "📄 Full log: $LOOP_LOG"
echo "📊 Session index: $SESSION_CSV"
rm -f "$_session_ref"
