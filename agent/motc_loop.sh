#!/bin/bash
#
# 交通部客服專案 — 全自動 Dev ↔ Agent 迴圈
#
# Usage:
#   ./agent/motc_loop.sh                          # 從現有 session 繼續
#   ./agent/motc_loop.sh --max-rounds 5           # 限制 5 輪
#   ./agent/motc_loop.sh --initial-prompt "繼續開發快速選單 UI"  # 指定起始任務
#   ./agent/motc_loop.sh --model-agent sonnet     # agent 用 sonnet 省錢
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "$SCRIPT_DIR/loop.sh" \
    --project-dir "/Users/henry/Desktop/公司/AI交通部客服" \
    --spec "$SCRIPT_DIR/spec_dev.txt" \
    --prompt-template "$SCRIPT_DIR/prompts/motc_agent.prompt.md" \
    "$@"
