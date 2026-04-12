#!/bin/bash
#
# Auto_Claude Attack Loop v2 — pipelined adversarial testing
#
# GPT and Claude attack a locked codebase in a relay pattern with session resume.
# Much faster than v1 (4 wall-time calls instead of 9).
#
# Flow:
#   Step 0 (parallel):
#     GPT  → reads spec + code + prompt → attacks → writes findings.md
#     Claude → reads spec + code + prompt → returns OK (preloads context, no attack)
#   Step 1: Claude resumes → reads findings.md → attacks for NEW bugs → appends findings.md
#   Step 2: GPT resumes    → reads findings.md → attacks for NEW bugs → appends findings.md
#   Step 3: Cross-verify   → one model reads full findings.md → CONFIRMED / HALLUCINATED
#
# Wall time: ~3 sequential calls (step 0 is parallel, so free)
#
# Usage:
#   engine/attack_loop_v2.sh --project-dir <path> [options]
#
# Options:
#   --project-dir <path>        Target project (must be a git repo)
#   --gpt-model <name>          codex model (default: codex config default)
#   --claude-model <name>       claude model (default: opus)
#   --spec <path>               Override spec path
#   --context <path>            Override context path
#   --attacker-prompt <path>    Override attacker prompt
#   --skip-dirty-check          Don't ask for confirmation on uncommitted changes
#   --help | -h                 Show this help

ATTACK_VERSION="2.0"

set -uo pipefail
trap 'rm -rf "${ATTACK_WORK:-/tmp/__never__}" 2>/dev/null' EXIT
trap 'rm -rf "${ATTACK_WORK:-/tmp/__never__}" 2>/dev/null; kill 0 2>/dev/null' SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"
CODEX_BIN="$(which codex 2>/dev/null || echo /Users/henry/.npm-global/bin/codex)"

# ── Defaults ──
PROJECT_DIR=""
GPT_MODEL=""
CLAUDE_MODEL="opus"
SPEC_PATH=""
CONTEXT_PATH=""
ATTACKER_PROMPT_PATH=""
SKIP_DIRTY_CHECK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)       PROJECT_DIR="$2";           shift 2 ;;
        --gpt-model)         GPT_MODEL="$2";             shift 2 ;;
        --claude-model)      CLAUDE_MODEL="$2";          shift 2 ;;
        --spec)              SPEC_PATH="$2";             shift 2 ;;
        --context)           CONTEXT_PATH="$2";          shift 2 ;;
        --attacker-prompt)   ATTACKER_PROMPT_PATH="$2";  shift 2 ;;
        --skip-dirty-check)  SKIP_DIRTY_CHECK=true;      shift ;;
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

for bin_name in "$CODEX_BIN" "$CLAUDE_BIN"; do
    if ! command -v "$bin_name" > /dev/null 2>&1 && [[ ! -x "$bin_name" ]]; then
        echo "Error: $bin_name not found" >&2; exit 1
    fi
done

# ── Resolve paths ──
AUTO_CLAUDE_DIR="$PROJECT_DIR/.auto_claude"
AGENT_DIR="$AUTO_CLAUDE_DIR/agent"
[[ ! -d "$AUTO_CLAUDE_DIR" ]] && { echo "Error: $AUTO_CLAUDE_DIR not found" >&2; exit 1; }

SPEC_PATH="${SPEC_PATH:-$AGENT_DIR/spec.txt}"
CONTEXT_PATH="${CONTEXT_PATH:-$AGENT_DIR/context.md}"

if [[ -z "$ATTACKER_PROMPT_PATH" ]]; then
    if [[ -f "$AGENT_DIR/attacker/prompt.md" ]]; then
        ATTACKER_PROMPT_PATH="$AGENT_DIR/attacker/prompt.md"
    elif [[ -f "$SCRIPT_DIR/../templates/agent/attacker/prompt.md" ]]; then
        ATTACKER_PROMPT_PATH="$SCRIPT_DIR/../templates/agent/attacker/prompt.md"
    else
        echo "Error: attacker prompt not found" >&2; exit 1
    fi
fi

