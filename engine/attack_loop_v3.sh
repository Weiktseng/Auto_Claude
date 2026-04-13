#!/bin/bash
#
# Auto_Claude Attack Loop v3 — GPT fire-and-forget + Claude main line
#
# GPT runs as an independent background attacker. Main pipeline is Claude-only
# and never waits for GPT. At merge time, whatever GPT has found gets folded in.
#
# Flow:
#   Background (fire-and-forget, runs entire duration):
#     GPT → reads spec + code → attacks repeatedly → writes gpt_findings.md
#     Each finding appended immediately. May still be running when main finishes.
#
#   Main pipeline (Claude-only, fast):
#     Step 0: Claude reads spec + code → attacks → writes findings
#     Step 1: Claude reads own findings → attacks for NEW bugs
#     Step 2: Merge — reads Claude findings + whatever GPT has produced so far
#             → cross-verify all → compile final report
#             → if GPT still running, mark "GPT: partial results"
#
# Wall time: ~2-3 Claude calls (~10-15 min). GPT is bonus, never blocks.
#
# Usage:
#   engine/attack_loop_v3.sh --project-dir <path> [options]
#
# Options:
#   --project-dir <path>        Target project (must be a git repo)
#   --gpt-model <name>          codex model (default: codex config default)
#   --claude-model <name>       claude model (default: opus)
#   --gpt-rounds N              How many attack rounds GPT does in background (default: 3)
#   --claude-rounds N           How many attack rounds Claude does (default: 2)
#   --spec <path>               Override spec path
#   --context <path>            Override context path
#   --attacker-prompt <path>    Override attacker prompt
#   --skip-dirty-check          Don't ask for confirmation on uncommitted changes
#   --no-gpt                    Skip GPT entirely (Claude-only attack)
#   --help | -h                 Show this help

ATTACK_VERSION="3.0"

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
GPT_ROUNDS=3
CLAUDE_ROUNDS=2
SPEC_PATH=""
CONTEXT_PATH=""
ATTACKER_PROMPT_PATH=""
SKIP_DIRTY_CHECK=false
NO_GPT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)       PROJECT_DIR="$2";           shift 2 ;;
        --gpt-model)         GPT_MODEL="$2";             shift 2 ;;
        --claude-model)      CLAUDE_MODEL="$2";          shift 2 ;;
        --gpt-rounds)        GPT_ROUNDS="$2";            shift 2 ;;
        --claude-rounds)     CLAUDE_ROUNDS="$2";         shift 2 ;;
        --spec)              SPEC_PATH="$2";             shift 2 ;;
        --context)           CONTEXT_PATH="$2";          shift 2 ;;
        --attacker-prompt)   ATTACKER_PROMPT_PATH="$2";  shift 2 ;;
        --skip-dirty-check)  SKIP_DIRTY_CHECK=true;      shift ;;
        --no-gpt)            NO_GPT=true;                shift ;;
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

if [[ "$NO_GPT" != true ]]; then
    if ! command -v "$CODEX_BIN" > /dev/null 2>&1 && [[ ! -x "$CODEX_BIN" ]]; then
        echo "Warning: codex CLI not found. Running Claude-only (--no-gpt)." >&2
        NO_GPT=true
    fi
fi

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
    echo "Uncommitted changes at lock time:"
    echo "$INITIAL_DIRTY" | head -10
    read -p "Continue? [y/N] " _confirm
    [[ "$_confirm" != "y" && "$_confirm" != "Y" ]] && { echo "Aborted."; exit 0; }
fi

# ── Workspace ──
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
LOG_DIR="$AUTO_CLAUDE_DIR/logs"
mkdir -p "$LOG_DIR"
ATTACK_WORK="/tmp/auto_claude_attack_v3_$$"
mkdir -p "$ATTACK_WORK/rounds" "$ATTACK_WORK/violations"

echo "$LOCKED_SHA" > "$LOG_DIR/attack_locked.sha"

ATTACK_LOG="$LOG_DIR/${TIMESTAMP}_attack_v3.md"
FINAL_REPORT="$LOG_DIR/${TIMESTAMP}_attack_v3_report.md"

# Shared findings files — separate for GPT (async) and Claude (main)
GPT_FINDINGS="$ATTACK_WORK/gpt_findings.md"
CLAUDE_FINDINGS="$ATTACK_WORK/claude_findings.md"
echo "# GPT Async Findings" > "$GPT_FINDINGS"
echo "" >> "$GPT_FINDINGS"
echo "# Claude Main Findings" > "$CLAUDE_FINDINGS"
echo "" >> "$CLAUDE_FINDINGS"

cat > "$ATTACK_LOG" <<EOF
# Attack Loop v3 Log (GPT fire-and-forget)

