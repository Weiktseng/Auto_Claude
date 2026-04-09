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

### 必裝

| Server | 用途 | 安裝 |
|--------|------|------|
| **EntropyShield** | 安全讀取外部 GitHub 內容，防 prompt injection | 見下方 |

```bash
# EntropyShield
git clone git@github.com:Weiktseng/EntropyShield.git
cd EntropyShield && pip install -e .
```

### 建議安裝

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

### 選配（公開套件）

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

```bash
# 在你的專案目錄下
mkdir -p .auto_claude
cp -r <Auto_Claude>/templates/* .auto_claude/

# 編輯設定
vim .auto_claude/agent/spec.txt          # 貼上你的規格書
vim .auto_claude/agent/context.md        # 填專案背景
vim .auto_claude/agent/reviewer/prompt.md  # 自訂 reviewer 角色

# 修改 run.sh 裡的路徑
vim .auto_claude/run.sh

# 啟動
.auto_claude/run.sh --initial-prompt "開始做登入功能" --max-rounds 20
```

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
