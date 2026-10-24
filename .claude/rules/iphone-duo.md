---
paths:
  - "BabyDocs/RootView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "BabyDocs/Views/DocumentsView.swift"
  - "BabyDocs/BabyDocsApp.swift"
  - "Shared/Utilities/AppTheme.swift"
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
- Under the bar: on the phone, rows pass under the glass tab bar with an 80 pt
  cushion past the last one. In the leading pane that read as rows showing
  through the bar beside a clean Documents pane (the fleet review flags it), so
  `RootView` sets `\.tabBarBackdrop` to `.solid` there: `planPageBackground`
  ends the page in a 20 pt fade and paints it solid behind the bar. The
  trailing pane has no bar, so it gets `.none` (a 20 pt cushion). Folded keeps
  `.glass`, the phone treatment.
- Still across the fold: the intake, the storage recovery and archived-children
  screens, and sheets (household answers, paywall, add a document). None are in
  the store set.
- Unattended captures: `-uitest-seed -uitest-pro -duo-screen <route>`, where
  the route is `plan`, `children`, `documents`, `plus`, `settings` or
  `task/<catalog key>` (`BabyDocsApp.openScreenshotRoute`, DEBUG only). It
  animates there seven seconds after launch, so gh-sim's recording catches the
  move. `documents` folded shows the Documents tab and unfolded lands on Plan
  beside it. Capture every surface in one `gh-sim all --device "iPhone Duo"`
  with one `--screen "-duo-screen <route>"` each (plan,
  task/insurance_employer, plus, children). Never `--url`: `simctl openurl`
  puts every custom-scheme link behind an "Open in Baby Docs?" alert.
- The folded outer display gets iOS 27.1's own vertical bar (toolbar buttons
  and the tab bar on the trailing edge). That is the system default and
  untouched here.
