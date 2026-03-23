"""
PETQ API 端點測試 + E2E Agent 測試（直接打 HTTP + 程式碼層測試）

用法：
    # 先啟動伺服器
    uv run python -m uvicorn petq_app:app --port 8081

    # 執行測試
    uv run python tests/test_petq_api.py
"""

import os
import sys
import tempfile
import csv
import requests

# 加入專案根目錄
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

BASE = os.getenv("TEST_BASE_URL", "http://localhost:8081")
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
    test("整體狀態非 unhealthy", data.get("status") != "unhealthy", data.get("status"))
    test("ChromaDB healthy", data["components"]["chromadb"]["status"] == "healthy")
    test("Embedding healthy", data["components"]["embedding"]["status"] == "healthy")
    test("Graph RAG 8 分類", data["components"]["graph_rag"]["categories"] == 8)

    # --- RAG 搜尋 ---
    print("\n[RAG 搜尋]")
    r = get("/api/rag/search", params={"query": "帶狗從日本回台灣", "top_k": 3})
    data = r.json()
    test("GET /api/rag/search 回傳 200", r.status_code == 200)
    test("有搜尋結果", len(data.get("results", [])) > 0, f"results: {len(data.get('results', []))}")
    if data.get("results"):
        first = data["results"][0]
        test("結果含 metadata", "metadata" in first or "section" in first)

    # 各種查詢情境
    for query, desc in [
        ("狂犬病抗體檢測費用", "費用查詢"),
        ("晶片規格", "文件規格"),
        ("隔離期間", "隔離措施"),
        ("FAVN", "專業術語(英文)"),
    ]:
        r = get("/api/rag/search", params={"query": query, "top_k": 3})
        data = r.json()
        test(f"搜尋「{query}」({desc}) 有結果",
             len(data.get("results", [])) > 0,
             f"results: {len(data.get('results', []))}")

    # --- RAG 統計 ---
    print("\n[RAG 統計]")
    r = get("/api/rag/stats")
    data = r.json()
    test("GET /api/rag/stats 回傳 200", r.status_code == 200)
    faq_count = data.get("faq_collection", {}).get("count", 0)
    test(f"FAQ collection 有 {faq_count} 筆 (>=20)", faq_count >= 20, f"count={faq_count}")

    # --- Graph RAG ---
    print("\n[Graph RAG]")
    r = get("/api/graph-rag/structure")
    data = r.json()
    test("GET /api/graph-rag/structure 回傳 200", r.status_code == 200)
    test("8 大分類", len(data.get("categories", {})) == 8, f"got {len(data.get('categories', {}))}")
    test("9 條跨分類關聯", len(data.get("cross_links", [])) == 9)
    test("5 部法規", len(data.get("regulations", {})) == 5)

    r = get("/api/graph-rag/query", params={"query": "輸入檢疫和狂犬病檢測"})
    data = r.json()
    test("Graph RAG query 回傳 200", r.status_code == 200)
    test("有 graph_context", "graph_context" in data)
    if "graph_context" in data:
        ctx = data["graph_context"]
        test("有主要分類", len(ctx.get("primary_categories", [])) > 0)

    # --- 檔案上傳 ---
    print("\n[檔案上傳]")

    # 圖片上傳（1x1 PNG）
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82')
        png_path = f.name
    r = post("/api/image/upload", files={"file": ("health_cert.png", open(png_path, "rb"), "image/png")})
    data = r.json()
    test("POST /api/image/upload 回傳 200", r.status_code == 200)
    test("圖片上傳成功", "path" in data and "error" not in data, data.get("error", ""))
    os.unlink(png_path)

    # 文件上傳 (TXT)
    with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
        f.write("犬貓健康證明書測試內容。\n晶片號碼：900123456789012。")
        txt_path = f.name
    r = post("/api/file/upload", files={"file": ("health_cert.txt", open(txt_path, "rb"), "text/plain")})
    data = r.json()
    test("POST /api/file/upload (TXT) 回傳 200", r.status_code == 200)
    test("文件上傳成功", data.get("type") == "document", data.get("error", ""))
    test("已解析文字", data.get("parsed_text") is not None and "晶片" in (data.get("parsed_text") or ""))
    if "path" in data:
        # 驗證快取
        r2 = get("/api/file/parsed", params={"path": data["path"]})
        d2 = r2.json()
        test("文件快取可讀", "text" in d2 and "晶片" in d2.get("text", ""))
    os.unlink(txt_path)

    # 不支援的格式
    with tempfile.NamedTemporaryFile(suffix=".xyz", delete=False) as f:
        f.write(b"test")
        xyz_path = f.name
    r = post("/api/file/upload", files={"file": ("test.xyz", open(xyz_path, "rb"), "application/octet-stream")})
    data = r.json()
    test("不支援格式拒絕", "error" in data, data)
    os.unlink(xyz_path)

    # 超過 10MB 測試（模擬大檔）
    with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
        f.write(b"x" * (11 * 1024 * 1024))
        big_path = f.name
    r = post("/api/file/upload", files={"file": ("big.txt", open(big_path, "rb"), "text/plain")})
    data = r.json()
    test("超過 10MB 拒絕", "error" in data, data.get("error", ""))
    os.unlink(big_path)

    # --- 頁面路由 ---
    print("\n[頁面路由]")
    for path, name in [
        ("/", "主客服頁面"),
        ("/widget", "嵌入式 Widget"),
        ("/docs", "Swagger UI"),
    ]:
        r = get(path)
        test(f"GET {path} ({name})", r.status_code == 200, f"status={r.status_code}")

    # 主頁包含品牌資訊
    r = get("/")
    content = r.text
    test("主頁含品牌名", "檢疫" in content)
    test("主頁含農業部", "農業部" in content or "防檢署" in content)
    test("主頁含 0800", "0800" in content)
    test("主頁含多語系提示", "English" in content and "Tiếng Việt" in content)

    # --- OpenAPI ---
    print("\n[OpenAPI 規範]")
    r = get("/openapi.json")
    data = r.json()
    test("GET /openapi.json 回傳 200", r.status_code == 200)
    paths = data.get("paths", {})
    test("含 /api/rag/search", "/api/rag/search" in paths)
    test("含 /api/file/upload", "/api/file/upload" in paths)
    test("含 /api/system/health", "/api/system/health" in paths)
    test("含 /api/graph-rag/structure", "/api/graph-rag/structure" in paths)


