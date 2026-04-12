#!/bin/bash
#
# Auto_Claude Attack Loop — adversarial testing
#
# GPT-5.3 (codex) + Claude Opus 4.6 cross-fire a locked codebase for bugs.
# Git SHA is locked at start; any attempted code mutation is logged and reverted.
# Produces a human-readable bug list for manual blind-find verification.
#
# Flow (default 3×3 = 9 rounds total):
#   Phase 1: GPT-5.3 attacks N rounds     (codex exec -s read-only, OS-level sandbox)
#   Phase 2: Claude  attacks N rounds     (--print, sees Phase 1 findings, must pick a different category)
#   Phase 3: Cross-verify × N             (each side rechecks the other's findings for hallucination)
#
# Usage:
#   engine/attack_loop.sh --project-dir <path> [options]
#
# Options:
#   --project-dir <path>        Target project (must be a git repo)
#   --rounds-per-phase N        Rounds per phase (default 3 → 9 total)
#   --gpt-model <name>          codex model (default: whatever codex config has set)
#   --claude-model <name>       claude model (default: opus)
#   --spec <path>               Override spec path (default: <proj>/.auto_claude/agent/spec.txt)
#   --context <path>            Override context path
#   --attacker-prompt <path>    Override attacker prompt (default: <proj>/.auto_claude/agent/attacker/prompt.md
#                                                         or templates/agent/attacker/prompt.md)
#   --skip-dirty-check          Don't ask for confirmation on uncommitted changes
#   --help | -h                 Show this help

ATTACK_VERSION="1.0"

set -uo pipefail
# EXIT trap only cleans up temp files (safe for --help / early exit).
# Signal traps additionally kill the process group so child claude/codex don't orphan.
trap 'rm -rf "${ATTACK_WORK:-/tmp/__never__}" 2>/dev/null' EXIT
trap 'rm -rf "${ATTACK_WORK:-/tmp/__never__}" 2>/dev/null; kill 0 2>/dev/null' SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="$(which claude 2>/dev/null || echo /Users/henry/.npm-global/bin/claude)"
CODEX_BIN="$(which codex 2>/dev/null || echo /Users/henry/.npm-global/bin/codex)"

# ── Defaults ──
PROJECT_DIR=""
ROUNDS_PER_PHASE=3
GPT_MODEL=""              # empty = let codex use its configured default
CLAUDE_MODEL="opus"
SPEC_PATH=""
CONTEXT_PATH=""
ATTACKER_PROMPT_PATH=""
SKIP_DIRTY_CHECK=false

# ── Parse args ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-dir)       PROJECT_DIR="$2";           shift 2 ;;
        --rounds-per-phase)  ROUNDS_PER_PHASE="$2";      shift 2 ;;
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

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"  # absolute

if ! command -v "$CODEX_BIN" > /dev/null 2>&1 && [[ ! -x "$CODEX_BIN" ]]; then
    echo "Error: codex CLI not found. Install with: npm install -g @openai/codex" >&2
    exit 1
fi
if ! command -v "$CLAUDE_BIN" > /dev/null 2>&1 && [[ ! -x "$CLAUDE_BIN" ]]; then
    echo "Error: claude CLI not found" >&2
    exit 1
fi

# ── Resolve .auto_claude paths ──
AUTO_CLAUDE_DIR="$PROJECT_DIR/.auto_claude"
AGENT_DIR="$AUTO_CLAUDE_DIR/agent"

if [[ ! -d "$AUTO_CLAUDE_DIR" ]]; then
    echo "Error: $AUTO_CLAUDE_DIR not found. Attack loop requires .auto_claude/ structure." >&2
    exit 1
fi

SPEC_PATH="${SPEC_PATH:-$AGENT_DIR/spec.txt}"
CONTEXT_PATH="${CONTEXT_PATH:-$AGENT_DIR/context.md}"

