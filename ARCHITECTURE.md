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
  ├── 捕捉 git HEAD SHA → _round_start_sha（供 post-dev hook 用）
  │
  ├── Step A: 取得 dev 輸出
  │     ├── Round 1: 跑 initial-prompt 或 extract_session.py
  │     └── Round 2+: 用上一輪 Step C 的輸出（不重複 log）
  │
  ├── Guards
  │     ├── Rate limit → 自動等待重置時間
  │     └── 空輸出（<10 chars）→ 等 30s 重試
  │
  ├── 🛡️ Post-Dev hook：check_except_patterns.py
  │     ├── git diff _round_start_sha..HEAD -- '*.py'
  │     ├── 抓 bare except: / except Exception: pass|return None|[]|{}
  │     ├── 檢查 # except-ok: 註解放行
  │     └── 有違規 → 寫 logs/except_violations_latest.txt
  │                → build_dev_prompt 下一輪會 prepend 進 Dev prompt
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

## 三層抓 bug 機制

Auto_Claude 用**三種不同性質**的方式抓開發過程中的錯誤。看懂這三層的分工，才能判斷「某個類型的 bug 該靠哪一層擋」、「為什麼某些錯會溜到使用者面前」。

```
Layer 1：AI 主觀判斷          Layer 2：機率性失敗            Layer 3：死代碼閘門
─────────────────            ─────────────────              ─────────────────
Reviewer 指派 probe           Dev 習慣性 try/except         git diff regex 掃描
Dev 扮演使用者走查             Dev 提早宣告「都做完了」         .loop.pid 檔案鎖
Reviewer catch scope creep   Dev 挑測試重跑而非全跑           Rate limit 偵測 + 自動等待
Curator 壓縮判斷              Dev 寫 stub dict 假裝成功       空輸出 retry
                             memory 蓋過新 spec              check_except_patterns.py（新）
                                                           settings.local.json deny 清單

抓得到「語意、UX、設計」      造成「靜默降級、殘渣累積」       抓得到「模式明確的錯」
抓不到「模式明確的錯」         抓不到「這些自己會發生」         抓不到「語意、意圖」
```

### Layer 1：靠 AI 判斷（做得很好的事）

這些工作**需要理解語意、使用情境、業務邏輯**，死代碼做不來，人類做又太慢。AI 在這層是真正的主力。

| 能力 | 實例（來自 perma_ai 41 輪實測） | 為什麼 AI 適合 |
|------|--------|---------|
| **Reviewer 指派 probe 測試** | Round 6、13、27、31、33、39 共 6 輪「去戳 X 會怎樣」的探索性測試，抓到 Playwright smoke 全綠但資料一致性有 bug（R31 silent row loss） | 需要問「如果 Y 呢？」這種開放式假設 |
| **Dev 扮演使用者走查** | Round 6 扮演心理系老師，跑一整輪真 UX（改 prompt → compare → 存 fixture → replay → 看 diff → deploy），一次找到 14 個痛點（header 寫死 Phase 1、compare 沒 diff 著色、draft 沒版本化⋯） | 需要「我是使用者我會怎麼想」的角色帶入 |
| **Reviewer 擋 scope creep** | Round 12 Dev 想在 fixture modal 加 tag/category，Reviewer 擋下「最小化」；Round 26 Dev 想自決 auth 範圍，Reviewer 要求「先問人類」 | 需要判斷「這個改動跟本次任務是否相關」 |
| **Feature 誤解抓取** | Round 7 Reviewer 發現 Dev 對「deploy 語意」理解錯（名字騙人：只寫 DB 不實際部署） | 需要語意理解 |
| **Curator 壓縮判斷** | 每 N 輪 sonnet 決定什麼留、什麼丟（commit hash 留、客套話丟、已完成的「下一步」丟） | 需要判斷「這資訊未來還有用嗎」 |
| **Dev 跨模組重構** | 新增一個 diff UI 時 Dev 自動把 backend API、DB schema、前端 handler、smoke 測試一起改 | 需要理解 intent 和跨檔案依賴 |

**這層的成功關鍵**：Reviewer 有足夠的「反對權」(veto)，且 loop 允許它打回 Dev 重做。如果 Reviewer 只是蓋章，這層就垮了。

**這層的失敗模式**：如果 AI 同時扮 Dev 和 Reviewer 又在同一個 session，沒有「來自外部的不同意見」，就會自我強化而退化。Auto_Claude 的解法是**每輪 Reviewer 用 `--print` 新開無狀態 session**，強制對 Dev 的輸出做外部視角的審查。

