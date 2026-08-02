# Auto_Claude

全自動 Dev ↔ Reviewer 開發迴圈引擎。兩個 AI 協作推進專案，人類睡覺。

## 概念

```
  Reviewer（審查者）              Dev（開發者）
  ┌──────────┐                  ┌──────────┐
  │ 讀 spec  │─── 回饋 ───→     │ 寫程式    │
  │ 讀 todo  │                  │ 跑測試    │
  │ 只讀工具  │←── 結果 ───     │ 全工具    │
  └──────────┘                  └──────────┘
       ↑                             ↑
  engine/loop.sh 每輪自動串接，人類可隨時插話
```

- **Dev**：Claude `--print` 模式，擁有完整工具（Write/Edit/Bash/MCP），在目標專案目錄執行
- **Reviewer**：Claude `--print` 模式，只有讀取工具，審查 Dev 的輸出後給回饋
- **Curator**：每 N 輪壓縮 context，殺掉舊 session、開新 session，防止 token 爆炸
- **人類**：隨時透過 `human_message.md` 插話，或用 `--human` 模式直接取代 Reviewer

## 引擎不含任何專案

這個 repo 是**純引擎**。專案配置放在各自的 `.auto_claude/` 目錄下，不在這裡。

```
Auto_Claude/          ← 你現在在這裡（引擎）
├── engine/           ← 核心引擎
├── templates/        ← 新專案模板
├── tools/            ← Reviewer 用的小工具
└── references/       ← 參考文件

<你的專案>/
└── .auto_claude/     ← 從 templates/ 複製過去，專案自治
    ├── agent/        ← AI 的 context、prompt、記憶
    ├── logs/         ← loop log、session index
    └── run.sh        ← 啟動腳本
```

## 快速開始

### 1. 安裝引擎

```bash
git clone git@github.com:Weiktseng/Auto_Claude.git
```

引擎是純 bash，不需要 `pip install`。但需要 Claude Code CLI：

```bash
npm install -g @anthropic-ai/claude-code
claude login  # OAuth 登入
```

### 2. 建立新專案

```bash
cd /path/to/your-project
mkdir -p .auto_claude
# 選一套架構複製（兩套獨立，不要都複製）：
cp -r /path/to/Auto_Claude/templates/classic/*  .auto_claude/   # Dev ↔ Reviewer 單迴圈
# cp -r /path/to/Auto_Claude/templates/pipeline/* .auto_claude/ # Stage 1→2→3 三段式

# 編輯三個關鍵檔案：
vim .auto_claude/agent/spec.txt            # 規格書（AI 的需求來源）
vim .auto_claude/agent/context.md          # 專案背景、技術棧、注意事項
vim .auto_claude/agent/reviewer/prompt.md  # Reviewer 的角色定義

# 改 run.sh 裡的 ENGINE_REPO 路徑
vim .auto_claude/run.sh
```

### 3. 設定權限

Dev 在 `--print` 模式跑，需要預先授權工具，否則每個動作都會卡住等確認：

```bash
mkdir -p .claude
cp /path/to/Auto_Claude/settings.local.json .claude/settings.local.json
```

### 4. 啟動

```bash
# 全自動模式（AI Reviewer ↔ AI Dev）
.auto_claude/run.sh --initial-prompt "開始做登入功能" --max-rounds 20

# 人類模式（你取代 Reviewer，直接跟 Dev 對話）
.auto_claude/run.sh --human --initial-prompt "修復首頁的 XSS 漏洞"

# 背景執行
nohup .auto_claude/run.sh --initial-prompt "..." --max-rounds 50 \
  > .auto_claude/logs/overnight.log 2>&1 &
```

## 兩種模式

### 全自動模式（預設）

```
Round 1: Dev 執行 initial-prompt → Reviewer 審查 → Dev 根據回饋繼續
Round 2: Dev 輸出 → Reviewer 審查 → Dev 繼續
...
Round N: 雙方都發 <!JOB_STOP_NOTHINGS_CAN_DO!> → 停止
```

### 人類模式（`--human`）

```
Round 1: Dev 執行 initial-prompt → 印出 Dev 輸出 → 等你輸入指令（Ctrl+D 送出）
Round 2: Dev 執行你的指令 → 印出結果 → 等你下一個指令
...
輸入 q → 退出
```

## 常用指令

```bash
# 監控
cat .auto_claude/logs/heartbeat                    # 看跑到第幾輪
tail -f .auto_claude/logs/dev_live_round*.log      # 即時看 Dev 輸出
tail -f .auto_claude/logs/*_loop.md                # 完整 loop log

# 人類插話（全自動模式下，不需要停 loop）
echo "先把測試補齊" > .auto_claude/agent/comms/human_message.md

# 看 Dev 對人類的回覆
cat .auto_claude/agent/comms/human_reply.md

# 停止 loop
kill $(cat .auto_claude/logs/heartbeat | python3 -c "import sys,json;print(json.load(sys.stdin)['pid'])")

# 清理殭屍進程
/path/to/Auto_Claude/engine/cleanup.sh --kill
```

## 參數

| 參數 | 預設 | 說明 |
|------|------|------|
| `--project-dir` | 必填 | 目標專案路徑 |
| `--initial-prompt` | 無 | 第一輪 Dev 起始指令（新啟動必填） |
| `--human` | false | 人類取代 Reviewer |
| `--max-rounds` | 10 | 最大輪數 |
| `--model-reviewer` | opus | Reviewer 模型 |
| `--model-dev` | opus | Dev 模型 |
| `--spec` | agent/spec.txt | 規範書路徑 |
| `--prompt-template` | agent/reviewer/prompt.md | Reviewer prompt 路徑 |
| `--context` | agent/context.md | context.md 路徑 |
| `--resume-session` | 無 | 接續已有的 Dev session |