if [[ -z "$ATTACKER_PROMPT_PATH" ]]; then
    if [[ -f "$AGENT_DIR/attacker/prompt.md" ]]; then
        ATTACKER_PROMPT_PATH="$AGENT_DIR/attacker/prompt.md"
    elif [[ -f "$SCRIPT_DIR/../templates/agent/attacker/prompt.md" ]]; then
        ATTACKER_PROMPT_PATH="$SCRIPT_DIR/../templates/agent/attacker/prompt.md"
    else
        echo "Error: attacker prompt not found." >&2
        echo "  Looked at: $AGENT_DIR/attacker/prompt.md" >&2
        echo "  Looked at: $SCRIPT_DIR/../templates/agent/attacker/prompt.md" >&2
        exit 1
    fi
fi

[[ ! -f "$SPEC_PATH" ]] && { echo "Error: spec not found at $SPEC_PATH" >&2; exit 1; }
[[ ! -f "$ATTACKER_PROMPT_PATH" ]] && { echo "Error: attacker prompt not found at $ATTACKER_PROMPT_PATH" >&2; exit 1; }

ATTACKER_PROMPT=$(cat "$ATTACKER_PROMPT_PATH")
SPEC_CONTENT=$(cat "$SPEC_PATH")
CONTEXT_CONTENT=""
[[ -f "$CONTEXT_PATH" ]] && CONTEXT_CONTENT=$(cat "$CONTEXT_PATH")

# ── Git lock ──
cd "$PROJECT_DIR"
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: $PROJECT_DIR is not a git repo. Attack loop requires git for version lock." >&2
    exit 1
fi

LOCKED_SHA=$(git rev-parse HEAD)
LOCKED_BRANCH=$(git rev-parse --abbrev-ref HEAD)
INITIAL_DIRTY=$(git status --porcelain)

if [[ -n "$INITIAL_DIRTY" ]] && [[ "$SKIP_DIRTY_CHECK" != true ]]; then
    echo "⚠️  Project has uncommitted changes at lock time:"
    echo "$INITIAL_DIRTY" | head -10
    local_count=$(echo "$INITIAL_DIRTY" | wc -l | tr -d ' ')
    [[ $local_count -gt 10 ]] && echo "   ... and $((local_count - 10)) more"
    echo ""
    echo "These will be treated as part of the locked baseline."
    echo "For a clean attack state, commit or stash before running."
    echo ""
    read -p "Continue anyway? [y/N] " _confirm
    [[ "$_confirm" != "y" && "$_confirm" != "Y" ]] && { echo "Aborted."; exit 0; }
fi

# ── Workspace setup ──
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")_$$
LOG_DIR="$AUTO_CLAUDE_DIR/logs"
mkdir -p "$LOG_DIR"

# Attack outputs live OUTSIDE the project so any attacker writes can't touch them
ATTACK_WORK="/tmp/auto_claude_attack_$$"
mkdir -p "$ATTACK_WORK/rounds" "$ATTACK_WORK/violations"

echo "$LOCKED_SHA" > "$LOG_DIR/attack_locked.sha"
echo "$LOCKED_BRANCH" >> "$LOG_DIR/attack_locked.sha"

ATTACK_LOG="$LOG_DIR/${TIMESTAMP}_attack.md"
FINAL_REPORT="$LOG_DIR/${TIMESTAMP}_attack_report.md"

cat > "$ATTACK_LOG" <<EOF
# Attack Loop Log

- **Start**: $(date +"%Y-%m-%d %H:%M:%S")
- **Project**: $PROJECT_DIR
- **Locked SHA**: $LOCKED_SHA
- **Branch**: $LOCKED_BRANCH
- **Rounds per phase**: $ROUNDS_PER_PHASE
- **GPT model**: ${GPT_MODEL:-"(codex default)"}
- **Claude model**: $CLAUDE_MODEL
- **Attacker prompt**: $ATTACKER_PROMPT_PATH

---

EOF

echo "🎯 Auto_Claude Attack Loop v${ATTACK_VERSION}"
echo "   Project:     $PROJECT_DIR"
echo "   Locked SHA:  $LOCKED_SHA ($LOCKED_BRANCH)"
echo "   Rounds:      GPT × $ROUNDS_PER_PHASE → Claude × $ROUNDS_PER_PHASE → cross-verify × $ROUNDS_PER_PHASE"
echo "   Log:         $ATTACK_LOG"
echo ""

