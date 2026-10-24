---
paths:
  - "BabyDocs/RootView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "BabyDocs/Views/DocumentsView.swift"
  - "BabyDocs/BabyDocsApp.swift"
  - "Shared/Utilities/AppTheme.swift"
---

# Baby Docs: iPhone Duo (2026-10-22, bar moved 2026-10-23)

- Unfolded (regular width, room for two panes of at least 360 pt), `RootView`
  puts the tab bar (at the top) and its open tab (Plan, Children, Plus or Settings) on the
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
- The tab bar heads the leading pane while split (2026-10-23). Every docked
  or floating bottom bar ended the leading pane's last visible row against
  it: rows read through glass, then a solid backdrop sliced and faded them,
  and the fleet review rejected both. Now `planPageBackground` hides the
  system bar when `\.tabBarBackdrop` is `.none` (both panes while split),
  `PaneTabBar` in `RootView` draws Plan, Children, Plus and Settings as text
  in one glass capsule at the top of the leading pane, as iPad does at
  regular width. `UnfoldedSplit.chrome` puts it in the status bar's band
  (the 82 pt top safe area, whose clock only draws over the trailing pane)
  and starts both panes just under that band, so the Plan and Documents
  titles share a line. Placed below the safe area instead, it pushed both
  titles 60 pt down (first capture of 2026-10-23). Both panes run to the
  display's bottom edge, where a 28 pt fade (`paneEdgeFade`) softens the
  last line. Tried and dropped: a 40 pt fade ending in solid page across the
  home indicator, which left a 34 pt empty strip with the last card cut
  hard against it. Text labels, not icons: no SF Symbol can push
  one label off the others' baseline. Folded keeps `.glass`, the phone's
  system bar, unchanged.
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