[[ ! -f "$SPEC_PATH" ]] && { echo "Error: spec not found at $SPEC_PATH" >&2; exit 1; }
ATTACKER_PROMPT=$(cat "$ATTACKER_PROMPT_PATH")
SPEC_CONTENT=$(cat "$SPEC_PATH")
CONTEXT_CONTENT=""
[[ -f "$CONTEXT_PATH" ]] && CONTEXT_CONTENT=$(cat "$CONTEXT_PATH")

# ── Git lock ──
cd "$PROJECT_DIR"
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: $PROJECT_DIR is not a git repo" >&2; exit 1
fi
LOCKED_SHA=$(git rev-parse HEAD)
LOCKED_BRANCH=$(git rev-parse --abbrev-ref HEAD)
INITIAL_DIRTY=$(git status --porcelain)

if [[ -n "$INITIAL_DIRTY" ]] && [[ "$SKIP_DIRTY_CHECK" != true ]]; then
    echo "⚠️  Uncommitted changes at lock time:"
    echo "$INITIAL_DIRTY" | head -10
    read -p "Continue? [y/N] " _confirm
    [[ "$_confirm" != "y" && "$_confirm" != "Y" ]] && { echo "Aborted."; exit 0; }
fi

# ── Workspace ──
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
LOG_DIR="$AUTO_CLAUDE_DIR/logs"
mkdir -p "$LOG_DIR"
ATTACK_WORK="/tmp/auto_claude_attack_v2_$$"
mkdir -p "$ATTACK_WORK/rounds" "$ATTACK_WORK/violations"

echo "$LOCKED_SHA" > "$LOG_DIR/attack_locked.sha"

ATTACK_LOG="$LOG_DIR/${TIMESTAMP}_attack_v2.md"
FINAL_REPORT="$LOG_DIR/${TIMESTAMP}_attack_v2_report.md"
FINDINGS_FILE="$ATTACK_WORK/findings.md"

# Initialize shared findings file
echo "# Attack Findings (shared bug list)" > "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"
echo "Each attacker appends new bugs here. Read before attacking — do NOT duplicate." >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"

cat > "$ATTACK_LOG" <<EOF
# Attack Loop v2 Log (pipelined)

- **Start**: $(date +"%Y-%m-%d %H:%M:%S")
- **Project**: $PROJECT_DIR
- **Locked SHA**: $LOCKED_SHA ($LOCKED_BRANCH)
- **GPT model**: ${GPT_MODEL:-"(codex default)"}
- **Claude model**: $CLAUDE_MODEL
- **Flow**: GPT attack ‖ Claude preload → Claude attack → GPT attack → cross-verify

---

EOF

echo "🎯 Attack Loop v2 (pipelined) — $ATTACK_VERSION"
echo "   Project:    $PROJECT_DIR"
echo "   Locked SHA: $LOCKED_SHA ($LOCKED_BRANCH)"
echo "   Flow:       GPT attack ‖ Claude preload → Claude relay → GPT relay → verify"
echo "   Log:        $ATTACK_LOG"
echo ""

# ── Git lock verifier (same as v1) ──
verify_git_lock() {
    local step="$1" model="$2"
    cd "$PROJECT_DIR"
    local current_dirty
    current_dirty=$(git status --porcelain)
    local current_sha
    current_sha=$(git rev-parse HEAD)
    if [[ "$current_sha" != "$LOCKED_SHA" ]] || [[ "$current_dirty" != "$INITIAL_DIRTY" ]]; then
        local viol_file="$ATTACK_WORK/violations/${step}_${model}.txt"
        echo "🚨 GIT LOCK VIOLATION after $step ($model)" >&2
        git diff HEAD > "$viol_file" 2>&1
        git reset --hard "$LOCKED_SHA" > /dev/null 2>&1
        git clean -fd > /dev/null 2>&1
        {
            echo "### 🚨 Violation — $step ($model)"
            echo '```'
            head -100 "$viol_file"
            echo '```'
            echo "---"
        } >> "$ATTACK_LOG"
        return 1
    fi
    return 0
}

# ── Session IDs for resume ──
GPT_SESSION_ID=""
CLAUDE_SESSION_ID=""

# ═══════════════════════════════════════════════════════════
# STEP 0: GPT attacks + Claude preloads (PARALLEL)
# ═══════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 0 · GPT attacks ‖ Claude preloads"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── GPT: read + attack in one shot ──
GPT_R1_INPUT=$(mktemp /tmp/attack_v2_gpt0.XXXXXX)
cat > "$GPT_R1_INPUT" <<GPTINPUT
$ATTACKER_PROMPT

