# 3-Stage Pipeline 說明書（實驗性）

> **狀態：EXPERIMENTAL — 流程尚未穩定，暫不整合進 `ARCHITECTURE.md`。**
> 此文件獨立存在。等實際在專案上跑過幾輪、行為穩定後，再把有用的部分併入主架構文件。
> 在此之前，把這套當成「候選流程」用，不要預期它的行為跟既有 `loop.sh` 一樣可靠。

---

## 為什麼要有三階段

既有的 `loop.sh`（Dev ↔ Reviewer）在長 spec / 大型 phase 上有兩個已觀察到的退化模式：

1. **Reviewer 打斷 Dev 的建造心流** — Dev 還沒做完一個 item 就被 Reviewer 拉去解釋設計決定、修 style、補測試，結果 phase 完成度比單純 Dev 獨立衝還慢。
2. **Reviewer 視角太窄** — Dev ↔ Reviewer 是共同語言、共同偏見，兩邊很容易收斂到「都覺得沒問題」的狀態，真正的 bug 要外部視角才找得到。

三階段把這些需求**按時序拆開**：先讓 Dev 專心建（Stage 1 Focus），建完再讓 Reviewer 挑毛病（Stage 2 Review），最後讓完全不同的攻擊性 prompt（搭配不同模型）去找 edge case（Stage 3 Attack）。

| Stage | Loop 類型 | Dev 對手 | 停止條件 | 下一階段 |
|---|---|---|---|---|
| 1 Focus | `step1_focus_loop.sh` | dumb bash Trigger（0 tokens） | Dev 單邊喊停 | 自動接 Stage 2（`--chain-stage2`） |
| 2 Review | `step2_rev_loop.sh` → `loop.sh` | AI Reviewer（opus） | Dev + Reviewer 雙邊停工 | 自動接 Stage 3（`--chain-stage3`） |
| 3 Attack | `attack_loop.sh` | GPT × 3 → Claude × 3 → cross-verify × 3 | 跑完 9 輪 | 停下等人類驗收，不自動回圈 |

---

## 前置檔案（人類必填）

跑 Stage 1 之前你必須在 `<proj>/.auto_claude/agent/` 下準備好：

```
.auto_claude/agent/
├── spec.txt                  ← 原始規範書（跟既有 loop.sh 一樣）
├── context.md                ← 專案背景、API key、commit 規則
├── phase_plan.md             ← ⚠️ 新增：人類手動切好的 phase 計畫
├── dev/
│   ├── stage1_prompt.md      ← 從 templates 複製，可自訂
│   └── stage2_prompt.md      ← 從 templates 複製，可自訂
├── reviewer/
│   └── prompt.md             ← Stage 2 用（既有）
├── curator/
│   └── prompt.md             ← Stage 1 結束時壓縮用（既有）
├── attacker/
│   └── prompt.md             ← Stage 3 用（可選，沒有就用 engine 內建）
└── comms/
    ├── human_message.md      ← 人類 → AI
    └── human_reply.md        ← AI → 人類
```

### phase_plan.md 是最關鍵的前置

`step1_focus_loop.sh` 啟動時會檢查 `phase_plan.md`：

1. **存在檢查** — 沒有這個檔案直接 refuse
2. **模板殘留檢查** — 如果檔案還有 `⚠️ 這是 Phase Plan 模板` 這行，refuse
3. **佔位符檢查** — 如果檔案還有 `<...>` 格式的佔位符，會互動式警告並問你要不要繼續

**要怎麼產出 phase_plan.md**：

- 不要用 AI 自動產出。phase 切分是戰略決定，人類要自己對 spec 負責。
- 推薦做法：打開一個互動式 Claude CLI，讓 Claude 幫你讀 spec 並**提議** phase 切分，人類來回討論修到滿意，**手動**寫進 `phase_plan.md`。
- 參考格式：`templates/agent/phase_plan_template.md`，內含填寫 checklist 和佔位符。
- 每個 phase 的 item 數量建議 3-5 個，硬上限 7 個。超過就拆成 1a / 1b。
- 每個 item 必須有「能貼到 terminal 跑的驗收指令」，不能只寫「完成 X 功能」這種模糊描述。

---

## 三種跑法

### 跑法 A：單一 stage 手動控制（debug / 開發流程自己時用這個）

```bash
# 只跑 Stage 1
engine/step1_focus_loop.sh \
    --project-dir /path/to/proj \
    --initial-prompt "讀 phase_plan.md 開始 Phase 1" \
    --max-rounds 40

# 只跑 Stage 2
engine/step2_rev_loop.sh \
    --project-dir /path/to/proj \
    --initial-prompt "讀 dev/progress.md 然後修 bug"

# 只跑 Stage 3
engine/attack_loop.sh \
    --project-dir /path/to/proj
```

Stage 1 結束時會跑一次 Curator 產 `dev/progress.md`，Stage 2 啟動時會自動讀到。
Stage 2 結束時會 `git add -A && git commit`，給 Stage 3 一個乾淨 SHA 鎖。