# ============================================================
#  Part 2: E2E Agent 測試（程式碼層，模擬使用者對話）
# ============================================================
def test_e2e_agent():
    print("\n" + "=" * 60)
    print("Part 2: E2E Agent 測試（模擬使用者對話流程）")
    print("=" * 60)

    import asyncio

    # --- E2E-1: 簡單 FAQ（應走 Fast RAG）---
    print("\n[E2E-1] 簡單 FAQ（應走 Fast RAG）")
    from petq.agent import PetqReActAgent

    agent = PetqReActAgent(verbose=False)

    async def run_simple_faq():
        events = []
        async for event in agent.run("狂犬病抗體檢測費用多少？"):
            events.append(event)
        return events

    events = asyncio.get_event_loop().run_until_complete(run_simple_faq())

    intent_event = next((e for e in events if e.get("type") == "intent"), None)
    test("路由到 fast_rag", intent_event and intent_event.get("route") == "fast_rag",
         intent_event.get("route") if intent_event else "no intent")

    final = next((e for e in events if e.get("type") == "final_answer"), None)
    test("有 final_answer", final is not None)
    if final:
        test("答案含費用相關", "5,000" in final["content"] or "5000" in final["content"] or "費" in final["content"],
             final["content"][:80])

    suggestions = next((e for e in events if e.get("type") == "suggestions"), None)
    test("有推薦問題", suggestions is not None)

    # --- E2E-2: 複雜查詢（應走 ReAct）---
    print("\n[E2E-2] 複雜查詢（應走 ReAct）")

    async def run_complex():
        events = []
        async for event in agent.run("從美國帶狗回台灣需要哪些手續？步驟流程是什麼？"):
            events.append(event)
        return events

    events = asyncio.get_event_loop().run_until_complete(run_complex())

    intent_event = next((e for e in events if e.get("type") == "intent"), None)
    test("路由到 react_agent", intent_event and intent_event.get("route") == "react_agent",
         intent_event.get("route") if intent_event else "no intent")

    final = next((e for e in events if e.get("type") == "final_answer"), None)
    test("有 final_answer", final is not None)
    if final:
        test("答案含美國/檢疫相關", any(kw in final["content"] for kw in ["美國", "檢疫", "180", "疫區", "隔離"]),
             final["content"][:80])

    # --- E2E-3: 轉真人偵測 ---
    print("\n[E2E-3] 轉真人偵測")

    async def run_transfer():
        events = []
        async for event in agent.run("我要投訴檢疫站的服務態度，請讓我跟真人客服講話"):
            events.append(event)
        return events

    events = asyncio.get_event_loop().run_until_complete(run_transfer())

    final = next((e for e in events if e.get("type") == "final_answer"), None)
    transfer = next((e for e in events if e.get("type") == "transfer_marker"), None)

    # 轉真人可能在 final_answer 中或作為單獨事件
    has_transfer = transfer is not None or (final and "[轉真人]" in final.get("content", ""))
    test("觸發轉真人", has_transfer)
    if final:
        test("答案含專線或聯絡方式",
             any(kw in final["content"] for kw in ["0800", "專線", "桃園分署", "電話"]),
             final["content"][:80])

    # --- E2E-4: 一般問題不觸發轉真人 ---
    print("\n[E2E-4] 一般問題不觸發轉真人")

    async def run_normal():
        events = []
        async for event in agent.run("晶片規格有什麼要求？"):
            events.append(event)
        return events

    events = asyncio.get_event_loop().run_until_complete(run_normal())
    transfer = next((e for e in events if e.get("type") == "transfer_marker"), None)
    test("不觸發 transfer_marker", transfer is None)

    # --- E2E-5: 範圍外問題 ---
    print("\n[E2E-5] 範圍外問題")

    async def run_out_of_scope():
        events = []
        async for event in agent.run("台積電今天股價多少？"):
            events.append(event)
        return events

    events = asyncio.get_event_loop().run_until_complete(run_out_of_scope())
    final = next((e for e in events if e.get("type") == "final_answer"), None)
    test("有 final_answer", final is not None)
    if final:
        test("回覆含引導文字",
             any(kw in final["content"] for kw in ["檢疫", "範圍", "0800", "防檢署"]),
             final["content"][:80])

    # --- E2E-6: 文件上傳注入 ---
    print("\n[E2E-6] 文件上傳注入")
    test_input = "請分析這份文件\n\n[上傳文件] 檔名：health_cert.txt，路徑：/tmp/test.txt"
    enriched, has_files = agent._extract_and_inject_files(test_input)
    test("偵測到文件", has_files)
    test("注入了文件內容", "系統已解析" in enriched)

    # --- E2E-7: Intent Router 分類正確性 ---
    print("\n[E2E-7] Intent Router 分類正確性")
    from petq.intent_router import IntentRouter
    router = IntentRouter()

    test_cases = [
        ("狂犬病抗體檢測費用多少？", "fast_rag", "簡單費用查詢"),
        ("從美國帶狗回台灣的完整步驟流程", "fast_rag", "帶寵物入境（FAQ 已收錄）"),
        ("如果抗體不足那該怎麼辦？", "react_agent", "條件推理"),
        ("那", "react_agent", "追問（有 history）"),
    ]

    for query, expected_route, desc in test_cases:
        history = [{"role": "user", "content": "之前的問題"}] if query == "那" else None
        result = router.classify(query, history=history)
        test(f"「{query}」→ {expected_route} ({desc})",
             result.route == expected_route,
             f"got {result.route}: {result.reason}")

    # 有圖片/文件 → ReAct
    result = router.classify("這是什麼", has_image=True)
    test("有圖片 → react_agent", result.route == "react_agent")
    result = router.classify("分析文件", has_file=True)
    test("有文件 → react_agent", result.route == "react_agent")

    # --- E2E-8: Scope 判斷 ---
    print("\n[E2E-8] Scope 關鍵字判斷")
    from petq.prompt_template import is_in_scope

    scope_cases = [
        ("帶狗從日本回台灣", True, "犬"),
        ("狂犬病疫苗接種", True, "狂犬病"),
        ("FAVN 檢測", True, "FAVN"),
        ("寵物晶片規格", True, "寵物"),
        ("防檢署電話", True, "防檢署"),
        ("台積電股價", True, "交由 LLM"),  # 不確定的交由 LLM，不直接拒絕
    ]

    for query, expected_in, desc in scope_cases:
        in_scope, reason = is_in_scope(query)
        test(f"scope(「{query}」) = {expected_in}",
             in_scope == expected_in,
             f"got {in_scope}: {reason}")

    # --- E2E-9: CSV 資料完整性 ---
    print("\n[E2E-9] FAQ CSV 資料完整性")
    csv_path = "./petq/petq_faq.csv"
    test("CSV 檔案存在", os.path.exists(csv_path))

    if os.path.exists(csv_path):
        with open(csv_path, "r", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        test(f"CSV 有 {len(rows)} 筆 (>=20)", len(rows) >= 20)
        test("CSV 有 section 欄位", "section" in rows[0])
        test("CSV 有 question 欄位", "question" in rows[0])
        test("CSV 有 answer 欄位", "answer" in rows[0])
        test("CSV 有 source 欄位", "source" in rows[0])

        # 檢查各分類有資料
        sections = set(r["section"] for r in rows if r["section"])
        expected_sections = {"輸入檢疫", "狂犬病檢測", "費用", "服務資訊", "文件與晶片", "法規"}
        for sec in expected_sections:
            test(f"分類「{sec}」有資料", sec in sections, f"有: {sections}")

        # 檢查無空白 question
        empty_q = [i for i, r in enumerate(rows) if not r["question"].strip()]
        test("無空白 question", len(empty_q) == 0, f"空白行: {empty_q}")

        # 檢查無空白 answer
        empty_a = [i for i, r in enumerate(rows) if not r["answer"].strip()]
        test("無空白 answer", len(empty_a) == 0, f"空白行: {empty_a}")

    # --- E2E-10: Config 隔離 ---
    print("\n[E2E-10] Config 隔離檢查")
    from petq.config import get_config
    config = get_config()
    test("chroma_persist_dir 指向 petq", "petq" in config.chroma_persist_dir)
    test("faq_csv_path 指向 petq", "petq" in config.faq_csv_path)
    test("qa_log_db_path 指向 petq", "petq" in config.qa_log_db_path)
    test("enabled_tool_categories 是 petq", config.enabled_tool_categories == ["petq"])

    # 確保不會混用 motc
    test("chroma 不含 motc", "motc" not in config.chroma_persist_dir)
    test("faq 不含 motc", "motc" not in config.faq_csv_path)

    # --- E2E-11: Prompt 內容檢查 ---
    print("\n[E2E-11] Prompt 內容檢查")
    from petq.prompt_template import get_petq_prompt
    prompt = get_petq_prompt("(tools)")
    test("Prompt 含防檢署", "防檢署" in prompt)
    test("Prompt 含檢疫小幫手", "檢疫小幫手" in prompt)
    test("Prompt 含多語言", "多語" in prompt or "語言" in prompt)
    test("Prompt 含情境引導", "情境引導" in prompt or "來源國" in prompt)
    test("Prompt 含轉真人", "轉真人" in prompt)
    test("Prompt 含 Prompt 注入防護", "忽略" in prompt and "扮演" in prompt)
    test("Prompt 不含公路局", "公路局" not in prompt)
    test("Prompt 不含 motc", "motc" not in prompt.lower())

    # --- E2E-12: 工具隔離 ---
    print("\n[E2E-12] 工具隔離檢查")
    from tools import tool_registry
    # 確保 petq 工具已載入
    from petq.tools import rag, web_search, suggest, image_describe, graph_rag  # noqa: F401

    petq_tools = tool_registry.get_by_category("petq")
    tool_names = [t.name for t in petq_tools]
    test(f"petq 類別有 {len(petq_tools)} 個工具 (>=5)", len(petq_tools) >= 5)
    test("有 search_petq_faq", "search_petq_faq" in tool_names)
    test("有 search_petq_all", "search_petq_all" in tool_names)
    test("有 search_petq_graph_rag", "search_petq_graph_rag" in tool_names)
    test("有 search_petq_regulation", "search_petq_regulation" in tool_names)
    test("有 describe_petq_document", "describe_petq_document" in tool_names)
    test("有 get_petq_related_questions", "get_petq_related_questions" in tool_names)

    # 確保工具名稱不含 motc
    for t in petq_tools:
        test(f"工具 {t.name} 不含 motc", "motc" not in t.name.lower())


# ============================================================
#  主程式
# ============================================================
def main():
    global PASS, FAIL

    print("🧪 PETQ API + E2E Agent 測試")
    print(f"目標伺服器: {BASE}")

    # Part 1: API 端點測試（需要 server）
    try:
        r = requests.get(f"{BASE}/api/system/health", timeout=5)
        if r.status_code != 200:
            print(f"⚠️ 伺服器回傳 {r.status_code}，跳過 API 測試")
        else:
            test_api()
    except Exception as e:
        print(f"⚠️ 無法連接 {BASE}: {e}")
        print("跳過 Part 1（API 測試），請先啟動: uv run python -m uvicorn petq_app:app --port 8081")

    # Part 2: E2E Agent 測試（不需要 server，直接呼叫程式碼）
    test_e2e_agent()

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
