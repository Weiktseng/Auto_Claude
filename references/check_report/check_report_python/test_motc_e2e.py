"""
MOTC 瀏覽器 E2E 測試（Playwright）
自動開啟瀏覽器，模擬使用者操作，驗證前端渲染

用法：
    # 先啟動伺服器
    uv run python -m uvicorn motc_app:app --port 8080

    # 執行測試（有頭模式，可觀看瀏覽器操作）
    uv run python tests/test_motc_e2e.py

    # 無頭模式（CI 用）
    HEADLESS=1 uv run python tests/test_motc_e2e.py
"""

import os
import sys
import tempfile
from playwright.sync_api import sync_playwright

BASE = os.getenv("TEST_BASE_URL", "http://localhost:8080")
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
        #  0. 登入
        # ============================================================
        print("\n[0] 登入")
        page.goto(f"{BASE}/")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(1000)

        # 如果被重導到登入頁面
        if "/login" in page.url:
            page.fill("input[name='username'], #username, input[type='text']", "demo")
            page.fill("input[name='password'], #password, input[type='password']", "demo")
            page.click("button[type='submit'], .login-btn, button:has-text('登入')")
            page.wait_for_timeout(2000)
            test("登入成功", "/login" not in page.url, f"still at {page.url}")
        else:
            test("無需登入", True)

        # ============================================================
        #  1. 主客服頁面
        # ============================================================
        print("\n[1] 主客服頁面")
        page.goto(f"{BASE}/")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)  # 等 JS 動態元素建立

        test("頁面載入", page.title() != "")
        test("有輸入框", page.locator("#messageInput").is_visible())
        test("有送出按鈕", page.locator("#sendBtn").is_visible())
        # 📎 按鈕是 JS 動態建立的，等它出現
        test("有 📎 上傳按鈕", page.locator(".image-upload-btn").count() > 0)

        # 快速提問按鈕
        quick_btns = page.locator(".quick-btn")
        test("有快速提問按鈕", quick_btns.count() > 0, f"count={quick_btns.count()}")

        # 頂部專線提示
        test("顯示 0800 專線", "0800" in page.content())

        # ============================================================
        #  2. 對話功能
        # ============================================================
        print("\n[2] 對話功能（送出問題 → 等待 AI 回覆）")
        page.fill("#messageInput", "駕照過期怎麼換發？")
        page.click("#sendBtn")

        # 等待 AI 回覆（final-answer 出現）
        try:
            page.wait_for_selector(".final-answer", timeout=30000)
            test("AI 回覆出現", True)
        except Exception:
            test("AI 回覆出現", False, "30 秒內未出現 .final-answer")

        # 檢查回覆內容
        answer_el = page.locator(".final-answer .step-content").last
        if answer_el.is_visible():
            answer_text = answer_el.inner_text()
            test("回覆含駕照相關", "駕照" in answer_text or "換發" in answer_text or "監理" in answer_text, answer_text[:50])
        else:
            test("回覆含駕照相關", False, "找不到 .step-content")

        # 檢查反饋按鈕
        test("有 👍👎 反饋按鈕", page.locator(".feedback-btn").count() >= 2)

        # 檢查推薦問題（面板可能需要滾動才可見）
        suggestions = page.locator(".suggestion-item")
        suggestions_panel = page.locator("#suggestionsPanel")
        has_suggestions = suggestions.count() > 0 or (suggestions_panel.count() > 0 and "none" not in (suggestions_panel.get_attribute("style") or ""))
        test("有推薦問題", has_suggestions, f"items={suggestions.count()}")

        # ============================================================
        #  3. 檔案上傳 UI
        # ============================================================
        print("\n[3] 檔案上傳 UI")

        # 建立測試 TXT 檔
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
            f.write("測試文件內容")
            txt_path = f.name

        # 觸發檔案選擇（Playwright 可直接設定 file input）
        file_input = page.locator("input[type='file']")
        file_input.set_input_files(txt_path)
        page.wait_for_timeout(1000)

        # 檢查預覽列出現
        preview = page.locator(".file-preview-bar")
        test("上傳後顯示預覽列", preview.is_visible())
        test("預覽列含檔名", "txt" in preview.inner_text().lower() if preview.is_visible() else False)

        # 移除檔案
        remove_btn = page.locator(".remove-file-btn").first
        if remove_btn.is_visible():
            remove_btn.click()
            page.wait_for_timeout(500)
            test("移除後預覽列隱藏", not preview.is_visible() or preview.inner_text().strip() == "")

        os.unlink(txt_path)

        # ============================================================
        #  4. 話務助理頁面
        # ============================================================
        print("\n[4] 話務助理頁面")
        page.goto(f"{BASE}/assistant")
        page.wait_for_load_state("networkidle")

        test("話務助理載入", page.locator(".assistant-toolbar").is_visible())

        # 三個模式 tab
        mode_tabs = page.locator(".mode-tab")
        test("有 3 個模式 tab", mode_tabs.count() == 3, f"count={mode_tabs.count()}")

        # 選擇劇本
        page.select_option("#scenarioSelect", "1")  # 違規罰鍰申訴
        page.wait_for_timeout(3000)  # 等客戶訊息播放

        # 檢查客戶訊息出現
        customer_msgs = page.locator(".msg-bubble.customer")
        test("客戶訊息出現", customer_msgs.count() > 0)

        # 等 AI 建議出現
        try:
            page.wait_for_selector(".suggestion-card", timeout=15000)
            test("AI 建議卡片出現", True)
        except Exception:
            test("AI 建議卡片出現", False, "15 秒內未出現")

        # 檢查自動標籤
        subtopic_tags = page.locator(".meta-tag.subtopic")
        test("有子分類標籤", subtopic_tags.count() > 0, f"count={subtopic_tags.count()}")

        unit_tags = page.locator(".meta-tag.unit")
        test("有關聯單位標籤", unit_tags.count() > 0, f"count={unit_tags.count()}")

        # 檢查分類標籤
        category_tags = page.locator(".meta-tag.category")
        test("有分類標籤", category_tags.count() > 0)

        # ============================================================
        #  5. 結案報告 + 錄案確認
        # ============================================================
        print("\n[5] 結案報告 + 錄案確認")
        page.wait_for_timeout(8000)  # 等劇本播完更多訊息

        page.click("#closeCallBtn")
        page.wait_for_timeout(1000)

        # 報告 overlay 出現
        overlay = page.locator("#reportOverlay")
        test("結案報告彈出", overlay.is_visible())

        # 可編輯摘要
        summary_textarea = page.locator("#reportSummary")
        test("摘要為可編輯 textarea", summary_textarea.is_visible())

        # 確認送出按鈕
        confirm_btn = page.locator("#reportConfirmBtn")
        test("有確認送出按鈕", confirm_btn.is_visible())

        # 關聯單位欄位
        report_content = overlay.inner_text()
        test("報告含關聯單位", "關聯單位" in report_content)

        # 點確認送出
        if confirm_btn.is_visible():
            confirm_btn.click()
            page.wait_for_timeout(500)

            # 驗證鎖定
            is_readonly = summary_textarea.get_attribute("readonly")
            test("摘要已鎖定", is_readonly is not None)
            test("顯示已確認", "已確認" in overlay.inner_text())

        # 關閉報告
        page.click("#reportCloseBtn")

        # ============================================================
        #  6. 擬稿助手
        # ============================================================
        print("\n[6] 擬稿助手")
        page.goto(f"{BASE}/drafting")
        page.wait_for_load_state("networkidle")
        test("擬稿助手載入", "擬稿" in page.content())

        # ============================================================
        #  7. 系統架構頁面
        # ============================================================
        print("\n[7] 系統架構頁面")
        page.goto(f"{BASE}/architecture")
        page.wait_for_load_state("networkidle")
        test("系統架構載入", "架構" in page.content() or "architecture" in page.content().lower())

        # ============================================================
        #  8. Swagger UI
        # ============================================================
        print("\n[8] Swagger UI")
        page.goto(f"{BASE}/docs")
        page.wait_for_load_state("networkidle")
        test("Swagger UI 載入", "swagger" in page.content().lower() or "openapi" in page.content().lower())

        # ============================================================
        #  9. Admin 頁面（HTTP Basic Auth: admin/admin）
        # ============================================================
        print("\n[9] Admin 功能測試")

        # 建立帶 Basic Auth 的新 context
        admin_context = browser.new_context(
            viewport={"width": 1280, "height": 900},
            http_credentials={"username": "admin", "password": "admin"},
        )
        admin_page = admin_context.new_page()

        # 9a. 對話管理
        admin_page.goto(f"{BASE}/admin")
        admin_page.wait_for_load_state("networkidle")
        admin_page.wait_for_timeout(1000)
        test("對話管理頁面載入", "對話" in admin_page.content())
        test("有統計卡片", admin_page.locator(".stat-card").count() > 0)

        # 9b. 統計報表
        admin_page.goto(f"{BASE}/admin/charts")
        admin_page.wait_for_load_state("networkidle")
        admin_page.wait_for_timeout(2000)  # 等 Chart.js 渲染
        test("統計報表頁面載入", "統計" in admin_page.content())
        canvas_count = admin_page.locator("canvas").count()
        test("Chart.js 圖表渲染", canvas_count >= 3, f"canvas={canvas_count}")

        # 9c. 主題報告
        admin_page.goto(f"{BASE}/admin/reports")
        admin_page.wait_for_load_state("networkidle")
        test("主題報告頁面載入", "報告" in admin_page.content())

        report_cards = admin_page.locator(".report-card")
        test("有 3 種報告選項", report_cards.count() == 3, f"count={report_cards.count()}")

        # 點擊客服週報
        report_cards.first.click()
        admin_page.wait_for_timeout(3000)  # 等圖表生成
        report_output = admin_page.locator("#reportOutput")
        test("客服週報生成", report_output.is_visible() and "客服" in report_output.inner_text())

        # 檢查報告含圖表
        report_canvas = admin_page.locator("#reportOutput canvas")
        test("報告含圖表", report_canvas.count() > 0, f"canvas={report_canvas.count()}")

        # 檢查報告含 AI 摘要
        ai_summary = admin_page.locator(".ai-summary")
        test("報告含 AI 摘要", ai_summary.count() > 0)

        # 9d. 用戶管理
        admin_page.goto(f"{BASE}/admin/users")
        admin_page.wait_for_load_state("networkidle")
        admin_page.wait_for_timeout(1000)
        test("用戶管理頁面載入", "用戶" in admin_page.content())

        # 9e. 系統設定
        admin_page.goto(f"{BASE}/admin/settings")
        admin_page.wait_for_load_state("networkidle")
        admin_page.wait_for_timeout(1000)
        test("系統設定頁面載入", "設定" in admin_page.content())
        test("有 LLM 設定區塊", "LLM" in admin_page.content())

        admin_context.close()
        browser.close()


def main():
    print("🧪 MOTC 瀏覽器 E2E 測試（Playwright）")
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
        print("請先啟動: uv run python -m uvicorn motc_app:app --port 8080")
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
