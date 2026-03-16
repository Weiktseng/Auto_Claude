#!/bin/bash
#
# Auto_Claude Agent Trigger
# 通用 AI 決策代理觸發器
#
# Usage:
#   ./agent/trigger.sh --project-dir <path> --spec <path> [options]
#
# Examples:
#   # 交通部客服專案
#   ./agent/trigger.sh \
#     --project-dir /Users/henry/Desktop/公司/AI交通部客服 \
#     --spec /Users/henry/Desktop/公司/AI交通部客服/06.招標規範.pdf \
#     --prompt-template ./agent/prompts/motc_agent.prompt.md
#
#   # 用 stdin 傳入開發者輸出（而非自動抓取）
#   echo "剛完成了登入功能" | ./agent/trigger.sh \
#     --project-dir /path/to/project \
#     --spec /path/to/spec.pdf \
#     --stdin
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Defaults ──
MODEL="opus"
PROJECT_DIR=""
SPEC_PATH=""
PROMPT_TEMPLATE=""
NUM_MESSAGES=5
USE_STDIN=false
ADD_DIRS=""
EXTRA_ARGS=""
OUTPUT_FILE=""

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)  PROJECT_DIR="$2";       shift 2 ;;
        --spec)         SPEC_PATH="$2";          shift 2 ;;
        --prompt-template) PROMPT_TEMPLATE="$2"; shift 2 ;;
        --model)        MODEL="$2";              shift 2 ;;
        --messages)     NUM_MESSAGES="$2";       shift 2 ;;
        --stdin)        USE_STDIN=true;          shift ;;
        --add-dir)      ADD_DIRS="$2";           shift 2 ;;
        --output)       OUTPUT_FILE="$2";        shift 2 ;;
        --help|-h)
            head -20 "$0" | grep "^#" | sed 's/^# \?//'
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
    echo "Error: --project-dir is required" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: Project directory not found: $PROJECT_DIR" >&2
    exit 1
fi

if [[ -z "$SPEC_PATH" ]]; then
    echo "Error: --spec is required" >&2
    exit 1
fi

if [[ ! -f "$SPEC_PATH" ]]; then
    echo "Error: Spec file not found: $SPEC_PATH" >&2
    exit 1
fi

# Default prompt template
if [[ -z "$PROMPT_TEMPLATE" ]]; then
    PROMPT_TEMPLATE="$SCRIPT_DIR/prompts/motc_agent.prompt.md"
fi

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
    echo "Error: Prompt template not found: $PROMPT_TEMPLATE" >&2
    exit 1
fi

echo "🤖 Auto_Claude Agent Trigger"
echo "   Project:  $PROJECT_DIR"
echo "   Spec:     $SPEC_PATH"
echo "   Template: $PROMPT_TEMPLATE"
echo "   Model:    $MODEL"
echo ""

# ── Step 1: Gather developer's latest output ──
echo "📥 Extracting latest session output..."

if [[ "$USE_STDIN" == true ]]; then
    DEV_OUTPUT=$(cat)
else
    DEV_OUTPUT=$(python3 "$SCRIPT_DIR/extract_session.py" \
        "$PROJECT_DIR" \
        --lines "$NUM_MESSAGES" \
        --memory \
        --format prompt \
        2>&1) || {
        echo "Warning: Could not extract session output, continuing without it" >&2
        DEV_OUTPUT="[Could not extract session output automatically]"
    }
fi

# ── Step 2: Read template as system prompt ──
TEMPLATE_PROMPT=$(cat "$PROMPT_TEMPLATE")
SPEC_CONTENT=$(cat "$SPEC_PATH")

# ── Step 3: Build user prompt file (spec + dev output) ──
# System prompt stays short (template only), spec goes in user prompt via file to avoid ARG_MAX
PROMPT_FILE=$(mktemp /tmp/agent_prompt_XXXXXX.txt)
trap "rm -f '$PROMPT_FILE'" EXIT

