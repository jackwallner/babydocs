---
paths:
  - "project-docs/design/design.md"
  - "scripts/design-audit.py"
  - "Shared/Utilities/AppTheme.swift"
  - "BabyDocs/Views/**/*.swift"
  - "BabyDocs/RootView.swift"
---

# Baby Docs: the design system

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

- **`project-docs/design/design.md` is the design system, and `scripts/design-audit.py` is what
  stops it being a document nobody reads.** Tokens live in `AppTheme`; the audit
  reads them out of that file and fails on any view that types a spacing number
  of its own, draws a `RoundedRectangle` without a continuous curve, defines a
  colour outside `AppTheme` or names a font. Four spacing values, all multiples
  of four; one radius and one curve; `.pressableCard()` rather than
  `.buttonStyle(.plain)` on anything card-shaped; four named haptics in
  `Haptics` and nothing for navigation. Run it before a release.

- **One margin, one colour system.** `AppTheme.margin` is the only horizontal
  inset, it is 20 because that is what `.insetGrouped` uses on iPhone (Settings
  and the sources list are system lists and always will be, so any other number
  guarantees two left edges), and colour means exactly one thing: how close a
  door is to closing.
  Categories are grey glyphs. The screen this replaced had two left edges and
  three competing colour systems in one row, which is why none of them read as
  information. Cards use `planCard()`/`planCardRow()`; pages use
  `planPageBackground()`, which also reserves the bottom margin the floating tab
  bar needs.
  - That margin is `AppTheme.floatingTabBarInset`, one number for the whole app,
    and it was guessed twice because the real bug was somewhere else.
    `planPageBackground` used to wrap every page in a `GeometryReader` and hand
    the scroll view an explicit height, which is exactly what stops the system's
    own tab-bar safe area from reaching the list. The page then had to buy the
    inset back by hand: 44 (the bar's glyph height, not its footprint, so six
    screens were clipped) and then 96, which bought a hard horizontal edge where
    the shortened scroll view ended and 96 points of dead page under it. That
    edge is the "big bar in the way" in the screenshots. The scroll view is full
    height again, the system contributes the bar's footprint, and the constant
    is 24 points of breathing room on top. `TabBarClearanceUITests` still
    asserts it on every tab, because a single-screen layout test cannot catch a
    bad shared constant. Sheets pass `underTabBar: false`.
