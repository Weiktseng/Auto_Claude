# Avoid Overengineering — 避免過度工程化

來源：Claude 4 Best Practices — Overeagerness 章節
適用：Dev prompt（最重要的行為控制片段之一）

## 問題

Claude Opus 4.5/4.6 有傾向過度工程化：建立多餘的檔案、加不必要的抽象層、
為沒人要求的未來需求設計彈性。

## 官方片段

```text
Avoid over-engineering. Only make changes that are directly requested or clearly
necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was asked.
  A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need extra
  configurability.

- Documentation: Don't add docstrings, comments, or type annotations to code you didn't
  change. Only add comments where the logic isn't self-evident.

- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios that
  can't happen. Trust internal code and framework guarantees. Only validate at system
  boundaries (user input, external APIs).

- Abstractions: Don't create helpers, utilities, or abstractions for one-time operations.
  Don't design for hypothetical future requirements. The right amount of complexity is the
  minimum needed for the current task.
```

## Auto_Claude 備註

這個片段我們的 Dev prompt 已經在用類似版本。
對照確認是否有遺漏的面向（特別是 Documentation 和 Defensive coding 兩點）。
