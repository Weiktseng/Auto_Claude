#!/bin/bash
#
# 專案健康檢查（按需執行，不自動跑）
#
# Usage:
#   bash tools/smoke_test.sh              # 快速：endpoint + pytest
#   bash tools/smoke_test.sh --full       # 完整：加覆蓋率 + 延遲測量
#
# Reviewer 覺得該跑時叫 Dev 執行這個
#

BASE_URL="${BASE_URL:-http://localhost:8001}"
PROJECT_DIR="/Users/henry/Desktop/公司/AI交通部客服"
FULL=false
[[ "${1:-}" == "--full" ]] && FULL=true

echo "═══ Smoke Test $(date +%H:%M:%S) ═══"
echo ""

# ── 1. Endpoint 存活 ──
echo "▸ Endpoints"
ENDPOINTS=(
    "/"
    "/assistant"
    "/admin"
    "/api/health"
    "/api/stats"
    "/api/chat/stream"
)
FAIL=0
for ep in "${ENDPOINTS[@]}"; do
    code=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE_URL$ep" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|405)$ ]]; then
        echo "  ✅ $ep ($code)"
    else
        echo "  ❌ $ep ($code)"
        ((FAIL++))
    fi
done
echo ""

# ── 2. Tests ──
echo "▸ Tests"
cd "$PROJECT_DIR"
if [[ "$FULL" == true ]]; then
    python3 -m pytest --cov=src --cov-report=term-missing -q 2>&1 | tail -5
else
    python3 -m pytest -q 2>&1 | tail -3
fi
echo ""

# ── 3. 延遲測量（--full only） ──
if [[ "$FULL" == true ]]; then
    if command -v hey &>/dev/null; then
        echo "▸ Response Time (30 requests)"
        hey -n 30 -c 5 "$BASE_URL/" 2>&1 | grep -E "Average|Fastest|Slowest|Requests/sec"
        echo ""
    else
        echo "▸ Response Time: hey not installed (brew install hey)"
        echo ""
    fi
fi

# ── Summary ──
if [[ $FAIL -eq 0 ]]; then
    echo "═══ PASS ═══"
else
    echo "═══ FAIL ($FAIL endpoints down) ═══"
fi
