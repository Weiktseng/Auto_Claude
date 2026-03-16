#!/bin/bash
#
# 交通部客服專案 — myReAct 分支全自動 Dev ↔ Agent 迴圈
#
# Usage:
#   ./agent/motc_myreact_loop.sh
#   ./agent/motc_myreact_loop.sh --max-rounds 10
#   ./agent/motc_myreact_loop.sh --model-agent sonnet  # agent 用 sonnet 省 quota
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "$SCRIPT_DIR/loop.sh" \
    --project-dir "/Users/henry/Desktop/公司/myReAct" \
    --spec "$SCRIPT_DIR/spec_dev.txt" \
    --prompt-template "$SCRIPT_DIR/prompts/motc_myreact_agent.prompt.md" \
    "$@"