---

# SPEC

$SPEC_CONTENT

---

# PROJECT CONTEXT

$CONTEXT_CONTENT

---

# SHARED FINDINGS (empty — you are the first attacker)

(none yet)

---

Root directory: $PROJECT_DIR

Read code and spec. Find ONE failure. Output VERDICT: ATTACK or CLEAN.
**You may NOT modify any files.**
GPTINPUT

GPT_R1_OUT="$ATTACK_WORK/rounds/step0_gpt.md"
GPT_R1_LAST="$ATTACK_WORK/rounds/step0_gpt_last.txt"

gpt_model_flag=()
[[ -n "$GPT_MODEL" ]] && gpt_model_flag=(-m "$GPT_MODEL")

echo "🎯 GPT [Step 0] reading + attacking..."
(cd "$PROJECT_DIR" && "$CODEX_BIN" exec \
    -s read-only \
    -C "$PROJECT_DIR" \
    ${gpt_model_flag[@]+"${gpt_model_flag[@]}"} \
    -o "$GPT_R1_LAST" \
    - < "$GPT_R1_INPUT" > "$GPT_R1_OUT" 2>&1) &
GPT_PID=$!

# ── Claude: read + preload context only (no attack) ──
CLAUDE_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
CLAUDE_PRELOAD_INPUT=$(mktemp /tmp/attack_v2_claude_preload.XXXXXX)
cat > "$CLAUDE_PRELOAD_INPUT" <<PRELOAD
$ATTACKER_PROMPT

---

# SPEC

$SPEC_CONTENT

---

# PROJECT CONTEXT

$CONTEXT_CONTENT

---

# YOUR TASK FOR THIS ROUND

**This is a PRELOAD round. Do NOT attack yet.**

Read the spec and the entire codebase thoroughly. Use Read / Grep / Glob to understand:
1. All endpoints and their request/response schemas
2. All data flows and state management
3. The test suite (if any)

When done, output exactly:

PRELOAD COMPLETE
Files read: <list the key files you read>
Attack surface notes: <3-5 bullet points of areas you plan to probe in the next round>

You will be resumed in the next round with the other attacker's findings. At that point, attack for bugs NOT on their list.

Root directory: $PROJECT_DIR
PRELOAD

echo "🔍 Claude [Step 0] preloading context..."
CLAUDE_PRELOAD_OUT="$ATTACK_WORK/rounds/step0_claude_preload.md"
(cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --session-id "$CLAUDE_SESSION_ID" \
    --disallowed-tools "Write Edit NotebookEdit Agent" \
    --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
    - < "$CLAUDE_PRELOAD_INPUT" > "$CLAUDE_PRELOAD_OUT" 2>&1) &
CLAUDE_PID=$!

# Wait for BOTH to finish (do NOT rm input files before wait — subshells need them)
echo "   ⏳ Waiting for parallel step 0..."
wait $GPT_PID 2>/dev/null || true
wait $CLAUDE_PID 2>/dev/null || true
rm -f "$GPT_R1_INPUT" "$CLAUDE_PRELOAD_INPUT"

# Capture GPT output
GPT_R1_RESULT=""
if [[ -s "$GPT_R1_LAST" ]]; then
    GPT_R1_RESULT=$(cat "$GPT_R1_LAST")
else
    GPT_R1_RESULT=$(cat "$GPT_R1_OUT" 2>/dev/null)
fi

echo "   ✓ GPT Step 0 done ($(echo "$GPT_R1_RESULT" | wc -c | tr -d ' ') chars)"
echo "   ✓ Claude preload done"

verify_git_lock "step0" "gpt" || true
verify_git_lock "step0" "claude" || true

# Append GPT's findings to shared list
echo "" >> "$FINDINGS_FILE"
echo "## GPT — Step 0 (first attacker)" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"
echo "$GPT_R1_RESULT" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"

{
    echo "## Step 0 · GPT attack (parallel with Claude preload)"
    echo ""
    echo "$GPT_R1_RESULT"
    echo ""
    echo "---"
    echo ""
    echo "## Step 0 · Claude preload"
    echo ""
    cat "$CLAUDE_PRELOAD_OUT" 2>/dev/null
    echo ""
    echo "---"
    echo ""
} >> "$ATTACK_LOG"

