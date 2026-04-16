#!/bin/bash
#
# 專案啟動腳本模板 — Pipeline 版（3 階段架構）
#
# Classic 版（單迴圈 Dev ↔ Reviewer）請用 templates/run.sh。
# 何時該用哪個 → 看 ARCHITECTURES.md
#
# 預設跑完整三段：stage1 focus → stage2 review → stage3 attack
#
# 用法：
#   ./run.sh                     # 完整三段 pipeline
#   ./run.sh --only-stage1       # 只跑 Stage 1 (Dev ↔ dumb Trigger)
#   ./run.sh --only-stage2       # 只跑 Stage 2 (Dev ↔ Reviewer，等同 classic)
#   ./run.sh --only-stage3       # 只跑 Stage 3 (attack)
#   ./run.sh --initial-prompt "..."  # 自訂 Round 1 指令
#

# ── 引擎版本鎖定 ──
ENGINE_TAG=""  # 例如 "pipeline-v1" 鎖定 2026-04-13 的 first stable pipeline

# ── 路徑 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_REPO="/Users/henry/Desktop/公司/Auto_Claude"

# ── Tag switch ──
if [[ -n "$ENGINE_TAG" ]]; then
    _current_tag=$(git -C "$ENGINE_REPO" describe --tags --exact-match 2>/dev/null || echo "none")
    if [[ "$_current_tag" != "$ENGINE_TAG" ]]; then
        echo "🔖 Switching engine to $ENGINE_TAG (current: $_current_tag)..."
        git -C "$ENGINE_REPO" stash -q 2>/dev/null
        if ! git -C "$ENGINE_REPO" checkout "$ENGINE_TAG" -q 2>/dev/null; then
            echo "❌ Engine tag $ENGINE_TAG not found. Available tags:"
            git -C "$ENGINE_REPO" tag -l
            git -C "$ENGINE_REPO" stash pop -q 2>/dev/null
            exit 1
        fi
        _prev_branch=$(git -C "$ENGINE_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        trap 'git -C "'"$ENGINE_REPO"'" checkout "'"$_prev_branch"'" -q 2>/dev/null; git -C "'"$ENGINE_REPO"'" stash pop -q 2>/dev/null' EXIT
    fi
fi

MODE="full"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --only-stage1) MODE="stage1"; shift ;;
        --only-stage2) MODE="stage2"; shift ;;
        --only-stage3) MODE="stage3"; shift ;;
        *) FORWARD_ARGS+=("$1"); shift ;;
    esac
done

case "$MODE" in
    full)
        exec "$ENGINE_REPO/engine/step1_focus_loop.sh" \
            --project-dir "$PROJ_DIR" \
            --chain-stage3 \
            "${FORWARD_ARGS[@]}"
        ;;
    stage1)
        exec "$ENGINE_REPO/engine/step1_focus_loop.sh" \
            --project-dir "$PROJ_DIR" \
            "${FORWARD_ARGS[@]}"
        ;;
    stage2)
        exec "$ENGINE_REPO/engine/step2_rev_loop.sh" \
            --project-dir "$PROJ_DIR" \
            "${FORWARD_ARGS[@]}"
        ;;
    stage3)
        exec "$ENGINE_REPO/engine/attack_loop_v3.sh" \
            --project-dir "$PROJ_DIR" \
            "${FORWARD_ARGS[@]}"
        ;;
esac
