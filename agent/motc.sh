#!/bin/bash
#
# 交通部客服專案 — 一鍵觸發 Agent
#
# Usage:
#   ./agent/motc.sh              # 自動抓取最新 session 輸出
#   ./agent/motc.sh --stdin      # 手動貼上開發者輸出
#   ./agent/motc.sh --model opus # 用 opus 模型
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "$SCRIPT_DIR/trigger.sh" \
    --project-dir "/Users/henry/Desktop/公司/AI交通部客服" \
    --spec "$SCRIPT_DIR/spec_dev.txt" \
    --prompt-template "$SCRIPT_DIR/prompts/motc_agent.prompt.md" \
    "$@"
