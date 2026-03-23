# General Principles — 通用 Prompt 工程原則

來源：Claude 4 Best Practices — General principles
適用：所有 prompt 設計

## 核心原則

### 1. 清晰直接

> Think of Claude as a brilliant but new employee who lacks context on your norms
> and workflows. The more precisely you explain what you want, the better the result.

**黃金法則**：把你的 prompt 給一個對任務背景不了解的同事看，
請他照做。如果他會困惑，Claude 也會。

### 2. 加上下文提升表現

解釋「為什麼」比只說「做什麼」更有效。

不好：
```text
NEVER use ellipses
```

好：
```text
Your response will be read aloud by a text-to-speech engine, so never use ellipses
since the text-to-speech engine will not know how to pronounce them.
```

Claude 聰明到可以從解釋中泛化。

### 3. 用範例引導

3-5 個範例是最可靠的控制輸出格式、語氣、結構的方式。
用 `<example>` 標籤包裝。

### 4. 用 XML 標籤結構化

用一致的、描述性的標籤名稱：`<instructions>`、`<context>`、`<input>`。
有層級關係時巢狀嵌套。

### 5. 給 Claude 角色

即使一句話也有效：

```python
system="You are a helpful coding assistant specializing in Python."
```

### 6. 長文件放在前面

20k+ token 的文件放在 prompt 最前面，query 放最後面。
測試顯示 query 放最後可提升 30% 品質。

## 4.6 版特別注意

- **更簡潔**：可能跳過工具呼叫後的摘要。如果你要摘要，明確要求。
- **不再支援 prefill**：用指令代替。
- **過度 prompting 會反效果**：之前為了讓工具觸發而加的激進語言
  （如 "CRITICAL: You MUST use this tool"），在 4.6 會導致過度觸發。
  改用正常語氣 "Use this tool when..."。
