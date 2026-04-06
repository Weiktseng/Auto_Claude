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

## 六、實測紀錄（2026-03-26）

### Claude Preview — 全項通過 ✅

測試環境：`test_server/app.py`（Python HTTP server, port 8099），5 按鈕 + 表單 + API + CSS 驗證區

| 測試項 | 結果 | 備註 |
|--------|------|------|
| `preview_start` | ✅ | 從 `.claude/launch.json` 啟動，返回 serverId |
| `preview_screenshot` | ✅ | JPEG 截圖，看佈局清晰 |
| `preview_snapshot` | ✅ | 返回完整 accessibility tree，每個元素有 ID |
| `preview_click(selector)` | ✅ | CSS selector 精準點擊 `#btn-ok`、`#btn-submit`、`#btn-api-get` |
| `preview_fill(selector, value)` | ✅ | 填寫 input/textarea/select 都成功 |
| `preview_inspect(selector, styles)` | ✅ | 返回精確 CSS 值：`color: rgb(13, 148, 136)`、`font-size: 18px` |
| `preview_console_logs(level="error")` | ✅ | 無錯誤時返回空 |
| `preview_network` | ✅ | 列出所有請求含 status code，可用 requestId 查 response body |

**結論：完全可以取代 Playwright MCP。** 優勢：不搶 browser profile lock、不需要真實瀏覽器、CSS selector 比座標更穩定。

### Computer Use — 部分通過 ⚠️

| 測試項 | 結果 | 備註 |
|--------|------|------|
| `request_access` | ✅ | Finder=full, Chrome=read-only（安全限制，瀏覽器不給完整控制） |
| `screenshot` | ✅ | 截到完整桌面，未授權 App 會被隱藏 |
| `open_application` | ✅ | 開啟 Finder 成功 |
| `computer_batch` | ✅ | 6 步驟（key→wait→type→key→wait→screenshot）一次完成 |
| 中文路徑 | ⚠️ | Finder "Go To Folder" 對話框中文路徑導航可能失敗，用英文路徑更穩 |
| Chrome 操控 | ❌ | 瀏覽器被鎖定為 read-only tier，只能截圖不能點擊打字 |

**結論：適合桌面級操作（Finder、Terminal），但瀏覽器測試不如 Claude Preview。**

### Claude in Chrome — 全項通過 ✅

| 測試項 | 結果 | 備註 |
|--------|------|------|
| `tabs_context_mcp` | ✅ | 取得 tab group 和 tabId |
| `navigate` | ✅ | 導航到 localhost:8099 |
| `computer(screenshot)` | ✅ | 真實 Chrome 截圖，看到實際渲染結果 |
| `find(自然語言)` | ✅ | `"OK button"` → ref_4, `"name input field"` → ref_11, `"role dropdown"` → ref_13 |
| `computer(left_click, ref)` | ✅ | 用 ref 點擊按鈕，result 區顯示 "OK button clicked ✅" |
| `form_input(ref, value)` | ✅ | 填入文字、選擇下拉選項都成功 |
| `javascript_tool` | ✅ | 讀取 DOM 值成功 |
| `get_page_text` | ✅ | 提取完整頁面純文字（含 script 內容） |

**結論：真實瀏覽器操控完全正常。** 自然語言 `find` 是殺手級功能 — 不需要知道 CSS selector，說「搜尋按鈕」就能找到元素。適合 agent 在不熟悉頁面結構時使用。

**vs Claude Preview 差異：**
- Chrome 操控的是真實瀏覽器（有 cookie、登入狀態、真實渲染）
- Preview 是 headless 內建瀏覽器（更輕量、不衝突）
- Chrome 的 `find` 用自然語言，Preview 的 `click` 用 CSS selector
- Chrome 的 `get_page_text` 會連 script 內容一起輸出，Preview 的 `snapshot` 只輸出 accessibility tree

### 跨工具協作技巧（實測發現）

**問題：** Computer Use 對 Chrome 只有 read-only 權限（截圖可以、點擊不行），Claude in Chrome 能操作 tab 內容但無法把 tab 切到前景讓人類看到。

**解法：** 用 Claude in Chrome 的 `javascript_tool` 執行 `window.focus()`

```
javascript_tool(tabId, "window.focus()")
```

效果：
- ✅ 把 Chrome 視窗帶到所有 App 前面
- ✅ 同時激活指定的 tab（讓人類看到操作過程）
- ✅ 穩定可重複，已驗證 2 次

**注意：** `chrome.tabs.update()` 在頁面 context 裡沒權限，不能用。`window.focus()` 是唯一可行方案。

**更簡單的替代方案（未測試）：**
如果把 Computer Use 的 Chrome 權限從 read 升到 full（`request_access` 時指定），理論上可以直接用 Computer Use 點擊 tab。但風險是 Computer Use 和 Claude in Chrome 同時操控 Chrome 可能產生衝突。

### 工具選擇決策樹

```
需要測試 Web UI？
├─ 是 → 有 dev server 嗎？
│   ├─ 是 → 用 Claude Preview（最穩定、不衝突）
│   └─ 否 → 用 Claude in Chrome（需要擴充套件）
└─ 否 → 需要操控桌面 App？
    ├─ 是 → 用 Computer Use（Finder、Terminal 等）
    └─ 否 → 用 Bash / Read / Write 等內建工具
```

---

## 五、`--print` 模式下的工具可用性（2026-03-26 實測結論）

### 關鍵發現：SDK MCP 是 Claude.app 獨佔的

