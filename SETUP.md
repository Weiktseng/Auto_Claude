# Auto_Claude 安裝指南

## 前置需求

- macOS（tested on Darwin 23.5.0）或 Linux
- Claude Code CLI >= 2.1.84
- Claude 帳號（OAuth 登入或 API key）
- Python 3.12+（MCP servers 需要）
- Node.js 18+（Claude Code CLI 需要）

## 1. 引擎本身

```bash
git clone git@github.com:Weiktseng/Auto_Claude.git
cd Auto_Claude
```

引擎核心是純 bash（`engine/loop.sh`），不需要 pip install。

```bash
# 安裝 Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 登入（OAuth，不需要 API key）
claude login
```

## 2. MCP Servers（AI 的工具箱）

MCP server 是 Claude Code 的外掛工具。安裝在你的電腦上，所有專案共用。

### 建議安裝

| Server | 用途 | 安裝 |
|--------|------|------|
| **EntropyShield** | 安全讀取外部 GitHub 內容，防 prompt injection | 見下方 |

```bash
# EntropyShield
git clone git@github.com:Weiktseng/EntropyShield.git
cd EntropyShield && pip install -e .
```

### 必裝

| Server | 用途 | 安裝 |
|--------|------|------|
| **chrome-mcp-bridge** | 操控真實 Chrome 瀏覽器（截圖、點擊、表單） | 自建，見下方 |
| **cron-manager** | 管理 scheduled tasks 生命週期 + 殭屍防護 | 見下方 |

```bash
# chrome-mcp-bridge（視覺測試用）
git clone git@github.com:Weiktseng/Auto_Claude_chrome-mcp-bridge.git chrome-mcp-bridge
# 使用前需啟動 Chrome:
# open -a 'Google Chrome' --args --remote-debugging-port=9222

# cron-manager（排程管理）
git clone git@github.com:Weiktseng/Claude_Destope_cron_manager.git cron-manager
```

### 必配（公開套件）

```bash
# Playwright MCP — headless 瀏覽器自動化
# 不需安裝，claude 會自動用 npx 拉取

# treesitter-mcp — AST 結構化分析
pip install treesitter-mcp==2.1
```

## 3. 全域 MCP 配置

安裝完 MCP server 後，需要在 Claude Code 全域設定裡註冊。

### `~/.claude/.mcp.json`（全域，所有專案共用）

```json
{
  "mcpServers": {
    "entropyshield": {
      "command": "entropyshield",
      "args": ["mcp"]
    },
    "cron-manager": {
      "command": "python3",
      "args": ["<path-to>/cron-manager/cron_manager.py", "serve"]
    },
    "treesitter": {
      "command": "treesitter-mcp",
      "args": []
    }
  }
}
```

### `<project>/.mcp.json`（專案級，覆蓋或追加）

```json
{
  "mcpServers": {
    "chrome": {
      "command": "python3",
      "args": ["<path-to>/chrome-mcp-bridge/src/chrome_mcp_server.py"],
      "env": { "CHROME_CDP_PORT": "9222" }
    }
  }
}
```

## 4. 全域 CLAUDE.md

`~/.claude/CLAUDE.md` 是 Claude Code 每次啟動都會載入的指令。Auto_Claude 依賴以下規則：

- **EntropyShield 使用規則** — 何時用 `shield_fetch` vs `WebFetch`
- **供應鏈安全規則** — 安裝前檢查、版本鎖定
- **Scheduled Tasks SOP** — cron-manager 4 層停止防護

參考本 repo 的 `references/` 目錄。

## 5. 建立新專案

**先選架構**（詳見 [ARCHITECTURES.md](ARCHITECTURES.md)）：

- **Classic** — 單迴圈 Dev ↔ Reviewer。已存在專案補 feature / 短 spec / 修 bug 用這個。
- **Pipeline** — 三階段 Focus → Review → Attack。從零開始、長 spec、要無人值守一整晚用這個。

兩套模板在 `templates/classic/` 和 `templates/pipeline/` 各自獨立，複製哪個就是什麼架構，**不會混在一起**。

### Classic 建立流程

```bash
cd /path/to/your-project
mkdir -p .auto_claude
cp -r <Auto_Claude>/templates/classic/* .auto_claude/

# 編輯設定
vim .auto_claude/agent/spec.txt          # 貼上你的規格書
vim .auto_claude/agent/context.md        # 填專案背景、技術棧、git 規則（見 §5.5）
vim .auto_claude/agent/reviewer/prompt.md  # 自訂 reviewer 角色

# 修改 run.sh 裡的 ENGINE_REPO 路徑
vim .auto_claude/run.sh

# 啟動
.auto_claude/run.sh --initial-prompt "開始做登入功能" --max-rounds 20
```

