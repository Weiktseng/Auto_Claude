"""
公路局 MOTC 系統完整測試
涵蓋：工具、API、Agent、頁面路由

執行方式：
    # 全部測試（不需啟動 server）
    uv run python -m pytest tests/test_motc.py -v

    # 只跑某一類
    uv run python -m pytest tests/test_motc.py -v -k "tool"
    uv run python -m pytest tests/test_motc.py -v -k "api"
    uv run python -m pytest tests/test_motc.py -v -k "agent"
    uv run python -m pytest tests/test_motc.py -v -k "page"
"""

import os
import sys
import tempfile
from pathlib import Path

import pytest

# 確保專案根目錄在 path
sys.path.insert(0, str(Path(__file__).parent.parent))


# ============================================================
# Fixtures
# ============================================================

@pytest.fixture(scope="session")
def test_image():
    """建立一個測試用的小 PNG 圖片"""
    # 1x1 紅色 PNG（最小合法 PNG）
    import base64
    png_b64 = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
        "nGP4z8BQDwAEgAF/pooBPQAAAABJRU5ErkJggg=="
    )
    data = base64.b64decode(png_b64)
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False, prefix="motc_test_") as f:
        f.write(data)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture(scope="session")
def test_image_with_keyword():
    """建立帶交通關鍵字檔名的測試圖片"""
    import base64
    png_b64 = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
        "nGP4z8BQDwAEgAF/pooBPQAAAABJRU5ErkJggg=="
    )
    data = base64.b64decode(png_b64)
    paths = {}
    for name in ["駕照正面.png", "違規罰單.png", "省道路況_坍方.png", "交通標誌.png"]:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False, prefix="", dir=tempfile.gettempdir()) as f:
            # 需要用指定檔名
            pass
        p = os.path.join(tempfile.gettempdir(), name)
        with open(p, "wb") as f:
            f.write(data)
        paths[name] = p
    yield paths
    for p in paths.values():
        if os.path.exists(p):
            os.unlink(p)


@pytest.fixture(scope="session")
def fastapi_client():
    """建立 FastAPI TestClient（不需啟動 server）"""
    from fastapi.testclient import TestClient
    import motc_app
    return TestClient(motc_app.app)


# ============================================================
# 1. 工具單元測試 (test_tool_*)
# ============================================================

class TestToolImageDescribe:
    """多模態圖像辨識工具"""

    def test_valid_image_fallback(self, test_image):
        from motc.tools.image_describe import describe_traffic_image
        result = describe_traffic_image(test_image)
        assert "📷" in result
        assert "多模態" in result or "圖像辨識" in result

    def test_keyword_classification(self, test_image_with_keyword):
        from motc.tools.image_describe import describe_traffic_image
        expectations = {
            "駕照正面.png": "駕照/行照證件",
            "違規罰單.png": "公文/表單文件",
            "省道路況_坍方.png": "道路路況",
            "交通標誌.png": "交通標誌/號誌",
        }
        for filename, expected_type in expectations.items():
            path = test_image_with_keyword[filename]
            result = describe_traffic_image(path)
            assert expected_type in result, f"{filename} should be classified as {expected_type}, got: {result[:80]}"

    def test_file_not_found(self):
        from motc.tools.image_describe import describe_traffic_image
        result = describe_traffic_image("/nonexistent/path.jpg")
        assert "❌" in result
        assert "找不到" in result

    def test_unsupported_format(self):
        from motc.tools.image_describe import describe_traffic_image
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            f.write(b"not an image")
            path = f.name
        try:
            result = describe_traffic_image(path)
            assert "❌" in result
            assert "不支援" in result
        finally:
            os.unlink(path)

    def test_base64_encoding(self, test_image):
        from motc.tools.image_describe import _encode_image_to_base64
        b64, mime = _encode_image_to_base64(test_image)
        assert len(b64) > 0
        assert mime == "image/png"


class TestToolRAG:
    """RAG 搜尋工具"""

    def test_search_faq_returns_string(self):
        from motc.tools.rag import search_motc_faq
        result = search_motc_faq("駕照過期")
        assert isinstance(result, str)
        assert len(result) > 0

    def test_search_all_returns_string(self):
        from motc.tools.rag import search_motc_all
        result = search_motc_all("汽燃費")
        assert isinstance(result, str)
        assert len(result) > 0


class TestToolGraphRAG:
    """Graph RAG 工具"""

    def test_categories_structure(self):
        from motc.tools.graph_rag import CATEGORIES, CROSS_LINKS, REGULATIONS
        assert len(CATEGORIES) >= 8
        assert len(CROSS_LINKS) >= 5
        assert len(REGULATIONS) >= 5

    def test_build_graph_context(self):
        from motc.tools.graph_rag import _build_graph_context
        ctx = _build_graph_context(["駕照"])
        assert isinstance(ctx, dict)
        assert "primary_categories" in ctx
        assert "駕照" in ctx["primary_categories"]