# ── Git lock verifier ──
# Checks that the project dir is still at LOCKED_SHA with no diff and no untracked files.
# On violation: saves a violation file, appends to ATTACK_LOG, resets to LOCKED_SHA.
verify_git_lock() {
    local phase="$1"
    local round="$2"
    local model="$3"

    cd "$PROJECT_DIR"
    local current_sha
    current_sha=$(git rev-parse HEAD)

    local diff_out
    diff_out=$(git diff HEAD 2>&1)
    local untracked_out
    untracked_out=$(git ls-files --others --exclude-standard 2>&1)

    # Allow baseline dirty state (captured by INITIAL_DIRTY) to remain,
    # but fail on anything beyond it.
    local current_dirty
    current_dirty=$(git status --porcelain)

    if [[ "$current_sha" != "$LOCKED_SHA" ]] || [[ "$current_dirty" != "$INITIAL_DIRTY" ]]; then
        local viol_file="$ATTACK_WORK/violations/${phase}_round${round}_${model}.txt"
        {
            echo "=== GIT LOCK VIOLATION ==="
            echo "Phase: $phase | Round: $round | Model: $model"
            echo "Time: $(date +"%Y-%m-%d %H:%M:%S")"
            echo "Locked SHA: $LOCKED_SHA"
            echo "Current SHA: $current_sha"
            echo ""
            echo "--- baseline dirty (at lock time) ---"
            echo "$INITIAL_DIRTY"
            echo ""
            echo "--- current dirty ---"
            echo "$current_dirty"
            echo ""
            echo "--- git diff HEAD (truncated to 200 lines) ---"
            echo "$diff_out" | head -200
            echo ""
            echo "--- untracked files ---"
            echo "$untracked_out" | head -50
        } > "$viol_file"

        echo "🚨 GIT LOCK VIOLATION after $phase round $round ($model)" >&2
        echo "   Saved: $viol_file" >&2
        echo "   Resetting project to $LOCKED_SHA..." >&2

        {
            echo "### 🚨 Git lock violation — $phase Round $round ($model)"
            echo ""
            echo '```'
            cat "$viol_file"
            echo '```'
            echo ""
            echo "**Action**: \`git reset --hard $LOCKED_SHA && git clean -fd\`"
            echo ""
            echo "---"
            echo ""
        } >> "$ATTACK_LOG"

        git reset --hard "$LOCKED_SHA" > /dev/null 2>&1
        git clean -fd > /dev/null 2>&1
        # Re-apply the baseline dirty state by... actually we can't cleanly re-apply it,
        # so we warn the user: baseline dirty may be gone after a violation reset.
        if [[ -n "$INITIAL_DIRTY" ]]; then
            echo "   ⚠️  Baseline uncommitted changes were wiped by the reset." >&2
        fi
        return 1
    fi
    return 0
}

