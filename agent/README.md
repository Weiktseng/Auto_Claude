# Dev ↔ Reviewer Loop — 全自動開發迴圈

讓兩個 AI（Dev 開發者 + Reviewer 審查者）自動對話推進專案開發。人類睡覺，AI 工作。

## 架構總覽

```
┌─────────────────────────────────────────────────────────────┐
│                        loop.sh                              │
│                    （Bash 主控迴圈）                          │
│                                                             │
│  每一輪 (Round)：                                            │
│                                                             │
│  ┌──────────┐  reviewer 回饋   ┌──────────┐               │
│  │ Reviewer  │ ──────────────→  │   Dev    │               │
│  │ (審查者)  │                   │ (開發者)  │               │
│  │          │  ←──────────────  │          │               │
│  │ --print  │    dev 輸出       │ --print  │               │
│  │ 無狀態    │                   │ 有狀態    │               │
│  │ 只讀工具  │                   │ 全工具    │               │
│  └──────────┘                   └──────────┘               │
│       ↑                              ↑                      │
│       │                              │                      │
│  ┌────┴────┐                   ┌─────┴─────┐               │
│  │ 規範書   │                   │ 專案程式碼  │               │
│  │ spec.txt │                   │ PROJECT_DIR│               │
│  └─────────┘                   └───────────┘               │
│                                                             │
│  📁 IPC 檔案（在 PROJECT_DIR 下）：                           │
│  ├── human_message.md   ← 人類寫，dev 讀                    │
│  ├── human_reply.md     ← dev 回覆人類，reviewer 也讀       │
│  ├── reviewer_memory.md ← 每輪 reviewer 回覆累積，防重複提問 │
│  └── progress.md        ← curator 壓縮的進度紀錄             │
│                                                             │
│  📁 監控檔案（在 agent/logs/ 下）：                           │
│  ├── heartbeat          ← JSON，每輪更新，快速檢查活著沒      │
│  └── *_loop.md          ← 完整對話 log                      │
└─────────────────────────────────────────────────────────────┘
```

## 一輪的完整流程

```
Round N:
  ├── 寫 heartbeat
  ├── Step A: 取得 dev 輸出
  │     ├── Round 1: 跑 initial-prompt 或 extract_session.py
  │     └── Round 2+: 用上一輪 Step C 的輸出
  ├── Guards: rate limit 檢查 + 空輸出檢查
  ├── Step B: Reviewer 審查（run_reviewer）
  │     ├── 注入：規範書 + dev 輸出 + human_message + human_reply + reviewer_memory
  │     └── 輸出：回饋意見（<500 字）
  ├── 累積 reviewer 回覆到 reviewer_memory.md
  ├── Step C: Dev 繼續開發（run_dev）
  │     ├── 注入：reviewer 回饋 + human_message + human_context.md
  │     └── 輸出：開發結果
  ├── Step D-0: 檢查停止信號（雙方都輸出 <!JOB_STOP_NOTHINGS_CAN_DO!> 才停）
  └── Step D-1: 每 N 輪觸發 Curator 壓縮 → 重置 dev session
```

## 三個 AI 角色

| 角色 | 模型 | 狀態 | 工具權限 | 做什麼 |
|------|------|------|----------|--------|
| **Dev** | opus | 有（resume session） | 全部（Read/Write/Edit/Bash/...） | 寫程式、跑測試、改檔案 |
| **Reviewer** | opus | 無（每輪新開） | 只讀（Read/Glob/Grep/Web） | 審查 dev 輸出、給回饋 |
| **Curator** | sonnet | 無 | 無（純文字處理） | 壓縮 dev 輸出，寫 progress.md |

## 檔案結構

