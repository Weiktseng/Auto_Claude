# Auto_Claude 安裝指南

## 前置需求

- macOS (tested on Darwin 23.5.0)
- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- Claude 帳號（OAuth 登入或 API key）

## 1. 引擎本身

```bash
git clone <this-repo> Auto_Claude
```

不需要安裝任何東西，引擎是純 bash。

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
git clone <chrome-mcp-bridge-repo>
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