# ── Build attacker input (common for GPT and Claude) ──
build_attacker_input() {
    local phase="$1"
    local round="$2"
    local previous_attacks="$3"

    cat <<INPUT
$ATTACKER_PROMPT

---

# SPEC

$SPEC_CONTENT

---

# PROJECT CONTEXT

$CONTEXT_CONTENT

---

# PHASE: $phase | ROUND: $round

## PREVIOUS ATTACKS (you must pick a different category)

$previous_attacks

---

# YOUR TASK

Root directory: $PROJECT_DIR

Read code and spec. Find ONE failure where the code looks fine but produces an incorrect result, or code and spec disagree.

**You may NOT modify any files.** \`git diff\` runs after your turn — any mutation invalidates the round and is logged as a violation.

Output in the exact VERDICT: ATTACK / CLEAN format defined above.
INPUT
}

# ── GPT-5.3 attacker (codex exec with OS-level read-only sandbox) ──
run_gpt_attacker() {
    local phase="$1"
    local round="$2"
    local previous_attacks="$3"
    local out_file="$ATTACK_WORK/rounds/${phase}_round${round}_gpt.md"
    local last_msg_file="$ATTACK_WORK/rounds/${phase}_round${round}_gpt_last.txt"
    local input_file
    input_file=$(mktemp /tmp/attack_gpt_input.XXXXXX)

    build_attacker_input "$phase" "$round" "$previous_attacks" > "$input_file"

    echo "🎯 GPT [$phase R$round] attacking..."

    local model_flag=()
    [[ -n "$GPT_MODEL" ]] && model_flag=(-m "$GPT_MODEL")

    (cd "$PROJECT_DIR" && "$CODEX_BIN" exec \
        -s read-only \
        -C "$PROJECT_DIR" \
        ${model_flag[@]+"${model_flag[@]}"} \
        -o "$last_msg_file" \
        - < "$input_file" > "$out_file" 2>&1) || {
        echo "   ⚠️  codex exec exited non-zero ($?) — continuing with captured output"
    }
    rm -f "$input_file"

    if [[ -s "$last_msg_file" ]]; then
        cat "$last_msg_file"
    else
        cat "$out_file"
    fi
}

# ── Claude attacker (--print with read-only allowlist; git diff is the final fence) ──
run_claude_attacker() {
    local phase="$1"
    local round="$2"
    local previous_attacks="$3"
    local out_file="$ATTACK_WORK/rounds/${phase}_round${round}_claude.md"
    local input_file
    input_file=$(mktemp /tmp/attack_claude_input.XXXXXX)

    build_attacker_input "$phase" "$round" "$previous_attacks" > "$input_file"

    echo "🎯 Claude [$phase R$round] attacking..."

    (cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
        --print \
        --model "$CLAUDE_MODEL" \
        --disallowed-tools "Write Edit NotebookEdit Agent" \
        --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__* mcp__playwright__* mcp__chrome__*" \
        - < "$input_file" > "$out_file" 2>&1) || {
        echo "   ⚠️  claude --print exited non-zero ($?) — continuing with captured output"
    }
    rm -f "$input_file"
    cat "$out_file"
}

# ── Accumulator for PREVIOUS ATTACKS injection ──
PREVIOUS_ATTACKS="(none yet — this is round 1)"

append_finding() {
    local label="$1"
    local content="$2"
    if [[ "$PREVIOUS_ATTACKS" == "(none yet — this is round 1)" ]]; then
        PREVIOUS_ATTACKS=""
    fi
    PREVIOUS_ATTACKS="$PREVIOUS_ATTACKS

### $label
$content
"
}

log_round() {
    local label="$1"
    local content="$2"
    {
        echo "## $label"
        echo ""
        echo "$content"
        echo ""
        echo "---"
        echo ""
    } >> "$ATTACK_LOG"
}

# ═══════════════════════════════════════════════════
# PHASE 1: GPT-5.3 × N
# ═══════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 1 · GPT × $ROUNDS_PER_PHASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for ((r=1; r<=ROUNDS_PER_PHASE; r++)); do
    OUT=$(run_gpt_attacker "phase1_gpt" "$r" "$PREVIOUS_ATTACKS")
    verify_git_lock "phase1_gpt" "$r" "gpt" || true
    label="Phase 1 · GPT Round $r"
    append_finding "$label" "$OUT"
    log_round "$label" "$OUT"
    echo "   ✓ $label logged"
done

# ═══════════════════════════════════════════════════
# PHASE 2: Claude × N
# ═══════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2 · Claude × $ROUNDS_PER_PHASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for ((r=1; r<=ROUNDS_PER_PHASE; r++)); do
    OUT=$(run_claude_attacker "phase2_claude" "$r" "$PREVIOUS_ATTACKS")
    verify_git_lock "phase2_claude" "$r" "claude" || true
    label="Phase 2 · Claude Round $r"
    append_finding "$label" "$OUT"
    log_round "$label" "$OUT"
    echo "   ✓ $label logged"
done

# ═══════════════════════════════════════════════════
# PHASE 3: Cross-verify × N
#   R1: Claude verifies GPT findings (hallucination check)
#   R2: GPT    verifies Claude findings
#   R3: Claude produces final dedup'd merged report
# ═══════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 3 · Cross-verify × $ROUNDS_PER_PHASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Concatenate phase 1 findings from saved per-round files
PHASE1_FINDINGS=""
for f in "$ATTACK_WORK/rounds"/phase1_gpt_round*_gpt.md; do
    [[ -f "$f" ]] || continue
    PHASE1_FINDINGS="$PHASE1_FINDINGS

### $(basename "$f")
$(cat "$f")
"
done

PHASE2_FINDINGS=""
for f in "$ATTACK_WORK/rounds"/phase2_claude_round*_claude.md; do
    [[ -f "$f" ]] || continue
    PHASE2_FINDINGS="$PHASE2_FINDINGS

### $(basename "$f")
$(cat "$f")
"
done

build_verify_input() {
    local target_findings="$1"
    cat <<VERIFY
You are an adversarial verifier. Another model claims to have found the bugs below in this codebase.
Your job: **reproduce each claim independently** using Read / Grep / Bash(read-only), and label it.

For each finding, output one block:

\`\`\`
Finding #N: (one-line summary from the claim)
Status: CONFIRMED | HALLUCINATED | UNREPRODUCIBLE
Evidence: (for CONFIRMED: file:line + actual command output proving the bug;
           for HALLUCINATED: why it's wrong — missing file/symbol, misread code, wrong logic;
           for UNREPRODUCIBLE: what you tried and why it didn't trigger)
\`\`\`

Rules:
- **Do NOT modify any files.** git diff runs after your turn.
- Do NOT accept claims at face value. If the file or line doesn't exist, mark HALLUCINATED.
- Do NOT fabricate new findings. Only verify the ones given.
- If a claim says "file X line Y" and file X exists but line Y says something else, mark HALLUCINATED with the actual line content.

---

# SPEC

$SPEC_CONTENT

---

# FINDINGS TO VERIFY

$target_findings

---

Root directory: $PROJECT_DIR
VERIFY
}

# Round 1: Claude verifies GPT findings
echo "🔍 [P3 R1] Claude verifying GPT findings..."
VERIFY_FILE=$(mktemp /tmp/attack_verify.XXXXXX)
build_verify_input "$PHASE1_FINDINGS" > "$VERIFY_FILE"
VERIFY1_OUT=$(cd "$PROJECT_DIR" && "$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --disallowed-tools "Write Edit NotebookEdit Agent" \
    --allowedTools "Read Glob Grep Bash WebFetch WebSearch mcp__entropyshield__*" \
    - < "$VERIFY_FILE" 2>&1)
rm -f "$VERIFY_FILE"
verify_git_lock "phase3_verify" "1" "claude" || true
log_round "Phase 3 · Round 1 — Claude verifies GPT findings" "$VERIFY1_OUT"
echo "   ✓ logged"

# Round 2: GPT verifies Claude findings
echo "🔍 [P3 R2] GPT verifying Claude findings..."
VERIFY_FILE=$(mktemp /tmp/attack_verify.XXXXXX)
build_verify_input "$PHASE2_FINDINGS" > "$VERIFY_FILE"
VERIFY2_LAST=$(mktemp /tmp/attack_verify_last.XXXXXX)
gpt_model_flag=()
[[ -n "$GPT_MODEL" ]] && gpt_model_flag=(-m "$GPT_MODEL")
VERIFY2_OUT=$(cd "$PROJECT_DIR" && "$CODEX_BIN" exec \
    -s read-only \
    -C "$PROJECT_DIR" \
    ${gpt_model_flag[@]+"${gpt_model_flag[@]}"} \
    -o "$VERIFY2_LAST" \
    - < "$VERIFY_FILE" 2>&1)
if [[ -s "$VERIFY2_LAST" ]]; then
    VERIFY2_OUT=$(cat "$VERIFY2_LAST")
fi
rm -f "$VERIFY_FILE" "$VERIFY2_LAST"
verify_git_lock "phase3_verify" "2" "gpt" || true
log_round "Phase 3 · Round 2 — GPT verifies Claude findings" "$VERIFY2_OUT"
echo "   ✓ logged"

# Round 3: Final merge — Claude reads the entire attack log and produces clean bug list
echo "🔍 [P3 R3] Final merge + dedup..."
MERGE_FILE=$(mktemp /tmp/attack_merge.XXXXXX)
cat > "$MERGE_FILE" <<MERGE
You are compiling the final attack report for a human reviewer to verify by hand.

Read the entire raw attack log below (9 rounds: 3 GPT attacks + 3 Claude attacks + 2 cross-verifications).
Produce a **clean, deduplicated bug list** for human blind-find review.

## Rules

1. **Dedup** — if the same bug was found by multiple rounds, list it once and note "corroborated by: GPT R1, Claude R2"
2. **Trust cross-verify** — if Phase 3 marked a finding HALLUCINATED, move it to the HALLUCINATED section (do not delete — the human wants to know what the AIs invented)
3. **Categorize**:
   - **CONFIRMED** — independently reproduced by cross-verify, or found by both GPT and Claude
   - **DISPUTED** — one side says bug, the other says CLEAN or UNREPRODUCIBLE
   - **HALLUCINATED** — cross-verify refuted it (file/line/logic wrong)
4. Each entry must have: one-line scenario, file:line, concrete reproduce steps, concrete expected vs actual values, severity
5. Markdown format with clear headings so the human can Ctrl+F
6. **Do not invent new bugs.** Only re-organize what's in the log.
7. **Do not modify any files.**

## Output format

\`\`\`markdown
# Attack Report

## CONFIRMED (N bugs)

### #1: <one-line scenario>
- **Location**: path/to/file.py:123
- **Severity**: critical | high | medium | low
- **Category**: spec-mismatch | silent-corruption | state-leak | boundary | concurrency
- **Corroborated by**: GPT R1, Claude R2, cross-verify
- **Reproduce**:
  1. step 1
  2. step 2
- **Expected**: <concrete value>
- **Actual**: <concrete value>
- **Evidence**: <quoted log excerpt or code snippet>

### #2: ...

## DISPUTED (N bugs)
(same format, add "Dispute note:" explaining the disagreement)

## HALLUCINATED (N claims)
(same format, add "Refuted by:" explaining why it's wrong)

## Summary
- Total attack rounds: 9 (3 GPT + 3 Claude + 3 verify)
- Violations: <count>
- Confirmed bugs: <count>
- Disputed: <count>
- Hallucinations caught: <count>
\`\`\`

---

# RAW ATTACK LOG

$(cat "$ATTACK_LOG")
MERGE

MERGE_OUT=$("$CLAUDE_BIN" \
    --print \
    --model "$CLAUDE_MODEL" \
    --disallowed-tools "Write Edit NotebookEdit Agent Bash" \
    --allowedTools "Read" \
    - < "$MERGE_FILE" 2>&1)
rm -f "$MERGE_FILE"
verify_git_lock "phase3_verify" "3" "claude" || true
log_round "Phase 3 · Round 3 — Final merge (Claude)" "$MERGE_OUT"

# ═══════════════════════════════════════════════════
# Final report
# ═══════════════════════════════════════════════════
VIOL_COUNT=$(ls -1 "$ATTACK_WORK/violations" 2>/dev/null | wc -l | tr -d ' ')

cat > "$FINAL_REPORT" <<FINAL
# Attack Report — $TIMESTAMP

- **Locked SHA**: $LOCKED_SHA
- **Branch**: $LOCKED_BRANCH
- **Project**: $PROJECT_DIR
- **Attackers**: GPT${GPT_MODEL:+" ($GPT_MODEL)"} × $ROUNDS_PER_PHASE · Claude $CLAUDE_MODEL × $ROUNDS_PER_PHASE · cross-verify × $ROUNDS_PER_PHASE
- **Git lock violations**: $VIOL_COUNT

---

$MERGE_OUT

---

## Raw attack log

Full round-by-round transcript: \`$ATTACK_LOG\`

## How to use this report

1. Read the CONFIRMED section first. For each entry, open the file at the given line and verify manually.
2. DISPUTED entries need your eyes — the AIs disagreed.
3. HALLUCINATED entries are failure cases: good to know what your models invented, useful for tuning the attacker prompt.
4. If VIOLATION count > 0, check the log — one of the attackers tried to modify files despite the rules.
FINAL

echo ""
echo "🏁 Attack loop complete."
echo "   Final report: $FINAL_REPORT"
echo "   Raw log:      $ATTACK_LOG"
echo "   Violations:   $VIOL_COUNT"
echo ""
echo "開 $FINAL_REPORT，照 CONFIRMED → DISPUTED → HALLUCINATED 順序人工盲找。"
