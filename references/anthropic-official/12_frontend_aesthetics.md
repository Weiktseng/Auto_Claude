# Frontend Aesthetics — 前端視覺美學指引

來源：Claude 4 Best Practices — Frontend design + 官方 Skill（SKILL.md）
Skill 來源：https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md
適用：Dev prompt（前端開發階段）

## 注意

這份指引幾乎全部在講「視覺美學」，不是前端工程實踐。
沒有：WebSocket、API 整合、無障礙/WCAG、性能指標、測試策略、組件架構。
適合在 UI 打磨階段注入，不適合在架構/功能開發階段使用。

## 官方片段（Best Practices 內嵌版）

```text
<frontend_aesthetics>
You tend to converge toward generic, "on distribution" outputs. In frontend design, this
creates what users call the "AI slop" aesthetic. Avoid this: make creative, distinctive
frontends that surprise and delight.

Focus on:
- Typography: Choose fonts that are beautiful, unique, and interesting. Avoid generic
  fonts like Arial and Inter; opt instead for distinctive choices that elevate the
  frontend's aesthetics.
- Color & Theme: Commit to a cohesive aesthetic. Use CSS variables for consistency.
  Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
  Draw from IDE themes and cultural aesthetics for inspiration.
- Motion: Use animations for effects and micro-interactions. Prioritize CSS-only
  solutions for HTML. Use Motion library for React when available. Focus on high-impact
  moments: one well-orchestrated page load with staggered reveals (animation-delay)
  creates more delight than scattered micro-interactions.
- Backgrounds: Create atmosphere and depth rather than defaulting to solid colors.
  Layer CSS gradients, use geometric patterns, or add contextual effects that match
  the overall aesthetic.

Avoid generic AI-generated aesthetics:
- Overused font families (Inter, Roboto, Arial, system fonts)
- Clichéd color schemes (particularly purple gradients on white backgrounds)
- Predictable layouts and component patterns
- Cookie-cutter design that lacks context-specific character

Interpret creatively and make unexpected choices that feel genuinely designed for the
context. Vary between light and dark themes, different fonts, different aesthetics.
You still tend to converge on common choices (Space Grotesk, for example) across
generations. Avoid this: it is critical that you think outside the box!
</frontend_aesthetics>
```

## 官方 SKILL.md 額外指引

SKILL.md 比 Best Practices 版本更詳細，額外包含：

- **Spatial Composition**：不對稱佈局、重疊、對角線、打破格線、
  策略性留白 vs 控制密度
- **Backgrounds & Visual Details**：漸層疊加、noise texture、
  幾何圖案、光暈、裝飾邊框、自訂圖示
- **設計前思考框架**：
  - Purpose：這個介面解決什麼問題？誰在用？
  - Tone：選一個極端美學方向（極簡/極繁/復古未來/奢華/工業...）
  - Constraints：技術限制（框架、響應式、無障礙）
  - Differentiation：什麼讓這個設計令人難忘？

## Auto_Claude 備註

這個 Skill 是 Claude Code 的官方 plugin，代表 Anthropic 認為
Claude 在前端設計上的主要盲點是「趨同於通用美學」。
但對我們的 motc 專案來說，政府系統的 UI 重點是清晰和可用性，
不是「令人難忘的設計」。注入時需要根據規格書調整方向。
