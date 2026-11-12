---
paths:
  - "BabyDocs/RootView.swift"
  - "Shared/Utilities/UnfoldedSplit.swift"
  - "Shared/Utilities/AppTheme.swift"
  - "BabyDocs/Views/Onboarding/OnboardingFlow.swift"
  - "BabyDocs/Views/PlusPurchaseView.swift"
  - "BabyDocs/Views/PlusView.swift"
  - "project.yml"
  - "BabyDocs/Info.plist"
---

# Baby Docs: iPad (2026-11-12)

iPad support is free of extra screens: `TARGETED_DEVICE_FAMILY "1,2"`, all four
orientations (`UISupportedInterfaceOrientations~ipad`). It can never be removed
once shipped, so keep this file true.

- **Two panes come from the Duo split, not from an iPad-only layout.** At
  regular width of 720 pt or more `UnfoldedSplit.make` splits the display in
  half (no fold): the open tab on the left, Documents on the right. That is
  every full-screen iPad, portrait and landscape. Under 720 pt (Split View
  two-thirds, about 678 pt) it is the single column with the system's own tab
  bar, which an iPad draws at the top. Compact width (Split View half and
  Slide Over) is the phone layout.
- **The pane tab bar clears a short status bar.** The Duo's 82 pt top safe area
  holds the bar beside the clock. An iPad's is about 24 pt and carries the date
  and app name, so `UnfoldedSplit.chrome` puts the bar a gap below the safe area
  when it is shorter than the bar needs. Both panes then start under the bar.
- **Forms and pitches are one column, 560 pt wide** (`AppTheme.readableWidth`,
  `readableColumn()`): the intake, the Plus pitch (scroll content and buy bar),
  the archived-children and storage-recovery screens. The background behind the
  column matches the page inside it (`OnboardingFlow.pageColor`), and the
  intake footer takes that colour on iPad instead of the bar material, which
  showed as a box.
- **Lists are not capped.** Plan, Documents, Children and Settings are
  `.insetGrouped` lists that fill their pane, as on Duo.
- **Nothing is reserved at the bottom edge on iPad.** The phone's floating tab
  bar clearance (`floatingTabBarInset`) applies to the phone idiom only.
- **The free Plus pitch hides the system bar while split**, like every other tab
  (`PlusView`), and sits on the page colour.
- **No programmatic rotation.** iPad windowing refuses
  `requestGeometryUpdate` ("windowing mode does not allow"). Landscape captures
  come from a UI test setting `XCUIDevice.shared.orientation`; the screenshot
  is the unrotated framebuffer, so rotate it 270 degrees with `sips -r 270`.
- **Captures.** Pool simulators are iPhones. Make a 13-inch iPad
  (`com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB`, on a runtime
  that accepts iPad types: 27.0, not the Duo's 27.1), or use
  `gh-sim ... --device "iPad Pro 13-inch (M4)"`. Per-launch `gh-sim --screen`
  routes: `-uitest-seed -uitest-pro -duo-screen <route>`; the onboarding welcome
  is `-uitest-wipe-store` alone and the free pitch omits `-uitest-pro`.
  Anything else in `--args` is added to every screen.
- Verified 2026-11-12: portrait and landscape of plan, task, children, Plus
  (paid and free), settings, onboarding welcome and first question, on iOS 27.0
  and 27.2. On 27.0 the trailing pane's large title sits at the pane edge; on
  27.2 it has its margin. That is the OS, not this code.
- **Store set.** `scripts/compose-ipad-screenshots.py` builds `en-US/ipad_01..05.png`
  (2064x2752) from `fastlane/screenshots/ipad-raw/`, with the iPhone set's five
  headlines word for word. The raws came from an iPad Pro 13-inch capture at
  9:41 (`simctl status_bar override`): the newborn-account and coverage intake
  pages, the plan beside Documents, the birth-certificate task and the
  job-based plan task. Upload only that type:
  `~/ios/appstore-screenshots/bin/asc-sync-screenshots --repo ~/babydocs --bundle com.jackwallner.babydocs --version <draft> --only-type APP_IPAD_PRO_3GEN_129 --only-locale en-US --apply`.
  The listing has one locale, en-US.
- **Known copy gap.** About thirty strings say "this phone" (vault, notes,
  sharing). They read wrong on an iPad and show in the Documents pane of the
  store frames. A device noun used in those strings is the fix.
