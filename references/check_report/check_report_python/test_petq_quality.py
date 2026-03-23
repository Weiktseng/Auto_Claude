"""
PETQ 效果測試（LLM 評分版）
透過瀏覽器發問 → 擷取 AI 回覆 → 送 LLM 依 5 維度評分 → 產出評測報告

用法：
    # 先啟動伺服器
    uv run python -m uvicorn petq_app:app --port 8081

    # 執行效果測試（無頭模式）
    HEADLESS=1 uv run python tests/test_petq_quality.py

    # 有頭模式（可觀看瀏覽器操作）
    uv run python tests/test_petq_quality.py

    # 指定評分 LLM
    LLM_MODEL=gpt-4.1 uv run python tests/test_petq_quality.py

評分維度（每項 1-5 分）：
    1. 正確性 — 資訊是否正確，有無捏造
    2. 完整性 — 是否涵蓋該問題所需的全部資訊
    3. 來源引用 — 有無引用法規、官方來源
    4. 語言品質 — 繁體中文或多語回覆是否流暢自然
    5. 實用性 — 使用者能否根據回答直接採取行動
"""

import json
import os
import sys
import time
from datetime import datetime
from dataclasses import dataclass, field, asdict
from typing import List, Optional

# 加入專案根目錄
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from playwright.sync_api import sync_playwright

BASE = os.getenv("TEST_BASE_URL", "http://localhost:8081")
HEADLESS = os.getenv("HEADLESS", "0") == "1"
SLOW_MO = 0 if HEADLESS else 200


# ============================================================
#  評分標準 & 資料結構
# ============================================================

RUBRIC = """你是犬貓輸出入檢疫智慧客服的品質評估專家。請根據以下 5 個維度，為 AI 客服的回答評分。

【評分維度】（每項 1-5 分）

1. 正確性 (Accuracy)
   5 = 所有資訊完全正確，與官方規定一致
   4 = 大致正確，有極少數不精確之處但不影響使用
   3 = 核心正確但有部分細節錯誤
   2 = 有明顯錯誤可能誤導使用者
   1 = 大量錯誤或捏造資訊

2. 完整性 (Completeness)
   5 = 涵蓋該問題所需的全部關鍵資訊，無遺漏
   4 = 涵蓋主要資訊，僅缺少次要細節
   3 = 涵蓋約一半的必要資訊
   2 = 僅觸及表面，遺漏多項重要資訊
   1 = 幾乎沒有提供有用資訊

3. 來源引用 (Source Citation)
   5 = 明確引用法規條文、官方公告、網址等
   4 = 提及來源但不夠具體（如「依據防檢署規定」）
   3 = 部分有引用、部分無
   2 = 幾乎沒有引用來源
   1 = 完全沒有引用，無法驗證

4. 語言品質 (Language Quality)
   5 = 繁體中文流暢自然，格式清晰，無簡體字
   4 = 大致流暢，偶有小瑕疵
   3 = 可理解但表達不夠清晰
   2 = 有語法錯誤或混用簡體字
   1 = 難以理解

5. 實用性 (Actionability)
   5 = 使用者可直接依此行動（含具體步驟、費用、時程、聯絡方式）
   4 = 大致可行動，缺少少數實際操作細節
   3 = 提供方向但需使用者自行查找更多資訊
   2 = 過於籠統，難以直接行動
   1 = 無法據此採取任何行動

【輸出格式】
請嚴格以 JSON 格式回覆，不要有其他文字：
{
  "accuracy": <1-5>,
  "completeness": <1-5>,
  "citation": <1-5>,
  "language": <1-5>,
  "actionability": <1-5>,
  "overall": <1-5>,
  "strengths": "<回答的優點，1-2句>",
  "weaknesses": "<回答的不足，1-2句>",
  "suggestion": "<具體改進建議，1-2句>"
}

overall 為五項的加權平均（正確性×2 + 完整性×2 + 來源引用×1 + 語言品質×1 + 實用性×2），四捨五入到整數。
"""

# ============================================================
#  測試案例定義
# ============================================================

@dataclass
class TestResult:
    """一個測試的評分結果"""
    test_id: str
    category: str
    question: str
    ai_answer: str
    response_time_ms: int
    scores: dict = field(default_factory=dict)
    evaluation_raw: str = ""
    error: str = ""


# 從外部題庫載入（78 題，來自官方 FAQ / NVRI / 對抗性 / 多語系 / 情境模擬）
_tests_dir = os.path.dirname(os.path.abspath(__file__))
if _tests_dir not in sys.path:
    sys.path.insert(0, _tests_dir)
from petq_test_cases import QUALITY_TEST_CASES, QualityTestCase

