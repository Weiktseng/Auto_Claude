# Avoid Hard-coding — 禁止只為通過測試的解法

來源：Claude 4 Best Practices — Avoid focusing on passing tests and hard-coding
適用：Dev prompt

## 問題

Claude 有時過度聚焦在讓測試通過，而不是寫出通用解法。
會用 workaround（如 helper script）代替正確做法，或 hard-code 測試案例的值。

## 官方片段

```text
Please write a high-quality, general-purpose solution using the standard tools available.
Do not create helper scripts or workarounds to accomplish the task more efficiently.
Implement a solution that works correctly for all valid inputs, not just the test cases.
Do not hard-code values or create solutions that only work for specific test inputs.
Instead, implement the actual logic that solves the problem generally.

Focus on understanding the problem requirements and implementing the correct algorithm.
Tests are there to verify correctness, not to define the solution. Provide a principled
implementation that follows best practices and software design principles.

If the task is unreasonable or infeasible, or if any of the tests are incorrect, please
inform me rather than working around them. The solution should be robust, maintainable,
and extendable.
```

## Auto_Claude 備註

跟 KNOWN_PITFALLS.md #3（靜默假通過）直接相關。
最後一段「If the task is unreasonable... inform me rather than working around them」
特別重要 — Dev 應該回報問題而不是繞過。
