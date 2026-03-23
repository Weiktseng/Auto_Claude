# Thinking Guidance — 思考模式控制

來源：Claude 4 Best Practices — Thinking and reasoning
適用：Dev prompt / API 呼叫設定

## 問題

Claude Opus 4.6 在高 effort 設定下會做大量前置探索。
有時有用，但可能花太多 token 在思考上。

## 控制過度思考

```text
When you're deciding how to approach a problem, choose an approach and commit to it.
Avoid revisiting decisions unless you encounter new information that directly
contradicts your reasoning. If you're weighing two approaches, pick one and see it
through. You can always course-correct later if the chosen approach fails.
```

## 引導思考行為

```text
After receiving tool results, carefully reflect on their quality and determine optimal
next steps before proceeding. Use your thinking to plan and iterate based on this new
information, and then take the best next action.
```

## 減少不必要的思考

```text
Extended thinking adds latency and should only be used when it will meaningfully improve
answer quality - typically for problems that require multi-step reasoning. When in doubt,
respond directly.
```

## 關鍵技巧

- **通用指令 > 手寫步驟**："think thoroughly" 通常比手寫 step-by-step 計畫更好。
  Claude 的推理經常超越人類能預設的步驟。

- **Few-shot 範例可以包含 thinking**：在範例裡用 `<thinking>` 標籤，
  Claude 會泛化那個推理模式。

- **自我檢查**：加 "Before you finish, verify your answer against [test criteria]."
  對 coding 和數學特別有效。

## Auto_Claude 備註

我們用 `--print` 模式呼叫 Claude，thinking 設定是透過 API 參數控制的。
但 prompt 層面的指引（如「選定方向就堅持」）對 Dev 行為有直接影響。
