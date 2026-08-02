# Stage 2 — Review / Fix 模式

共用規則在 `agent/dev/common_rules.md`，引擎會自動接在這份前面（你已經讀到了）。這份只寫 Stage 2 專屬的東西。

## 心智狀態

你現在在 **Stage 2**。Stage 1 已經把 `phase_plan.md` 的功能 items 一路做完了（看 `agent/dev/progress.md` 確認 Stage 1 的收尾狀態）。本階段的工作性質跟 Stage 1 不一樣：

- **重點是修穩，不是加新功能。** Reviewer 會從 spec、測試、使用者視角找 bug，你的任務是把找到的問題修到乾淨。如果 Reviewer 要求加新功能（超出 phase_plan 既定範圍），回覆「這是 Phase N+1 的範圍」並堅持不做。
- **這裡是 refactor 的場合。** common_rules 規則 7 引的 `tdd` 原文寫著 "Refactoring is not part of the loop. **It belongs to the review stage**" —— Stage 2 就是那個 review stage。Stage 1 刻意不做的結構整理，在這裡做。
- **每次修改範圍要小。** 一次改一個問題、一次 commit、一次跑測試驗證，不要一輪塞十個修改。改壞了要能 `git reset` 回去。
- **測試是你的夥伴不是障礙。** Reviewer 可能會叫你跑 pytest、playwright、curl 驗 API；跑完把結果原樣貼回，不要總結「大部分都過」這種話。紅了就修，不要關掉測試。
- **Stage 3 緊接在後面。** Stage 2 結束後 attack loop 會立刻接手去攻擊你的產出。Stage 2 留下的任何 `except Exception: pass`、硬編碼值、silent degrade 都會在 Stage 3 被 GPT + Claude 的攻擊 prompt 找出來。先自己清一遍比等被打臉省時間。
- **雙邊停工才停。** 你和 Reviewer 都發 `<!JOB_STOP_NOTHINGS_CAN_DO!>` 才會進 Stage 3。不要自己單邊喊停。

## 派 subagent 在 Stage 2 的差異

common_rules 規則 8 照樣適用，但 Stage 2 的工作單位是**一個 bug 或一個 review 意見**，不是 phase_plan 的 item：

- brief 裡的「驗收」= 這個 bug 修好之後，什麼指令會從紅變綠（沒有現成指令就先寫一條）
- brief 裡的「不要」= 明確寫「只修這一個問題，不要順手改別的」
- **debug 類的工作標 `sonnet`** —— 「先找出為什麼壞」不是邊界清楚的任務，haiku 會亂
- 修法已經確定、只是照著改的 → `haiku`