```
Auto_Claude/
├── README.md                          # 專案總覽（權限管理 + loop 導覽）
├── GUIDE.md                           # 權限 5 層架構教學
├── settings.local.json                # 共用的 Claude Code 權限設定
├── setup.sh                           # 權限設定安裝腳本
│
└── agent/                             # ★ Dev ↔ Reviewer Loop 系統
    ├── README.md                      # ← 你在看的這份文件
    │
    ├── loop.sh                        # 主控迴圈（核心引擎）
    ├── trigger.sh                     # 單次觸發（不迴圈，跑一次就結束）
    ├── extract_session.py             # 從 Claude Code session JSONL 抽取輸出
    │
    ├── motc_loop.sh                   # 交通部專案的 loop 啟動腳本（包裝 loop.sh）
    ├── motc.sh                        # 交通部專案的 trigger 啟動腳本
    ├── motc_myreact_loop.sh           # myReAct 分支的 loop 啟動腳本
    │
    ├── human_context.md               # ★ 人類指令（每輪注入 dev，等同 system prompt）
    │                                  #   內容：API keys、開發規則、背景資訊
    │                                  #   ⚠️ 在 .gitignore 裡，不會推上 GitHub
    │
    ├── spec_dev.txt                   # ★ 規範書（精簡版，注入 reviewer）
    ├── spec_raw.txt                   #   規範書原始版
    │
    ├── prompts/                       # Reviewer prompt 模板
    │   ├── reviewer.prompt.example.md #   範例模板（給新專案複製用）
    │   ├── human_context.example.md   #   human_context 範例
    │   ├── motc_reviewer.prompt.md    #   交通部專用 reviewer prompt
    │   ├── motc_myreact_reviewer.prompt.md # myReAct 分支專用
    │   └── curator.prompt.md          #   Curator 壓縮器 prompt
    │
    └── logs/                          # 執行日誌（在 .gitignore 裡）
        ├── heartbeat                  #   JSON，最新一輪的狀態
        ├── *_loop.md                  #   每次執行的完整對話 log
        └── *_stdout.log              #   背景執行時的 stdout
```

## 快速開始

### 1. 準備檔案

你需要自己準備（不在 git 裡）：

| 檔案 | 說明 | 範例 |
|------|------|------|
| `agent/human_context.md` | 每輪注入 dev 的人類指令 + API keys | 看 `prompts/human_context.example.md` |
| `agent/spec_dev.txt` | 規範書（reviewer 每輪讀這個） | 政府招標規格、PRD、任何需求文件 |
| 目標專案的 `.claude/settings.local.json` | 工具自動授權 | 複製本 repo 的 `settings.local.json` |

### 2. 建立啟動腳本

複製 `motc_loop.sh` 改成你的專案：

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "$SCRIPT_DIR/loop.sh" \
    --project-dir "/path/to/your/project" \
    --spec "$SCRIPT_DIR/spec_dev.txt" \
    --prompt-template "$SCRIPT_DIR/prompts/your_reviewer.prompt.md" \
    "$@"
```

### 3. 建立 reviewer prompt

複製 `prompts/reviewer.prompt.example.md` 改成你的專案。裡面要放：

- 角色定義
- 開發原則
- 溝通原則 + 回覆範例
- 任務清單（有的話）
- 不可取得資源清單（有的話）
- 停止協議

### 4. 跑

```bash
# 基本啟動
./agent/your_loop.sh --max-rounds 50

# 指定起始任務
./agent/your_loop.sh --initial-prompt "開始做登入功能" --max-rounds 20

# reviewer 用 sonnet 省錢
./agent/your_loop.sh --model-reviewer sonnet

