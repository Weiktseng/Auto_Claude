# State Management — 跨 Session 狀態追蹤

來源：Claude 4 Best Practices — State management best practices
適用：Curator / Dev prompt / loop.sh 架構

## 官方建議

- **結構化資料用 JSON**：追蹤測試結果、任務狀態等用 JSON，
  幫助 Claude 理解 schema

- **進度筆記用非結構化文字**：一般進度追蹤用自由格式文字

- **用 git 追蹤狀態**：git 提供做過什麼的 log 和可恢復的 checkpoint。
  Claude 最新模型特別擅長用 git 跨 session 追蹤狀態

- **強調增量進度**：明確要求 Claude 追蹤進度，聚焦漸進式工作

## 官方範例

```json
// 結構化狀態檔（tests.json）
{
  "tests": [
    { "id": 1, "name": "authentication_flow", "status": "passing" },
    { "id": 2, "name": "user_management", "status": "failing" },
    { "id": 3, "name": "api_endpoints", "status": "not_started" }
  ],
  "total": 200,
  "passing": 150,
  "failing": 25,
  "not_started": 25
}
```

```text
// 進度筆記（progress.txt）
Session 3 progress:
- Fixed authentication token validation
- Updated user model to handle edge cases
- Next: investigate user_management test failures (test #2)
- Note: Do not remove tests as this could lead to missing functionality
```

## Auto_Claude 備註

我們已經有：
- todo.md = 結構化任務追蹤（但目前是 markdown 不是 JSON）
- reviewer_memory.md = 非結構化進度筆記
- loop log = 每輪記錄

可以考慮把 todo.md 改為 JSON 格式，讓 Dev/Reviewer 更容易解析。
但 markdown 對人類可讀性更好 — 需要權衡。