- **Start**: $(date +"%Y-%m-%d %H:%M:%S")
- **Project**: $PROJECT_DIR
- **Locked SHA**: $LOCKED_SHA ($LOCKED_BRANCH)
- **GPT model**: ${GPT_MODEL:-"(codex default)"} | rounds: $GPT_ROUNDS | mode: background fire-and-forget
- **Claude model**: $CLAUDE_MODEL | rounds: $CLAUDE_ROUNDS | mode: main pipeline
- **GPT disabled**: $NO_GPT

---

EOF

echo "🎯 Attack Loop v3 (GPT fire-and-forget) — $ATTACK_VERSION"
echo "   Project:    $PROJECT_DIR"
echo "   Locked SHA: $LOCKED_SHA ($LOCKED_BRANCH)"
if [[ "$NO_GPT" == true ]]; then
    echo "   GPT:        disabled"
else
    echo "   GPT:        background × $GPT_ROUNDS (fire-and-forget)"
fi
echo "   Claude:     main × $CLAUDE_ROUNDS + verify"
echo "   Log:        $ATTACK_LOG"
echo ""

# ── Git lock verifier ──
verify_git_lock() {
    local step="$1" model="$2"
    cd "$PROJECT_DIR"
    local current_dirty current_sha
    current_dirty=$(git status --porcelain)
    current_sha=$(git rev-parse HEAD)
    if [[ "$current_sha" != "$LOCKED_SHA" ]] || [[ "$current_dirty" != "$INITIAL_DIRTY" ]]; then
        local viol_file="$ATTACK_WORK/violations/${step}_${model}.txt"
        echo "VIOLATION: $step ($model) at $(date)" > "$viol_file"
        git diff HEAD >> "$viol_file" 2>&1
        git reset --hard "$LOCKED_SHA" > /dev/null 2>&1
        git clean -fd > /dev/null 2>&1
        echo "   VIOLATION detected ($step/$model) — reset to $LOCKED_SHA" >&2
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════
# GPT BACKGROUND WORKER (fire-and-forget)
# Runs N rounds independently. Appends to gpt_findings.md.
# Main pipeline never waits for this.
# ═══════════════════════════════════════════════════════════
GPT_BG_PID=""

if [[ "$NO_GPT" != true ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "GPT background worker launching ($GPT_ROUNDS rounds, fire-and-forget)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # GPT worker runs as a background subshell
    (
        gpt_model_flag=()
        [[ -n "$GPT_MODEL" ]] && gpt_model_flag=(-m "$GPT_MODEL")

        for ((gr=1; gr<=GPT_ROUNDS; gr++)); do
            # Read current findings (own + any Claude findings that appeared)
            gpt_prev=""
            [[ -f "$GPT_FINDINGS" ]] && gpt_prev=$(cat "$GPT_FINDINGS")
            [[ -f "$CLAUDE_FINDINGS" ]] && gpt_prev="$gpt_prev

$(cat "$CLAUDE_FINDINGS")"

            gpt_input=$(mktemp /tmp/attack_v3_gpt_r${gr}.XXXXXX)
            cat > "$gpt_input" <<GPTPROMPT
$ATTACKER_PROMPT

---

# SPEC

$SPEC_CONTENT

---

# PROJECT CONTEXT

$CONTEXT_CONTENT

---

# EXISTING FINDINGS (do NOT duplicate these)

$gpt_prev

---

Root directory: $PROJECT_DIR

Round $gr of $GPT_ROUNDS. Find ONE failure NOT already listed above.
If no new bugs found, output VERDICT: CLEAN.
**You may NOT modify any files.**
GPTPROMPT

            gpt_out="$ATTACK_WORK/rounds/gpt_bg_round${gr}.md"
            gpt_last="$ATTACK_WORK/rounds/gpt_bg_round${gr}_last.txt"

            echo "   [GPT bg R$gr] attacking..." >&2

            (cd "$PROJECT_DIR" && "$CODEX_BIN" exec \
                -s read-only \
                -C "$PROJECT_DIR" \
                ${gpt_model_flag[@]+"${gpt_model_flag[@]}"} \
                -o "$gpt_last" \
                - < "$gpt_input" > "$gpt_out" 2>&1) || true
            rm -f "$gpt_input"

            # Capture result
            gpt_result=""
            if [[ -s "$gpt_last" ]]; then
                gpt_result=$(cat "$gpt_last")
            else
                gpt_result=$(cat "$gpt_out" 2>/dev/null)
            fi

            # Append to async findings file immediately
            {
                echo ""
                echo "## GPT Background Round $gr ($(date +%H:%M:%S))"
                echo ""
                echo "$gpt_result"
                echo ""
            } >> "$GPT_FINDINGS"

            echo "   [GPT bg R$gr] done ($(echo "$gpt_result" | wc -c | tr -d ' ') chars)" >&2

            # Verify git lock after each round
            cd "$PROJECT_DIR"
            local_sha=$(git rev-parse HEAD)
            local_dirty=$(git status --porcelain)
            if [[ "$local_sha" != "$LOCKED_SHA" ]] || [[ "$local_dirty" != "$INITIAL_DIRTY" ]]; then
                echo "   [GPT bg R$gr] VIOLATION — resetting" >&2
                git reset --hard "$LOCKED_SHA" > /dev/null 2>&1
                git clean -fd > /dev/null 2>&1
            fi
        done

        echo "   [GPT bg] all $GPT_ROUNDS rounds complete" >&2
    ) &
    GPT_BG_PID=$!
    echo "   GPT background PID: $GPT_BG_PID"
    echo ""
fi

# ═══════════════════════════════════════════════════════════
# CLAUDE MAIN PIPELINE (never waits for GPT)
# ═══════════════════════════════════════════════════════════
CLAUDE_SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

for ((cr=1; cr<=CLAUDE_ROUNDS; cr++)); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Claude main · Round $cr / $CLAUDE_ROUNDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Snapshot current findings (own previous + any GPT async results so far)
    findings_so_far=""
    [[ -f "$CLAUDE_FINDINGS" ]] && findings_so_far=$(cat "$CLAUDE_FINDINGS")
    if [[ -f "$GPT_FINDINGS" ]]; then
        findings_so_far="$findings_so_far

--- GPT async findings (may be partial) ---

$(cat "$GPT_FINDINGS")"
    fi

    claude_input=$(mktemp /tmp/attack_v3_claude_r${cr}.XXXXXX)

    if [[ $cr -eq 1 ]]; then
        # First round: full context + attack
        cat > "$claude_input" <<CLAUDE_R1
$ATTACKER_PROMPT

---

# SPEC

$SPEC_CONTENT

---

# PROJECT CONTEXT

$CONTEXT_CONTENT

---

# EXISTING FINDINGS (from GPT background worker — may be empty or partial)

$findings_so_far

---

Root directory: $PROJECT_DIR

Round $cr of $CLAUDE_ROUNDS. Read code and spec. Find ONE failure.
If GPT has already found bugs (listed above), find something DIFFERENT.
If no bugs found, output VERDICT: CLEAN.
**You may NOT modify any files.**
CLAUDE_R1
    else
        # Subsequent rounds: resume session, inject updated findings
        cat > "$claude_input" <<CLAUDE_RN
Continue attacking. Here are all findings so far (yours + GPT's async results):

---

$findings_so_far

---

Find ONE additional failure NOT already on the list.
If no new bugs, output VERDICT: CLEAN.
**Do NOT modify any files.**
CLAUDE_RN
    fi

    echo "🎯 Claude [R$cr] attacking..."
    claude_out="$ATTACK_WORK/rounds/claude_main_r${cr}.md"

    if [[ $cr -eq 1 ]]; then
        (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
            --print \
            --model "$CLAUDE_MODEL" \
            --session-id "$CLAUDE_SESSION_ID" \
            --disallowed-tools "Write Edit NotebookEdit Agent" \
            --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
            - < "$claude_input" > "$claude_out" 2>&1) || true
    else
        (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
            --print \
            --model "$CLAUDE_MODEL" \
            --resume "$CLAUDE_SESSION_ID" \
            --disallowed-tools "Write Edit NotebookEdit Agent" \
            --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
            - < "$claude_input" > "$claude_out" 2>&1) || true
    fi
    rm -f "$claude_input"

    claude_result=$(cat "$claude_out" 2>/dev/null)
    echo "   ✓ Claude R$cr done ($(echo "$claude_result" | wc -c | tr -d ' ') chars)"

    verify_git_lock "claude_r$cr" "claude" || true

    # Append to Claude findings
    {
        echo ""
        echo "## Claude Main Round $cr ($(date +%H:%M:%S))"
        echo ""
        echo "$claude_result"
        echo ""
    } >> "$CLAUDE_FINDINGS"

    {
        echo "## Claude Main Round $cr"
        echo ""
        echo "$claude_result"
        echo ""
        echo "---"
        echo ""
    } >> "$ATTACK_LOG"
done

# ═══════════════════════════════════════════════════════════
# MERGE + CROSS-VERIFY
# Check if GPT is still running. Collect whatever it has.
# ═══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cross-verify + merge"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

GPT_STATUS="disabled"
if [[ -n "$GPT_BG_PID" ]]; then
    if kill -0 "$GPT_BG_PID" 2>/dev/null; then
        GPT_STATUS="still running (partial results)"
        echo "   GPT background worker still running (PID $GPT_BG_PID) — using partial results"
    else
        GPT_STATUS="completed"
        echo "   GPT background worker finished"
    fi
fi

# Collect all findings
ALL_FINDINGS=""
[[ -f "$CLAUDE_FINDINGS" ]] && ALL_FINDINGS=$(cat "$CLAUDE_FINDINGS")
if [[ -f "$GPT_FINDINGS" ]] && [[ $(wc -c < "$GPT_FINDINGS" | tr -d ' ') -gt 30 ]]; then
    ALL_FINDINGS="$ALL_FINDINGS

---

# GPT Background Findings ($GPT_STATUS)

$(cat "$GPT_FINDINGS")"
fi

{
    echo "## GPT Background Findings at merge time ($GPT_STATUS)"
    echo ""
    cat "$GPT_FINDINGS" 2>/dev/null
    echo ""
    echo "---"
    echo ""
} >> "$ATTACK_LOG"

# Cross-verify
verify_input=$(mktemp /tmp/attack_v3_verify.XXXXXX)
cat > "$verify_input" <<VERIFY
You are compiling the final attack report. Two attackers worked in parallel:
- Claude (main pipeline, $CLAUDE_ROUNDS rounds)
- GPT (background, $GPT_STATUS)

Below are all findings. Your tasks:

1. **Verify each ATTACK finding**: use Read / Grep / Bash to check if the file, line, and scenario are real. Mark CONFIRMED or HALLUCINATED.
2. **Dedup**: same bug from both → list once, note "corroborated by"
3. **Compile the final report**:

# Attack Report

## CONFIRMED (N bugs)
### #1: <scenario>
- **Location**: file:line
- **Severity**: critical | high | medium | low
- **Category**: spec-mismatch | silent-corruption | state-leak | boundary | concurrency
- **Found by**: GPT bg R1 / Claude R2 / etc
- **Reproduce**: <steps>
- **Expected**: <value>
- **Actual**: <value>
- **Evidence**: <your verification>

## HALLUCINATED (N claims)
(same format, add why it's wrong)

## Summary
- Claude rounds: $CLAUDE_ROUNDS
- GPT rounds: $GPT_STATUS
- Confirmed: N
- Hallucinated: N

**Do not invent new bugs. Do not modify any files.**

---

# SPEC

$SPEC_CONTENT

---

# ALL FINDINGS

$ALL_FINDINGS

---

Root directory: $PROJECT_DIR
VERIFY

echo "🔍 Cross-verifying all findings..."
verify_out="$ATTACK_WORK/rounds/verify_final.md"
(cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --disallowed-tools "Write Edit NotebookEdit Agent" \
    --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
    - < "$verify_input" > "$verify_out" 2>&1) || true
rm -f "$verify_input"

VERIFY_RESULT=$(cat "$verify_out" 2>/dev/null)
echo "   ✓ Cross-verify done"

verify_git_lock "verify" "claude" || true

{
    echo "## Cross-verify + Final Report"
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
# Attack Report v3 — $TIMESTAMP

- **Locked SHA**: $LOCKED_SHA
- **Branch**: $LOCKED_BRANCH
- **Project**: $PROJECT_DIR
- **Claude**: $CLAUDE_ROUNDS main rounds + 1 verify
- **GPT**: $GPT_STATUS (background, $GPT_ROUNDS rounds max)
- **Git lock violations**: $VIOL_COUNT

---

$VERIFY_RESULT

---

## Raw data

- Attack log: \`$ATTACK_LOG\`
- Claude findings: \`$CLAUDE_FINDINGS\` (in /tmp)
- GPT findings: \`$GPT_FINDINGS\` (in /tmp)
FINAL

echo ""
echo "🏁 Attack loop v3 complete."
echo "   Final report: ${FINAL_REPORT}"
echo "   Raw log:      $ATTACK_LOG"
echo "   Violations:   $VIOL_COUNT"
echo "   GPT status:   $GPT_STATUS"
echo ""
echo "開 ${FINAL_REPORT}，CONFIRMED 先看。"

# If GPT is still running, let the user know
if [[ -n "$GPT_BG_PID" ]] && kill -0 "$GPT_BG_PID" 2>/dev/null; then
    echo ""
    echo "NOTE: GPT background worker (PID $GPT_BG_PID) is still running."
    echo "   Its findings so far are included in the report above."
    echo "   When it finishes, updated findings will be in: $GPT_FINDINGS"
    echo "   To wait: wait $GPT_BG_PID"
    echo "   To kill: kill $GPT_BG_PID"
fi
