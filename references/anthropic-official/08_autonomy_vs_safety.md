# Autonomy vs Safety — 自主性與安全性的平衡

來源：Claude 4 Best Practices — Balancing autonomy and safety
適用：Dev + Reviewer prompt

## 問題

沒有指引的情況下，Claude Opus 4.6 可能執行難以逆轉的操作：
刪檔案、force push、發訊息到外部服務。

## 官方片段

```text
Consider the reversibility and potential impact of your actions. You are encouraged to
take local, reversible actions like editing files or running tests, but for actions that
are hard to reverse, affect shared systems, or could be destructive, ask the user before
proceeding.

Examples of actions that warrant confirmation:
- Destructive operations: deleting files or branches, dropping database tables, rm -rf
- Hard to reverse operations: git push --force, git reset --hard, amending published
  commits
- Operations visible to others: pushing code, commenting on PRs/issues, sending messages,
  modifying shared infrastructure

When encountering obstacles, do not use destructive actions as a shortcut. For example,
don't bypass safety checks (e.g. --no-verify) or discard unfamiliar files that may be
in-progress work.
```

## Auto_Claude 適用場景

- Dev：需要這個指引，因為 Dev 有完整工具權限
- Reviewer：已經被限制為唯讀，但如果改為有限寫入權限時需要加上
- 跟 KNOWN_PITFALLS.md #4（Port 衝突只 warn 不處理）相關 —
  但方向相反：這裡是「該確認就確認」，#4 是「該修就修」。
  區分在於：修 port 衝突是本地可逆操作（應該直接做），
  force push 是不可逆操作（應該確認）。
