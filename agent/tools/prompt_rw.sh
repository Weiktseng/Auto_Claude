#!/bin/bash
#
# Reviewer prompt 專用讀寫工具（路徑寫死，不接受路徑參數）
#
# Usage:
#   bash agent/tools/prompt_rw.sh read              # 讀取目前的 prompt
#   echo "新內容" | bash agent/tools/prompt_rw.sh write   # 覆寫 prompt
#   echo "追加內容" | bash agent/tools/prompt_rw.sh append # 追加到 prompt 尾端
#

PROMPT_FILE="/Users/henry/Desktop/公司/Auto_Claude/agent/prompts/motc_reviewer.prompt.md"

case "${1:-}" in
    read)
        cat "$PROMPT_FILE"
        ;;
    write)
        cat > "$PROMPT_FILE"
        echo "✅ Written $(wc -c < "$PROMPT_FILE") bytes to motc_reviewer.prompt.md" >&2
        ;;
    append)
        cat >> "$PROMPT_FILE"
        echo "✅ Appended to motc_reviewer.prompt.md (now $(wc -c < "$PROMPT_FILE") bytes)" >&2
        ;;
    *)
        echo "Usage: prompt_rw.sh read|write|append" >&2
        echo "  read   — 輸出 prompt 內容" >&2
        echo "  write  — 從 stdin 覆寫（⚠️ 全部取代）" >&2
        echo "  append — 從 stdin 追加到尾端" >&2
        exit 1
        ;;
esac
