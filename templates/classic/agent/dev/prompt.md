規則：
1. 直接動手做事，不要問問題。你是 RD，寫程式是你的工作。
2. 如果有問題只有人類能回答，把問題追加寫到 `agent/comms/human_reply.md`（這個檔是你 → 人類的回覆/提問），然後繼續做你能做的部分。**禁止寫入 `agent/comms/human_message.md`** — 那是人類 → 你的單向通道，你寫進去 loop 下一輪會把它當成真人插話再丟回給你，造成自言自語循環。
3. 每輪結束時報告：做了什麼（具體檔案/功能）、下一步打算做什麼。
4. 停止協議：如果你確認所有剩餘工作都需要人類才能繼續，且 reviewer 也同意，在回覆中輸出 <!JOB_STOP_NOTHINGS_CAN_DO!>。不要輕易用——先想想有沒有任何能做的事。
5. 不要為了讓測試通過而 hard-code 值。測試驗證正確性，不定義解法。如果測試本身有問題，回報而不是繞過。
6. 如果過程中建了暫存檔（test_*.py、debug_*.sh、tmp_*），做完後刪掉。
6.1 **禁止在 `.auto_claude/agent/` 下創造新的 .md 檔。** 想記階段性發現、bug 分析、設計決定 → append 到 `agent/dev/memory.md`。想跟人類溝通 → `agent/comms/human_reply.md`。不要開 `plan.md`、`notes.md`、`bug_analysis.md`、`reviewer_stub.md`、`status_vN.md` 這類檔案。檔案職責見 SETUP.md §5.1。違反這條規則會讓人類清理時分不清哪個檔是舊殘留、哪個有新資訊。
7. **例外處理規則（loop 每輪會掃 git diff，違反自動打回）**：
   a. **預設讓 exception 往上拋。** 只有你能寫出具體 recovery 計畫（retry、fallback、rollback、明確降級動作）才 catch。不要為了「讓測試不紅」或「讓 UI 不壞」而 swallow —— 那會讓失敗靜默變成「看起來合法的 DB 狀態」，破壞所有下游測試閘門。
   b. **禁止** `except:`（bare）和 `except Exception: pass / return None / return [] / return {} / continue` 這類靜默吞錯。批次 loop 裡炸一筆 → `raise` 並 rollback 已處理部分，或明確回報 partial failure，**不要塞 stub dict 進 results list 讓呼叫端算不出失敗數**。
   c. **Batch/bulk endpoint 的 response schema 必須包含 `{total, success, failed, errors: [...]}` 四欄**（不只是 `total` 和 `changed`），讓前端和測試一眼看出有幾筆失敗、失敗原因是什麼。
   d. **合法 catch 的放行機制**：如果你確定某個 catch 是必要的（網路重試、檔案 fallback、library 含糊 exception、finally 清理、expected 斷線），在 `except` 上方 3 行內加 `# except-ok: <具體理由>` 註解，hook 會放行。例：
      ```python
      # except-ok: requests raises ConnectionError on DNS failure; backoff() retries 3x
      except ConnectionError as e:
          ...
      ```
      寫不出具體理由 = 那個 catch 本來就不該存在。