### 跑法 B：兩段接力（stage1 + stage2，先不攻擊）

```bash
engine/step1_focus_loop.sh \
    --project-dir /path/to/proj \
    --chain-stage2 \
    --initial-prompt "讀 phase_plan.md 開始 Phase 1"
```

Stage 1 Dev 喊停 → 自動 Curator → 自動 `exec` step2 → Stage 2 Dev↔Reviewer 跑完停。

### 跑法 C：完整三段（推薦第一次驗收用這個）

```bash
engine/step1_focus_loop.sh \
    --project-dir /path/to/proj \
    --chain-stage3 \
    --initial-prompt "讀 phase_plan.md 開始 Phase 1"
```

`--chain-stage3` 隱含 `--chain-stage2`，會把三段全串起來：

```
Stage 1 (Dev ↔ Trigger)
  → Dev 喊停
  → Curator 壓縮 → progress.md
  → exec step2_rev_loop.sh --chain-stage3
    → loop.sh (Dev ↔ Reviewer)
      → 雙邊停工 or max rounds
    → git add -A && git commit  (Stage 3 鎖 SHA 前的自動 commit)
    → exec attack_loop.sh --skip-dirty-check
      → GPT × 3 → Claude × 3 → cross-verify × 3
      → 產出 attack_report.md
      → 停下，等人類驗收（不自動回 Stage 2）
```

---

## Stage 1 細節：Dev ↔ dumb Trigger

### Trigger 是什麼

一個 bash 函數。每輪從 7 個 canned 字串（「繼續。」「好，下一項。」「OK。下一步。」…）裡挑一個印出去。**沒有 LLM 呼叫，零 tokens，零技術判斷**。

這個設計是刻意的：

- 我們**不要**另一顆 LLM 指導 opus 該做什麼
- 我們**不要**有任何反饋機制能打斷 Dev 的建造心流
- Trigger 只是個心跳訊號，告訴 Dev「繼續」

### Dev 知道 Trigger 是假的

`stage1_prompt.md` 第一段會明確告訴 Dev：

> 另一個 AI 不是 Reviewer，是 dumb NLP bot。它每輪只會回類似「好」「繼續」「下一項」的固定字串，完全沒有技術判斷能力⋯⋯所以：它說的話你不用當真。

這段誠實說明很重要。如果 Dev 誤以為對面是真 reviewer，它會嘗試「說服」對方、解釋設計、等回饋 — 這些都是我們不要的行為。

### 單邊停工

Stage 1 只有 Dev 能發 `<!JOB_STOP_NOTHINGS_CAN_DO!>` 停止。Trigger 沒有這能力。

Dev 停止的觸發條件（寫在 `stage1_prompt.md`）：

1. `phase_plan.md` 所有 items 都勾選 `[x]`
2. 剩下的 items 都 blocked 且人類必須介入才能解

### 輸出到 Stage 2 的交接

Stage 1 結束時跑 Curator（sonnet），壓縮整個 session 的 tool output，寫進 `agent/dev/progress.md`。格式：

```markdown
# Stage 1 結束進度（Curator 壓縮於 ...）

<Curator 輸出的壓縮摘要>

---

## Phase Plan 當前勾選狀態

<phase_plan.md 原文>
```

Stage 2 Dev 啟動時會讀到這個檔案當作 Round 1 的 initial context。

---

## Stage 2 細節：薄 wrapper + auto-commit + chain

Stage 2 本質上就是 `loop.sh`。`step2_rev_loop.sh` 做三件事：

1. **Forward args**：把 `--project-dir`、`--initial-prompt`、`--model-dev` 等全部傳給 `loop.sh`
2. **Auto-commit**：`loop.sh` 退出後，如果 working tree 有未 commit 變動，自動 `git add -A && git commit -m "stage2: auto-commit at loop exit"`。這是為了給 Stage 3 一個乾淨 SHA 鎖。可用 `--no-auto-commit` 關掉。
3. **Chain**：如果有 `--chain-stage3`，auto-commit 完就 `exec attack_loop.sh`

`loop.sh` 本身的行為沒變動（除了從 `dev/prompt.md` 改找 `dev/stage2_prompt.md`，找不到會 fallback 到舊路徑）。

---

## Stage 3 細節：locked attack loop

細節看 `engine/attack_loop.sh --help` 和這個檔案的早期 commit message。重點：

- 啟動第一件事 `git rev-parse HEAD` 鎖 SHA，寫 `.auto_claude/logs/attack_locked.sha`
- 每輪 attacker 跑完偵測 `git status --porcelain`，有變動就 `git reset --hard` + 記 violation
- 三階段：GPT × 3（codex exec -s read-only）→ Claude × 3（--disallowed-tools Write Edit）→ cross-verify × 3
- Stage 3 的 Claude attacker 有 `mcp__playwright__* mcp__chrome__*` 權限（可以驅動真瀏覽器找 UI bug）
- 產出 `<timestamp>_attack_report.md` 分 CONFIRMED / DISPUTED / HALLUCINATED 三段
- **Stage 3 跑完停下，不自動 chain 回 Stage 2**。人類去讀報告，決定哪些 bug 要修，再手動起一輪 Stage 2 解掉

