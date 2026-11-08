# Baby Docs pre-submit review, 2026-11-07

Version under review: 1.1.4 (build 30), `origin/main` at `794112b`.
Live version: 1.1.3. Diff base: `b75792a` (the 1.1.3 version bump), so the
1.1.3 bug-hunt fixes made before the 1.1.4 bump are covered too.
Scope: app sources only (`BabyDocs/`, `Shared/`, `project.yml`), 12 files,
+187 / -54.

## What changed

- First-run intake gate moved from `RootView` state into `AppNavigator`, and an
  imported shared plan now ends the intake (`AppNavigator.planWasImported`).
- `PlanTimeline` treats a certificate or SSN card recorded on the Children
  screen as arrived, not only a ticked ordering task.
- The vault orphan sweep is skipped while the store runs in memory or while a
  moved-aside `BabyDocs-unreadable-*` store exists.
- Contrast tokens (`AppTheme.urgent`, `caution`, `positive`, `quiet`), Reduce
  Motion guards, a 44 pt accessibility target on `ProgressBar`.

## Checks run

- Crash and data loss: no new force unwraps, subscripts or schema changes. No
  SwiftData model changed, so no migration. `isInMemoryFallback` is written once
  inside the `sharedModelContainer` initialiser, which runs before any reader.
  The unreadable-archive check reads the same Application Support folder the
  store is moved aside in (`BabyModelStore.storeURL`, `VaultStore.rootDirectory`).
- Purchase and paywall: no purchase, offering, restore or `isPro` code changed.
  The paywall still carries Restore, Terms of Use and Privacy Policy
  (`PlusPurchaseView.swift:303`, `:340`).
- State: the intake cannot reopen over an existing plan (the gate defaults to
  finished and only the intake's own `onAppear` clears it). An import whose save
  fails leaves zero children, so the empty-store rule keeps the intake up. An
  import that skips the intake's notification page still asks for permission in
  `ImportPlanSheet` (`SharePlanSheet.swift:313`).
- App Review: every launch-argument switch in the app target is under
  `#if DEBUG` (`BabyDocsApp.swift`, `OnboardingFlow.swift:793`,
  `RevenueCatProbe`). No hard-coded prices, no health claims, no other-platform
  links in Swift sources. `scripts/design-audit.py`: 0 drifted across 41 files.

## Findings

| Severity | Where | What happens | Status |
|---|---|---|---|
| P2 | `Shared/Services/VaultStore.swift:157` | Once any `BabyDocs-unreadable-*` file exists, the launch sweep never runs again on that install, so a page orphaned by a crash between writing a photo and saving its row stays on disk (protected, excluded from backup, unreachable from any screen) until the archive is removed. | Not fixed: deliberate trade-off documented in the code. Keeping photographs that might belong to the moved-aside store is the safe side; not a defect. |

No P0 or P1 findings. Nothing was changed in app code.

## Tests

See the commit message for the `gh-sim` run id and result.
