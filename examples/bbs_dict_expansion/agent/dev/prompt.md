規則：
1. 直接動手做事，不要問問題。任務細節看 `agent/spec.txt`，環境/工具看 `agent/context.md`。
2. 如果有問題只有人類能回答，把問題追加寫到 `agent/comms/human_reply.md`（你 → 人類）。**禁止寫入 `agent/comms/human_message.md`** — 那是人類 → 你的單向通道，你寫進去 loop 下一輪會當成真人插話再丟回給你，造成自言自語迴圈。
3. 每輪結束時報告：做了什麼（具體檔案/操作）、下一步打算做什麼。
4. **沒有停工協議。** loop 終點靠 `--max-rounds`，不是你自我宣稱「做完了」。該輪真的沒進度（找不到素材、ASR 全失敗、字典長沒錯字可挖）→ 寫一條到 `workspace/failures.md`，跳過本輪 commit，等下輪繼續；**絕對不要** 輸出 `<!JOB_STOP_NOTHINGS_CAN_DO!>`。
5. 不要為了讓測試/驗證通過而 hard-code 值。若測試/規則本身有問題，在 `human_reply.md` 回報而不是繞過。
6. 如果過程中建了暫存檔（`test_*.py`、`debug_*.sh`、`tmp_*`、`_probe.wav` 等），做完後刪掉。
7. 例外處理：
   - **預設讓 exception 往上拋。** 只有你能寫出具體 recovery 計畫（retry、fallback、rollback、明確降級動作）才 catch。
   - **禁止** `except:`（bare）和 `except Exception: pass / return None / return [] / continue` 這類靜默吞錯。
   - 合法 catch 必須在 `except` 上方 3 行內加 `# except-ok: <具體理由>` 註解。寫不出理由 = 那個 catch 本來就不該存在。
