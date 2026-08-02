# ⚠️ 這是 Phase Plan 模板 — 人類必須填寫才能啟動 Stage 1

**這個檔案的存在本身就是一個提醒：Stage 1 focus loop 不能自動跑，你必須先填這份 phase plan。**
Dev 會整塊讀這個檔案當作工作清單。沒填 = Stage 1 無事可做，會立刻停工。

---

# 怎麼用

1. 複製此檔到專案：`cp templates/agent/phase_plan_template.md <proj>/.auto_claude/agent/phase_plan.md`
2. 打開規範書（spec.txt），人類自己動腦筋切 phase（或用 Claude CLI 互動對話幫你切）
3. **切好後把下面所有 `<...>` 的佔位符和「填寫範例」段落整塊換成真實內容**
4. 確認每個 item 都有具體可執行的驗收指令，才能啟動 step1_focus_loop.sh

---

# Phase 1: <填 phase 名稱，例：核心對話引擎>

**目標**：<一句話說清楚這個 phase 完成後使用者能做什麼。demo-critical 的最小端對端路徑>

**Demo 條件**：<一行 shell 指令 or 一個 URL，能讓人類 30 秒內確認 phase 有動。不是「功能都做完」這種模糊描述>

## 怎麼切 item（人類切 phase 時對照這段）

以下引文出自 Matt Pocock 的 `to-tickets` skill（MIT，https://github.com/mattpocock/skills）。
**這是原文，不是本專案的轉述。**

> <vertical-slice-rules>
>
> - Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer
> - A completed slice is demoable or verifiable on its own
> - Each slice is sized to fit in a single fresh context window
> - Any prefactoring should be done first
>
> </vertical-slice-rules>
>
> Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**第三條對本專案特別重要** —— 「Each slice is sized to fit in a single fresh context window」直接對應 `KNOWN_PITFALLS.md` #9（context rot）。
Curator 每 8 輪壓縮是**事後補救**，item 尺寸限制是**事前預防**。一個 item 大到需要壓縮才做得完，就是切太粗了，拆。

### 大範圍重構的例外（expand–contract）

> **Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch.

**為什麼無人值守特別需要這條**：大範圍 rename 硬塞進一個 item，Dev 會一次改完 → CI 全紅 → 然後**在紅色狀態下亂修好幾輪**，因為它分不清哪個紅是自己造成的。expand → migrate 分批 → contract 讓每一步都能綠，Dev 隨時知道自己有沒有搞砸。

### 模型怎麼標（人類填，Dev 不准自己升級）

Dev 會**派 subagent** 去執行每個 item，「模型」欄決定派哪個。這一欄是**上限** —— Dev 可以往下調（判斷比標的更簡單），但**不准往上調**。

> haiku — 任務邊界清楚時做得又快又對。任務中途出現預期外的分支時會亂。
> sonnet — 能在多個檔案的上下文之間分配注意力。不擅長推論上下文裡沒寫的東西，所以 brief 要寫全。

**照 item 的欄位對照著標，不要憑感覺猜難度**：

| 標 `haiku`（預設） | 標 `sonnet` |
|---|---|
| 「檔案」列 1–2 個，且是**新增**檔案 | 「檔案」列 3 個以上 |
| 照專案裡已有的 pattern 複製一份 | 要先**讀懂既有檔案的行為**才能動它 |
| 「完成條件」是二元的（指令跑得過 / 跑不過） | 「完成條件」講的是行為正確性 |
| 加一支 endpoint、CRUD、格式轉換、補一條驗收測試 | 包含「先找出為什麼壞」（debug） |

**對照不出來就標 haiku**，做失敗再說 —— 試過的失敗比事前的猜測可靠，而且便宜。

> ⚠️ **為什麼這欄要人類填**：讓 Dev 自己選模型會系統性往上飄 —— 派弱了的代價看得見（任務失敗要重來），派強了的代價看不見（只是錢，而且不是它的錢）。這個專案已經因為這個不對稱燒穿過一次 weekly limit。你填 phase_plan 的時候有帳單意識，Dev 在第 14 輪的凌晨三點沒有。

## Items（建議 3-5 項，硬上限 7 項，超過就拆成 Phase 1a / 1b）

- [ ] 1.1 <item 名稱>
  - **檔案**：`<path/to/file1.py>`, `<path/to/file2.tsx>`
  - **Blocked by**：<擋住這項的 item 編號，或「無 — 可立即開始」。不要靠編號順序暗示依賴，明寫出來>
  - **模型**：<haiku | sonnet — 見下面「模型怎麼標」。留空 = haiku>
  - **驗收**：`<能真實跑的指令，例：python -c "from backend.llm.client import chat; print(chat('hi'))">`
  - **完成條件**：<驗收指令預期回傳什麼，例：印出非空字串且不拋例外>
  - **不要**：<明確列出這個 item 不包含什麼，避免 Dev 範圍漂移。例：不做重試、不做 streaming、不做多 provider>

- [ ] 1.2 <item 名稱>
  - **檔案**：`<...>`
  - **驗收**：`<...>`
  - **完成條件**：<...>
  - **不要**：<...>

- [ ] 1.3 <item 名稱>
  - **檔案**：`<...>`
  - **驗收**：`<...>`
  - **完成條件**：<...>
  - **不要**：<...>

## 不做（本 Phase 禁碰的 spec 章節 — 硬禁區）

- <列出 spec 裡 Dev 讀到必須跳過的章節編號 + 一句理由>
- 範例：§4 推播（依賴手機殼，Phase 3 才做）
- 範例：§12 多語系（demo 不需要）

## Phase 1 完成後的狀態

- <具體描述：哪些檔案會存在、哪些指令會能跑、哪些 URL 會有回應>
- <這段用來給 Stage 2 Reviewer 和 Stage 3 Attacker 當作「驗收基線」>

---

# Phase 2: <下一個 phase 名稱>

（同樣結構。Phase 2 的 items 不可以「動」Phase 1 的 schema / API / 核心函數行為 — 只能 append 新東西。如果要動 Phase 1，代表原本的 phase 邊界畫錯了，重切。）

...

---

# 填寫檢查清單（人類對著這個清單檢查你自己的 phase_plan）

- [ ] 每個 item 都有具體檔案路徑（不是「大概在 backend/」）
- [ ] 每個 item 都有一條能貼到 terminal 直接跑的驗收指令
- [ ] 每個 item 都有明確的「不要」欄位擋 scope creep
- [ ] 每個 item 都明寫 **Blocked by**（沒有依賴就寫「無」，不要留空讓 Dev 自己猜）
- [ ] 每個 item 都標了 **模型**（對照上面那張表標，對照不出來就 haiku）
- [ ] 每個 item 都是 **vertical slice** — 切穿 schema / API / UI / test 的完整窄路，不是「只做 backend 那層」
- [ ] 每個 item 完成後**單獨可 demo 或可驗證**（驗收指令跑得過就算）
- [ ] 每個 item 都**塞得進一個全新的 context window**（大到需要 Curator 壓縮才做得完 = 切太粗，拆）
- [ ] 有大範圍重構的話，已經拆成 expand → migrate 分批 → contract 三段，不是一個 item 硬幹
- [ ] Phase 1 items 數量 ≤ 5（超過就拆）
- [ ] Phase 1 Demo 條件能被人類在 30 秒內驗證
- [ ] 「不做」章節明確列出 spec 裡要跳過的編號
- [ ] 沒有任何 `<...>` 佔位符殘留（殘留一個 = 忘記填）

**任何一項沒 checked → phase_plan 還沒準備好，不要啟動 step1_focus_loop.sh。**
