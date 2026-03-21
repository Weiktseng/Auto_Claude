#!/bin/bash
#
# Todo 清單專用讀寫工具
# 路徑由第一個參數指定（loop.sh 傳入 comms 目錄）
#
# Usage:
#   bash tools/todo_rw.sh <comms_dir> read
#   echo "新內容" | bash tools/todo_rw.sh <comms_dir> write
#   echo "追加" | bash tools/todo_rw.sh <comms_dir> append
#

COMMS_DIR="${1:-}"
ACTION="${2:-}"
TODO_FILE="$COMMS_DIR/todo.md"

if [[ -z "$COMMS_DIR" || -z "$ACTION" ]]; then
    echo "Usage: todo_rw.sh <comms_dir> read|write|append" >&2
    exit 1
fi

case "$ACTION" in
    read)
        cat "$TODO_FILE" 2>/dev/null || echo "（尚無 todo 清單）"
        ;;
    write)
        cat > "$TODO_FILE"
        echo "✅ Written $(wc -c < "$TODO_FILE") bytes to todo.md" >&2
        ;;
    append)
        cat >> "$TODO_FILE"
        echo "✅ Appended to todo.md (now $(wc -c < "$TODO_FILE") bytes)" >&2
        ;;
    *)
        echo "Usage: todo_rw.sh <comms_dir> read|write|append" >&2
        exit 1
        ;;
esac