### Pipeline 建立流程

```bash
cd /path/to/your-project
mkdir -p .auto_claude
cp -r <Auto_Claude>/templates/pipeline/* .auto_claude/

# 編輯設定
vim .auto_claude/agent/spec.txt          # 貼上你的規格書
vim .auto_claude/agent/context.md        # 專案背景
vim .auto_claude/agent/phase_plan.md     # 必填，模板會拒絕在未填時啟動（見 §5.5）
vim .auto_claude/run.sh                  # ENGINE_REPO 路徑

# 啟動（預設跑完整三段，結束等人類驗收）
.auto_claude/run.sh
```

## 5.1 檔案職責表（每個檔案幹嘛，誰寫誰讀 — Dev / Reviewer 必遵）

`.auto_claude/agent/` 下**只允許這些檔案存在**。Dev 和 Reviewer **禁止自己創造新的 .md 檔**（例如 `reviewer_stub.md`、`dev_notes.md`、`plan_v2.md` 這類）— 想記東西就寫到「你的 memory」那欄的對應檔案，不要開新檔。

### Classic 專用

| 檔案 | 功能 | 人類寫 | Dev 寫 | Reviewer 寫 | 引擎寫 |
|---|---|:-:|:-:|:-:|:-:|
| `spec.txt` | **需求**：產品要做什麼（客戶/PM 的契約原文） | ✅ 一次性 | ❌ | ❌ | ❌ |
| `context.md` | **環境**：技術棧、git 規則、API keys、禁做範圍 | ✅ 一次性 | ❌ | ❌ | ❌ |
| `dev/prompt.md` | **Dev 角色規則**：怎麼工作、何時停、exception 規則 | ✅ 一次性 | ❌ | ❌ | ❌ |
| `dev/memory.md` | **Dev 自己的筆記**（跨輪累積，只有 Dev 看） | ❌ | ✅ append | ❌ | ❌ |
| `reviewer/prompt.md` | **Reviewer 角色規則** | ✅ 一次性 | ❌ | ❌ | ❌ |
| `reviewer/memory.md` | **Reviewer 審查歷史**（Curator 會自動壓縮） | ❌ | ❌ | ❌ | ✅ 每輪自動 |
| `curator/prompt.md` | **Curator 壓縮規則** | ✅ 一次性 | ❌ | ❌ | ❌ |
| `dev/progress.md` | **Curator 壓縮的進度摘要**（session 重啟時載入） | ❌ | ❌ | ❌ | ✅ 每 8 輪自動 |
| `comms/human_message.md` | **人類 → AI** 單向通道（下一輪生效） | ✅ 隨時 | ❌ | 讀 | ✅ 自動清 |
| `comms/human_reply.md` | **AI → 人類** 單向通道 | ❌ | ✅ | 讀 | ❌ |
| `comms/human_message_history.log` | 人類插話歷史歸檔 | ❌ | ❌ | ❌ | ✅ |
| `comms/todo.md` | Dev + Reviewer 共用任務清單（選用） | ✅ 可寫 | ✅ | ✅ | ❌ |

### Pipeline 額外的

| 檔案 | 功能 | 人類寫 | Dev 寫 | Reviewer 寫 | 引擎寫 |
|---|---|:-:|:-:|:-:|:-:|
| `phase_plan.md` | **Phase 計畫**：每 phase 的 items + 驗收指令 | ✅ 一次性（必填） | ✅ 勾選完成 `[x]` | 讀 | ❌ |
| `dev/stage1_prompt.md` | **Stage 1 Dev 規則**（Focus 模式） | ✅ 一次性 | ❌ | ❌ | ❌ |
| `dev/stage2_prompt.md` | **Stage 2 Dev 規則**（Review/Fix 模式） | ✅ 一次性 | ❌ | ❌ | ❌ |
| `attacker/prompt.md` | **Attacker 角色規則**（Stage 3 GPT + Claude 讀） | ✅ 一次性 | ❌ | ❌ | ❌ |

### 如果 AI 想寫「不屬於上面任何一項」的東西

**階段性報告、bug 分析、決策紀錄、設計筆記 → 全部寫進 `dev/memory.md`**（自己的筆記）。不要開新 .md 檔。

**想跟人類溝通的 → `comms/human_reply.md`**（不是 `questions.md`、不是 `blockers.md`、不是 `status.md`）。