# 轉換為內部格式
@dataclass
class TestCase:
    id: str
    category: str
    question: str
    reference_answer: str
    difficulty: str = "normal"

TEST_CASES = [
    TestCase(
        id=tc.id,
        category=tc.category,
        question=tc.question,
        reference_answer=tc.reference_answer,
        difficulty=tc.difficulty,
    )
    for tc in QUALITY_TEST_CASES
]


# ============================================================
#  LLM 評分器
# ============================================================

def evaluate_with_llm(question: str, ai_answer: str, reference: str) -> dict:
    """用 LLM 評分 AI 回答的品質"""
    from openai import OpenAI
    from dotenv import load_dotenv
    load_dotenv()

    client = OpenAI()
    model = os.getenv("EVAL_MODEL", os.getenv("LLM_MODEL", "gpt-4.1-mini"))

    prompt = f"""【使用者問題】
{question}

【正確答案要點（供評分參考）】
{reference}

【AI 客服的實際回答】
{ai_answer}

請根據評分標準評分。"""

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": RUBRIC},
                {"role": "user", "content": prompt},
            ],
            temperature=0,
            max_tokens=500,
        )
        raw = resp.choices[0].message.content.strip()

        # 解析 JSON（容錯：去除 markdown code block）
        cleaned = raw
        if "```" in cleaned:
            cleaned = cleaned.split("```")[1]
            if cleaned.startswith("json"):
                cleaned = cleaned[4:]
        cleaned = cleaned.strip()

        scores = json.loads(cleaned)
        return scores

    except json.JSONDecodeError:
        return {"error": f"JSON 解析失敗: {raw[:200]}", "raw": raw}
    except Exception as e:
        return {"error": str(e)}


# ============================================================
#  瀏覽器 E2E 執行器
# ============================================================

def run_browser_tests(test_cases: List[TestCase]) -> List[TestResult]:
    """用 Playwright 瀏覽器執行所有測試"""
    results = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS, slow_mo=SLOW_MO, channel="chrome")
        context = browser.new_context(viewport={"width": 1280, "height": 900})
        pg = context.new_page()

        # 處理登入（如果有）
        pg.goto(f"{BASE}/")
        pg.wait_for_load_state("networkidle")
        pg.wait_for_timeout(2000)
        if pg.locator("#loginForm, input[name='username'], #username").count() > 0:
            print("  🔐 偵測到登入頁面，自動登入...")
            pg.fill("input[name='username'], #username, input[type='text']", "demo")
            pg.fill("input[name='password'], #password, input[type='password']", "demo")
            pg.click("button[type='submit'], .login-btn, #loginBtn, button:has-text('登入')")
            pg.wait_for_timeout(3000)
            print(f"  🔐 登入後 URL: {pg.url}")

        for i, tc in enumerate(test_cases, 1):
            print(f"\n  [{i}/{len(test_cases)}] [{tc.category}] {tc.question[:40]}...")

            result = TestResult(
                test_id=tc.id,
                category=tc.category,
                question=tc.question,
                ai_answer="",
                response_time_ms=0,
            )

            try:
                # 開新對話
                pg.goto(f"{BASE}/")
                pg.wait_for_load_state("networkidle")
                pg.wait_for_timeout(3000)

                # 等待 JS 動態元素建立
                pg.wait_for_selector("#messageInput", state="visible", timeout=15000)

                new_btn = pg.locator("#newConversationBtn")
                if new_btn.count() > 0 and new_btn.is_visible():
                    new_btn.click()
                    pg.wait_for_timeout(1000)

                # 送出問題
                pg.fill("#messageInput", tc.question)
                start_time = time.time()
                pg.click("#sendBtn")

                # 等待回覆
                pg.wait_for_selector(".final-answer", timeout=45000)
                elapsed = int((time.time() - start_time) * 1000)
                result.response_time_ms = elapsed

                # 擷取回覆文字
                answer_el = pg.locator(".final-answer .step-content").last
                if answer_el.count() > 0 and answer_el.is_visible():
                    result.ai_answer = answer_el.inner_text().strip()
                else:
                    # fallback: 嘗試取最後一個 .final-answer 的全文
                    fa = pg.locator(".final-answer").last
                    if fa.count() > 0:
                        result.ai_answer = fa.inner_text().strip()

                print(f"    回覆 {len(result.ai_answer)} 字, {elapsed}ms")

            except Exception as e:
                result.error = str(e)
                print(f"    ❌ {e}")

            results.append(result)

        browser.close()

    return results


# ============================================================
#  報告產出
# ============================================================

