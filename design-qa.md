# POS Design QA

- Source visual truth: `C:\Users\ansar\Downloads\POS Refined — Normal Buttons — 1024×600.png`
- Implementation capture: `D:\POS_store\build\design_qa\pos-1024x600.png`
- Combined comparison: `D:\POS_store\build\design_qa\comparison.png`
- Viewport: 1024 × 600 logical pixels, device pixel ratio 1
- Source pixels: 2048 × 1200 (normalized to 1024 × 600)
- Implementation pixels: 1024 × 600
- State: cashier POS, six products, three cart lines, online/synced fixture state

## Full-view comparison

The implementation preserves the reference composition: 58px top bar, 76px dark navy sidebar, neutral catalog canvas, fixed right-side bill, restrained borders/radii, green actions, and a three-column product grid at the baseline viewport. Real shop, cashier, reporting, product, stock, cart, and sync values remain state-driven.

The product image treatment intentionally follows the later product-image clarification rather than the reference's large colored blocks: each card reserves a compact 68 × 56 thumbnail, keeping name, price, stock, and Add action dominant.

## Focused-region comparison

- Product cards: checked thumbnail crop/fallback, two-line name safety, price/stock hierarchy, and 44px Add target.
- Current Bill: checked three-line visibility, 44px rectangular quantity controls, red Remove action, totals, primary payment action, and rectangular secondary controls.
- Header/sidebar: checked status placement, navy navigation, selected Sale state, and absence of owner-only destinations.

## Comparison history

1. Initial capture found a P2 theme-shape mismatch (pill/circular controls instead of normal rectangular controls), a P2 cart-density issue clipping the third line's controls, and a P2 heading rhythm mismatch.
2. Fixed the heading/stat stack, search border, selected category styling, cart spacing, explicit green actions, text-only sidebar treatment, and 7–8px rectangular control shapes.
3. Post-fix capture shows all persistent controls and three cart lines within 1024 × 600 with no RenderFlex overflow. Responsive widget checks also pass at 1280 × 800, 1366 × 768, 1920 × 1080, and the narrow fallback.

## Findings

No actionable P0/P1/P2 visual findings remain.

P3: currency formatting retains the application's established two-decimal display in several POS labels, while the reference examples omit `.00`. This was left unchanged to avoid changing shared formatting behavior during the UI-only phase.

## Final result

passed