**Reviewer 想記錄審查觀察 → `reviewer/memory.md`**（引擎會自動追加，Reviewer 自己不要手動改）。

**違反這個規則的代價**：下次 loop 啟動時，Dev 會看到奇怪的 `plan_v2.md` / `reviewer_stub.md` / `bug_analysis_draft.md`，不知道該讀哪個、也不知道哪個是舊的殘留。人類來清理時要逐個判斷是廢檔還是重要資訊。**一句話：功能歸檔，不要開新檔。**

## 5.5 Spec Phase 切分分析（長 spec 必做，30 分鐘人類工作）

> Pipeline 架構會強制這一步（沒填 `phase_plan.md` Stage 1 會拒絕啟動）。Classic 架構不強制，但長 spec 建議在 `context.md` 裡做同樣的 phase 邊界宣告。

**拿到 >1000 行的外部規格書時，不要直接丟給 Dev 開始做。** 先做 Phase 切分。

### 為什麼要切

長 spec 造成三種明確問題：

1. **Context 壓力** — Dev 每輪讀 spec、Curator 每 N 輪壓縮、Reviewer 也吃 spec，長 spec = 全流程都貴且容易 context rot
2. **注意力分散** — Dev 讀到推播章節會開始認真想 APNs，即使手機殼 demo 根本還沒做；讀到多語系會順手寫 i18n placeholder
3. **後期殘渣** — Dev 做 §4 一半發現要等 §3 才能測，scaffold 留在 code 裡變死程式碼，之後沒人敢刪（見 ARCHITECTURE.md「Layer 2 機率性失敗：舊 spec 殘渣不清」）

### 切分步驟（人類執行）

1. **通讀 spec，列所有章節**：`grep '^##' .auto_claude/agent/spec.txt`
2. **標記 demo-critical**：能 demo 給客戶看的**最小端對端路徑**要哪幾節？（使用者打開 → 做核心動作 → 看到結果 → 完成）
3. **劃 Phase 1 = demo-critical minimum**：能跑、能展示、客戶看得懂的最小集。**通常只佔全 spec 的 20–40%**。
4. **其他章節歸 Phase 2+**，標註每一節「依賴 Phase 1 的哪些 API / schema」
5. **驗證 phase 隔離**：Phase 2+ 的每一節回答三個問題：
   - 它要**修改** Phase 1 的哪個 DB schema？**答案必須是「無」**，只能 append 新表/新欄位
   - 它要**修改** Phase 1 的哪個 API 契約？**答案必須是「無」**，只能加新 endpoint
   - 它要**修改** Phase 1 的哪個核心函數行為？**答案必須是「無」**，只能寫 wrapper
6. **任何「是」→ Phase 1 畫錯了**。那塊 Phase 1 功能還沒成熟就被塞進去、或 Phase 2 依賴了尚未穩定的介面。**重畫 Phase 1 邊界**，把那塊挪到 Phase 2 一起做，或擴大 Phase 1 把依賴也納入。

### 把結果寫進 `agent/context.md`（不要改 spec.txt）