class TestToolSuggest:
    """推薦問題工具"""

    def test_returns_list(self):
        from motc.tools.suggest import get_related_questions
        result = get_related_questions("駕照過期怎麼辦", "需要換發", 3)
        assert isinstance(result, list)
        assert len(result) <= 3

    def test_generic_fallback(self):
        from motc.tools.suggest import get_related_questions
        result = get_related_questions("你好", "歡迎", 3)
        assert isinstance(result, list)
        assert len(result) > 0


# ============================================================
# 2. API 測試 (test_api_*)
# ============================================================

class TestAPIHealth:
    """系統健康檢查 API"""

    def test_health_endpoint(self, fastapi_client):
        resp = fastapi_client.get("/api/system/health")
        assert resp.status_code == 200
        data = resp.json()
        assert "status" in data
        assert "components" in data
        assert "timestamp" in data

    def test_health_components(self, fastapi_client):
        data = fastapi_client.get("/api/system/health").json()
        components = data["components"]
        expected = ["fastapi", "chromadb", "embedding", "bm25", "llm", "graph_rag"]
        for comp in expected:
            assert comp in components, f"Missing component: {comp}"
            assert "status" in components[comp]


class TestAPIRAG:
    """RAG API"""

    def test_rag_search(self, fastapi_client):
        resp = fastapi_client.get("/api/rag/search", params={"query": "駕照"})
        assert resp.status_code == 200
        data = resp.json()
        assert "results" in data

    def test_rag_stats(self, fastapi_client):
        resp = fastapi_client.get("/api/rag/stats")
        assert resp.status_code == 200
        data = resp.json()
        assert "faq_collection" in data


class TestAPIGraphRAG:
    """Graph RAG API"""

    def test_graph_rag_structure(self, fastapi_client):
        resp = fastapi_client.get("/api/graph-rag/structure")
        assert resp.status_code == 200
        data = resp.json()
        assert "categories" in data
        assert "cross_links" in data
        assert "regulations" in data

    def test_graph_rag_query(self, fastapi_client):
        resp = fastapi_client.get("/api/graph-rag/query", params={"query": "駕照過戶"})
        assert resp.status_code == 200
        data = resp.json()
        assert "results" in data
        assert "graph_context" in data


