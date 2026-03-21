# Auto_Claude 系統架構

完整的系統設計文件。維護、修改、擴展系統前請先讀這份。

## 目錄

1. [架構總覽](#架構總覽)
2. [檔案結構與權限](#檔案結構與權限)
3. [三個 AI 角色](#三個-ai-角色)
4. [一輪的完整流程](#一輪的完整流程)
5. [Prompt 實際組裝](#prompt-實際組裝)
6. [工具系統](#工具系統)
7. [非同步溝通（comms）](#非同步溝通comms)
8. [記憶與 Context 管理](#記憶與-context-管理)
9. [停止機制](#停止機制)
10. [已知限制](#已知限制)
11. [成本估算](#成本估算)
12. [權限自動化（settings.local.json）](#權限自動化)

---

## 架構總覽

```
┌──────────────────────────────────────────────────────────────────┐
│                      engine/loop.sh                              │
│                    （Bash 主控迴圈）                               │
│                                                                  │
│  ┌───────────┐  reviewer 回饋   ┌───────────┐                   │
│  │ Reviewer   │ ──────────────→  │   Dev     │                   │
│  │ (審查者)   │                   │ (開發者)   │                   │
│  │           │  ←──────────────  │           │                   │
│  │ --print   │    dev 輸出       │ --print   │                   │
│  │ 無狀態     │                   │ 有狀態     │                   │
│  │ 只讀工具   │                   │ 全工具     │                   │
│  └───────────┘                   └───────────┘                   │
│        ↑                              ↑                          │
│   spec.txt                      PROJECT_DIR                      │
│   todo.md                       (目標專案程式碼)                   │
│   reviewer_memory                                                │
│                                                                  │
│  📁 comms/（非同步溝通）    📁 logs/（監控）                       │
│  ├── human_message.md       ├── heartbeat                        │
│  ├── human_reply.md         └── *_loop.md                        │
│  ├── todo.md                                                     │
│  └── reviewer_memory.md                                          │
└──────────────────────────────────────────────────────────────────┘
```

---

## 檔案結構與權限

```
Auto_Claude/
│
├── engine/                              🔒 共用引擎（人類改，loop 不碰）
│   ├── loop.sh                          🔒 主控迴圈
│   ├── trigger.sh                       🔒 單次觸發（不迴圈）
│   └── extract_session.py               🔒 從 Claude session JSONL 抽取輸出
│
├── tools/                               🔒 共用工具引擎（人類寫，AI 只能呼叫）
│   ├── prompt_rw.sh                     🔒 reviewer prompt 讀寫
│   ├── todo_rw.sh                       🔒 todo 清單讀寫
│   ├── vision.sh                        🔒 Playwright 截圖引擎（未來）
│   └── healthcheck.sh                   🔒 服務狀態檢查引擎（未來）
│
├── templates/                           🔒 新專案模板（cp -r 開始）
│   ├── run.sh                           🔒 啟動腳本模板
│   ├── spec.txt                         🔒 規範書佔位
│   ├── context.md                       🔒 human_context 模板
│   ├── curator.prompt.md                🔒 curator prompt
│   ├── prompts/
│   │   └── reviewer.prompt.md           🔒 reviewer prompt 模板
│   ├── comms/
│   │   ├── human_message.md             🔒 初始值「（目前沒有人類插話）」
│   │   └── human_reply.md               🔒 初始值空白
│   ├── tools/                           🔒 專案工具目錄佔位
│   ├── refs/                            🔒 參考文件目錄佔位
│   └── logs/                            🔒 log 目錄佔位
│
├── projects/                            ★ 每個標案/專案一個資料夾
│   └── motc/                            交通部客服專案（範例）
│       ├── run.sh                       🔒 啟動腳本（人類設定路徑）
│       ├── spec.txt                     👁️ Reviewer 每輪讀
│       ├── context.md                   👁️ Dev 每輪讀（API keys、開發規則）
│       │
│       ├── prompts/
│       │   ├── reviewer.prompt.md       ✏️ Reviewer 可改（透過 prompt_rw.sh）
│       │   └── curator.prompt.md        👁️ Curator 每輪讀
│       │
│       ├── comms/                       📡 非同步溝通區
│       │   ├── human_message.md         👤→🔄 人類寫入，loop.sh 讀完自動清
│       │   ├── human_reply.md           🤖→👤 Dev 用 Bash 寫，人類讀
│       │   ├── todo.md                  ✏️ Dev + Reviewer 共用任務清單
│       │   └── reviewer_memory.md       📝 loop.sh 每輪追加，Reviewer 每輪讀
│       │
│       ├── tools/                       ✏️ 專案特化工具（Dev/Reviewer 可新增修改執行）
│       │   ├── vision_targets.md        ✏️ 截圖驗證目標
│       │   ├── docker_check.sh          ✏️ 專案的 compose 檢查
│       │   └── ...                      ✏️ Dev 可自由新增
│       │
│       ├── refs/                        👁️ 參考文件（唯讀）
│       │   └── myreact/                 👁️ 公司基礎架構參考
│       │
│       └── logs/                        📝 loop.sh 自動寫入
│           ├── heartbeat                📝 每輪覆寫（JSON）
│           └── *_loop.md                📝 完整對話 log
│
├── settings.local.json                  🔒 共用 Claude Code 權限設定
├── setup.sh                             🔒 權限設定安裝腳本
├── README.md                            🔒 快速入門
├── ARCHITECTURE.md                      🔒 ← 你在看的這份
└── GUIDE.md                             🔒 權限 5 層架構教學
```

### 目標專案（不在 Auto_Claude 裡）

```
AI交通部客服/                            🤖 Dev 的工作區（全權讀寫）
├── src/**                               ✏️ Dev 自由改
├── tests/**                             ✏️ Dev 自由改
├── progress.md                          📝 Curator 壓縮後覆寫
└── .claude/settings.local.json          🔒 人類設定
```

### 權限圖例

| 符號 | 意義 | 誰能改 |
|------|------|--------|
| 🔒 | 人類專屬 | 只有人類 |
| 👁️ | AI 可讀不可寫 | — |
| ✏️ | AI 可寫 | 標示的角色 |
| 📝 | 系統自動寫 | loop.sh / Curator |
| 📡 | 雙向通道 | 多方讀寫 |
| 👤→🔄 | 人類寫，系統清 | 人類 → loop.sh |
| 🤖→👤 | AI 寫，人類讀 | Dev → 人類 |

### 工具權限分層

| 層級 | 位置 | 誰寫 | AI 能改嗎 | 用途 |
|------|------|------|-----------|------|
| **共用引擎** | `tools/*.sh` | 人類 | 不能，只能呼叫 | 通用工具邏輯 |
| **專案工具** | `projects/xxx/tools/` | Dev/Reviewer | 可新增、修改、執行 | 專案特化檢修腳本 |

---

## 三個 AI 角色

| 角色 | 模型 | 狀態 | 工具權限 | 做什麼 |
|------|------|------|----------|--------|
| **Dev** | opus | 有（resume session） | 全部（Read/Write/Edit/Bash/...） | 寫程式、跑測試、改檔案 |
| **Reviewer** | opus | 無（每輪新開） | 只讀 + prompt_rw + todo_rw + 專案 tools/ | 審查 dev 輸出、派任務、更新 todo |
| **Curator** | sonnet | 無 | 無（純文字處理） | 壓縮 dev 輸出，寫 progress.md |

### Dev vs Reviewer 關鍵差異

```
Reviewer（審查者）                  Dev（執行者）
─────────────────                  ─────────────────
每輪重新呼叫（無狀態）              resume 同一個 session（有狀態）
system prompt = prompt 模板         system prompt = Claude Code 內建
user prompt = spec + todo + 動態     user prompt = reviewer 回饋 + todo + 人類插話
記憶靠 reviewer_memory.md           記憶靠 session context + progress.md
被 curator 重置不影響               被 curator 重置 = 換新 session
可改：自己的 prompt + todo          可改：PROJECT_DIR 全部 + todo（Bash）
```

---

## 一輪的完整流程

```
Round N:
  ├── 寫 heartbeat（JSON：pid, round, time, log path）
  │
  ├── Step A: 取得 dev 輸出
  │     ├── Round 1: 跑 initial-prompt 或 extract_session.py
  │     └── Round 2+: 用上一輪 Step C 的輸出（不重複 log）
  │
  ├── Guards
  │     ├── Rate limit → 自動等待重置時間
  │     └── 空輸出（<10 chars）→ 等 30s 重試
  │
  ├── Step B: Reviewer 審查（run_reviewer）
  │     ├── 注入：spec + dev 輸出 + human_message + human_reply
  │     │         + reviewer_memory + todo.md
  │     ├── 空回覆 guard（<5 chars）→ 替換為 fallback 訊息
  │     └── 輸出：回饋意見（<500 字）
  │
  ├── 累積 reviewer 回覆到 comms/reviewer_memory.md
  │
  ├── Step C: Dev 繼續開發（run_dev）
  │     ├── 注入：靜態規則 + reviewer 回饋 + spec 路徑提示
  │     │         + todo.md + human_message（注入後自動清除）+ context.md
  │     └── 輸出：開發結果（程式碼變更 + 測試結果 + 報告）
  │
  ├── Step D-0: 檢查停止信號
  │     └── Reviewer + Dev 都輸出 <!JOB_STOP_NOTHINGS_CAN_DO!> → 停止
  │
  └── Step D-1: Curator（每 8 輪）
        ├── sonnet 壓縮 dev 輸出 → progress.md
        └── 重置 dev session（下一輪用新 session 讀 progress.md）
```

---

## Prompt 實際組裝

`[靜態]` = 每輪一樣，`[動態]` = 每輪變化

### Reviewer 收到的（Step B: run_reviewer）

每輪全新 `claude --print` 呼叫，無 session。

```
┌─────────────────────────────────────────────────────────────────┐
│  --append-system-prompt（來自 prompts/reviewer.prompt.md）        │
│  [靜態] 角色定義 + 開發原則 + 溝通原則 + 回覆範例                   │
│         + 不可取得資源 + 停止協議                                   │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│  stdin（動態組裝的臨時檔案）                                       │
│                                                                 │
│  [靜態]  招標規範書（spec.txt 完整內容）                            │
│  [動態]  ⚠️ 人類主管的原話（human_message.md，有才出現）            │
│  [動態]  開發者對人類指示的回覆（human_reply.md，有才出現）          │
│  [動態]  審查紀錄（reviewer_memory.md 最近 100 行）                │
│  [動態]  任務清單（todo.md 完整內容）                               │
│  [動態]  開發者最新輸出（上一輪 DEV_OUTPUT）                        │
│  [靜態]  重要規則（不重複提問 + 人類指示優先 + 從 todo 挑任務）       │
│  [靜態]  工具說明（todo_rw.sh + prompt_rw.sh 使用方式）             │
└─────────────────────────────────────────────────────────────────┘
工具：Read, Glob, Grep, WebFetch, WebSearch, Bash
禁止：Write, Edit, NotebookEdit, Agent（Claude 內建工具名）
```

### Dev 收到的（Step C: run_dev）

`claude --print --resume`，有持續 session。

```
┌─────────────────────────────────────────────────────────────────┐
│  [靜態]  規則（直接做事、問題寫 questions_for_human.md、            │
│          每輪報告、目標日期、停止協議）                              │
│  [動態]  AI 審查者的回饋（REVIEWER_RESPONSE）                      │
│  [靜態]  規範書路徑提示（「不確定時自己用 Read 去看」）               │
│  [動態]  任務清單（todo.md 完整內容 + Bash 更新指引）               │
│  [動態]  ⚠️ 人類即時插話（human_message.md，注入後自動清除）        │
│  [靜態]  已知背景（context.md：API keys、開發規則等）               │
└─────────────────────────────────────────────────────────────────┘
Session context 還包含：
- 之前所有輪次的對話歷史（--resume 帶入）
- .claude/CLAUDE.md（Claude Code 自動載入）
- .claude/settings.local.json 權限設定
```

### 每輪變化摘要

| 輪次 | Reviewer 變化 | Dev 變化 |
|------|--------------|---------|
| Round 1 | reviewer_memory 空，todo 完整 | initial-prompt + spec 路徑 + todo |
| Round 2+ | memory 累積增長（上限 100 行），todo 被更新 | session context 持續累積 |
| Round 8（Curator） | memory 不受影響 | session 重置，讀 progress.md 接續 |

---

## 工具系統

### 共用工具（`tools/`）

腳本本身 🔒 不可改，AI 只能呼叫。

| 工具 | 用途 | 呼叫方式 |
|------|------|---------|
| `prompt_rw.sh` | 讀寫 reviewer prompt | `bash tools/prompt_rw.sh read\|write\|append` |
| `todo_rw.sh` | 讀寫 todo 清單 | `bash tools/todo_rw.sh <comms_dir> read\|write\|append` |
| `vision.sh` | Playwright 截圖（未來） | — |
| `healthcheck.sh` | 服務狀態檢查（未來） | — |

### 專案工具（`projects/xxx/tools/`）

Dev 和 Reviewer 可自由新增、修改、執行 ✏️。

用途：專案特化的檢修腳本。例如：
- `vision_targets.md` — 要截圖驗證的 URL + CSS selector + 驗證條件
- `docker_check.sh` — 專案特化的 Docker compose 檢查
- `etl_test.py` — 專案特化的 ETL 驗證

共用 `tools/vision.sh` 提供 Playwright 引擎，專案 `tools/vision_targets.md` 定義「截哪裡、看什麼」。

---

## 非同步溝通（comms）

位置：`projects/xxx/comms/`

| 檔案 | 寫入者 | 讀取者 | 生命週期 |
|------|--------|--------|----------|
| `human_message.md` | 人類 | Dev + Reviewer | loop.sh 注入 dev 後**自動清除** |
| `human_reply.md` | Dev（Bash echo） | 人類 + Reviewer | 持久，不自動清 |
| `todo.md` | Dev（Bash）+ Reviewer（todo_rw.sh） | Dev + Reviewer + 人類 | 持久，雙方更新狀態 |
| `reviewer_memory.md` | loop.sh（自動追加） | Reviewer | 持久，每輪增長（讀最近 100 行） |

### 溝通流向

```
人類 ──human_message.md──→ Dev（讀完自動清）
                           ↓
Dev ──human_reply.md──→ 人類 + Reviewer
                           ↓
Reviewer ──todo.md──→ Dev（下一輪看到更新的任務狀態）
Dev ──todo.md──→ Reviewer（做完標 ✅）
```

---

## 記憶與 Context 管理

### reviewer_memory.md

- loop.sh 每輪追加 reviewer 回覆
- Reviewer 每輪讀取最近 100 行（`tail -100`）
- 防止 reviewer 重複提問（鬼打牆問題）
- 不受 Curator 重置影響

### progress.md

- 位置：`PROJECT_DIR/progress.md`（目標專案裡）
- 每 8 輪（CURATOR_INTERVAL）由 Curator（sonnet）壓縮生成
- 保留：檔案路徑、function 名、commit hash、測試結果、架構決策
- 砍掉：重複資訊、客套話、已執行的「下一步」
- 壓縮後重置 dev session，下一輪讀 progress.md 接續

### todo.md

- 位置：`projects/xxx/comms/todo.md`
- Dev + Reviewer 共用任務清單
- 每輪注入雙方 prompt
- 不受 Curator 重置影響（不在 PROJECT_DIR）

### Context rot 對策

Dev 跑久了 context 會滿，品質下降：
1. Curator 每 8 輪壓縮 + 重開 session
2. Claude Code 內建 auto-compact（~190K tokens 觸發）
3. context.md 保持精簡
4. Dev 第一輪讀 spec，後續按需自己 Read（不每輪注入）

---

## 停止機制

| 方式 | 觸發條件 | 說明 |
|------|---------|------|
| 自然結束 | 跑完 max-rounds | — |
| 雙方同意 | Reviewer + Dev 都輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>` | 兩邊都認為無事可做 |
| 手動 | `kill <PID>` | heartbeat 裡有 PID |
| Rate limit | 自動偵測 | 解析重置時間，sleep 到重置 +60s buffer |

---

## 已知限制

1. **Bash for loop 記憶體模型**：loop.sh 跑起來後，整個 for 迴圈已載入記憶體。改 loop.sh 不會影響正在跑的 process，必須 kill 再重啟
2. **Reviewer 無狀態**：每輪新的 `--print` 呼叫，靠 reviewer_memory.md 模擬記憶
3. **Dev session 路徑依賴**：`--resume` 需要在正確的 PROJECT_DIR 下執行，否則找不到 session 檔案
4. **Reviewer 寫入限制**：沒有 Write/Edit 工具權限。能寫的只有：自己的 prompt（prompt_rw.sh）、todo（todo_rw.sh）、專案 tools/（Bash）
5. **Dev 寫入 comms 限制**：comms 在 Auto_Claude 目錄下，Dev 的 Write 工具受 project-dir 限制，需用 Bash echo 寫入
6. **Reviewer 空回覆**：偶爾發生（rate limit 或模型回傳空字串），已有 guard 自動替換為 fallback 訊息，但該輪等於沒有審查

---

## 成本估算

| 角色 | 每輪 input | 每輪 output |
|------|-----------|------------|
| Dev | ~50K-150K tokens | ~2K-10K tokens |
| Reviewer | ~20K-40K tokens | ~200-500 tokens |
| Curator（每 8 輪） | ~5K-15K tokens | ~1K-3K tokens |

50 輪 opus 跑一晚約 $50-150 USD，視 dev 輸出長度和工具呼叫次數而定。

---

## 權限自動化

Claude Code `settings.local.json` 團隊共用設定。減少不必要的授權確認提示。

> 完整的 5 層權限架構教學 → **[GUIDE.md](GUIDE.md)**

### allow（自動允許）

| 類別 | 涵蓋範圍 |
|------|---------|
| `Bash(*)` | 基礎萬用匹配（不夠，見 GUIDE.md） |
| Python | `python3 *`, `pip3 *`, `pip *` 及其 `\|` `&&` 變體 |
| Node.js | `node *`, `npm *`, `npx *` 及其 `\|` `&&` 變體 |
| Git / GitHub | `git *`, `gh *` 及其 `\|` `&&` 變體 |
| 檔案操作 | `ls`, `cat`, `cp`, `mv`, `mkdir`, `touch`, `chmod`, `head`, `tail`, `wc`, `sort`, `diff`, `find`, `du`, `df` |
| 文字處理 | `echo`, `grep`, `sed`, `awk`, `xargs`, `tee` |
| 壓縮/下載 | `unzip`, `tar`, `curl`, `wget` |
| 資料庫 | `sqlite3 *` |
| 遠端 | `ssh *`, `scp *` |
| 環境 | `env *`, `export *`, `source *`, `. *` |
| 套件管理 | `brew *`, `pip install *` |
| 開發伺服器 | `uvicorn *`, `pytest *` |
| Shell 導航 | `cd *`, `cd *&&*`, `cd *;*` |
| Claude 工具 | `Read`, `Write`, `Edit`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `NotebookEdit` |

### deny（封鎖）

| 規則 | 原因 |
|------|------|
| `rm -rf /`, `rm -rf /*` | 刪除整台電腦 |
| `rm -rf ~`, `rm -rf ~/*` | 刪除整個家目錄 |
| `sudo *` | 提權操作 |
| `git push --force *` | 覆蓋遠端歷史 |
| `git reset --hard *` | 丟棄未提交變更 |

### 已知限制（權限相關）

- **Brace expansion `{}`**：Claude Code 內建攔截，改寫成展開形式可避開
- **`cd && git` 組合**：內建防護，加 `Bash(cd *&&*)` 可減少觸發
- **首次專案存取**：選 "always allow access" 後不再問
- `Bash(*)` 不是萬能的，必須搭配明確模式匹配（見 [GUIDE.md](GUIDE.md) 實戰案例）
