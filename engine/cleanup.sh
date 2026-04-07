#!/bin/bash
#
# Auto_Claude — 殭屍進程清理工具
#
# 殺掉所有非當前 session 的 claude 進程及其 MCP 子進程
#
# Usage:
#   ./engine/cleanup.sh          # 預覽模式（只列出，不殺）
#   ./engine/cleanup.sh --kill   # 實際執行清理
#   ./engine/cleanup.sh --force  # 跳過確認直接殺
#

set -uo pipefail

MODE="preview"
[[ "${1:-}" == "--kill" ]] && MODE="kill"
[[ "${1:-}" == "--force" ]] && MODE="force"

# 找出呼叫鏈上的所有祖先 PID（保護自己的 claude session）
_ancestor_pids=""
_walk_pid=$$
while [[ $_walk_pid -gt 1 ]]; do
    _ancestor_pids="$_ancestor_pids $_walk_pid"
    _walk_pid=$(ps -o ppid= -p "$_walk_pid" 2>/dev/null | tr -d ' ')
    [[ -z "$_walk_pid" ]] && break
done

echo "🔍 掃描 claude 及 MCP 進程..."
echo ""

# 收集所有 claude 進程
total_mem=0
stale_count=0
stale_pids=()
mcp_pids=()

while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $2}')
    tty=$(echo "$line" | awk '{print $7}')
    mem_kb=$(echo "$line" | awk '{print $6}')
    start=$(echo "$line" | awk '{print $9}')
    mem_mb=$((mem_kb / 1024))

    # 跳過自己的祖先鏈（不管 TTY，用 PID 判斷）
    if echo "$_ancestor_pids" | grep -qw "$pid"; then
        echo "  ✅ PID $pid (tty=$tty, ${mem_mb}MB, $start) — 當前 session，保留"
        continue
    fi

    echo "  💀 PID $pid (tty=$tty, ${mem_mb}MB, $start) — 殭屍"
    stale_pids+=("$pid")
    total_mem=$((total_mem + mem_mb))
    ((stale_count++))

    # 找這個 claude 的 MCP 子進程
    while IFS= read -r child_line; do
        child_pid=$(echo "$child_line" | awk '{print $1}')
        child_cmd=$(echo "$child_line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i}')
        child_mem_kb=$(echo "$child_line" | awk '{print $3}')
        child_mem_mb=$((child_mem_kb / 1024))
        echo "    └─ PID $child_pid (${child_mem_mb}MB) $child_cmd"
        mcp_pids+=("$child_pid")
        total_mem=$((total_mem + child_mem_mb))
    done < <(ps -eo pid,ppid,rss,command | awk -v ppid="$pid" '$2 == ppid' 2>/dev/null)

done < <(ps aux | grep '[c]laude' | grep -v grep | grep -v '/bin/zsh' | grep -v 'cleanup.sh')

echo ""

if [[ $stale_count -eq 0 ]]; then
    echo "✨ 沒有殭屍進程，一切乾淨。"
    exit 0
fi

echo "📊 發現 $stale_count 個殭屍 claude + ${#mcp_pids[@]} 個 MCP 子進程，共 ~${total_mem}MB"

if [[ "$MODE" == "preview" ]]; then
    echo ""
    echo "👆 以上為預覽。執行清理："
    echo "   ./engine/cleanup.sh --kill    # 確認後清理"
    echo "   ./engine/cleanup.sh --force   # 直接清理"
    exit 0
fi

if [[ "$MODE" == "kill" ]]; then
    echo ""
    read -rp "確定要殺掉這些進程？(y/N) " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "取消。" && exit 0
fi

# 先殺 MCP 子進程，再殺 claude 主進程
echo ""
for pid in "${mcp_pids[@]}"; do
    kill "$pid" 2>/dev/null && echo "  killed MCP $pid"
done
sleep 1
for pid in "${stale_pids[@]}"; do
    kill "$pid" 2>/dev/null && echo "  killed claude $pid"
done
sleep 2
# 確認死透
for pid in "${stale_pids[@]}" "${mcp_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null && echo "  force-killed $pid"
    fi
done

echo ""
echo "✅ 清理完成，釋放 ~${total_mem}MB"