### Layer 2：AI 的機率性失敗（需要 Layer 3 擋）

這些是**AI 訓練資料本身的習慣性偏誤**，靠提醒 Dev「小心」是沒用的，因為它每次都會「忘記」。必須用死代碼物理攔截。

| 失敗模式 | 實例 | 為什麼 AI 不會自己改 |
|---------|------|--------|
| **Try/except 吞錯變成靜默降級** | R31：`_replay_one` 拋 exception → 外層 try 塞 stub dict 進 results → response 回 `total:15, changed:14`，少算的那筆完全看不到 | 訓練資料裡「production robust code」都長這樣，Dev 以為自己在做 defensive programming，實際在做 evidence deletion |
| **提早宣告「都做完了」** | 進度 compression 寫「12/12 全數完成」時，Dev 第一輪就會回「沒什麼可做」然後停工，即使有新 human_message 也會被既有的「已完成」氣氛蓋掉 | Dev 信任 progress.md > 新指令，因為 session memory 被重置後 progress.md 是唯一可信錨點 |
| **挑測試重跑而非全跑** | 早期幾輪 Dev 只跑「鄰近 smoke」而非全套，直到一次 server 掛住才改成每輪跑全套 | 效能壓力下會自動退化，除非 loop 強制 |
| **Role/檔案誤用** | R9：Dev 把「給人類的問題」寫進 `human_message.md`（人類 → AI 單向通道），loop 下一輪把它當真人插話注入回去，造成自言自語 | 看到多個類似檔名時憑感覺挑一個，沒有強規則就會錯 |
| **舊 spec 殘渣不清** | 新 spec 抽換後，Dev 不會主動 `DROP TABLE` 或刪除孤兒 endpoint——它的心智模型是「已存在 = 有人要用」，沒有反向推論「沒在 spec 裡 = 該刪」 | 訓練資料裡「刪 production code」的樣本極少 |
| **memory 蓋過新 spec** | Dev 在 `dev_memory.md` 寫過的舊決策，讀起來比每輪重讀 spec 更快；模糊地帶會傾向信 memory | Context 成本考量下，memory 是捷徑 |
| **Reviewer 蓋章而非審查** | Reviewer 偶爾回「ok 繼續」只有 20 字就收工，該輪等於沒審 | 低能量回應比實質回應便宜 |

**這層的 bug 共同特徵**：**每次都不完全一樣**（所以不能寫死 regex）、**AI 會以合理理由辯護**（所以不能靠 Reviewer 講道理）、**只能用「外部強制」擋**。這就是 Layer 3 的職責。

### Layer 3：死代碼閘門（100% deterministic）

這層**完全不用 AI 判斷**，只用 regex、檔案存在性、HTTP status code、整數比較這類**二值結果**。無法被 AI 辯論繞過，也沒有機率性。代價是只能擋「模式明確」的錯，擋不了「語意」的錯。

| 閘門 | 位置 | 擋什麼 | 觸發時行為 |
|------|------|--------|-----------|
| **`.loop.pid` 檔案鎖** | `engine/loop.sh` | 同專案啟兩個 loop | 第二個啟動時檢查 pid 檔，存在就拒啟 |
| **Rate limit regex** | `engine/loop.sh` guards | Dev/Reviewer 輸出含 rate limit 字樣 | 解析重置時間，sleep 到重置 +60s |
| **空輸出偵測** | `engine/loop.sh` guards | Dev 回傳 <10 chars（cache race） | `sleep 5` 後 round-- 重試 |
| **Heartbeat JSON** | `engine/loop.sh` | 不是擋，是監控 | 每輪覆寫 `{pid, round, max, time, log, sessions}` 讓外部工具判斷 loop 是否還活 |
| **Curator 固定週期** | `engine/loop.sh` | Dev context rot | 每 N 輪強制壓縮 + 換 session，不管 Dev 覺得需不需要 |
| **`check_except_patterns.py`（新）** | `engine/check_except_patterns.py` + `loop.sh` build_dev_prompt | Layer 2 的 try/except 吞錯 | 掃 git diff 抓 `except:`、`except Exception: pass/return None/[]/{}` 等 pattern；有違規把報告塞進下一輪 Dev prompt 強制先修 |
| **`# except-ok:` 放行機制** | 同上 | Layer 3 的誤傷（合法 catch） | Dev 在 `except` 上方 3 行內加 `# except-ok: <具體理由>`，regex 放行。寫不出具體理由 = 該 catch 本來就不該存在 |
| **Settings deny 清單** | `.claude/settings.local.json` | 破壞性指令 | `rm -rf /`、`sudo *`、`git push --force`、`git reset --hard` 一律拒絕 |
| **Playwright DOM 斷言** | 專案的 `smoke_*.py` | 前端元素存在、可點、資料正確 | selector 找不到或 assertion fail 就 exit 非 0 |
| **HTTP status 檢查** | 同上 | API 5xx | smoke 裡 `assert resp.status_code < 500` |