class TestAPIImageUpload:
    """圖片上傳 API"""

    def test_upload_valid_image(self, fastapi_client, test_image):
        with open(test_image, "rb") as f:
            resp = fastapi_client.post(
                "/api/image/upload",
                files={"file": ("test.png", f, "image/png")},
            )
        assert resp.status_code == 200
        data = resp.json()
        assert "path" in data
        assert "filename" in data
        assert data["size"] > 0
        # 清理
        if os.path.exists(data["path"]):
            os.unlink(data["path"])

    def test_upload_invalid_format(self, fastapi_client):
        resp = fastapi_client.post(
            "/api/image/upload",
            files={"file": ("test.txt", b"not an image", "text/plain")},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "error" in data


# ============================================================
# 3. 頁面路由測試 (test_page_*)
# ============================================================

class TestPageRoutes:
    """HTML 頁面可訪問性"""

    @pytest.mark.parametrize("path,expected_text", [
        ("/", "交通部公路局"),
        ("/assistant", "助理"),
        ("/drafting", "擬稿"),
        ("/architecture", "架構"),
    ])
    def test_page_accessible(self, fastapi_client, path, expected_text):
        resp = fastapi_client.get(path)
        assert resp.status_code == 200
        assert expected_text in resp.text


# ============================================================
# 4. Agent 測試 (test_agent_*)
# ============================================================

class TestAgentSetup:
    """Agent 初始化與工具載入"""

    def test_agent_loads_all_tools(self):
        from motc.agent import MotcReActAgent
        agent = MotcReActAgent(verbose=False)
        expected_tools = [
            "search_motc_faq",
            "search_motc_all",
            "search_motc_realtime",
            "search_motc_law",
            "get_related_questions",
            "describe_traffic_image",
            "search_motc_graph_rag",
            "ask_user",
        ]
        for tool in expected_tools:
            assert tool in agent.tools, f"Missing tool: {tool}"

    def test_agent_tool_list_in_prompt(self):
        from motc.agent import MotcReActAgent
        agent = MotcReActAgent(verbose=False)
        prompt = agent.render_system_prompt()
        assert "describe_traffic_image" in prompt
        assert "search_motc_faq" in prompt
        assert "search_motc_graph_rag" in prompt

    def test_scope_check_in_scope(self):
        from motc.prompt_template import is_in_scope
        in_scope, reason = is_in_scope("駕照過期怎麼辦")
        assert in_scope is True

    def test_scope_check_generic(self):
        from motc.prompt_template import is_in_scope
        # 不含關鍵字的問題也會放行（交給 LLM 判斷）
        in_scope, reason = is_in_scope("你好")
        assert in_scope is True
        assert "LLM" in reason


class TestActionParser:
    """Action 解析器（含容錯格式）"""

    @pytest.fixture
    def parser(self):
        from core.base_agent import BaseWebAgent

        class MockAgent(BaseWebAgent):
            def _load_tools(self): pass
            def render_system_prompt(self): return ""

        agent = MockAgent.__new__(MockAgent)
        agent.tools = {
            "describe_traffic_image": lambda: None,
            "search_motc_faq": lambda: None,
            "search_motc_all": lambda: None,
        }
        return agent

    def test_standard_format(self, parser):
        tool, args = parser.parse_action('search_motc_faq("駕照過期")')
        assert tool == "search_motc_faq"
        assert args == ["駕照過期"]

    def test_kwargs_format(self, parser):
        tool, args = parser.parse_action('search_motc_faq(query="駕照過期", top_k=3)')
        assert tool == "search_motc_faq"
        assert args[0] == "駕照過期"

    def test_space_kwargs_format(self, parser):
        """修復 LLM 輸出空格分隔 kwargs 的問題"""
        tool, args = parser.parse_action(
            'describe_traffic_image image_path=/Users/test/行照.jpeg context=請辨識車輛行照'
        )
        assert tool == "describe_traffic_image"
        assert len(args) == 2
        assert "行照.jpeg" in args[0]
        assert "辨識" in args[1]

    def test_no_args(self, parser):
        tool, args = parser.parse_action("search_motc_all")
        assert tool == "search_motc_all"
        assert args == []

    def test_partial_format(self, parser):
        tool, args = parser.parse_action('search_motc_faq(駕照')
        assert tool == "search_motc_faq"


# ============================================================
# 5. 資料完整性測試 (test_data_*)
# ============================================================

class TestDataIntegrity:
    """FAQ 資料與知識圖譜完整性"""

    def test_faq_csv_exists(self):
        path = Path("motc/motc_faq.csv")
        assert path.exists(), "FAQ CSV not found"

    def test_faq_csv_has_rows(self):
        import csv
        with open("motc/motc_faq.csv", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        assert len(rows) >= 30, f"FAQ should have at least 30 entries, got {len(rows)}"

    def test_faq_csv_columns(self):
        import csv
        with open("motc/motc_faq.csv", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
        required = {"question", "answer", "section"}
        assert required.issubset(set(headers)), f"Missing columns: {required - set(headers)}"

    def test_graph_rag_categories_match_faq_sections(self):
        """知識圖譜分類應涵蓋 FAQ 的所有 section"""
        import csv
        from motc.tools.graph_rag import CATEGORIES

        with open("motc/motc_faq.csv", encoding="utf-8") as f:
            sections = {row["section"] for row in csv.DictReader(f) if row.get("section")}

        graph_categories = set(CATEGORIES.keys())
        uncovered = sections - graph_categories
        # 允許少量不匹配（FAQ section 名稱可能與 graph 略有差異）
        assert len(uncovered) <= 2, f"Graph RAG missing sections: {uncovered}"


# ============================================================
# 6. 設定與 Prompt 測試 (test_config_*)
# ============================================================

class TestConfig:
    """設定與 Prompt"""

    def test_motc_config_loads(self):
        from motc.config import get_config
        config = get_config()
        assert config.faq_collection_name
        assert config.chroma_persist_dir

    def test_prompt_has_scope_rules(self):
        from motc.prompt_template import get_motc_prompt
        prompt = get_motc_prompt(tool_list="test_tool(): 測試工具")
        assert "服務範圍" in prompt
        assert "ReAct" in prompt
        assert "test_tool" in prompt

    def test_prompt_has_date(self):
        from motc.prompt_template import get_motc_prompt
        prompt = get_motc_prompt()
        assert "2026" in prompt  # 當前年份

    def test_in_scope_keywords_exist(self):
        from motc.prompt_template import IN_SCOPE_KEYWORDS
        assert len(IN_SCOPE_KEYWORDS) >= 50
        assert "駕照" in IN_SCOPE_KEYWORDS
        assert "罰鍰" in IN_SCOPE_KEYWORDS
