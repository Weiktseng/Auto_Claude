# Auto_Claude 視覺測試工具參考手冊

> 本文件供 Dev / Reviewer agent 在 context.md 或 detail_upgrade_guides/ 中注入使用。
> 撰寫日期：2026-03-26，來源：Claude Code 官方環境實測。

## 三套工具總覽

| 工具套件 | MCP Server | 適用場景 | 需要的前置條件 |
|----------|-----------|---------|--------------|
| **Claude Preview** | `mcp__Claude_Preview__*` | 啟動 dev server → 截圖 → 點擊 → 驗 CSS | `.claude/launch.json` 定義 server |
| **Claude in Chrome** | `mcp__Claude_in_Chrome__*` | 操控真實 Chrome 瀏覽器 | Chrome + 擴充套件安裝 |
| **Computer Use** | `mcp__computer-use__*` | 控制整台 Mac 桌面 | macOS + 需 `request_access` 授權 |

---

## 一、Claude Preview（推薦用於 Web 開發測試）

最適合 motc 這類 FastAPI + 前端專案。不需要真實瀏覽器，用內建 headless browser。

### 設定 `.claude/launch.json`

```json
{
  "version": "0.0.1",
  "configurations": [
    {
      "name": "motc-server",
      "runtimeExecutable": "python",
      "runtimeArgs": ["-m", "uvicorn", "src.api.app:app", "--host", "0.0.0.0", "--port", "8001", "--reload"],
      "port": 8001
    }
  ]
}
```

### 工作流程

```
1. preview_start(name="motc-server")         → 啟動 server，返回 serverId
2. preview_screenshot(serverId)              → 截圖看佈局
3. preview_snapshot(serverId)                → 取 accessibility tree（文字驗證比截圖準）
4. preview_click(serverId, selector)         → 用 CSS selector 點擊元素
5. preview_fill(serverId, selector, value)   → 填寫表單
6. preview_inspect(serverId, selector, styles=["color","padding"]) → 驗 CSS 屬性
7. preview_console_logs(serverId, level="error")  → 檢查前端錯誤
8. preview_network(serverId, filter="failed")     → 檢查失敗的 API 請求
9. preview_logs(serverId, level="error")          → 檢查後端 server 錯誤
```

### 關鍵注意事項
- `preview_inspect` 驗證顏色/字體/間距比截圖準確 — **截圖只看佈局，不要用來判斷顏色**
- `preview_snapshot` 返回 accessibility tree — 用來驗證文字內容和元素結構
- `preview_eval` 只做 debug 用 — **不要用它改 DOM，改 source code**
- `preview_network` 可以用 `requestId` 查看完整 response body

### 全站自動測試範例流程

```
# 對每一頁執行：
for page in ["/", "/chat", "/knowledge", "/drafting", "/reporting", ...]:
    1. preview_eval → window.location.href = "http://localhost:8001{page}"
    2. preview_screenshot → 存檔
    3. preview_snapshot → 驗證關鍵元素存在
    4. preview_console_logs(level="error") → 如果有 error 就記錄
    5. preview_network(filter="failed") → 記錄失敗 API
    6. 找到所有按鈕 → preview_click 逐一點擊 → 再截圖驗證結果
```

---

## 二、Claude in Chrome（真實瀏覽器測試）

操控使用者的真實 Chrome，適合需要登入、cookie、真實渲染的場景。

### 工作流程

```
1. tabs_context_mcp(createIfEmpty=true)     → 取得 tab group，拿到 tabId
2. tabs_create_mcp()                         → 新建 tab（每次對話用新 tab）
3. navigate(tabId, url="localhost:8001")      → 導航到目標頁
4. read_page(tabId, filter="interactive")     → 取 accessibility tree（只看可互動元素）
5. find(tabId, query="搜尋按鈕")             → 自然語言找元素，返回 ref_id
6. computer(tabId, action="left_click", ref="ref_1") → 用 ref 點擊
7. form_input(tabId, ref="ref_2", value="我要查汽燃費") → 填表單
8. get_page_text(tabId)                       → 提取頁面純文字
9. javascript_tool(tabId, text="document.querySelectorAll('.error').length") → 跑 JS
10. computer(tabId, action="screenshot")      → 截圖
```

