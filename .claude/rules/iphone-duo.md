---
paths:
  - "BabyDocs/RootView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "BabyDocs/Views/DocumentsView.swift"
  - "BabyDocs/BabyDocsApp.swift"
---

# Baby Docs: iPhone Duo (2026-10-22)

- Unfolded (regular width, room for two panes of at least 360 pt), `RootView`
  puts the tab bar and its open tab (Plan, Children, Plus or Settings) on the
  leading side of the fold and Documents on the trailing side: what to do
  beside what to bring. The Documents tab drops out of the bar while split, and
  a route that asks for it lands on Plan with Documents already open beside it.
  Portrait unfolded (669 pt) and every compact width keep the five-tab phone
  layout.
- Fold edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split. The math is
  `UnfoldedSplit`, tested in `UnfoldedSplitTests`. Same shape as Vitals.
- One view tree: folding only changes frames, so the TabView (and the Plan's
  pushed task and scroll) is never rebuilt. Documents does move between the
  tab and its pane, so its To bring / Photos switch is `@SceneStorage`.
  Each pane gets `horizontalSizeClass = .compact`.
- iOS 27.1 moves a `NavigationStack`'s toolbar into a vertical bar on its
  trailing edge, which in the leading pane sits against the fold and narrows
  the Plan by about 84 pt. While split, `horizontalToolbarsInPanes` sets
  `toolbarVerticalBehavior(.disabled)`.
- Still across the fold: the intake, the storage recovery and archived-children
  screens, and sheets (household answers, paywall, add a document). None are in
  the store set.
- Unattended captures: `-uitest-seed -uitest-pro` plus the DEBUG routes
  `babydocs://screen/<plan|children|documents|plus|settings>` and
  `babydocs://screen/task/<catalog key>` (`BabyDocsApp.openScreenshotRoute`).
