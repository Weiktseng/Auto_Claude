#!/bin/bash
#
# 交通部客服專案 — 全自動 Dev ↔ Reviewer 迴圈
#
# Usage:
#   ./projects/motc/run.sh                          # 從現有 session 繼續
#   ./projects/motc/run.sh --max-rounds 50
#   ./projects/motc/run.sh --initial-prompt "繼續開發快速選單 UI"
#   ./projects/motc/run.sh --model-reviewer sonnet
#

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PROJ_DIR/../.." && pwd)"

exec "$ROOT_DIR/engine/loop.sh" \
    --project-dir "/Users/henry/Desktop/公司/AI交通部客服" \
    --spec "$PROJ_DIR/spec.txt" \
    --prompt-template "$PROJ_DIR/prompts/reviewer.prompt.md" \
    --context "$PROJ_DIR/context.md" \
    --comms-dir "$PROJ_DIR/comms" \
    --log-dir "$PROJ_DIR/logs" \
    "$@"