### 關鍵注意事項
- **必須先 `tabs_context_mcp`** 取得 tabId，否則所有操作都會失敗
- `find` 支援自然語言（「登入按鈕」「搜尋框」），比 CSS selector 更靈活
- `read_page` 的 `max_chars` 預設 50000，大頁面要設 `depth` 或用 `ref_id` 聚焦子樹
- `computer` 的 `action="zoom"` 可以放大看小元素細節
- 和 Playwright MCP 的差異：不搶 browser profile lock，不會造成 hang

### vs Playwright MCP

| | Playwright MCP | Claude in Chrome |
|---|---|---|
| Browser 控制 | 啟動獨立 Chromium | 控制使用者的 Chrome |
| Profile 衝突 | ⚠️ 會搶 lock（已知 bug） | ✅ 不衝突 |
| 需要安裝 | npm package | Chrome 擴充套件 |
| 元素定位 | CSS selector / XPath | 自然語言 `find` + ref_id |
| headed 模式 | 需要 --headed flag | 永遠是 headed（真實 Chrome） |

---

## 三、Computer Use（桌面級控制）

控制整台 Mac，不限於瀏覽器。可操作 Finder、Terminal、任何 App。

### 工作流程

```
1. request_access(apps=["Google Chrome","Finder"], reason="測試 UI") → 請求權限
2. open_application(app="Google Chrome")     → 開啟 App
3. screenshot()                               → 截圖整個桌面
4. left_click(coordinate=[x, y])             → 點擊座標
5. type(text="hello")                         → 打字
6. key(text="cmd+a")                          → 快捷鍵
7. scroll(coordinate=[x,y], scroll_direction="down", scroll_amount=3) → 捲動
```

### computer_batch（批次操作，大幅加速）

```json
{
  "actions": [
    {"action": "left_click", "coordinate": [100, 200]},
    {"action": "type", "text": "搜尋內容"},
    {"action": "key", "text": "Return"},
    {"action": "wait", "duration": 2},
    {"action": "screenshot"}
  ]
}
```

一次 API call 完成整個序列，省掉 4 次 round trip。

### 關鍵注意事項
- **必須先 `request_access`** 授權 App 清單，否則所有操作都報錯
- 座標以截圖為準 — 先截圖再點擊
- `computer_batch` 中的座標以**批次開始前**的截圖為準，中途截圖不影響座標
- 批次操作遇到第一個錯誤就停止
- 不能操作未授權的 App — 如果操作導致切換到未授權 App，後續動作會被擋

---

## 四、Auto_Claude 整合建議

### 對 Dev Agent

在 `context.md` 中注入以下指示：

```markdown
## 視覺測試工具
- 優先用 Claude Preview（不搶瀏覽器、不衝突）
- 需要真實瀏覽器才用 Claude in Chrome
- 測試前確認 .claude/launch.json 有定義 server
- 每修改一個前端檔案後：截圖 + console_logs(error) + network(failed)
- 驗證顏色/間距用 preview_inspect，不要看截圖猜
```

### 對 Reviewer Agent

Reviewer 只需要讀取能力，不需要操控瀏覽器：

```markdown
## Reviewer 可用工具
- preview_screenshot → 看佈局是否合理
- preview_snapshot → 驗證元素結構
- preview_console_logs → 確認無前端錯誤
- preview_network → 確認無失敗 API
- 不需要 click / fill / type
```

### MCP 設定建議

在專案的 `.claude/.mcp.json` 或 `.mcp.json` 中：

```json
{
  "mcpServers": {
    "claude-preview": {
      "command": "claude-preview-server",
      "args": []
    }
  }
}
```

> ⚠️ 注意：`claude --print` 模式下 MCP server 是否可用需要實測確認。
> 如果 `--print` 模式不支援某個 MCP，則該工具只能在互動模式使用。

---

## 五、取代 Playwright MCP 的遷移路徑

目前 motc 用 Playwright MCP 做 UI 測試，但有 profile lock 衝突問題。遷移方案：

1. **短期**：Reviewer 拔掉 Playwright MCP（已在 loop.sh 的 `--disallowed-tools` 中限制）
2. **中期**：Dev 改用 Claude Preview 做 UI 測試（不需要真實瀏覽器）
3. **長期**：需要真實瀏覽器時用 Claude in Chrome（不衝突）

遷移時 Dev context.md 加一行：
```
禁止使用 Playwright MCP。用 Claude Preview 的 preview_* 工具做 UI 測試。
```
