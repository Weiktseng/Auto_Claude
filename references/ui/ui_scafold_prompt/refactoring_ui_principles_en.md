# Refactoring UI — Core Design Principles

Source: refactoringui.com + Steve Schoger Twitter tips

---

## 1. Visual Hierarchy

- Not every element deserves equal visual weight
- Size alone isn't enough to establish hierarchy
- De-emphasize secondary elements to emphasize primary ones
- Labels are a last resort — let the design communicate
- Visual hierarchy and document hierarchy are separate concerns
- Balance typographic weight with color contrast

## 2. Layout & Spacing

- Start with too much white space, then reduce
- Establish a consistent spacing and sizing system
- Don't feel obligated to fill the entire screen
- Grids are less critical than intentional spacing
- Relative sizing doesn't scale proportionally across contexts
- Eliminate ambiguous spacing that confuses the layout
- Use multiples to define spacing for vertical rhythm

## 3. Typography

- Establish a type scale before selecting fonts
- Quality fonts matter significantly
- Maintain appropriate line length for readability
- Align text to baseline, not center
- Line height should be proportional to font size
- Not every hyperlink needs color differentiation
- Use letter-spacing intentionally for visual balance
- **16px font, 1.5 line height** — reliable default for body copy
- Add letter-spacing to all-caps text to improve readability
- To make text of different sizes feel the same weight, make larger text thinner and smaller text bolder

## 4. Color

- HSL is more intuitive than hex for color manipulation
- One primary color requires many supporting shades
- Define your complete color palette upfront
- Avoid desaturating colors when lightening them
- Grey can have warm or cool undertones
- Accessible design doesn't require bland aesthetics
- Don't rely solely on color for information distinction
- On colored backgrounds, add a hint of the background hue to grey text for visual harmony
- Shift gradient hues by 10-20 degrees to make them appear more vibrant

## 5. Borders

- Borders are a great way to distinguish two elements from one another, but using too many of them can make your design feel busy and cluttered
- Instead, apply box shadows, contrasting background colors, or increased spacing
- Use subtle contrast instead of keylines to distinguish panel titles
- Keylines can both divide and visually connect separate content areas

## 6. Depth

- Emulate a consistent light source throughout designs
- Shadows indicate elevation and layering
- Shadows have multiple components (blur, spread, color)
- Flat designs still benefit from depth through layering
- Overlapping elements create visual depth
- Apply slight vertical offsets to box shadows for more natural-looking effects

## 7. Images

- Use high-quality photography
- Ensure sufficient contrast between text and image backgrounds
- Respect the intended display size of imagery
- Plan for unpredictable user-uploaded content
- Combine desaturated photos with bold colors and multiply blend modes for high contrast text areas

## 8. Icons

- Rather than enlarging small icons for landing pages, place them within shapes and apply background colors
- Use lighter icon weights than text for inactive states when icons are weightier than surrounding text
- Replace standard bullets with generic icons like arrows or checkmarks for visual interest

## 9. Forms

- Apply consistent, thoughtful styling details across all input components
- Organize lengthy forms into two columns to better utilize wide screens without awkward fields
- Design dropdown menus as flexible containers, such as two-column layouts with supporting text

## 10. Polish

- Customize and enhance default components
- Accent borders add visual interest without clutter
- Background decoration should feel intentional
- Empty states deserve design attention
- Unexpected details elevate finished products
- Use understated links rather than prominent buttons for secondary negative actions, with a confirmation step
- Add a 4-6px color band at the top of hero sections to increase liveliness
- Present field-value data creatively rather than using one-to-one database mapping to the interface

## 11. Subtraction Principle

- **Less borders** — use fewer borders whenever possible
- **Less labels** — let the design speak for itself
- **Less color** — fewer primary colors, more supporting shades
- **Less weight** — secondary elements should feel lighter
