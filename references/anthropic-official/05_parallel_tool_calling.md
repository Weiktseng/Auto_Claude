# Parallel Tool Calling — 平行工具呼叫指引

來源：Claude 4 Best Practices — Optimize parallel tool calling
適用：Dev prompt

## 背景

Claude 最新模型擅長平行執行工具。會同時跑多個搜尋、讀多個檔案、
平行執行 bash 指令。可以進一步提升或降低這個行為。

## 官方片段（最大化平行）

```text
<use_parallel_tool_calls>
If you intend to call multiple tools and there are no dependencies between the tool
calls, make all of the independent tool calls in parallel. Prioritize calling tools
simultaneously whenever the actions can be done in parallel rather than sequentially.
For example, when reading 3 files, run 3 tool calls in parallel to read all 3 files
into context at the same time. Maximize use of parallel tool calls where possible to
increase speed and efficiency. However, if some tool calls depend on previous calls to
inform dependent values like the parameters, do NOT call these tools in parallel and
instead call them sequentially. Never use placeholders or guess missing parameters in
tool calls.
</use_parallel_tool_calls>
```

## 官方片段（降低平行）

```text
Execute operations sequentially with brief pauses between each step to ensure stability.
```

## Auto_Claude 適用場景

- Dev：用最大化版本，加速開發
- Reviewer：不太需要（Reviewer 主要是讀 + 思考，工具呼叫少）
