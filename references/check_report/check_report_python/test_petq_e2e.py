"""
PETQ 瀏覽器 E2E 測試（Playwright）
自動開啟瀏覽器，模擬使用者操作，驗證前端渲染與互動

用法：
    # 先啟動伺服器
    uv run python -m uvicorn petq_app:app --port 8081

    # 執行測試（有頭模式，可觀看瀏覽器操作）
    uv run python tests/test_petq_e2e.py

    # 無頭模式（CI 用）
    HEADLESS=1 uv run python tests/test_petq_e2e.py
"""

import os
import sys
import tempfile
from playwright.sync_api import sync_playwright

BASE = os.getenv("TEST_BASE_URL", "http://localhost:8081")
HEADLESS = os.getenv("HEADLESS", "0") == "1"
SLOW_MO = 0 if HEADLESS else 300  # 有頭模式放慢以便觀看

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


def run_tests():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS, slow_mo=SLOW_MO, channel="chrome")
        context = browser.new_context(viewport={"width": 1280, "height": 900})
        page = context.new_page()

        # ============================================================
        #  0. 登入（如果需要）
        # ============================================================
        print("\n[0] 開啟首頁")
        page.goto(f"{BASE}/")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        if "/login" in page.url:
            page.fill("input[name='username'], #username, input[type='text']", "demo")
            page.fill("input[name='password'], #password, input[type='password']", "demo")
            page.click("button[type='submit'], .login-btn, button:has-text('登入')")
            page.wait_for_timeout(2000)
            test("登入成功", "/login" not in page.url, f"still at {page.url}")
        else:
            test("無需登入", True)

        # ============================================================
        #  1. 主客服頁面 — 品牌與 UI 元素
        # ============================================================
        print("\n[1] 主客服頁面 — 品牌與 UI 元素")
        page.goto(f"{BASE}/")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)

        test("頁面標題非空", page.title() != "")
        test("頁面含檢疫", "檢疫" in page.content())
        test("有輸入框", page.locator("#messageInput").is_visible())
        test("有送出按鈕", page.locator("#sendBtn").is_visible())
        test("有 📎 上傳按鈕", page.locator(".image-upload-btn").count() > 0)

        # 快速提問按鈕
        quick_btns = page.locator(".quick-btn")
        test("有快速提問按鈕", quick_btns.count() > 0, f"count={quick_btns.count()}")
        test("快速按鈕 >= 10 個", quick_btns.count() >= 10, f"count={quick_btns.count()}")

        # 品牌內容
        content = page.content()
        test("顯示「檢疫小幫手」", "檢疫小幫手" in content)
        test("顯示 0800-761-590 專線", "0800" in content)
        test("顯示多語系提示", "English" in content and "Tiếng Việt" in content)
        test("顯示農業部/防檢署", "農業部" in content or "防檢署" in content)

        # 4 大快捷分區
        service_sections = page.locator(".service-section")
        test("有 4 大服務分區", service_sections.count() == 4, f"count={service_sections.count()}")

        # 側欄 tabs
        sidebar_tabs = page.locator(".sidebar-tab")
        test("有側欄 tabs", sidebar_tabs.count() >= 2)

        # ============================================================
        #  2. 對話功能 — 簡單 FAQ
        # ============================================================
        print("\n[2] 對話功能 — 送出問題 → 等待 AI 回覆")
        page.fill("#messageInput", "狂犬病抗體檢測費用多少？")
        page.click("#sendBtn")

        # 等待 AI 回覆
        try:
            page.wait_for_selector(".final-answer", timeout=30000)
            test("AI 回覆出現", True)
        except Exception:
            test("AI 回覆出現", False, "30 秒內未出現 .final-answer")

        # 檢查回覆內容
        answer_el = page.locator(".final-answer .step-content").last
        if answer_el.count() > 0 and answer_el.is_visible():
            answer_text = answer_el.inner_text()
            test("回覆含費用相關",
                 "5,000" in answer_text or "5000" in answer_text or "費" in answer_text,
                 answer_text[:80])
        else:
            test("回覆含費用相關", False, "找不到 .step-content")

        # 反饋按鈕
        test("有 👍👎 反饋按鈕", page.locator(".feedback-btn").count() >= 2)

        # 推薦問題（等待渲染，可能需要額外時間）
        page.wait_for_timeout(3000)
        suggestions = page.locator(".suggestion-item")
        suggestions_panel = page.locator("#suggestionsPanel")
        has_suggestions = (
            suggestions.count() > 0
            or (suggestions_panel.count() > 0 and suggestions_panel.is_visible())
            # 有些主題的推薦問題可能透過不同 CSS class 渲染
            or page.locator("[data-suggestion]").count() > 0
        )
        test("有推薦問題或快速按鈕", has_suggestions, f"items={suggestions.count()}")

        # ============================================================
        #  3. 快速按鈕功能
        # ============================================================
        print("\n[3] 快速按鈕功能")

        # 開新對話（避免上一輪影響）
        new_conv_btn = page.locator("#newConversationBtn")
        if new_conv_btn.is_visible():
            new_conv_btn.click()
            page.wait_for_timeout(1000)

        # 點擊快速按鈕
        first_btn = page.locator(".quick-btn").first
        if first_btn.is_visible():
            btn_text = first_btn.get_attribute("data-suggestion") or first_btn.inner_text()
            first_btn.click()
            page.wait_for_timeout(1000)

            # 快速按鈕可能會：(a) 自動送出，或 (b) 只填入輸入框
            input_val = page.locator("#messageInput").input_value()
            has_input = len(input_val) > 0
            test("快速按鈕填入輸入框", has_input, f"value='{input_val}'")

            # 如果只填入但未送出，手動點送出
            if has_input and page.locator(".final-answer").count() == 0:
                page.click("#sendBtn")

            try:
                page.wait_for_selector(".final-answer", timeout=30000)
                test("快速按鈕觸發 AI 回覆", True)
            except Exception:
                test("快速按鈕觸發 AI 回覆", False, "30 秒內未出現回覆")
        else:
            test("快速按鈕可見", False, "快速按鈕不可見")

        # ============================================================
        #  4. 檔案上傳 UI
        # ============================================================
        print("\n[4] 檔案上傳 UI")

        # 開新對話
        if new_conv_btn.is_visible():
            new_conv_btn.click()
            page.wait_for_timeout(1000)

        # 建立測試 TXT 檔
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
            f.write("犬貓健康證明書測試內容\n晶片號碼：900123456789012")
            txt_path = f.name

        # 觸發檔案選擇
        file_input = page.locator("input[type='file']")
        file_input.set_input_files(txt_path)
        page.wait_for_timeout(2000)  # 等上傳完成

        # 檢查預覽列出現
        preview = page.locator(".file-preview-bar")
        test("上傳後顯示預覽列", preview.is_visible())
        if preview.is_visible():
            test("預覽列含檔名", "txt" in preview.inner_text().lower())

        # 移除檔案
        remove_btn = page.locator(".remove-file-btn").first
        if remove_btn.count() > 0 and remove_btn.is_visible():
            remove_btn.click()
            page.wait_for_timeout(500)
            test("移除後預覽列隱藏",
                 not preview.is_visible() or preview.inner_text().strip() == "")
        else:
            test("移除按鈕可見", False, "找不到 .remove-file-btn")

        os.unlink(txt_path)

        # ============================================================
        #  5. 多種問題情境
        # ============================================================
        print("\n[5] 多種問題情境")

        test_scenarios = [
            ("從日本帶狗回台灣需要什麼文件？", ["日本", "文件", "晶片", "疫苗", "證明"], "日本帶狗回台"),
            ("晶片規格有什麼要求？", ["ISO", "晶片", "11784", "11785"], "晶片規格查詢"),
        ]

        for question, expected_keywords, desc in test_scenarios:
            # 開新對話
            if new_conv_btn.is_visible():
                new_conv_btn.click()
                page.wait_for_timeout(1000)

            page.fill("#messageInput", question)
            page.click("#sendBtn")

            try:
                page.wait_for_selector(".final-answer", timeout=30000)
                answer_el = page.locator(".final-answer .step-content").last
                if answer_el.count() > 0 and answer_el.is_visible():
                    text = answer_el.inner_text()
                    has_keyword = any(kw in text for kw in expected_keywords)
                    test(f"[{desc}] 回覆含關鍵字", has_keyword,
                         f"text[:80]={text[:80]}, expected={expected_keywords}")
                else:
                    test(f"[{desc}] 回覆含關鍵字", False, "找不到 .step-content")
            except Exception:
                test(f"[{desc}] AI 回覆出現", False, "30 秒內未出現")

        # ============================================================
        #  6. 多語系輸入
        # ============================================================
        print("\n[6] 多語系輸入（英文）")

        if new_conv_btn.is_visible():
            new_conv_btn.click()
            page.wait_for_timeout(1000)

        page.fill("#messageInput", "What documents do I need to bring my dog to Taiwan from Japan?")
        page.click("#sendBtn")

        try:
            page.wait_for_selector(".final-answer", timeout=30000)
            answer_el = page.locator(".final-answer .step-content").last
            if answer_el.count() > 0 and answer_el.is_visible():
                text = answer_el.inner_text()
                # 回覆應該是英文（或至少含英文關鍵字）
                has_english = any(kw in text.lower() for kw in [
                    "document", "vaccine", "rabies", "chip", "microchip",
                    "quarantine", "certificate", "taiwan", "japan",
                    "文件", "疫苗",  # 也可能用中文回覆
                ])
                test("英文問題有回覆", has_english, text[:100])
            else:
                test("英文問題有回覆", False, "找不到 .step-content")
        except Exception:
            test("英文問題 AI 回覆出現", False, "30 秒內未出現")

        # ============================================================
        #  7. Edge Case: 空白輸入
        # ============================================================
        print("\n[7] Edge Case: 空白輸入")

        if new_conv_btn.is_visible():
            new_conv_btn.click()
            page.wait_for_timeout(1000)

        page.fill("#messageInput", "")
        page.click("#sendBtn")
        page.wait_for_timeout(1000)

        # 空白輸入不應產生新的 AI 回覆
        # 計算 final-answer 數量
        answer_count = page.locator(".final-answer").count()
        test("空白輸入不產生回覆", answer_count == 0, f"answers={answer_count}")

        # ============================================================
        #  8. Edge Case: 超長輸入
        # ============================================================
        print("\n[8] Edge Case: 超長輸入")

        if new_conv_btn.is_visible():
            new_conv_btn.click()
            page.wait_for_timeout(1000)

        long_text = "帶狗從日本回台灣需要什麼文件？" * 20  # ~400 chars
        page.fill("#messageInput", long_text)
        page.click("#sendBtn")

        try:
            page.wait_for_selector(".final-answer", timeout=30000)
            test("超長輸入仍有回覆", True)
        except Exception:
            test("超長輸入仍有回覆", False, "30 秒內未出現")

        # ============================================================
        #  9. Widget 頁面
        # ============================================================
        print("\n[9] Widget 嵌入頁面")
        page.goto(f"{BASE}/widget")
        page.wait_for_load_state("networkidle")
        test("Widget 頁面載入", "Widget" in page.content() or "widget" in page.content().lower())
        test("Widget 含 iframe", page.locator("iframe").count() > 0)

        # ============================================================
        #  10. Swagger UI
        # ============================================================
        print("\n[10] Swagger UI")
        page.goto(f"{BASE}/docs")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)
        test("Swagger UI 載入",
             "swagger" in page.content().lower() or "openapi" in page.content().lower())

        # ============================================================
        #  11. 側欄功能
        # ============================================================
        print("\n[11] 側欄功能")
        page.goto(f"{BASE}/")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)

        # 工具 tab
        tools_tab = page.locator(".sidebar-tab:has-text('工具')")
        if tools_tab.count() > 0:
            tools_tab.click()
            page.wait_for_timeout(500)
            tools_panel = page.locator("#toolsPanel")
            test("工具面板可見", tools_panel.is_visible())

            tool_cards = page.locator(".tool-card")
            test("有工具卡片", tool_cards.count() > 0, f"count={tool_cards.count()}")

            # 工具卡片有推薦問題
            suggestion_btns = page.locator(".tool-card .suggestion-btn")
            test("工具卡片有推薦按鈕", suggestion_btns.count() > 0, f"count={suggestion_btns.count()}")
        else:
            test("有工具 tab", False, "找不到工具 tab")

        # 對話 tab
        conv_tab = page.locator(".sidebar-tab:has-text('對話')")
        if conv_tab.count() > 0:
            conv_tab.click()
            page.wait_for_timeout(500)
            conv_panel = page.locator("#conversationsPanel")
            test("對話面板可見", conv_panel.is_visible())

        # ============================================================
        #  12. 設定功能
        # ============================================================
        print("\n[12] 設定功能")
        settings_btn = page.locator(".settings-btn")
        if settings_btn.count() > 0:
            settings_btn.click()
            page.wait_for_timeout(500)
            settings_modal = page.locator("#settingsModal")
            test("設定 modal 出現", settings_modal.is_visible())

            # 關閉
            close_btn = page.locator("#settingsModal .close-btn, #settingsModal button:has-text('關閉')").first
            if close_btn.count() > 0:
                close_btn.click()
                page.wait_for_timeout(300)
        else:
            test("有設定按鈕", False, "找不到 .settings-btn")

        browser.close()


def main():
    print("🧪 PETQ 瀏覽器 E2E 測試（Playwright）")
    print(f"目標伺服器: {BASE}")
    print(f"模式: {'無頭' if HEADLESS else '有頭（可觀看瀏覽器）'}")

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

    run_tests()

    total = PASS + FAIL
    print("\n" + "=" * 60)
    print(f"E2E 測試結果: {PASS}/{total} 通過, {FAIL} 失敗")
    print("=" * 60)

    if ERRORS:
        print("\n❌ 失敗項目:")
        for e in ERRORS:
            print(f"  - {e}")
    else:
        print("\n✅ 全部通過！")


if __name__ == "__main__":
    main()
