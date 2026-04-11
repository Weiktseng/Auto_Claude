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
cp -r /path/to/Auto_Claude/templates/* .auto_claude/

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

## 與其他多 agent 框架的 HITL 設計比較

本節記錄 Auto_Claude 與 **AutoGen（Microsoft）** 在 **Human-in-the-Loop（HITL）** 設計上的根本差異。Auto_Claude 的檔案式 async 通訊 pattern 於 **2026-03-16 commit `a7c923b`**（首版 loop.sh 就有 `questions_for_human.md` Dev→人類單向訊息）落地，完整的 **人類↔AI 非同步雙向 mid-loop HITL**（`comms/human_message.md` + `human_reply.md`）於 **2026-03-21 commit `f595905`** 進入 repo。兩套設計解的是不同問題，列此僅為釐清技術定位，不代表其中一方優劣。

### AutoGen `UserProxyAgent`（同步阻塞 HITL）

直接引用 Microsoft 官方文件（[autogen human-in-the-loop docs](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/human-in-the-loop.html)，2026-04-11 查核）：

> "When UserProxyAgent is called during a run, **it blocks the execution of the team until the user provides feedback or errors out.**"
>
> "This will **hold up the team's progress and put the team in an unstable state that cannot be saved or resumed.**"
>
> 官方建議僅用於 "short interactions that require immediate feedback from the user, such as asking for approval or disapproval with a button click."

特性：
- 預設從 **stdin** 讀（`input_func=input`），可客製成 websocket
- 人類必須**同步在線**；不在線整個 team 卡住
- 執行中的 team **無法 save/resume**（官方警告）
- 官方明確說適用場景是**短互動**（如按鈕確認）

### Auto_Claude `comms/human_message.md`（非同步檔案 HITL）

- 人類在**任何時候**用任何編輯器寫入 `comms/human_message.md`（或完全不寫）
- `loop.sh` 每輪開頭讀一次：若非預設值就注入到該輪 Dev prompt、歸檔到 `human_message_history.log`、清空回預設
- Loop **從不為了等人類而阻塞**——人類 3 小時不回，loop 就跑 3 小時的自主開發；3 天不回，就 3 天
- 歷史自動追蹤在 `human_message_history.log`，附每筆的時間戳和當時的 round 編號
- 設計目的：**長時間無人值守自主迴圈**（整夜跑、週末跑、人類偶爾檢查）

### 對照表

| 維度 | AutoGen `UserProxyAgent` | Auto_Claude `human_message.md` |
|---|---|---|
| 輸入機制 | stdin / 客製 websocket | 檔案系統（vim / echo / 任何編輯器） |
| 執行模式 | **同步阻塞** | **非同步非阻塞** |
| 人類必須在線？ | 是 | 否 |
| Team/loop 可否 save/resume？ | 阻塞時官方警告「無法」 | 一律可以（每輪間無跨輪狀態） |
| 適用情境 | 短互動、即時決策、approval click | 長時間自主、偶爾介入、整夜跑 |
| 歷史追蹤 | 需客製實作 | 自動 append 到 `human_message_history.log` |
| 人類「插話」後的 AI 反應 | 阻塞結束後直接接收 | 下一輪開頭看到，視為最高優先指令 |
| 首次 commit | 早於 2026-04 | 檔案式 async pattern 2026-03-16 `a7c923b`；雙向 mid-loop HITL 2026-03-21 `f595905` |

### 為什麼差別重要

AutoGen 的同步模式在**互動式開發**（開發者坐在終端前即時指導 agent）很合理。Auto_Claude 的非同步模式在**無人值守長時間自主開發**（這正是 Auto_Claude 被設計的場景——人類交代任務後去睡覺/上班，早上回來看進度）才會 shine。

兩個設計反映兩種不同的 human-AI 協作哲學：
- **AutoGen**：AI 是助手，人類是主控，隨時在場
- **Auto_Claude**：AI 是值班工程師，人類是主管，定期 check-in

因此 `human_message.md` 的 design 核心不是「讓人類講話」，而是「**讓人類在場和不在場都不影響 AI 產出速度**」。這個不對稱性是 AutoGen 同步模式無法提供的。
