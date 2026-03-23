# Subagent Guidance — 何時該/不該用 subagent

來源：Claude 4 Best Practices — Subagent orchestration
適用：Dev prompt

## 問題

Claude Opus 4.6 非常喜歡 spawn subagent，有時在簡單任務上也會用，
但直接 grep 一下就夠了。

## 官方片段

```text
Use subagents when tasks can run in parallel, require isolated context, or involve
independent workstreams that don't need to share state. For simple tasks, sequential
operations, single-file edits, or tasks where you need to maintain context across
steps, work directly rather than delegating.
```

## 適用時機

✅ 用 subagent：
- 可以平行跑的獨立任務
- 需要隔離 context 的工作
- 不需要共享狀態的獨立工作流

❌ 不要用 subagent：
- 簡單任務
- 順序操作
- 單檔案修改
- 需要跨步驟維持 context 的任務

## Auto_Claude 備註

我們的 Reviewer prompt 已經用 `--disallowed-tools "Agent"` 禁止 Reviewer 用 subagent。
Dev 可以用但需要這個指引來避免濫用。
