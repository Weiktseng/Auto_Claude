#!/bin/bash
#
# Auto_Claude Stage 2 — Review Loop (thin wrapper over loop.sh)
#
# Purpose:
#   Stage 2 is the existing Dev ↔ Reviewer loop. This wrapper exists so the
#   three-stage pipeline has a consistent naming scheme (step1_focus_loop,
#   step2_rev_loop, attack_loop) and so we can optionally chain to Stage 3
#   (attack_loop.sh) when Stage 2 finishes.
#
# Flow:
#   1. exec loop.sh with forwarded args (Dev ↔ Reviewer, curator every 8 rounds)
#   2. When loop.sh exits (bilateral stop or max rounds), auto-commit any WIP
#      so Stage 3's git lock starts from a clean SHA
#   3. If --chain-stage3: auto-exec attack_loop.sh
#
# Usage:
#   engine/step2_rev_loop.sh --project-dir <path> [loop.sh options] [--chain-stage3]
#
# Options (stage2-specific):
#   --chain-stage3              After Stage 2 exits, auto-exec attack_loop.sh
#   --no-auto-commit            Don't auto-commit WIP at Stage 2 exit
#   (all other options are forwarded verbatim to loop.sh)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOOP_SH="$SCRIPT_DIR/loop.sh"
ATTACK_SH="$SCRIPT_DIR/attack_loop.sh"

[[ ! -x "$LOOP_SH" ]] && { echo "Error: $LOOP_SH not executable" >&2; exit 1; }

# ── Split our flags from loop.sh's flags ──
CHAIN_STAGE3=false
AUTO_COMMIT=true
PROJECT_DIR=""
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --chain-stage3)   CHAIN_STAGE3=true;  shift ;;
        --no-auto-commit) AUTO_COMMIT=false;  shift ;;
        --project-dir)
            PROJECT_DIR="$2"
            FORWARD_ARGS+=("$1" "$2")
            shift 2 ;;
        --help|-h)
            awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/,""); print; next} {exit}' "$0"
            echo ""
            echo "=== forwarded loop.sh options ==="
            "$LOOP_SH" --help 2>&1 || true
            exit 0 ;;
        *)
            FORWARD_ARGS+=("$1")
            shift ;;
    esac
done

[[ -z "$PROJECT_DIR" ]] && { echo "Error: --project-dir is required" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

echo "🔄 Stage 2 (rev loop) starting — delegating to $LOOP_SH"
echo "   Chain to Stage 3: $CHAIN_STAGE3"
echo "   Auto-commit WIP:  $AUTO_COMMIT"
echo ""

# Run loop.sh in the foreground. Don't exec — we want to run post-hooks when it exits.
"$LOOP_SH" "${FORWARD_ARGS[@]}"
LOOP_EXIT=$?

echo ""
echo "🔄 Stage 2 (rev loop) exited with status $LOOP_EXIT"

# ── Auto-commit any WIP so Stage 3 locks a clean SHA ──
if [[ "$AUTO_COMMIT" == true ]]; then
    cd "$PROJECT_DIR"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        if [[ -n "$(git status --porcelain)" ]]; then
            echo "📦 Auto-committing Stage 2 WIP so Stage 3 has a clean SHA..."
            git add -A
            git commit -m "stage2: auto-commit at loop exit

Uncommitted changes at Stage 2 exit. Committed automatically so Stage 3
attack_loop can lock a clean SHA. Review the diff and squash/rewrite
if you prefer a cleaner history." > /dev/null 2>&1 || {
                echo "   ⚠️  Auto-commit failed (hook? empty diff?). Continuing anyway."
            }
            if [[ -n "$(git status --porcelain)" ]]; then
                echo "   ⚠️  Working tree still dirty after auto-commit. Stage 3 will ask about it."
            else
                echo "   ✅ Committed: $(git rev-parse --short HEAD)"
            fi
        else
            echo "✅ Working tree already clean."
        fi
    fi
fi

# ── Chain to Stage 3 ──
if [[ "$CHAIN_STAGE3" == true ]]; then
    if [[ ! -x "$ATTACK_SH" ]]; then
        echo "⚠️  --chain-stage3 set but $ATTACK_SH not executable. Exiting." >&2
        exit $LOOP_EXIT
    fi
    echo ""
    echo "🎯 Chaining to Stage 3 (attack_loop.sh)..."
    exec "$ATTACK_SH" \
        --project-dir "$PROJECT_DIR" \
        --skip-dirty-check
fi

exit $LOOP_EXIT
