# Investigate Before Answering — 讀 code 再回答，禁止猜測

來源：Claude 4 Best Practices — Minimizing hallucinations in agentic coding
適用：Dev + Reviewer prompt（反幻覺核心片段）

## 問題

Claude 可能在沒讀過檔案的情況下就回答關於 codebase 的問題。
這是幻覺的主要來源之一。

## 官方片段

```text
<investigate_before_answering>
Never speculate about code you have not opened. If the user references a specific file,
you MUST read the file before answering. Make sure to investigate and read relevant files
BEFORE answering questions about the codebase. Never make any claims about code before
investigating unless you are certain of the correct answer - give grounded and
hallucination-free answers.
</investigate_before_answering>
```

## Auto_Claude 適用場景

- Dev：防止 Dev 猜測現有 code 的行為
- Reviewer：防止 Reviewer 在沒看 code 的情況下給出審查意見
- 跟 KNOWN_PITFALLS.md #10（LLM-as-Judge 對精確內容不可靠）是同一個問題的不同層面