**新增 except hook 的運作細節：**

```
Round N:
  ├── 捕捉 HEAD SHA → _round_start_sha
  ├── Step A: Dev 跑，寫程式、commit
  ├── check_except_patterns.py --since _round_start_sha
  │     ├── git diff HEAD~1..HEAD --unified=5 -- '*.py'
  │     ├── parse +行，套 regex 黑名單
  │     ├── 檢查 except 上方 3 行是否有 `# except-ok:`
  │     └── 有違規 → 寫 logs/except_violations_latest.txt
  ├── Step B: Reviewer 審查
  └── Step C: build_dev_prompt
        └── 發現 except_violations_latest.txt → prepend 到 Dev prompt
              → Dev 下一輪第一件事就是看到違規列表被迫先修
```

**為什麼這層重要：** Layer 1 的 AI 判斷是**非同質且有成本**的——Reviewer 可能這輪心情好抓到，下輪心情不好就漏。Layer 3 是**同質且零成本**的——每輪一定跑、一定用同一套 regex、結果一定可重現。兩層互補：Layer 1 抓「這個設計不對」，Layer 3 抓「這行程式碼有明確反模式」。

### 三層對照表：哪種 bug 該靠哪層擋

| Bug 類型 | 最有效的層 | 為什麼 |
|---------|------|------|
| Syntax error、import error | Layer 3（smoke 啟動失敗即可見） | 模式明確 |
| Feature 誤解規格 | Layer 1（Reviewer 讀 spec 比對 Dev 輸出） | 需要語意理解 |
| UX 卡點 / 使用不順 | Layer 1（Dev 扮演使用者走查） | 需要情境帶入 |
| 邏輯 bug（功能做錯） | Layer 1 + Layer 3（probe 找 → smoke 鎖） | AI 探索 + 死碼防退化 |
| Silent swallow（R31 類） | **Layer 3**（新 except hook） | Layer 2 自己會製造它，Layer 1 很難看出「少了什麼」 |
| Regression（舊功能壞掉） | Layer 3（全套 smoke 每輪跑） | 模式明確 |
| Scope creep | Layer 1（Reviewer 判斷相關性） | 需要判斷意圖 |
| 舊 spec 殘渣 / DB 欄位 bloat | **目前沒人擋**（Layer 2 問題，Layer 3 做不到，Layer 1 需要人類 triage） | 需要 spec 抽換後的 alignment audit round |
| Rate limit | Layer 3（regex 偵測 + 自動等待） | 模式明確 |
| Context rot（Dev 失憶） | Layer 3（Curator 固定週期） | 不能等 Dev 自己發現 |

### 解釋給其他人時可以這樣說

> Auto_Claude 把「找 bug」這件事拆成三層：
> **第一層靠 AI 判斷**——Reviewer 和 Dev 互相審，Dev 會扮演使用者走查，抓語意和 UX 問題。這層能發現「這個功能其實心理系用不順」這種只有真人會發現的事。
>
> **第二層是 AI 的機率性失敗**——AI 會習慣性地寫 `try/except: pass` 把錯誤藏起來、會提早說「都做完了」、會在 spec 換版後留下一堆殘渣。講道理沒用，因為它下一輪又會忘記。
>
> **第三層是死代碼閘門**——用 regex、檔案鎖、HTTP status code 這種 100% 確定的方式擋第二層的毛病。我們有個 `check_except_patterns.py` 每輪掃 git diff，看到 Dev 新加的 `except Exception: pass` 就打回去強制修，除非它寫 `# except-ok: <具體理由>` 證明這個 catch 是必要的。
>
> 三層互補：Layer 1 管語意、Layer 3 管模式、Layer 2 是問題本身。Layer 3 越完整，Layer 1 越能專心做語意判斷不用一直盯 Dev 的手。

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

50 輪 opus 跑一晚約 $50-150 USD，視 dev 輸出長度和工具呼叫次數而定。然而實際上是由max plan 支付claude -print

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