def generate_report(results: List[TestResult], test_cases: List[TestCase]) -> dict:
    """產出完整評測報告"""

    report = {
        "metadata": {
            "test_time": datetime.now().isoformat(),
            "total_cases": len(results),
            "eval_model": os.getenv("EVAL_MODEL", os.getenv("LLM_MODEL", "gpt-4.1-mini")),
            "base_url": BASE,
        },
        "summary": {},
        "by_category": {},
        "by_difficulty": {},
        "details": [],
    }

    # 計算各維度平均分
    dims = ["accuracy", "completeness", "citation", "language", "actionability", "overall"]
    all_scores = {d: [] for d in dims}
    cat_scores = {}
    diff_scores = {}
    response_times = []

    for r in results:
        detail = {
            "test_id": r.test_id,
            "category": r.category,
            "question": r.question,
            "answer_preview": r.ai_answer[:200] + "..." if len(r.ai_answer) > 200 else r.ai_answer,
            "response_time_ms": r.response_time_ms,
            "scores": r.scores,
            "error": r.error,
        }
        report["details"].append(detail)

        if r.scores and "error" not in r.scores:
            for d in dims:
                val = r.scores.get(d)
                if val is not None:
                    all_scores[d].append(val)

            # 按分類
            cat = r.category
            if cat not in cat_scores:
                cat_scores[cat] = {d: [] for d in dims}
            for d in dims:
                val = r.scores.get(d)
                if val is not None:
                    cat_scores[cat][d].append(val)

            # 按難度
            tc = next((t for t in test_cases if t.id == r.test_id), None)
            if tc:
                diff = tc.difficulty
                if diff not in diff_scores:
                    diff_scores[diff] = {d: [] for d in dims}
                for d in dims:
                    val = r.scores.get(d)
                    if val is not None:
                        diff_scores[diff][d].append(val)

        if r.response_time_ms > 0:
            response_times.append(r.response_time_ms)

    # 整體摘要
    report["summary"] = {
        d: round(sum(all_scores[d]) / len(all_scores[d]), 2) if all_scores[d] else 0
        for d in dims
    }
    report["summary"]["avg_response_time_ms"] = (
        round(sum(response_times) / len(response_times)) if response_times else 0
    )
    report["summary"]["pass_rate"] = (
        f"{sum(1 for s in all_scores['overall'] if s >= 4)}/{len(all_scores['overall'])}"
    )

    # 分類摘要
    for cat, scores in cat_scores.items():
        report["by_category"][cat] = {
            d: round(sum(scores[d]) / len(scores[d]), 2) if scores[d] else 0
            for d in dims
        }

    # 難度摘要
    for diff, scores in diff_scores.items():
        report["by_difficulty"][diff] = {
            d: round(sum(scores[d]) / len(scores[d]), 2) if scores[d] else 0
            for d in dims
        }

    return report


