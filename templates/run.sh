#!/bin/bash
#
# 專案啟動腳本模板
#
# 兩種用法：
#   A) 放在 Auto_Claude/projects/<專案>/ 下（傳統）
#   B) 放在 <專案>/.auto_claude/ 下（推薦，專案自治）
#
# Usage:
#   ./run.sh --max-rounds 50
#   ./run.sh --initial-prompt "開始做登入功能"
#   ./run.sh --model-reviewer sonnet
#

# ── 引擎版本鎖定 ──
# 指定要用哪個 git tag 的引擎版本。留空 = 用最新（不鎖版本）。
ENGINE_TAG=""  # 例如 "v3.1"

# ── 路徑設定 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_REPO="/Users/henry/Desktop/公司/Auto_Claude"

# ── 切換引擎版本（如果有指定 tag）──
if [[ -n "$ENGINE_TAG" ]]; then
    _current_tag=$(git -C "$ENGINE_REPO" describe --tags --exact-match 2>/dev/null || echo "none")
    if [[ "$_current_tag" != "$ENGINE_TAG" ]]; then
        echo "🔖 Switching engine to $ENGINE_TAG (current: $_current_tag)..."
        # Stash any uncommitted changes, checkout tag, then unstash
        git -C "$ENGINE_REPO" stash -q 2>/dev/null
        if ! git -C "$ENGINE_REPO" checkout "$ENGINE_TAG" -q 2>/dev/null; then
            echo "❌ Engine tag $ENGINE_TAG not found. Available tags:"
            git -C "$ENGINE_REPO" tag -l
            git -C "$ENGINE_REPO" stash pop -q 2>/dev/null
            exit 1
        fi
        echo "   ✅ Engine now at $ENGINE_TAG"
        # Register cleanup: restore previous branch on exit
        _prev_branch=$(git -C "$ENGINE_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        trap 'git -C "'"$ENGINE_REPO"'" checkout "'"$_prev_branch"'" -q 2>/dev/null; git -C "'"$ENGINE_REPO"'" stash pop -q 2>/dev/null' EXIT
    fi
fi

exec "$ENGINE_REPO/engine/loop.sh" \
    --project-dir "$PROJ_DIR" \
    "$@"