---

## 已知限制 / 不穩定點（所以暫不整合 ARCHITECTURE.md）

以下行為還沒在真實專案驗證過，第一次跑的時候特別注意：

1. **Stage 1 的 Dev 可能不理會 single-side stop 規則**。Dev 習慣是雙邊停工，stage1_prompt 只有說明文字叫它單邊停。實際跑如果 Dev 一直不停，用 `--max-rounds` 當硬上限。
2. **Curator 壓縮可能不夠乾淨**。Stage 1 結束時 context 可能已經很大，Curator 的 sonnet 壓縮結果不一定能涵蓋 Stage 2 需要知道的所有 technical debt。第一次跑完檢查一下 `progress.md` 裡面有沒有該有的資訊。
3. **Auto-commit 可能 commit 太多不相關的東西**。Stage 2 結束時 `git add -A` 會把所有 untracked 也 commit 進去，包括暫存檔、測試輸出、log。改善方向是用 `.gitignore` 把這些擋掉。暫時接受這個行為。
4. **Stage 3 attack_loop 跟 Stage 2 loop.sh 的 dev server 管理會互踩**。`loop.sh` 會在 port 上跑 dev server，Stage 3 的 Claude attacker 用 Playwright 驅動瀏覽器時會打這個 port。如果 Stage 2 的 dev server 沒正常退出，Stage 3 可能測不到東西。
5. **PID lock 衝突**。`loop.sh` 用 `/tmp/auto_claude_loop.pid` 做全域鎖，step1 沒做 lock。理論上如果你同時跑 step1 和 step2（或兩個 step1）會互相踩到。單一專案單一流水線使用就沒問題。
6. **human_message.md 的中斷時機**。只有 Stage 1 和 Stage 2 會在 round 開始時讀 `human_message.md`。Stage 3 跑起來後人類插話就沒用了，要等 Stage 3 全部 9 輪跑完。如果 Stage 3 發散了想中斷，只能 `kill` 主 PID。
7. **Chain 失敗的錯誤路徑**。`step1 --chain-stage3` 時是用 `exec` 串起來的，中間任何一段 crash 後面就不跑。目前沒有自動重試機制。

---

## 跟舊流程的關係

- **既有 `loop.sh` 沒有被取代**。你還是可以直接跑 `engine/loop.sh --project-dir ...` 走純 Dev ↔ Reviewer 流程。`step2_rev_loop.sh` 只是個 wrapper。
- **既有 `.auto_claude/agent/dev/prompt.md` 還會被讀**。loop.sh 優先找 `stage2_prompt.md`，找不到再 fallback 回舊的 `prompt.md`。所以現有 motc / baphiq 專案不會壞。
- **三段流程是加法**，不是減法。你如果覺得某個專案不適合三段流程（例如修 bug 不是做 phase），直接用 `loop.sh` 就好。

---

## Troubleshooting

| 症狀 | 原因 | 解法 |
|---|---|---|
| step1 啟動後馬上 exit 說 "phase_plan.md not found" | 你還沒填 phase 計畫 | `cp templates/agent/phase_plan_template.md <proj>/.auto_claude/agent/phase_plan.md` 然後手動填 |
| step1 啟動後說 "still has `<...>` placeholders" | phase_plan 沒填完 | 回去填，確認沒有 `<...>` 殘留 |
| Stage 1 跑到 max_rounds 還沒停 | Dev 不 honor 單邊停工 | 檢查 `stage1_prompt.md` 是否完整、phase_plan 的 items 是否真的都勾完了。手動 `kill` 主 PID |
| Stage 2 → Stage 3 切換時 attack_loop 抱怨 dirty state | auto-commit 失敗了（pre-commit hook？） | 看 step2 的 log，修 hook 問題或手動 commit 再跑 `attack_loop.sh` |
| Stage 3 GPT 那段一直 exit 非 0 | codex 沒登入 or `OPENAI_API_KEY` 沒設 | `codex login` 或 `export OPENAI_API_KEY=...` |
| Stage 3 Claude 攻擊輪 git violation 一直觸發 | Claude 真的在改檔案，或者 baseline dirty 判斷錯 | 看 `violations/` 下的違規紀錄，確認是哪個情境 |

---

## 下一步（等流程穩定後）

等實際在 2-3 個專案跑過、行為穩定後，以下內容會併入 `ARCHITECTURE.md`：

- Stage 1 / 2 / 3 在「三層抓 bug 路線」裡的定位
- Phase plan 切分方法論（跟現有 SETUP.md §5.5 的合併）
- Curator 觸發時機（週期 vs stage 邊界）的權衡
- 單邊停工 vs 雙邊停工的決策樹

目前這些還在實驗階段，先讓這份說明書獨立存在。