## 專案目錄結構

```
<你的專案>/.auto_claude/
├── run.sh                        ← 啟動腳本（指向 Auto_Claude 引擎）
├── agent/
│   ├── spec.txt                  ← 規格書（需求來源）
│   ├── context.md                ← 專案背景、技術棧
│   ├── reviewer/
│   │   ├── prompt.md             ← Reviewer 角色定義 + 審查規則
│   │   └── memory.md             ← Reviewer 累積記憶（自動產生）
│   ├── dev/
│   │   ├── prompt.md             ← Dev 規則（如何工作、何時停止）
│   │   ├── memory.md             ← Dev 筆記（自動產生）
│   │   └── progress.md           ← Curator 壓縮的進度摘要（自動產生）
│   ├── curator/
│   │   └── prompt.md             ← Curator 壓縮規則
│   └── comms/                    ← 人類 ↔ AI 溝通管道
│       ├── human_message.md      ← 人類寫，AI 讀（下一輪生效）
│       ├── human_reply.md        ← Dev 寫，人類讀
│       └── todo.md               ← 任務清單（Dev + Reviewer 共用）
└── logs/
    ├── *_loop.md                 ← 完整 loop log
    ├── *_sessions.csv            ← session UUID 對照表
    ├── dev_live_round*.log       ← Dev 即時輸出
    └── heartbeat                 ← JSON：pid、round、時間
```

## 停止機制

1. **雙邊停工協議**：Dev 和 Reviewer 都在回應中輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>` 才停（`--human` 模式下 Reviewer 是你，所以只有你說停才停）
2. **最大輪數**：達到 `--max-rounds` 自動停
3. **手動 kill**：`kill <pid>`

## 其他文件

| 文件 | 內容 |
|------|------|
| [SETUP.md](SETUP.md) | 完整安裝指南（MCP servers、全域配置、Phase 切分分析） |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 系統架構、Prompt 組裝、三層抓 bug 機制 |
| [GUIDE.md](GUIDE.md) | 權限 5 層架構教學 |
| [KNOWN_PITFALLS.md](KNOWN_PITFALLS.md) | 已知坑和解法 |

## 能力邊界

Auto_Claude 架構上不限制只能做 dev loop。通用 autonomous AI agent（例如 OpenClaw）的核心能力，Auto_Claude 都能提供：

| 能力 | Auto_Claude 對應實現 |
|---|---|
| 本機執行、零雲端依賴 | bash loop 本機跑 |
| 長期記憶 | `agent/reviewer/memory.md`（Reviewer 跨輪）+ `agent/dev/progress.md`（Curator 每 8 輪壓縮）+ Dev session `--resume` + `agent/dev/memory.md` 四層 |
| Self-improving | Dev 有全工具權限，每輪可自由新增專案內的工具腳本 / helper 檔案 |
| Proactive 自主推進 | loop 每輪主動推進不等人類（這正是 `loop.sh` 的全部工作） |
| 任意介面接入 | 核心介面 `bash loop.sh --initial-prompt "..."`；要接 messaging（Signal/Telegram/Discord）、webhook、chatbot、cron 都是 adapter 層問題——寫個薄殼呼叫 loop，或把訊息寫進 `agent/comms/human_message.md` 即可 |
| LLM 替換 | 預設 `claude --print` 吃 Claude Max plan（推薦）；`run_dev` 呼叫層替換後可接其他 CLI-based LLM |

**但大多數通用助理場景根本不需要 loop**：一顆設定好的 Claude CLI + 一個好的 `settings.local.json` 就能把「幫我查資料 / 整理筆記 / 跑一次性腳本 / 操作雲端服務」這類任務做得很好，一次搞定。Auto_Claude 的多輪架構是**專門為單輪 CLI 做不到的事**準備的——那種跑 8 小時、會自我退化、會把 bug 藏起來、需要外部視角反覆審查的長程 dev 任務。

換句話說：loop 的複雜度只該在需要它的地方出現。通用任務用 Claude CLI 一次性搞定就好，不需要也不應該套上多輪架構。

---

## 開發歷程（公開時間戳證明）

本 repo 所有時間戳可在 `git log --format="%h %ai %s"` 驗證。以下是核心里程碑：

| 日期（git `%ai` 原值） | 里程碑 | Commit |
|---|---|---|
| 2026-03-13 14:42:14 +0800 | Repo init（權限底座） | [`819c0bd`](../../commit/819c0bd) |
| **2026-03-16 19:53:32 +0800** | **首版 Dev ↔ Reviewer 自動化迴圈** + 檔案式 async 通訊 pattern（`questions_for_human.md` Dev→人類單向） | [**`a7c923b`**](../../commit/a7c923b) |
| **2026-03-21 19:34:08 +0800** | **`comms/human_message.md` + `human_reply.md` 完整非同步雙向 mid-loop HITL 落地**（同一 commit 也做了 engine/projects/templates 架構拆分） | [**`f595905`**](../../commit/f595905) |
| 2026-03-24 02:41:01 +0800 | `.auto_claude/` 專案自治 + `human_message_history.log` 自動歸檔 + reviewer timeout | [`738b673`](../../commit/738b673) |
| 2026-04-11 | Except 反模式 hook + Phase 切分指引 + 三層防禦文件 | `834e0e3` |

