#!/bin/bash
#
# 專案啟動腳本模板
# 複製到 projects/<你的專案>/ 後，修改 PROJECT_DIR
#
# Usage:
#   ./projects/your_project/run.sh --max-rounds 50
#   ./projects/your_project/run.sh --initial-prompt "開始做登入功能"
#   ./projects/your_project/run.sh --model-reviewer sonnet
#

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PROJ_DIR/../.." && pwd)"

exec "$ROOT_DIR/engine/loop.sh" \
    --project-dir "/path/to/your/project" \
    --spec "$PROJ_DIR/spec.txt" \
    --prompt-template "$PROJ_DIR/prompts/reviewer.prompt.md" \
    --context "$PROJ_DIR/context.md" \
    --comms-dir "$PROJ_DIR/comms" \
    --log-dir "$PROJ_DIR/logs" \
    "$@"