Claude.app 啟動 session 時的實際命令（從 session jsonl 逆向取得）：

```
/Users/henry/Library/Application Support/Claude/claude-code/2.1.78/claude.app/Contents/MacOS/claude
  --input-format stream-json --output-format stream-json
  --mcp-config {"mcpServers":{
    "Claude Preview":    {"type":"sdk","name":"Claude Preview"},
    "Claude in Chrome":  {"type":"sdk","name":"Claude in Chrome"},
    "computer-use":      {"type":"sdk","name":"computer-use"},
    "scheduled-tasks":   {"type":"sdk","name":"scheduled-tasks"},
    "mcp-registry":      {"type":"sdk","name":"mcp-registry"},
    "plugin:github:github": {"type":"sdk","name":"plugin:github:github"}
  }}
```

**`"type":"sdk"` 不是獨立 process** — 它由 Claude.app 的 Electron 主進程作為 runtime host。
`claude --print`（headless CLI）無法載入 SDK MCP，即使用同一個二進位檔 + 同樣的 `--mcp-config` 也不行。

### 可用性矩陣

| 工具 | MCP type | Claude.app 互動 | `claude --print` | loop.sh Dev |
|------|----------|-----------------|------------------|-------------|
| **Playwright** | `stdio` | ✅ | ✅ | ✅ 唯一可用 |
| **EntropyShield** | `stdio` | ✅ | ✅ | ✅ |
| **Claude Preview** | `sdk` | ✅ | ❌ | ❌ |
| **Claude in Chrome** | `sdk` | ✅ | ❌ | ❌ |
| **Computer Use** | `sdk` | ✅ | ❌ | ❌ |

### SDK MCP 底層拆解

SDK MCP 不神奇，只是包裝：

| SDK MCP | 底層實現 | stdio 可替代方案 |
|---------|---------|-----------------|
| Computer Use | macOS Accessibility API / AppleScript | PyAutoGUI + screencapture |
| Claude Preview | 內建 headless browser | **Playwright MCP（已有）** |
| Claude in Chrome | Chrome DevTools Protocol via Native Messaging | 直接跟 chrome-native-host 通訊 |

Chrome MCP 的鏈條：
```
Claude.app → SDK runtime → chrome-native-host (stdio) → Chrome 擴充套件 → 真實 Chrome
                           ↑ 這個是獨立 binary，用 stdio 協議
```

Native Messaging Host 路徑：`/Applications/Claude.app/Contents/Helpers/chrome-native-host`

### 遷移路徑（修正版）

~~原計畫：Dev 改用 Claude Preview → 不可行（SDK MCP）~~

修正方案：

1. **短期（現在）**：Dev 用 Playwright MCP（headless `stdio`）自檢，Reviewer 禁用 Playwright 防 hang
2. **中期**：自建 stdio MCP server 包裝 Playwright，提供 Claude Preview 同等 API：
   - `preview_screenshot` → `playwright screenshot`
   - `preview_click` → `playwright click`
   - `preview_fill` → `playwright fill`
   - `preview_snapshot` → `playwright accessibility tree`
   - `find(自然語言)` → LLM 解析 accessibility tree 找元素
3. **長期**：用 Claude Agent SDK（直接 API）重寫 loop，脫離對 CLI 的依賴

---

## 六、Chrome MCP 實戰坑（2026-03-26 踩過的）

### CodeMirror / Monaco 等富文字編輯器

`computer(type)` 打字時 `\n` 不會被解析成換行，變成純文字 `\n`。

**解法**：用 `javascript_tool` 直接操作編輯器 API：
```javascript
// CodeMirror
document.querySelector('.CodeMirror').CodeMirror.setValue("line1\nline2")

// Monaco (VS Code 系)
monaco.editor.getModels()[0].setValue("line1\nline2")
```

### Facebook / Threads 等 contentEditable

這類網站用 `contentEditable` div，不是 `<textarea>`。`form_input` 可能不生效。

**解法**：用 `computer(left_click)` 點進去 → `computer(type)` 打字 → `key(Enter)` 換行

### Chrome Tab 前景切換

Claude in Chrome 操作 tab 內容不需要 tab 在前面，但人類看不到。

**解法**：`javascript_tool("window.focus()")` 可以把 tab 帶到前景。

### 工具間 MCP 獨佔

Claude.app 互動 session 佔住 SDK MCP 時，同機器的 `claude --print` 無法使用同一 MCP。Chrome 擴充套件是單連線。

**解法**：跑 loop 前關掉 Claude.app，或用不同的 MCP（Playwright）。

---

## 七、Gist 發文端到端驗證（2026-03-26 ✅）

完整流程，全自動無人工介入：

1. `tabs_context_mcp(createIfEmpty=true)` → tabId
2. `navigate(tabId, "https://gist.github.com")` → 登入狀態自動帶入
3. `find("Gist description input")` → ref_66
4. `form_input(ref_66, "描述文字")` → 填入描述
5. `find("filename input")` → ref_70
6. `form_input(ref_70, "hello_from_claude.md")` → 填入檔名
7. `javascript_tool("document.querySelector('.CodeMirror').CodeMirror.setValue(...)")` → 填入內容（含換行）
8. `find("Create secret gist button")` → ref_128
9. `computer(left_click, ref=ref_128)` → 發布
10. `computer(screenshot)` → 驗證成功，Markdown 渲染正確

**結論：Claude in Chrome 可以完成任何有「輸入 + 發布」的網站操作。**
關鍵技巧：遇到富文字編輯器用 JS 注入，遇到普通表單用 form_input。
