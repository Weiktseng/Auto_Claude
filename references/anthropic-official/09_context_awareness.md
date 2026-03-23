# Context Awareness — Context Window 管理

來源：Claude 4 Best Practices — Context awareness and multi-window workflows
適用：Curator 策略 / loop.sh 設計

## 背景

Claude 4.6/4.5 能追蹤自己剩餘的 context window 大小。
這讓它可以在接近極限時主動保存進度。

## 官方片段（防止 AI 提前停工）

```text
Your context window will be automatically compacted as it approaches its limit, allowing
you to continue working indefinitely from where you left off. Therefore, do not stop
tasks early due to token budget concerns. As you approach your token budget limit, save
your current progress and state to memory before the context window refreshes. Always be
as persistent and autonomous as possible and complete tasks fully, even if the end of
your budget is approaching. Never artificially stop any task early regardless of the
context remaining.
```

## 官方建議（多 context window 工作流）

1. **第一個 window 用不同 prompt**：先建立框架（寫測試、建 setup script），
   後續 window 用 todo-list 迭代

2. **讓 model 寫結構化測試格式**：如 tests.json，方便長期追蹤。
   提醒：「不可刪除或修改測試，這可能導致功能缺失」

3. **建立生活品質工具**：鼓勵 Claude 建 init.sh 來啟動 server、跑測試、linter。
   避免每次新 window 重複做同樣的事

4. **Fresh start vs compaction**：有時全新 window 比 compaction 更好。
   Claude 最新模型很擅長從本地檔案系統重新發現狀態。指示它：
   - "Call pwd; you can only read and write files in this directory."
   - "Review progress.txt, tests.json, and the git logs."
   - "Manually run through a fundamental integration test before moving on."

5. **提供驗證工具**：長任務需要 Claude 自己驗證正確性。
   Playwright MCP server 或 computer use 可用於測試 UI。

6. **鼓勵用完 context**：
   ```text
   This is a very long task, so it may be beneficial to plan out your work clearly.
   It's encouraged to spend your entire output context working on the task - just make
   sure you don't run out of context with significant uncommitted work. Continue working
   systematically until you have completed this task.
   ```

## Auto_Claude 備註

這跟我們的 Curator 機制直接對應：
- 第 1 點 = 我們的 initial-prompt 參數
- 第 2 點 = todo.md
- 第 3 點 = smoke_test.sh
- 第 4 點 = Curator 壓縮 + session 重置

Anthropic 官方建議的「fresh start > compaction」驗證了我們的設計方向。
