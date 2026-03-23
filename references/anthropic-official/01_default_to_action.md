# Default to Action — 讓 AI 動手做，不要只建議

來源：Claude 4 Best Practices — Tool usage 章節
適用：Dev prompt

## 問題

如果你說 "can you suggest some changes"，Claude 有時只會給建議而不動手改。
即使你想要它改，它也可能只是列出建議。

## 官方片段

```text
<default_to_action>
By default, implement changes rather than only suggesting them. If the user's intent is
unclear, infer the most useful likely action and proceed, using tools to discover any
missing details instead of guessing. Try to infer the user's intent about whether a tool
call (e.g., file edit or read) is intended or not, and act accordingly.
</default_to_action>
```

## 反向版本（保守模式，適合 Reviewer）

如果你希望 AI 不要自己動手、只提供建議：

```text
<do_not_act_before_instructions>
Do not jump into implementation or changes files unless clearly instructed to make
changes. When the user's intent is ambiguous, default to providing information, doing
research, and providing recommendations rather than taking action. Only proceed with
edits, modifications, or implementations when the user explicitly requests them.
</do_not_act_before_instructions>
```

## Auto_Claude 適用場景

- Dev：用主動版本（default_to_action）
- Reviewer：用保守版本（do_not_act_before_instructions）— 正好符合 Reviewer 只讀不寫的設計
