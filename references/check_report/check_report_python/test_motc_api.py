"""
MOTC API 端點測試（直接打 HTTP）

用法：
    # 先啟動伺服器
    uv run python -m uvicorn motc_app:app --port 8080

    # 執行測試
    uv run python tests/test_motc_65.py
"""

import os
import tempfile
import requests

BASE = os.getenv("TEST_BASE_URL", "http://localhost:8080")
PASS = 0
FAIL = 0
ERRORS = []


def test(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL += 1
        ERRORS.append(f"{name}: {detail}")
        print(f"  ❌ {name} — {detail}")


def get(path, **kwargs):
    return requests.get(f"{BASE}{path}", timeout=15, **kwargs)


def post(path, **kwargs):
    return requests.post(f"{BASE}{path}", timeout=15, **kwargs)


# ============================================================
#  Part 1: API 端點測試
# ============================================================
def test_api():
    print("\n" + "=" * 60)
    print("Part 1: API 端點測試")
    print("=" * 60)

    # --- 系統健康 ---
    print("\n[系統健康檢查]")
    r = get("/api/system/health")
    data = r.json()
    test("GET /api/system/health 回傳 200", r.status_code == 200)
    test("整體狀態 healthy", data.get("status") == "healthy", data.get("status"))
    test("ChromaDB healthy", data["components"]["chromadb"]["status"] == "healthy")
    test("Embedding healthy", data["components"]["embedding"]["status"] == "healthy")
    test("BM25 已索引", data["components"]["bm25"]["indexed"] is True)
    test("Graph RAG 8 分類", data["components"]["graph_rag"]["categories"] == 8)

    # --- RAG 搜尋 ---
    print("\n[RAG 搜尋]")
    r = get("/api/rag/search", params={"query": "駕照過期", "top_k": 3})
    data = r.json()
    test("GET /api/rag/search 回傳 200", r.status_code == 200)
    test("有搜尋結果", len(data.get("results", [])) > 0, f"results: {len(data.get('results', []))}")
    if data.get("results"):
        first = data["results"][0]
        test("結果含 metadata", "metadata" in first or "section" in first)

    # --- RAG 統計 ---
    print("\n[RAG 統計]")
    r = get("/api/rag/stats")
    data = r.json()
    test("GET /api/rag/stats 回傳 200", r.status_code == 200)
    test("FAQ collection 有 120 筆", data.get("faq_collection", {}).get("count") == 120,
         f"count={data.get('faq_collection', {}).get('count')}")

    # --- 法規知識庫 ---
    print("\n[法規知識庫搜尋]")
    r = get("/api/rag/search", params={"query": "超速處罰", "collection": "motc_law", "top_k": 3})
    data = r.json()
    test("搜尋 motc_law 回傳 200", r.status_code == 200)
    test("法規搜尋有結果", len(data.get("results", [])) > 0, f"results: {len(data.get('results', []))}")

    # --- Graph RAG ---
    print("\n[Graph RAG]")
    r = get("/api/graph-rag/structure")
    data = r.json()
    test("GET /api/graph-rag/structure 回傳 200", r.status_code == 200)
    test("8 大分類", len(data.get("categories", {})) == 8, f"got {len(data.get('categories', {}))}")
    test("9 條跨分類關聯", len(data.get("cross_links", [])) == 9)
    test("9 部法規", len(data.get("regulations", {})) == 9)

    r = get("/api/graph-rag/query", params={"query": "車輛過戶和保險"})
    data = r.json()
    test("Graph RAG query 回傳 200", r.status_code == 200)
    test("有 graph_context", "graph_context" in data)

    # --- 檔案上傳 ---
    print("\n[檔案上傳]")

    # 圖片上傳
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82')
        png_path = f.name
    r = post("/api/image/upload", files={"file": ("test.png", open(png_path, "rb"), "image/png")})
    data = r.json()
    test("POST /api/image/upload 回傳 200", r.status_code == 200)
    test("圖片上傳成功", "path" in data and "error" not in data, data.get("error", ""))
    os.unlink(png_path)

    # 文件上傳 (TXT)
    with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
        f.write("這是測試文件內容。\n第二行。")
        txt_path = f.name
    r = post("/api/file/upload", files={"file": ("test.txt", open(txt_path, "rb"), "text/plain")})
    data = r.json()
    test("POST /api/file/upload (TXT) 回傳 200", r.status_code == 200)
    test("文件上傳成功", data.get("type") == "document", data.get("error", ""))
    test("已解析文字", data.get("parsed_text") is not None and "測試" in (data.get("parsed_text") or ""))
    os.unlink(txt_path)

    # 不支援的格式
    with tempfile.NamedTemporaryFile(suffix=".xyz", delete=False) as f:
        f.write(b"test")
        xyz_path = f.name
    r = post("/api/file/upload", files={"file": ("test.xyz", open(xyz_path, "rb"), "application/octet-stream")})
    data = r.json()
    test("不支援格式拒絕", "error" in data, data)
    os.unlink(xyz_path)

    # PDF 上傳
    pdf_path = "RFI/交通部客服/交通部公路局_AI交通客服與資料治理基礎推動計畫_01_00/06.招標規範.pdf"
    if os.path.exists(pdf_path):
        r = post("/api/file/upload", files={"file": ("招標規範.pdf", open(pdf_path, "rb"), "application/pdf")})
        data = r.json()
        test("POST /api/file/upload (PDF) 成功", data.get("type") == "document", data.get("error", ""))
        test("PDF 已解析", data.get("parsed_text") is not None and len(data.get("parsed_text", "")) > 100)

    # --- 頁面路由 ---
    print("\n[頁面路由]")
    for path, name in [
        ("/", "主客服頁面"),
        ("/assistant", "話務助理"),
        ("/drafting", "擬稿助手"),
        ("/architecture", "系統架構"),
        ("/docs", "Swagger UI"),
    ]:
        r = get(path)
        test(f"GET {path} ({name})", r.status_code == 200, f"status={r.status_code}")

    # --- Admin 頁面 ---
    print("\n[Admin 頁面]")
    for path, name in [
        ("/admin", "對話管理"),
        ("/admin/charts", "統計報表"),
        ("/admin/reports", "主題報告"),
        ("/admin/users", "用戶管理"),
        ("/admin/settings", "系統設定"),
    ]:
        r = get(path)
        test(f"GET {path} ({name})", r.status_code in [200, 401, 302], f"status={r.status_code}")

    # --- OpenAPI ---
    print("\n[OpenAPI 規範]")
    r = get("/openapi.json")
    data = r.json()
    test("GET /openapi.json 回傳 200", r.status_code == 200)
    paths = data.get("paths", {})
    test("含 /api/rag/search", "/api/rag/search" in paths)
    test("含 /api/file/upload", "/api/file/upload" in paths)
    test("含 /api/system/health", "/api/system/health" in paths)
    rag_search = paths.get("/api/rag/search", {}).get("get", {})
    test("RAG search 有 summary", bool(rag_search.get("summary")), rag_search.get("summary", ""))


# ============================================================
#  主程式
# ============================================================
def main():
    global PASS, FAIL

    print("🧪 MOTC API 端點測試")
    print(f"目標伺服器: {BASE}")

    try:
        r = requests.get(f"{BASE}/api/system/health", timeout=5)
        if r.status_code != 200:
            print(f"❌ 伺服器回傳 {r.status_code}，請先啟動伺服器")
            return
    except Exception as e:
        print(f"❌ 無法連接 {BASE}: {e}")
        print("請先啟動: uv run python -m uvicorn motc_app:app --port 8080")
        return

    test_api()

    total = PASS + FAIL
    print("\n" + "=" * 60)
    print(f"測試結果: {PASS}/{total} 通過, {FAIL} 失敗")
    print("=" * 60)

    if ERRORS:
        print("\n❌ 失敗項目:")
        for e in ERRORS:
            print(f"  - {e}")
    else:
        print("\n✅ 全部通過！")


if __name__ == "__main__":
    main()

'''
On 2026/03/16
⏺ Bash(uv run python test_single.py 2>&1 | grep -E "^(  ✅|  ❌|測試結果|✅ 全部|❌
      失敗|Part|===|\[)")
  ⎿  ============================================================
     Part 1: API 端點測試
     ============================================================
     [系統健康檢查]
       ✅ GET /api/system/health 回傳 200
       ✅ 整體狀態 healthy
       ✅ ChromaDB healthy
       ✅ Embedding healthy
       ✅ BM25 已索引
       ✅ Graph RAG 8 分類
     [RAG 搜尋]
       ✅ GET /api/rag/search 回傳 200
       ✅ 有搜尋結果
       ✅ 結果含 metadata
     [RAG 統計]
       ✅ GET /api/rag/stats 回傳 200
       ✅ FAQ collection 有 120 筆
     [法規知識庫搜尋]
       ✅ 搜尋 motc_law 回傳 200
       ✅ 法規搜尋有結果
     [Graph RAG]
       ✅ GET /api/graph-rag/structure 回傳 200
       ✅ 8 大分類
       ✅ 9 條跨分類關聯
       ✅ 9 部法規
       ✅ Graph RAG query 回傳 200
       ✅ 有 graph_context
     [檔案上傳]
       ✅ POST /api/image/upload 回傳 200
       ✅ 圖片上傳成功
       ✅ POST /api/file/upload (TXT) 回傳 200
       ✅ 文件上傳成功
       ✅ 已解析文字
       ✅ 不支援格式拒絕
       ✅ POST /api/file/upload (PDF) 成功
       ✅ PDF 已解析
     [頁面路由]
       ✅ GET / (主客服頁面)
       ✅ GET /assistant (話務助理)
       ✅ GET /drafting (擬稿助手)
       ✅ GET /architecture (系統架構)
       ✅ GET /docs (Swagger UI)
     [Admin 頁面]
       ✅ GET /admin (對話管理)
       ✅ GET /admin/charts (統計報表)
       ✅ GET /admin/reports (主題報告)
       ✅ GET /admin/users (用戶管理)
       ✅ GET /admin/settings (系統設定)
     [OpenAPI 規範]
       ✅ GET /openapi.json 回傳 200
       ✅ 含 /api/rag/search
       ✅ 含 /api/file/upload
       ✅ 含 /api/system/health
       ✅ RAG search 有 summary
     ============================================================
     Part 2: E2E Agent 測試（模擬使用者對話流程）
     ============================================================
     [E2E-1] 簡單 FAQ（應走 Fast RAG）
     [EmbeddingService] 載入模型 BAAI/bge-m3...
     [EmbeddingService] 使用設備: mps
     [EmbeddingService] 模型載入完成 (SentenceTransformers)
     [RAGService] 從快取載入 BM25 索引: motc_faq (120 文件)
       ✅ 路由到 fast_rag
       ✅ 有 final_answer
       ✅ 答案含駕照相關
       ✅ 有推薦問題
     [E2E-2] 即時路況（應走 ReAct）
     [Tool: DuckDuckGo Search 執行中... 關鍵字: 蘇花改路況 路況 site:thb.gov.tw OR
     site:1968.freeway.gov.tw]
     [Tool: DuckDuckGo Search 執行中... 關鍵字: 蘇花改路況 即時路況]
     [Tool: DuckDuckGo Search 執行中... 關鍵字: 蘇花改路況]
       ✅ 路由到 react_agent
       ✅ 有 final_answer
       ✅ 使用了搜尋工具
     [E2E-3] 轉真人偵測
       ✅ 觸發 transfer_marker
       ✅ 答案含 0800
     [E2E-4] 一般問題不觸發轉真人
       ✅ 不觸發 transfer_marker
     [E2E-5] 範圍外問題
       ✅ 有 final_answer
       ✅ 回覆含引導文字
     [E2E-6] 文件上傳注入
       ✅ 偵測到文件
       ✅ 注入了文件內容
     [E2E-7] Intent Router 分類正確性
       ✅ 「汽燃費怎麼繳？」→ fast_rag
       ✅ 「蘇花改目前路況」→ react_agent
       ✅ 「駕照和違規有什麼關係？需要注意什麼？」→ react_agent
       ✅ 追問+history → react_agent
       ✅ 有圖片 → react_agent
       ✅ 有文件 → react_agent
     [E2E-8] 文件解析模組
       ✅ TXT 解析
       ✅ CSV 解析為 Markdown 表格
       ✅ 不支援格式拋 ValueError
     ============================================================
     測試結果: 65/65 通過, 0 失敗
     ============================================================
     ✅ 全部通過！
'''