```markdown
# 開發範圍（本階段限定，Dev 每輪都看到）

**Phase 1 只做**：§5 AI 對話引擎、§13 prompt 工程、§14 測試、§15 成本、§18 控制台
**Phase 1 禁碰**：§3 Capacitor 原生殼、§4 推播、§6 記憶 agent、§8 週間關懷、§10 多媒體、§12 多語系

**禁碰章節的處理規則**：
- Dev 讀 spec 看到禁碰章節，**跳過不實作、不留 stub、不留 placeholder、不留 TODO 註解**
- 若 Phase 1 功能「需要」禁碰章節的東西才能跑，用最簡單的 hardcoded fallback，並加 `# phase-2: <章節編號>` 註解
- 禁止為了 Phase 2 預先鋪路而改 Phase 1 的 schema 或 API 設計
```

### 為什麼不直接改 spec.txt

spec.txt 是客戶/PM 的原始契約，之後會被引用、對照、審計、交接。**Phase 切分是 RD 策略決定，屬於 context 不屬於 spec**。改 spec.txt 會讓原始契約失真，之後沒人分得清哪些是客戶要的、哪些是 RD 自己劃的範圍。

### 常見陷阱

- ❌ **把 "nice to have" 塞 Phase 1 因為「順便做」** — Phase 1 不會因為多做而變快，只會變脆
- ❌ **Phase 切分後才發現 Phase 2 需要動 Phase 1 核心** — 代表原切分錯，立刻重切，不要硬幹
- ❌ **跑到一半才想換 spec 版本** — 會留殘渣（舊 DB 表、孤兒 endpoint、過時 smoke 測試），應該先在新 loop 開一個 audit round 清完再換
- ❌ **不切 phase 直接開跑** — Dev 會在 spec 章節之間亂跳，context 很快就飽和，且 Curator 壓縮後無法判斷哪些是主線、哪些是支線殘渣
- ❌ **Phase 2+ 預先 mock 進 Phase 1** — 看起來「之後接上就好」，實際上 mock 的 interface 一定跟最後真實的不一樣，Phase 2 要來時還是要改 Phase 1


## 6. 權限設定

每個專案需要 `.claude/settings.local.json` 來控制 `--print` 模式下的工具權限。
可從 Auto_Claude 複製基本版：

```bash
mkdir -p .claude
cp <Auto_Claude>/settings.local.json .claude/settings.local.json
```

## 目錄結構速查

```
Auto_Claude/                    ← 引擎 repo（不含任何專案資料）
├── engine/loop.sh              ← 核心 loop 引擎
├── templates/                  ← 新專案模板
│   ├── agent/                  ← AI context 模板
│   │   ├── reviewer/prompt.md
│   │   ├── curator/prompt.md
│   │   ├── dev/prompt.md
│   │   ├── comms/
│   │   ├── context.md
│   │   └── spec.txt
│   ├── mcp.json                ← MCP 配置模板
│   └── run.sh                  ← 啟動腳本模板
├── tools/                      ← 引擎工具
├── references/                 ← 參考文件
└── SETUP.md                    ← 本文件

<你的專案>/
├── .auto_claude/               ← Auto_Claude 配置（從 templates/ 複製）
│   ├── agent/
│   │   ├── reviewer/
│   │   │   ├── prompt.md       ← reviewer 角色定義
│   │   │   └── memory.md       ← reviewer 累積記憶（自動產生）
│   │   ├── curator/prompt.md
│   │   ├── dev/
│   │   │   ├── prompt.md       ← dev 規則
│   │   │   ├── memory.md       ← dev 筆記（自動產生）
│   │   │   └── progress.md     ← 壓縮進度（自動產生）
│   │   ├── comms/              ← 人類 ↔ agent 溝通
│   │   │   ├── human_message.md
│   │   │   ├── human_reply.md
│   │   │   └── todo.md
│   │   ├── spec.txt
│   │   └── context.md
│   ├── logs/
│   └── run.sh
├── .claude/settings.local.json  ← 工具權限
├── .mcp.json                    ← 專案級 MCP（選配）
└── <專案程式碼>/
```

## 7. 驗證安裝

```bash
cd /path/to/your-project

# 測試 claude --print 是否能正常呼叫
claude --print "回答 OK" --model sonnet

# 用人類模式測試引擎（你當 Reviewer，1 輪就夠）
.auto_claude/run.sh --human --max-rounds 1 \
  --initial-prompt "列出這個專案的檔案結構"
```

看到 Dev 輸出 + `👤 你的回合` 提示就代表安裝成功。

## 8. Troubleshooting

### 殭屍進程累積

每個 `claude` 進程會帶 2-3 個 MCP python 子進程。Interactive session 沒關會一直佔記憶體。

```bash
# 掃描殭屍（預覽，不殺）
/path/to/Auto_Claude/engine/cleanup.sh

# 確認後清理
/path/to/Auto_Claude/engine/cleanup.sh --kill

# 跳過確認直接清理
/path/to/Auto_Claude/engine/cleanup.sh --force
```

### Loop 啟動失敗

| 症狀 | 原因 | 解法 |
|------|------|------|
| `Loop already running` | 上次沒正常退出，lock file 殘留 | `rm .auto_claude/logs/.loop.pid` |
| `--spec is required` | 沒有 spec.txt | 放到 `.auto_claude/agent/spec.txt` |
| `Invalid API key` | 過期的 API key 蓋掉 OAuth | `unset ANTHROPIC_API_KEY` 或刪 `.auto_claude/.env` |
| Dev 第一輪就停工 | `progress.md` 記錄「全部完成」 | 清空 `progress.md` 或給明確的新 initial-prompt |

### claude --print 很慢

`claude --print` 每次呼叫都要啟動 MCP servers（2-5 秒），加上 Opus 模型推理（1-3 分鐘），一輪 Dev+Reviewer 大約 5-10 分鐘是正常的。