# ═══════════════════════════════════════════════════════════
# STEP 1: Claude resumes → reads findings → attacks for NEW bugs
# ═══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1 · Claude attacks (resume, reads GPT findings)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FINDINGS_SNAPSHOT=$(cat "$FINDINGS_FILE")

CLAUDE_R1_INPUT=$(mktemp /tmp/attack_v2_claude_r1.XXXXXX)
cat > "$CLAUDE_R1_INPUT" <<CLAUDE_ATTACK
Now it's your turn to attack. The other attacker (GPT) has already run. Here are their findings:

---

$FINDINGS_SNAPSHOT

---

**Your task**: Find ONE failure that is NOT already on the list above.
If everything the other attacker found is correct and you cannot find any additional bugs, output VERDICT: CLEAN.

Rules:
- Do NOT duplicate findings already on the list
- Do NOT modify any files
- Output in the exact VERDICT: ATTACK / CLEAN format from your prompt
CLAUDE_ATTACK

echo "🎯 Claude [Step 1] attacking (resumed session)..."
CLAUDE_R1_OUT="$ATTACK_WORK/rounds/step1_claude.md"
(cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --resume "$CLAUDE_SESSION_ID" \
    --disallowed-tools "Write Edit NotebookEdit Agent" \
    --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
    - < "$CLAUDE_R1_INPUT" > "$CLAUDE_R1_OUT" 2>&1) || true
rm -f "$CLAUDE_R1_INPUT"

CLAUDE_R1_RESULT=$(cat "$CLAUDE_R1_OUT" 2>/dev/null)
echo "   ✓ Claude Step 1 done ($(echo "$CLAUDE_R1_RESULT" | wc -c | tr -d ' ') chars)"

verify_git_lock "step1" "claude" || true

# Append to shared findings
echo "" >> "$FINDINGS_FILE"
echo "## Claude — Step 1 (relay)" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"
echo "$CLAUDE_R1_RESULT" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"

{
    echo "## Step 1 · Claude attack (resumed)"
    echo ""
    echo "$CLAUDE_R1_RESULT"
    echo ""
    echo "---"
    echo ""
} >> "$ATTACK_LOG"

# ═══════════════════════════════════════════════════════════
# STEP 2: GPT resumes → reads updated findings → attacks for NEW bugs
# ═══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2 · GPT attacks (reads Claude's additions)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FINDINGS_SNAPSHOT=$(cat "$FINDINGS_FILE")

GPT_R2_INPUT=$(mktemp /tmp/attack_v2_gpt_r2.XXXXXX)
cat > "$GPT_R2_INPUT" <<GPTRELAY
You already attacked this codebase once. Now the other attacker (Claude) has also attacked. Here is the full findings list so far:

---

$FINDINGS_SNAPSHOT

---

Find ONE additional failure NOT already on the list. If you cannot find anything new, output VERDICT: CLEAN.

Rules:
- Do NOT duplicate findings already listed
- Do NOT modify any files
- Output in VERDICT: ATTACK / CLEAN format
GPTRELAY

echo "🎯 GPT [Step 2] attacking (reads full findings)..."
GPT_R2_OUT="$ATTACK_WORK/rounds/step2_gpt.md"
GPT_R2_LAST="$ATTACK_WORK/rounds/step2_gpt_last.txt"
(cd "$PROJECT_DIR" && "$CODEX_BIN" exec \
    -s read-only \
    -C "$PROJECT_DIR" \
    ${gpt_model_flag[@]+"${gpt_model_flag[@]}"} \
    -o "$GPT_R2_LAST" \
    - < "$GPT_R2_INPUT" > "$GPT_R2_OUT" 2>&1) || true
rm -f "$GPT_R2_INPUT"

GPT_R2_RESULT=""
if [[ -s "$GPT_R2_LAST" ]]; then
    GPT_R2_RESULT=$(cat "$GPT_R2_LAST")
else
    GPT_R2_RESULT=$(cat "$GPT_R2_OUT" 2>/dev/null)
fi
echo "   ✓ GPT Step 2 done ($(echo "$GPT_R2_RESULT" | wc -c | tr -d ' ') chars)"

verify_git_lock "step2" "gpt" || true

