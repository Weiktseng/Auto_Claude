# Anthropic 官方 Prompt 工程參考資料

來源：https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices
擷取日期：2026-03-21

這些是 Anthropic 官方發布的行為控制片段，不是完整角色 prompt。
每個片段是獨立的最小單位，可以直接拼裝進 Auto_Claude 的 Dev/Reviewer prompt。

## 檔案列表

### Dev 相關
- `01_default_to_action.md` — 讓 AI 動手做，不要只建議
- `02_investigate_before_answering.md` — 讀 code 再回答，禁止猜測（反幻覺）
- `03_avoid_overengineering.md` — 避免過度工程化（最重要的片段之一）
- `04_avoid_hardcoding.md` — 禁止只為通過測試的 hard-coding
- `05_parallel_tool_calling.md` — 平行工具呼叫指引
- `06_subagent_guidance.md` — 何時該/不該用 subagent
- `07_reduce_file_creation.md` — 減少暫存檔案

### Reviewer 相關
- `08_autonomy_vs_safety.md` — 自主性與安全性的平衡（破壞性操作確認）

### Curator / 架構相關
- `09_context_awareness.md` — Context window 管理與多 window 工作流
- `10_state_management.md` — 跨 session 狀態追蹤最佳實踐
- `11_long_horizon_reasoning.md` — 長任務增量進度管理

### 前端設計
- `12_frontend_aesthetics.md` — 前端視覺美學指引（避免 AI slop）
- `12_ui_polish_injection.md` — **動態注入模組**：Playwright 全頁面按鈕測試 + Bug 清單（由 `<!PHASE_UI_POLISH!>` 觸發）

### 通用技巧
- `13_general_principles.md` — 清晰指令、角色設定、範例寫法、XML 結構
- `14_thinking_guidance.md` — 思考模式控制（adaptive/extended thinking）
- `15_research_patterns.md` — 研究型任務的結構化方法

## 使用方式

這些片段的設計意圖是「提醒 AI 它已有但容易忽略的能力」。
不要整份塞進 prompt — 根據當前開發階段選擇性注入。

例如：
- 前端開發階段 → 注入 #12 + #01 + #03
- Code review 階段 → 注入 #02 + #08
- 長時間自動跑 → 注入 #09 + #10 + #11
