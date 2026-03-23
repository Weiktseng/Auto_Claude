# Refactoring UI — 核心設計原則

來源：refactoringui.com + Steve Schoger Twitter tips

---

## 1. 視覺層級 (Visual Hierarchy)

- 不是所有元素都值得相同的視覺權重
- 單靠字體大小不足以建立層級
- 弱化次要元素來強調主要元素
- Label 應該是最後手段 — 讓設計本身傳達資訊
- 視覺層級和文件層級是兩回事
- 用顏色和字重做強調，不要只靠放大字體

> **Original (EN):**
> - Not every element deserves equal visual weight
> - Size alone isn't enough to establish hierarchy
> - De-emphasize secondary elements to emphasize primary ones
> - Labels are a last resort — let the design communicate
> - Visual hierarchy and document hierarchy are separate concerns
> - Balance typographic weight with color contrast

## 2. 排版與間距 (Layout & Spacing)

- 先給大量留白，再逐步縮減
- 建立一致的間距和尺寸系統
- 不需要填滿整個螢幕
- Grid 系統沒有刻意的間距重要
- 相對尺寸在不同情境下不會等比縮放
- 消除模糊的間距（會讓版面混亂）
- 用倍數定義間距，維持垂直節奏

> **Original (EN):**
> - Start with too much white space, then reduce
> - Establish a consistent spacing and sizing system
> - Don't feel obligated to fill the entire screen
> - Grids are less critical than intentional spacing
> - Relative sizing doesn't scale proportionally across contexts
> - Eliminate ambiguous spacing that confuses the layout
> - Use multiples to define spacing for vertical rhythm

## 3. 字體排印 (Typography)

- 先建立字體大小比例再選字體
- 好字體很重要
- 維持適當的行長度以利閱讀
- 文字對齊基線，不是對齊中心
- 行高應該與字體大小成比例 — 字越大行高越緊
- 不是每個超連結都需要顏色區分
- 刻意使用字距 (letter-spacing)
- **16px 字體 + 1.5 行高** 是內文的可靠預設值
- 大寫文字加 letter-spacing 增加可讀性
- 不同大小的文字要看起來同樣重量：大字用細體、小字用粗體

> **Original (EN):**
> - Establish a type scale before selecting fonts
> - Quality fonts matter significantly
> - Maintain appropriate line length for readability
> - Align text to baseline, not center
> - Line height should be proportional to font size
> - Not every hyperlink needs color differentiation
> - Use letter-spacing intentionally for visual balance
> - **16px font, 1.5 line height** — reliable default for body copy
> - Add letter-spacing to all-caps text to improve readability
> - To make text of different sizes feel the same weight, make larger text thinner and smaller text bolder

## 4. 色彩策略 (Color)

- HSL 比 hex 更直覺
- 一個主色需要很多支援色調
- 預先定義完整色板
- 淡化顏色時不要去飽和
- 灰色可以有暖色或冷色底調
- 無障礙設計不等於醜陋
- 不要只靠顏色傳達資訊
- 彩色背景上的灰字：加入背景色的色相會更和諧
- 漸層：色相偏移 10-20 度會更鮮豔

> **Original (EN):**
> - HSL is more intuitive than hex for color manipulation
> - One primary color requires many supporting shades
> - Define your complete color palette upfront
> - Avoid desaturating colors when lightening them
> - Grey can have warm or cool undertones
> - Accessible design doesn't require bland aesthetics
> - Don't rely solely on color for information distinction
> - On colored backgrounds, add a hint of the background hue to grey text for visual harmony
> - Shift gradient hues by 10-20 degrees to make them appear more vibrant

## 5. 邊框與分隔 (Borders)

- 邊框太多會讓設計顯得雜亂
- 替代方案：box shadow、對比背景色、增加間距
- 用微妙對比取代 keyline 來區分面板標題
- Keyline 可以同時分隔和連接內容

> **Original (EN):**
> - Borders are a great way to distinguish two elements from one another, but using too many of them can make your design feel busy and cluttered
> - Instead, apply box shadows, contrasting background colors, or increased spacing
> - Use subtle contrast instead of keylines to distinguish panel titles
> - Keylines can both divide and visually connect separate content areas

## 6. 深度與維度 (Depth)

- 整個設計模擬一致的光源
- 陰影表示高度和層次
- 陰影有多個組成：blur、spread、顏色
- 扁平設計仍然受益於深度分層
- 重疊元素創造視覺深度
- Box shadow 用些微垂直偏移會更自然

> **Original (EN):**
> - Emulate a consistent light source throughout designs
> - Shadows indicate elevation and layering
> - Shadows have multiple components (blur, spread, color)
> - Flat designs still benefit from depth through layering
> - Overlapping elements create visual depth
> - Apply slight vertical offsets to box shadows for more natural-looking effects

## 7. 圖片處理 (Images)

- 用高品質照片
- 確保文字和圖片背景之間有足夠對比
- 尊重圖片原始的顯示尺寸
- 規劃使用者上傳內容的不可預測性
- Hero banner：去飽和照片 + 粗體顏色 + multiply 混合模式

> **Original (EN):**
> - Use high-quality photography
> - Ensure sufficient contrast between text and image backgrounds
> - Respect the intended display size of imagery
> - Plan for unpredictable user-uploaded content
> - Combine desaturated photos with bold colors and multiply blend modes for high contrast text areas

## 8. 圖標 (Icons)

- 小圖標放大到 landing page 用時，放在形狀裡加背景色
- 圖標比周圍文字重時，用較淡的圖標
- 用箭頭或勾勾取代標準項目符號

> **Original (EN):**
> - Rather than enlarging small icons for landing pages, place them within shapes and apply background colors
> - Use lighter icon weights than text for inactive states when icons are weightier than surrounding text
> - Replace standard bullets with generic icons like arrows or checkmarks for visual interest

## 9. 表單 (Forms)

- 對所有輸入元件套用一致、有想法的樣式
- 長表單用兩欄排版善用寬螢幕
- Dropdown 可以設計成彈性容器（雙欄 + 輔助文字）

> **Original (EN):**
> - Apply consistent, thoughtful styling details across various input components
> - Organize lengthy forms into two columns to better utilize wide screens without awkward fields
> - Design dropdown menus as flexible containers, such as two-column layouts with supporting text

## 10. 細節打磨 (Polish)

- 自訂和強化預設元件
- 強調色邊框增加視覺趣味而不雜亂
- 背景裝飾要有意圖
- 空狀態值得設計
- 意想不到的細節提升完成品質感
- 負面操作（如刪除）用低調連結而非醒目按鈕，加確認步驟
- 頂部加 4-6px 色帶增加活力
- 資料呈現要跳脫資料庫的一對一映射

> **Original (EN):**
> - Customize and enhance default components
> - Accent borders add visual interest without clutter
> - Background decoration should feel intentional
> - Empty states deserve design attention
> - Unexpected details elevate finished products
> - Use understated links rather than prominent buttons for secondary negative actions, with a confirmation step
> - Add a 4-6px color band at the top of hero sections to increase liveliness
> - Present field-value data creatively rather than using one-to-one database mapping to the interface

## 11. 減法原則

- **Less borders** — 能不用邊框就不用
- **Less labels** — 讓設計自己說話
- **Less color** — 主色少、支援色多
- **Less weight** — 次要元素要輕

> **Original (EN):**
> - **Less borders** — use fewer borders whenever possible
> - **Less labels** — let the design speak for itself
> - **Less color** — fewer primary colors, more supporting shades
> - **Less weight** — secondary elements should feel lighter
