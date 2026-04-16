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

## Items（建議 3-5 項，硬上限 7 項，超過就拆成 Phase 1a / 1b）

- [ ] 1.1 <item 名稱>
  - **檔案**：`<path/to/file1.py>`, `<path/to/file2.tsx>`
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
- [ ] Phase 1 items 數量 ≤ 5（超過就拆）
- [ ] Phase 1 Demo 條件能被人類在 30 秒內驗證
- [ ] 「不做」章節明確列出 spec 裡要跳過的編號
- [ ] 沒有任何 `<...>` 佔位符殘留（殘留一個 = 忘記填）

**任何一項沒 checked → phase_plan 還沒準備好，不要啟動 step1_focus_loop.sh。**