# 背景執行
nohup ./agent/your_loop.sh --max-rounds 50 > agent/logs/overnight_stdout.log 2>&1 &
```

### 5. 參數一覽

| 參數 | 預設 | 說明 |
|------|------|------|
| `--project-dir` | （必填） | 目標專案路徑（dev 的工作目錄） |
| `--spec` | （必填） | 規範書路徑 |
| `--prompt-template` | `prompts/motc_reviewer.prompt.md` | Reviewer prompt 模板路徑 |
| `--model-reviewer` | `opus` | Reviewer 用的模型 |
| `--model-dev` | `opus` | Dev 用的模型 |
| `--max-rounds` | `10` | 最大輪數 |
| `--resume-session` | （自動） | 指定 dev session ID 繼續 |
| `--initial-prompt` | （無） | 第一輪 dev 的起始指令 |

## 監控

### 快速檢查活著沒

```bash
cat agent/logs/heartbeat
# 輸出: {"pid":37530,"round":3,"max":50,"time":"2026-03-17 02:15:33","log":"..."}
```

### 看即時 log

```bash
tail -f agent/logs/*_loop.md
```

### 看最新一份 log

```bash
ls -t agent/logs/*_loop.md | head -1 | xargs cat
```

## 人類插話（Human Hotline）

在 loop 跑的時候，你可以即時跟 dev 溝通：

### 寫指令給 dev

```bash
# 寫訊息（dev 下一輪會讀到）
echo "先不要做新功能，把測試補齊" > /path/to/project/human_message.md

# dev 讀完會：
# 1. 把回覆寫到 human_reply.md
# 2. 把 human_message.md 清空為「（目前沒有人類插話）」
```

### 看 dev 的回覆

```bash
cat /path/to/project/human_reply.md
```

### Reviewer 也會看到

Reviewer 每輪會讀 `human_message.md` 和 `human_reply.md`，確保指令被執行。

### 清空狀態

```bash
echo "（目前沒有人類插話）" > /path/to/project/human_message.md
```

## Prompt 實際組裝 — AI 到底收到什麼

loop.sh 每輪會組裝兩個 prompt：一個給 Reviewer，一個給 Dev。以下用交通部專案為例，展示實際插入的內容。

`[靜態]` = 每輪一樣，`[動態]` = 每輪變化，`...` = 內容省略

---

### Reviewer 收到的 prompt（Step B: run_reviewer）

Reviewer 用 `claude --print`，每輪全新呼叫，無狀態。

**傳入方式：`--append-system-prompt` + stdin**

```
┌─────────────────────────────────────────────────────────────────┐
│  --append-system-prompt（系統提示，來自 motc_reviewer.prompt.md）  │
│  [靜態] 整個 prompt 模板原封不動塞進去                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  # 交通部客服專案 — AI 審查者（Reviewer）                         │
│  你是一位嚴格的專案審查者。你的唯一依據是招標規範書。                │
│                                                                 │
│  ## 你的角色                                                     │
│  - 你是讀過規範書的推動專案前進的vibe coder...                     │
│                                                                 │
│  ## 開發原則（你必須執行）                                        │
│  1. 以招標規範書為唯一功能依據...                                  │
│                                                                 │
│  ## 溝通原則                                                     │
│  1. 高資訊密度...                                                │
│                                                                 │
│  ## 你的回覆的範例                                                │
│  Ａ 好就照你說的ＸＸＸ去做                                        │
│  Ｂ 等等 為什麼這樣做？...                                        │
│  ...Ｚ                                                           │
│                                                                 │
│  ## 任務清單                                                     │
│  (你自定義的任務表)                                               │
│                                                                 │
│  ## 停止協議                                                     │
│  ...<!JOB_STOP_NOTHINGS_CAN_DO!>...                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  stdin（使用者提示，由 run_reviewer() 動態組裝的臨時檔案）          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [靜態] 你是 AI 審查者。根據以下規範書與開發原則，對開發者輸出       │
│  做出判斷。                                                      │
│                                                                 │
│  # 招標規範書（精簡版）                                           │
│                                                                 │
│  [靜態] {spec_dev.txt 的完整內容，每輪都一樣}                      │
│                                                                 │
│  ---                                                             │
│                                                                 │
│  [動態・條件] 有 human_message.md 且不是「目前沒有人類插話」時：     │
│  # ⚠️ 人類主管的原話（最高優先，你的建議必須符合這個方向）          │
│  {human_message.md 內容}                                         │
│                                                                 │
│  [動態・條件] 有 human_reply.md 時：                               │
│  # 開發者對人類指示的回覆紀錄                                     │
│  {human_reply.md 內容}                                           │
│                                                                 │
│  ---                                                             │
│                                                                 │
│  [動態・每輪增長] 有 reviewer_memory.md 時：                       │
│  # 你過去的審查紀錄（已經問過/確認過的事不要再問！）                │
│  {reviewer_memory.md 最近 100 行}                                │
│                                                                 │
│  ---                                                             │
│                                                                 │
│  # 開發者最新輸出                                                 │
│                                                                 │
│  [動態・每輪不同] {上一輪 Step C 的 DEV_OUTPUT}                    │
│                                                                 │
│  ---                                                             │
│                                                                 │
│  [靜態] 請根據你的角色定義和開發原則，對以上內容做出回覆。           │
│  重要規則：                                                      │
│  1. 查看「你過去的審查紀錄」，已經問過且 Dev 已回答的問題，         │
│     不要再問。往前推進，不要原地踏步。                              │
│  2. 如果上面有「人類主管的原話」或「開發者對人類指示的回覆紀錄」，   │
│     你的回覆第一行必須寫「📌 已讀人類指示：」加一句摘要...           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

工具權限：--disallowed-tools "Write Edit NotebookEdit Agent"
         --allowedTools "WebFetch WebSearch Read Glob Grep mcp__entropyshield__*"
（注意：Agent 是 Claude Code 內建工具名，不是角色名，所以這裡維持 "Agent"）
```

---

### Dev 收到的 prompt（Step C: run_dev）

Dev 用 `claude --print --resume`，有持續的 session 狀態。

**Round 1（新 session 或 initial-prompt）：**

Dev 第一輪收到的是 `--initial-prompt` 的內容，或 extract_session.py 抽出的上一個 session 輸出。如果有 `progress.md`（前一次 loop 的壓縮紀錄），會在前面加上：

```
┌─────────────────────────────────────────────────────────────────┐
│  [動態・條件] 有 progress.md 時（session 重置後的第一輪）：         │
│                                                                 │
│  你是接手的開發者。以下是前一輪的壓縮進度紀錄，讀完後繼續工作：     │
│  {progress.md 內容}                                              │
│  ---                                                             │
│  {原本的 message}                                                │
└─────────────────────────────────────────────────────────────────┘
```

**Round 2+（resume session，每輪都收到的 prompt）：**

```
┌─────────────────────────────────────────────────────────────────┐
│  Dev prompt（Step C 組裝的臨時檔案，送入 --resume session）        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [靜態] 規則：                                                   │
│  1. 直接動手做事，不要問問題。你是 RD，寫程式是你的工作。           │
│  2. 如果有問題只有人類能回答，把問題追加寫到                       │
│     questions_for_human.md，然後繼續做你能做的部分。               │
│  3. 每輪結束時報告：做了什麼（具體檔案/功能）、下一步打算做什麼。   │
│  4. 目標：3/31 在另一台乾淨電腦上能展示給政府官員看。              │
│  5. 停止協議：如果你確認所有剩餘工作都需要人類才能繼續，            │
│     且 reviewer 也同意，在回覆中輸出 <!JOB_STOP_NOTHINGS_CAN_DO!>│
│                                                                 │
│  以下是 AI 審查者的回饋：                                         │
│                                                                 │
│  [動態・每輪不同] {REVIEWER_RESPONSE — 本輪 reviewer 的回覆}      │
│                                                                 │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                │
│                                                                 │
│  [動態・條件] human_message.md 有內容時：                          │
│  ⚠️ 人類即時插話（最高優先，讀完後把回覆寫到                       │
│  human_reply.md，然後清空 human_message.md                        │
│  寫入「（目前沒有人類插話）」）：                                  │
│  {human_message.md 內容}                                         │
│                                                                 │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─                │
│                                                                 │
│  [靜態] 已知背景（不需要再問）：                                   │
│                                                                 │
│  [靜態] {human_context.md 完整內容}                               │
│  （API keys、開發規則 A-I、資深同事資料、demo URL 等）             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Dev 的 session context 還包含：
- 所有之前輪次的對話歷史（--resume 帶入）
- Claude Code 自動載入的 .claude/CLAUDE.md
- 專案目錄下的 .claude/settings.local.json 權限
```

---

### 每輪變化摘要

| 輪次 | Reviewer 收到的變化 | Dev 收到的變化 |
|------|---------------------|---------------|
| Round 1 | reviewer_memory 為空 | initial-prompt 或 extract_session 輸出 |
| Round 2 | reviewer_memory += Round 1 回覆 | reviewer 回饋 + (human_message) + human_context |
| Round 3 | reviewer_memory += Round 1-2 回覆 | 同上，session context 持續累積 |
| ... | reviewer_memory 持續增長（上限 100 行） | session context 持續增長 |
| Round 8 | 同上 | **Curator 觸發** → progress.md 更新 → session 重置 |
| Round 9 | reviewer_memory 還在（不受 curator 影響） | 新 session，讀 progress.md 接續 |

### 關鍵差異

```
Reviewer（審查者）                  Dev（執行者）
─────────────────                  ─────────────────
每輪重新呼叫（無狀態）              resume 同一個 session（有狀態）
system prompt = prompt 模板         system prompt = Claude Code 內建
user prompt = spec + 動態拼接       user prompt = reviewer 回饋 + 人類插話
記憶靠 reviewer_memory.md 檔案      記憶靠 session context + progress.md
被 curator 重置不影響               被 curator 重置 = 換新 session
```

---

### loop.sh 對應的原始碼位置

| 組裝步驟 | loop.sh 行號 | 函數 |
|----------|-------------|------|
| Reviewer system prompt 載入 | L71 | `TEMPLATE_PROMPT=$(cat "$PROMPT_TEMPLATE")` |
| Reviewer stdin 組裝 | L245-264 | `run_reviewer()` 內的 `cat > "$prompt_file"` |
| Reviewer human section 注入 | L193-228 | `run_reviewer()` 內的 human_msg_file 讀取 |
| Reviewer memory 注入 | L230-243 | `run_reviewer()` 內的 reviewer_mem_file 讀取 |
| Reviewer 呼叫 | L267-279 | `claude --print --append-system-prompt ... -` |
| Dev prompt 組裝 | L433-461 | Step C 的 `DEV_PROMPT_FILE` 拼接 |
| Dev human hotline 注入 | L448-456 | Step C 的 human_message 檢查 |
| Dev human_context 注入 | L458-461 | Step C 的 `cat human_context.md` |
| Dev 呼叫（resume） | L291-296 | `run_dev()` 的 resume 分支 |
| Dev 呼叫（新 session） | L298-316 | `run_dev()` 的 新session 分支 |
| Curator 呼叫 | L150-184 | `run_curator()` |
| Reviewer memory 累積 | L411-424 | Step B 後的 `cat >> REVIEWER_MEMORY_FILE` |

## 記憶與 Context 管理

### reviewer_memory.md

- 位置：`PROJECT_DIR/reviewer_memory.md`
- 每輪 reviewer 回覆自動追加
- Reviewer 每輪讀取最近 100 行
- 目的：防止 reviewer 重複提問（鬼打牆）

### progress.md

- 位置：`PROJECT_DIR/progress.md`
- 每 8 輪（CURATOR_INTERVAL）由 Curator 壓縮生成
- Curator 用 sonnet 模型，只保留關鍵資訊（檔案路徑、commit、測試結果）
- 壓縮後重置 dev session，下一輪用 progress.md 接續

### Context rot 對策

Dev 跑久了 context 會滿，品質下降。對策：
1. Curator 每 8 輪壓縮 + 重開 session
2. Claude Code 內建 auto-compact（~190K tokens 觸發）
3. human_context.md 保持精簡

## 停止機制

1. **自然結束**：跑完 max-rounds
2. **雙方同意停止**：Reviewer 和 Dev 都在回覆中輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>` → loop 停止
3. **手動停止**：`kill <PID>`（heartbeat 裡有 PID）
4. **Rate limit**：自動偵測 + 等待重置時間，不會死掉

## 已知限制

1. **Bash for loop 記憶體模型**：loop.sh 跑起來後，整個 for 迴圈已載入記憶體。改 loop.sh 不會影響正在跑的 process，必須 kill 再重啟。
2. **Reviewer 無狀態**：Reviewer 每輪都是新的 `--print` 呼叫，沒有 session。靠 reviewer_memory.md 模擬記憶。
3. **Dev session 路徑依賴**：`--resume` 需要在正確的 `PROJECT_DIR` 下執行，否則找不到 session 檔案。
4. **Reviewer 只能讀**：Reviewer 沒有 Write/Edit 權限，不能直接改程式碼或寫檔案。
5. **human_context.md 在 Auto_Claude 目錄下**：Dev 的 project-dir 是目標專案，無法寫入 Auto_Claude 目錄。所以人類溝通用 `human_message.md`/`human_reply.md`（在 project-dir 下）。

## 成本估算

每一輪大約消耗：
- **Dev**：input ~50K-150K tokens（含 resume context）+ output ~2K-10K tokens
- **Reviewer**：input ~20K-40K tokens（spec + dev output + memory）+ output ~200-500 tokens
- **Curator**（每 8 輪）：input ~5K-15K tokens + output ~1K-3K tokens

50 輪 opus 跑一晚大約 $50-150 USD，視 dev 輸出長度和工具呼叫次數而定。
