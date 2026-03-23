# UI 打磨注入模組 — Playwright 全頁面自動測試

此檔案在 Reviewer 發出 <!PHASE_UI_POLISH!> 時由 loop.sh 動態注入 Dev prompt。

## 指令

你現在進入 UI 打磨階段。用 Playwright MCP 工具逐頁測試每個互動元素。

### 步驟 1：啟動 server 並逐頁掃描

先確認 server 在跑（port 8001），然後按以下順序逐頁打開、截圖、點擊所有按鈕：

| # | 頁面 | URL | 前端檔案 | 後端 API | 互動元素估計 |
|---|------|-----|----------|----------|------------|
| 1 | 首頁（AI客服） | /  | static/index.html | src/api/chat.py, app.py | ~99 buttons, 9 forms |
| 2 | AI 助理 | /assistant | static/assistant.html | src/api/assistant.py | ~73 buttons, 9 forms |
| 3 | 資料治理 | /data-governance | static/data-governance.html | src/api/data_governance.py | ~52 buttons, 15 forms |
| 4 | 擬稿助手 | /drafting | static/drafting.html | src/api/drafting.py | ~31 buttons, 5 forms |
| 5 | 知識庫 | /knowledge | static/knowledge.html | src/api/knowledge_graph.py | ~25 buttons, 8 forms |
| 6 | 知識圖譜 | /knowledge-graph | static/knowledge-graph.html | src/api/knowledge_graph.py | ~14 buttons |
| 7 | 報告 | /reporting | static/reporting.html | src/api/reporting.py | ~14 buttons, 1 form |
| 8 | 問卷 | /survey | static/survey.html | src/api/schemas.py | ~12 buttons, 33 forms |
| 9 | 語音 Demo | /voice-demo | static/voice-demo.html | src/api/chat.py | ~22 buttons |
| 10 | LINE Demo | /line-demo | static/line-demo.html | src/api/line_bot.py | ~17 buttons, 1 form |
| 11 | 登入 | /login | static/login.html | src/api/auth.py | ~12 buttons, 2 forms |
| 12 | 後台管理 | /admin | static/admin.html | src/api/app.py | ~7 buttons |
| 13 | 官員 Portal | /portal-official | static/portal-official.html | — | ~3 buttons |
| 14 | 員工 Portal | /portal-employee | static/portal-employee.html | — | links only |
| 15 | 架構圖 | /architecture | static/architecture.html | — | static page |

### 步驟 2：每頁執行

對每個頁面：
1. `browser_navigate` 到 URL
2. `browser_screenshot` 截初始狀態
3. 找出所有 `<button>`、`onclick`、`<a>`、`<form>` 元素
4. 逐一 `browser_click` 每個按鈕，每次點擊後截圖
5. 表單頁面：填入測試資料 `browser_type`，submit，截圖
6. 記錄每個元素的反應：✅ 正常 / ❌ 報錯 / ⚠️ 無反應 / 🐌 超過 3 秒

### 步驟 3：產出 Bug 清單

在專案根目錄建立 `docs/ui-test-report.md`：

```markdown
# UI 自動測試報告 — {date}

## 總覽
- 測試頁面：15
- 總互動元素：{count}
- ✅ 正常：{count}
- ❌ 報錯：{count}
- ⚠️ 無反應：{count}
- 🐌 慢（>3s）：{count}

## 逐頁結果

### 1. 首頁（/）
| 元素 | 類型 | 結果 | 截圖 | 備註 |
|------|------|------|------|------|
| 送出聊天 | button | ✅ | screenshots/index_chat_submit.png | 1.2s |
| ... | ... | ... | ... | ... |

## Bug 清單（需修復）

| # | 頁面 | 元素 | 問題 | 前端檔案 | 後端檔案 | 嚴重度 |
|---|------|------|------|----------|----------|--------|
| 1 | /drafting | 版本歷史 | 點擊無反應 | static/drafting.html | src/api/drafting.py | 🔴 |
```

### 步驟 4：修 Bug

按嚴重度排序修復。每修一個：
1. 改 code
2. 重新用 Playwright 點擊驗證
3. 截圖確認
4. commit

### 注意事項
- 3/31 要 demo 給政府官員。官員不會等 loading 超過 3 秒。
- error 不能讓官員看到白屏或 traceback — 至少要有「系統忙碌中」。
- SSE 串流（chat、assistant 頁面）需要等串流完成再截圖。
- 語音功能在 0.0.0.0 下不能用（非 secure context），用 localhost 測。