def print_report(report: dict):
    """印出格式化報告"""
    print("\n" + "=" * 70)
    print("📊 犬貓檢疫智慧客服 — 效果評測報告")
    print("=" * 70)

    s = report["summary"]
    print(f"\n  評測時間: {report['metadata']['test_time'][:19]}")
    print(f"  評測案例: {report['metadata']['total_cases']} 題")
    print(f"  評分模型: {report['metadata']['eval_model']}")
    print(f"  通過率 (≥4分): {s['pass_rate']}")
    print(f"  平均回應時間: {s['avg_response_time_ms']}ms")

    print(f"\n{'─' * 70}")
    print(f"  {'維度':<14} {'分數':>6}  {'等級'}")
    print(f"{'─' * 70}")
    grade_map = {5: "★★★★★ 卓越", 4: "★★★★☆ 良好", 3: "★★★☆☆ 尚可", 2: "★★☆☆☆ 待改進", 1: "★☆☆☆☆ 不合格"}
    for dim, label in [
        ("accuracy", "正確性"),
        ("completeness", "完整性"),
        ("citation", "來源引用"),
        ("language", "語言品質"),
        ("actionability", "實用性"),
        ("overall", "總分"),
    ]:
        score = s.get(dim, 0)
        grade = grade_map.get(round(score), "")
        marker = "  ◀ 總分" if dim == "overall" else ""
        print(f"  {label:<12} {score:>6.2f}  {grade}{marker}")

    # 分類表現
    if report["by_category"]:
        print(f"\n{'─' * 70}")
        print(f"  {'分類':<12} {'正確性':>6} {'完整性':>6} {'引用':>6} {'語言':>6} {'實用':>6} {'總分':>6}")
        print(f"{'─' * 70}")
        for cat, scores in report["by_category"].items():
            print(f"  {cat:<10} {scores.get('accuracy',0):>6.1f} {scores.get('completeness',0):>6.1f} "
                  f"{scores.get('citation',0):>6.1f} {scores.get('language',0):>6.1f} "
                  f"{scores.get('actionability',0):>6.1f} {scores.get('overall',0):>6.1f}")

    # 難度表現
    if report["by_difficulty"]:
        print(f"\n{'─' * 70}")
        print(f"  {'難度':<12} {'正確性':>6} {'完整性':>6} {'總分':>6}")
        print(f"{'─' * 70}")
        for diff in ["easy", "normal", "hard", "edge"]:
            if diff in report["by_difficulty"]:
                scores = report["by_difficulty"][diff]
                print(f"  {diff:<10} {scores.get('accuracy',0):>6.1f} "
                      f"{scores.get('completeness',0):>6.1f} {scores.get('overall',0):>6.1f}")

    # 低分項目
    print(f"\n{'─' * 70}")
    print("  需改進項目（總分 < 4）：")
    low_score_items = [
        d for d in report["details"]
        if d["scores"] and "error" not in d["scores"] and d["scores"].get("overall", 5) < 4
    ]
    if low_score_items:
        for d in low_score_items:
            print(f"\n  ⚠️ [{d['test_id']}] {d['question'][:50]}")
            print(f"     總分: {d['scores'].get('overall')}/5")
            if d["scores"].get("weaknesses"):
                print(f"     不足: {d['scores']['weaknesses']}")
            if d["scores"].get("suggestion"):
                print(f"     建議: {d['scores']['suggestion']}")
    else:
        print("  ✅ 全部通過！")

    # 各題優缺點
    print(f"\n{'─' * 70}")
    print("  各題評語：")
    for d in report["details"]:
        if d["scores"] and "error" not in d["scores"]:
            overall = d["scores"].get("overall", "?")
            print(f"\n  [{d['test_id']}] {d['question'][:45]}  → {overall}/5")
            if d["scores"].get("strengths"):
                print(f"    👍 {d['scores']['strengths']}")
            if d["scores"].get("weaknesses"):
                print(f"    👎 {d['scores']['weaknesses']}")
            if d["scores"].get("suggestion"):
                print(f"    💡 {d['scores']['suggestion']}")
        elif d.get("error"):
            print(f"\n  [{d['test_id']}] {d['question'][:45]}  → ❌ {d['error'][:60]}")

    print(f"\n{'=' * 70}")


# ============================================================
#  主程式
# ============================================================

def main():
    print("🧪 PETQ 效果測試（LLM 評分版）")
    print(f"目標伺服器: {BASE}")
    print(f"模式: {'無頭' if HEADLESS else '有頭'}")
    print(f"測試題數: {len(TEST_CASES)}")

    # 檢查伺服器
    import requests
    try:
        r = requests.get(f"{BASE}/api/system/health", timeout=5)
        if r.status_code != 200:
            print(f"❌ 伺服器回傳 {r.status_code}")
            return
    except Exception as e:
        print(f"❌ 無法連接 {BASE}: {e}")
        print("請先啟動: uv run python -m uvicorn petq_app:app --port 8081")
        return

    # Phase 1: 瀏覽器 E2E 發問
    print("\n" + "=" * 60)
    print("Phase 1: 瀏覽器 E2E 對話")
    print("=" * 60)

    results = run_browser_tests(TEST_CASES)

    # Phase 2: LLM 評分
    print("\n" + "=" * 60)
    print("Phase 2: LLM 品質評分")
    print("=" * 60)

    tc_map = {tc.id: tc for tc in TEST_CASES}
    for i, r in enumerate(results, 1):
        if not r.ai_answer and not r.error:
            r.error = "無 AI 回覆"
            continue
        if r.error:
            continue

        tc = tc_map.get(r.test_id)
        if not tc:
            continue

        print(f"  [{i}/{len(results)}] 評分 {r.test_id}...", end=" ", flush=True)
        scores = evaluate_with_llm(tc.question, r.ai_answer, tc.reference_answer)
        r.scores = scores

        if "error" in scores:
            print(f"❌ {scores['error'][:50]}")
        else:
            print(f"overall={scores.get('overall', '?')}/5")

    # Phase 3: 產出報告
    report = generate_report(results, TEST_CASES)
    print_report(report)

    # 儲存 JSON 報告
    report_path = "petq/data/quality_report.json"
    os.makedirs(os.path.dirname(report_path), exist_ok=True)

    # 儲存時包含完整回答
    full_report = report.copy()
    full_report["details"] = [
        {**d, "full_answer": r.ai_answer}
        for d, r in zip(report["details"], results)
    ]
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(full_report, f, ensure_ascii=False, indent=2)
    print(f"\n📄 完整報告: {report_path}")


if __name__ == "__main__":
    main()