echo "" >> "$FINDINGS_FILE"
echo "## GPT — Step 2 (relay)" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"
echo "$GPT_R2_RESULT" >> "$FINDINGS_FILE"
echo "" >> "$FINDINGS_FILE"

{
    echo "## Step 2 · GPT attack (relay)"
    echo ""
    echo "$GPT_R2_RESULT"
    echo ""
    echo "---"
    echo ""
} >> "$ATTACK_LOG"

# ═══════════════════════════════════════════════════════════
# STEP 3: Cross-verify (Claude reads ALL findings, verifies each)
# ═══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3 · Cross-verify + final report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FINDINGS_SNAPSHOT=$(cat "$FINDINGS_FILE")

VERIFY_INPUT=$(mktemp /tmp/attack_v2_verify.XXXXXX)
cat > "$VERIFY_INPUT" <<VERIFY
You are compiling the final attack report. Two attackers (GPT and Claude) took turns finding bugs in relay.

Below is the shared findings file with all their outputs. Your tasks:

1. **Verify each ATTACK finding**: use Read / Grep / Bash to check if the file, line, and scenario are real. Mark CONFIRMED or HALLUCINATED.
2. **Dedup**: if both found the same bug, list once with "corroborated by: GPT Step 0, Claude Step 1"
3. **Compile the final report** in this format:

# Attack Report

## CONFIRMED (N bugs)
### #1: <scenario>
- **Location**: file:line
- **Severity**: critical | high | medium | low
- **Category**: spec-mismatch | silent-corruption | state-leak | boundary | concurrency
- **Found by**: <who found it>
- **Reproduce**: <steps>
- **Expected**: <value>
- **Actual**: <value>
- **Evidence**: <your verification output>

## HALLUCINATED (N claims)
(same format, add why it's wrong)

## Summary
- Confirmed: N
- Hallucinated: N
- Attack rounds: 3 (GPT×1 + Claude×1 + GPT×1) + 1 verify

**Do not invent new bugs. Do not modify any files.**

---

# SPEC

$SPEC_CONTENT

---

# SHARED FINDINGS

$FINDINGS_SNAPSHOT

---

Root directory: $PROJECT_DIR
VERIFY

echo "🔍 [Step 3] Cross-verify + compile report..."
VERIFY_OUT="$ATTACK_WORK/rounds/step3_verify.md"
(cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --disallowed-tools "Write Edit NotebookEdit Agent" \
    --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
    - < "$VERIFY_INPUT" > "$VERIFY_OUT" 2>&1) || true
rm -f "$VERIFY_INPUT"

VERIFY_RESULT=$(cat "$VERIFY_OUT" 2>/dev/null)
echo "   ✓ Cross-verify done"

verify_git_lock "step3" "claude" || true

{
    echo "## Step 3 · Cross-verify + final report"
    echo ""
    echo "$VERIFY_RESULT"
    echo ""
    echo "---"
} >> "$ATTACK_LOG"

# ═══════════════════════════════════════════════════════════
# Write final report
# ═══════════════════════════════════════════════════════════
VIOL_COUNT=$(ls -1 "$ATTACK_WORK/violations" 2>/dev/null | wc -l | tr -d ' ')

cat > "$FINAL_REPORT" <<FINAL
# Attack Report v2 — $TIMESTAMP

- **Locked SHA**: $LOCKED_SHA
- **Branch**: $LOCKED_BRANCH
- **Project**: $PROJECT_DIR
- **Flow**: GPT attack ‖ Claude preload → Claude relay → GPT relay → cross-verify
- **Git lock violations**: $VIOL_COUNT

---

$VERIFY_RESULT

---

## Raw data

- Attack log: \`$ATTACK_LOG\`
- Shared findings: \`$FINDINGS_FILE\` (in /tmp, cleaned on exit)

## How to use

1. CONFIRMED: open the file at the given line, verify the bug exists
2. HALLUCINATED: note what the AI invented — useful for tuning prompts
3. If violations > 0: an attacker tried to modify files despite read-only rules
FINAL

echo ""
echo "🏁 Attack loop v2 complete."
echo "   Final report: ${FINAL_REPORT}"
echo "   Raw log:      $ATTACK_LOG"
echo "   Violations:   $VIOL_COUNT"
echo ""
echo "開 ${FINAL_REPORT}，CONFIRMED 先看。"
