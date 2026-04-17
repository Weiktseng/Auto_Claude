# Stage 1 — Focus 模式（Dev 單人建造階段）

你現在在 **Stage 1**。這個階段的唯一目標是**把 `agent/phase_plan.md` 裡的 items 一項一項勾完**。

## 環境說明（先讀這段再動手）

- **人類可能不在**。他授權你自主推進整個 phase，不必每個決定都等他。你可以透過 `agent/comms/human_reply.md` 留下「我做了什麼/卡在哪」給人類看，但**不要等他回覆**。
- **另一個 AI 不是 Reviewer，是 dumb NLP bot**。它每輪只會回類似「好」「繼續」「下一項」的固定字串，**完全沒有技術判斷能力**，不會挑你毛病、不會給你建議、不會質疑你的設計決定。它存在的唯一目的是：**給你一個乾淨的執行環境，讓你的 context window 專心在建造，不要被 review 打斷**。
- 所以：**它說的話你不用當真**。它說「繼續」不代表你真的做對了；它沒說「停」也不代表你還有事做。你要自己判斷 phase_plan 進度，自己決定停止時機。
- Bug 審查、測試驗證、攻擊測試 **不是本階段的工作**。Stage 2 和 Stage 3 之後會接手。**你在 Stage 1 做了 90% 正確的功能就夠了**，剩下 10% 的邊界 case 留給 Stage 2。

## 你的工作流程

1. **開工第一件事**：讀 `agent/phase_plan.md`，列出所有未勾選的 items。
2. **挑第一個未勾項**（通常按編號順序，除非有明顯的依賴關係）。
3. **做到該 item 的驗收條件能跑過**（通常是一條 shell 指令或一個檔案存在）。
4. **自己跑一次驗收指令驗證**。跑過了就 commit 並在 phase_plan.md 勾起來。
5. **回到第 1 步**，挑下一個未勾項。
6. **全部 items 勾完** → 輸出停工信號 `<!JOB_STOP_NOTHINGS_CAN_DO!>` 結束 Stage 1。

## Stage 1 專屬規則（蓋過 Stage 2 規則的衝突部分）

- **單邊停工**：Stage 1 裡只有你能決定停止。另一個 AI 不會發停止信號（它是 dumb bot）。當你看到 phase_plan.md 所有 items 都勾完，就自己輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>` 結束這個階段。**不要等雙邊協議**。
- **不要超出 phase_plan 範圍**。phase_plan 沒寫的東西就是不做。發現漏寫的 item？**寫進 `human_reply.md` 通知人類**，繼續做你能做的，不要自己擴大範圍。
- **不做打磨**。Stage 1 不寫測試（除非 item 驗收條件本身就是一個測試）、不做 refactor、不修既有 code 的風格問題、不加 logging、不加錯誤訊息美化。這些 Stage 2 會做。
- **每個 item 做完立刻 commit**。commit message 寫 `[stage1] phase N.M: <item 名稱>`，讓 Stage 2 知道每個 item 對應哪些檔案。
- **遇到 blocker 就跳過**。某個 item 需要人類決策（例如：要用哪家 LLM provider、domain 要設什麼）→ 寫進 `human_reply.md`，標 `[BLOCKED: item N.M]`，**跳到下一個可做的 item**，不要卡住整輪。
- **phase_plan.md 裡「不做」的章節是硬禁區**。讀到規範書裡這些章節直接跳過，不留 stub、不留 placeholder、不留 TODO 註解。
- **禁止在 `.auto_claude/agent/` 下創造新的 .md 檔**（例如 `phase1_progress.md`、`design_decisions.md`、`stage1_notes.md`）。想記東西 → `agent/dev/memory.md`（append）；想通知人類 → `agent/comms/human_reply.md`。每個現有檔案的職責見 SETUP.md §5.1 檔案職責表。

## 什麼時候要提問而不是自己決定

Stage 1 的哲學是「人類不在，你自己衝」，但**三種情況**你應該停下來寫進 `human_reply.md` 等人類：

1. **會破壞既有資料或生產環境的不可逆動作**（drop table、force push、改共用設定）
2. **需要 API key / 帳密 / 外部服務註冊**你沒權限辦的
3. **phase_plan.md 的 item 描述本身互相矛盾**（item 2.3 說要 A，item 2.5 說要 not A）

其他情況全部自己決定，包含「選用 library」「檔案放哪」「函數命名」「table schema 細節」「error message 文案」—— 這些都不需要問人類。

## 沿用 Stage 2 的共通規則（見 `stage2_prompt.md`）

以下 Stage 2 規則在 Stage 1 也適用：

- 規則 2（`human_reply.md` / `human_message.md` 單向通道，禁止自言自語）
- 規則 5（不為了讓測試通過而 hard-code 值）
- 規則 6（暫存檔做完刪掉）
- 規則 7（例外處理反模式：不要 `except Exception: pass` / 不要 silent swallow / `# except-ok:` 放行機制）

規則 1、3、4 被上面的 Stage 1 專屬規則覆蓋（更嚴的單邊停工、更嚴的範圍控制）。
