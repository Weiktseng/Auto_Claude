#!/bin/bash
# 將 Auto_Claude 的 settings.local.json 複製到指定專案的 .claude/ 下
# 用法：
#   ./setup.sh /path/to/your/project
#   ./setup.sh                          # 預設複製到全域 ~/.claude/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/settings.local.json"

if [ ! -f "$SOURCE" ]; then
  echo "找不到 $SOURCE"
  exit 1
fi

if [ -z "$1" ]; then
  TARGET="$HOME/.claude/settings.local.json"
  mkdir -p "$HOME/.claude"
else
  TARGET="$1/.claude/settings.local.json"
  mkdir -p "$1/.claude"
fi

if [ -f "$TARGET" ]; then
  echo "已存在: $TARGET"
  echo "要覆寫嗎？(y/N)"
  read -r ans
  if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
    echo "取消"
    exit 0
  fi
fi

cp "$SOURCE" "$TARGET"
echo "已複製到: $TARGET"
echo "請重新開啟 Claude Code session 生效"
