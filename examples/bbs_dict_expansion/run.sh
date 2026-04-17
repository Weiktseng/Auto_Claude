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
ENGINE_REPO="/home/henry/Auto_Claude"

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

# ── 這個專案的特殊設定 ──
# 無 dev server 可啟動（只是字典擴充，不跑 web）
export SKIP_DEV_SERVER=1
# 啞 Reviewer（工具鏈任務，AI 審查無加值，省 API quota）
# 可用 `DUMB_REVIEWER=0 ./run.sh ...` 臨時關閉
export DUMB_REVIEWER="${DUMB_REVIEWER:-1}"

# ── 專案特製 pre-flight gate ──
#
# 因為 DUMB_REVIEWER=1 讓 Reviewer 不會輸出 STOP signal，且 dev/prompt.md
# 明文禁止 Dev 自宣停工 → loop 終止**只靠 --max-rounds**。
# 所以啟動時 --max-rounds 必須顯式指定，不接受沈默 default，避免誤會。
#
_HAS_MAX_ROUNDS=0
for _arg in "$@"; do
    [[ "$_arg" == "--max-rounds" ]] && _HAS_MAX_ROUNDS=1 && break
done
if [[ $_HAS_MAX_ROUNDS -eq 0 ]]; then
    echo "❌ 必須顯式指定 --max-rounds。" >&2
    echo "   本專案沒有 STOP 協議，loop 終止完全靠你設的輪數。" >&2
    echo "   例：$0 --max-rounds 30 --model-dev sonnet --initial-prompt \"開工\"" >&2
    exit 1
fi

# ASR 容器是產線服務，沒跑 Dev 做不了事；先 fail fast
_ASR_CONTAINER="meetlingo-worker-transcribe"
if ! docker ps --format '{{.Names}}' | grep -qx "$_ASR_CONTAINER"; then
    echo "❌ ASR container 未運行: $_ASR_CONTAINER" >&2
    echo "   請找 sam 確認；本 script 不會自動啟動產線服務。" >&2
    exit 2
fi

# ASR wrapper script 存在且可執行
_ASR_SCRIPT="$PROJ_DIR/.auto_claude/tools/asr_via_docker.sh"
if [[ ! -x "$_ASR_SCRIPT" ]]; then
    echo "❌ ASR wrapper 缺失或不可執行: $_ASR_SCRIPT" >&2
    exit 3
fi

echo "✅ pre-flight pass: max-rounds 已指定 / ASR container 在跑 / tools 就位"

exec "$ENGINE_REPO/engine/loop.sh" \
    --project-dir "$PROJ_DIR" \
    "$@"