cat > "$PROMPT_FILE" <<PROMPT_HEADER
你是 AI 決策代理。根據以下規範書與開發原則，對開發者輸出做出判斷。

# 招標規範書（精簡版）

PROMPT_HEADER
cat "$SPEC_PATH" >> "$PROMPT_FILE"
cat >> "$PROMPT_FILE" <<PROMPT_FOOTER

---

# 開發者最新輸出

$DEV_OUTPUT

---

請根據你的角色定義和開發原則，對以上內容做出回覆。
PROMPT_FOOTER

USER_PROMPT=$(cat "$PROMPT_FILE")

# ── Step 4: Prepare log ──
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
LOG_FILE="$LOG_DIR/${TIMESTAMP}_${MODEL}.md"

SPEC_CHARS=${#SPEC_CONTENT}
SPEC_TOKENS_EST=$((SPEC_CHARS / 3))
TEMPLATE_CHARS=${#TEMPLATE_PROMPT}
TEMPLATE_TOKENS_EST=$((TEMPLATE_CHARS / 3))
USER_CHARS=${#USER_PROMPT}
USER_TOKENS_EST=$((USER_CHARS / 3))
TOTAL_INPUT_EST=$((TEMPLATE_TOKENS_EST + USER_TOKENS_EST))

# Write log header
cat > "$LOG_FILE" <<LOG_HEADER
# Agent Trigger Log

- **Time**: $(date +"%Y-%m-%d %H:%M:%S")
- **Model**: $MODEL
- **Project**: $PROJECT_DIR
- **Spec**: $SPEC_PATH (${SPEC_CHARS} chars, ~${SPEC_TOKENS_EST} tokens)

## Token Estimates (input)

| Part | Chars | ~Tokens |
|------|-------|---------|
| System prompt (template) | ${TEMPLATE_CHARS} | ~${TEMPLATE_TOKENS_EST} |
| User prompt (dev output + memory) | ${USER_CHARS} | ~${USER_TOKENS_EST} |
| **Total input** | **$((TEMPLATE_CHARS + USER_CHARS))** | **~${TOTAL_INPUT_EST}** |

---

## System Prompt (template only, spec omitted for readability)

\`\`\`
${TEMPLATE_PROMPT}
\`\`\`

---

## User Prompt (dev output + memory)

${USER_PROMPT}

---

## Agent Response

LOG_HEADER

# ── Step 5: Call claude ──
echo "🧠 Calling Claude agent ($MODEL)..."
echo ""

CMD_ARGS=(
    --print
    --model "$MODEL"
    --append-system-prompt "$TEMPLATE_PROMPT"
    --disallowed-tools "Write Edit NotebookEdit Agent" --allowedTools "WebFetch WebSearch Read Glob Grep mcp__entropyshield__*"
)

CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"

START_TIME=$(date +%s)

AGENT_RESPONSE=$(cat "$PROMPT_FILE" | env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" "${CMD_ARGS[@]}" - 2>&1)

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
RESPONSE_CHARS=${#AGENT_RESPONSE}
RESPONSE_TOKENS_EST=$((RESPONSE_CHARS / 3))

# Append response + stats to log
cat >> "$LOG_FILE" <<LOG_RESPONSE
${AGENT_RESPONSE}

---

## Stats

| Metric | Value |
|--------|-------|
| Duration | ${DURATION}s |
| Response chars | ${RESPONSE_CHARS} |
| Response ~tokens | ~${RESPONSE_TOKENS_EST} |
| Total ~tokens (in+out) | ~$((TOTAL_INPUT_EST + RESPONSE_TOKENS_EST)) |
LOG_RESPONSE

# Print to terminal
echo "$AGENT_RESPONSE"

# Save to custom output file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$AGENT_RESPONSE" > "$OUTPUT_FILE"
    echo ""
    echo "💾 Output also saved to: $OUTPUT_FILE"
fi

echo ""
echo "✅ Agent trigger complete. (${DURATION}s)"
echo "📄 Log: $LOG_FILE"
