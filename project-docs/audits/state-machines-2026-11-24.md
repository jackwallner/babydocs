# State machine audit, 2026-11-24

Scope: the Baby Docs iOS app (one app target, no widget, Watch app, App Intents or extension; local notifications only, no push, no server). Android is out of scope. Audited from committed code at `8cf5b89`. No app code was changed for this audit.

**Summary: 2 bugs proved by a failing test, 3 code path only (not proved).** Plus 5 product calls (not counted).

Evidence run: `gh-sim test --scheme BabyDocs --only BabyDocsTests/StateMachineAuditRepro` on `8cf5b89` plus the repro file, run ``bd-start-imacb6ee-1125-152333-29059``, GitHub run `45721010315`. Result: pending at the time of this commit (GitHub Macs queued); recorded in `state-machines-2026-11-24-fixes.md`. The repro suite is `state-machines-2026-11-24-repro.swift` beside this file (copy it into `BabyDocsTests/` to run it). No build setting needs a placeholder: the RevenueCat key is compiled in and never configured on a simulator.

Seams used: `BabyModelStore.makeInMemoryContainer()`, `RequirementEngine.reconcile` over an in-memory `ModelContext`, `ReviewPromptTracker.useDefaultsForTesting`. Seams that do not exist: an injected RevenueCat client or a constructible `CustomerInfo` for `StoreService`, and a fake `UNUserNotificationCenter`. That is why the entitlement and notification items stay code path.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | A document already in hand is asked for again by a task a changed answer adds | A parent ticks "Proof of the birth" on the Documents tab. Later they answer a question differently (coverage was "Not sure" and is now known, or someone is now taking leave). The new task's checklist and the Documents tab's "Still to find" list "Proof of the birth" again, unticked, while "Already in hand" also lists it. | `DocumentsView.swift:277-280`: "A document title appears on several of one child's tasks, so ticking it has to tick all of them. Anything else means a parent finds the certificate, ticks it, and the app keeps asking for it on three other screens." Also `:144-145` and `:177`. | Documents tab, tick "Proof of the birth" (ticks it on the Social Security task and any other live task). Plan tab, the sliders button (Change household answers), change coverage from Not sure to Job-based or Marketplace, or parental leave from Nobody to One parent, Save. Documents tab: "Proof of the birth" is back under the new task. | Any family that gathers documents before answering every question, which the "Not sure" design invites: unknown coverage is a task about finding out, so answering it later is the expected path. Six rules ask for "Proof of the birth". Cost: a parent re-checks the drawer for a paper they have, and the app contradicts itself on one screen. No data lost. | Test `newTaskInheritsDocumentAlreadyInHand`: result in the fixes doc. Preconditions asserted first (two or more proof rows, no leave task, every proof row ticked). Control `controlUntickedDocumentStaysToFind` (result in the fixes doc) (an untouched document on the new task stays to find). | `RequirementEngine.swift:332` (`syncDocuments` inserts every new `DocumentItem` with `isOnHand` false) |
| B2 | Ticking, unticking and ticking one hard-deadline task counts as two deadlines beaten | Nothing on screen. The review gate's "two deadlines beaten" is met by one task ticked twice. | `ReviewPromptTracker.swift:49-51`: "Deadlines beaten. Two, because one could be luck". `.claude/rules/plus-pricing-and-review.md`: "a task with a **hard** deadline ticked **before** that deadline closed (`recordCompletion`), two of them". | Plan tab, tick the job-based plan (or Marketplace) task, tap it again to untick, tick again. `PlanView.toggle` (`PlanView.swift:316-320`) and `TaskDetailView.toggleDone` (`:531-537`) both call `recordCompletion` on every tick. | Anyone who corrects a tick. Cost: the rating ask can come after one beaten deadline rather than two. The ask itself still follows a real met deadline. | Test `retickingOneTaskCountsOnce`: result in the fixes doc. Control `controlTwoTasksCountTwice` (result in the fixes doc). | `ReviewPromptTracker.swift:129-133` |
| C1 | (Code path, not proved) A pending Ask to Buy is shown as a failed purchase | A child on a Family Sharing account taps Start my free trial, Apple's sheet sends the request to a parent, and the app shows the alert "Purchases: The purchase could not be completed. Check your Apple Account and try again." | Rollout A: Ask to Buy must read as waiting, not as an error. No in-app copy promises otherwise; the alert's own text ("could not be completed") is false for a request that is pending. | Plus tab or the intake's last page, Start my free trial, Ask to Buy on Apple's sheet. | Family Sharing child accounts only. Cost: a purchase that will succeed reads as failed, and a second tap sends a second request. | Not run: RevenueCat is never configured on a simulator, and there is no purchases seam. `PlusPurchaseView.swift:373-375` maps every thrown error to the one message. | `PlusPurchaseView.swift:373-375`, `StoreService.swift:352` |
| C2 | (Code path, not proved) An Ask to Buy approved while the app is open does not unlock Plus until the app next comes to the foreground | After the parent approves, Plus stays locked on screen. Backgrounding and reopening unlocks it (`RootView.swift:146-152` refreshes on `.active`). | `StoreService.swift:71-74`: the entitlement notification exists so reminders are laid down "after a purchase". | As C1, then the parent approves while the child keeps the app open. | Family Sharing child accounts; also a renewal or lapse that lands mid-session. Cost: Plus looks unbought until the next foreground. | Not run (needs a RevenueCat seam). No `PurchasesDelegate` is set anywhere (`grep delegate` finds only notifications and location). | `StoreService.swift:431-462` (`configureIfNeeded`, no delegate) |
| C3 | (Code path, not proved) The foreground refresh during a purchase can overwrite the purchase's entitlement with older customer info | After buying, the sheet dismisses but the Plus tab can show the pitch again until the next foreground. | `StoreService.swift:71-74` (as C2). | Apple's purchase sheet makes the scene inactive and then active, so `RootView` starts `StoreService.refresh()` while `purchase` is in flight; if `customerInfo()` returns cached pre-purchase info after `purchase` applied the new info, `apply` sets `isPro` back to false. | Any purchaser, only if RevenueCat's `customerInfo()` answers from a pre-purchase cache after the purchase result. Not shown to happen. | Not run. Ordering depends on SDK caching; the `PurchasesDelegate` added for C2 delivers the newer info afterwards, which bounds it either way. | `RootView.swift:146-152`, `StoreService.swift:136-151`, `:354` |

## Product calls (not counted: no cited promise, or a design choice)

1. **The review gate is out of reach for a one-child family.** `minimumPositiveMoments` is 2, but the catalog gives a child at most one hard deadline (job-based or Marketplace, never both; Medicaid, none and not sure have none). The repro's `atMostOneHardDeadlinePerChild` checks every coverage answer (result in the fixes doc). So for a one-child household B2 is the only way the ask is ever reached. Fixing B2 alone would leave the app asking nobody but twins' parents. This is the question Rollout S (the good-moment star prompt) answers; held for Jack.
2. `isPro` is not persisted (`StoreService.swift:104`). A Plus family cold-launching offline gets the launch reschedule with `Options.current` built from `isPro == false`, so suggested-date reminders, the digest and custom reminders are removed until the store answers. The `PurchasesDelegate` added in Rollout A receives RevenueCat's cached customer info right after configure, which should restore them on the same launch; the SDK's offline behaviour was not verified here.
3. Delivered (already shown) notifications stay in Notification Center after their task is ticked; only pending requests are cleared (`DeadlineReminderScheduler.swift:318-322`). A tap on one for a finished task opens that task, which is harmless.
4. The Sunday digest's week runs from Sunday 9:00 to the next Sunday 9:00, and dates are stored at UTC noon (`DateOnly`), which is before 9:00 in every US zone. A task due on a Sunday is in the previous Sunday's digest, not the one on its own day. Arguably correct ("reaches its date this week").
5. Two `reschedule` calls racing can interleave a remove-all with the other's adds (`DeadlineReminderScheduler.swift:301-309`): the second waits for the first only once, so a third arriving during that wait runs beside the second. Plans are computed from live objects at run time, so both write the same set; no route found where the result differs.

## State machines

### SM1. Entitlement and purchase (`StoreService`, `PlusPurchaseView`)

State: `isConfigured`, `isPro`, `localOverride`, `offerings`, `plans`, `isLoading`, `loadError`; per view `selection`, `isWorking`, `errorMessage`.

States: Unconfigured (simulator) / Configured, unknown (launch, before `customerInfo`) / Free / Plus. A pending Ask to Buy has no state at all at `8cf5b89` (C1).

Invariants: E1 `isPro` equals an active `BabyDocs+` (or fallback) entitlement after every `apply`; E2 every flip posts `babyDocsEntitlementChanged`, which reschedules reminders; E3 the buy button never promises a trial the account cannot take (`eligibleIntroLabel`); E4 the button is not left spinning (`defer { isWorking = false }`).

| From | Event | To | Invariant |
|---|---|---|---|
| Unconfigured | `start()` on device | Configured, unknown | none |
| Configured, unknown | `customerInfo()` ok | Free or Plus | E1, E2 |
| any | `refresh()` throws | unchanged, `loadError` set | E1 kept (no flip on failure) |
| Free | purchase ok with entitlement | Plus, conversion recorded | E1, E2 |
| Free | user cancels Apple's sheet | Free, no alert | E4 |
| Free | `paymentPendingError` | Free, error alert | C1 |
| Free (pending) | parent approves, app open | Free until next `.active` | C2 |
| Free | restore finds entitlement | Plus | E1 |
| Plus | lapse seen on a foreground refresh | Free | E1, E2 |
| any | scene `.active` during a purchase | `refresh()` races the purchase | C3 |

### SM2. Reminders (`DeadlineReminderScheduler`, `NotificationService`, `ReminderPreferences`)

State: pending `UNNotificationRequest`s with prefixes `deadline.`, `suggested.`, `custom.`, `digest.`; authorization status; two `UserDefaults` switches; `isPro`.

Invariants: N1 pending requests equal `plans(for:)` of the live open tasks after every reschedule (wholesale cancel and re-add); N2 hard-deadline warnings never depend on Plus or a switch; N3 hard warnings claim the 24-request budget first; N4 nothing is scheduled without permission, and a permission granted later in iOS Settings is picked up on the next `.active`.

| From | Event | To | Invariant |
|---|---|---|---|
| any | task ticked, dismissed, edited, child added, archived or restored, household edited, plan imported | rescheduled | N1 (every write path checked: `PlanView`, `TaskDetailView`, `ChildrenView` x4, `HouseholdEditorView`, `SharePlanSheet`, `OnboardingFlow`, `PlusView`, `SettingsView`) |
| any | entitlement flips | rescheduled | N2 (Plus-only plans added or removed) |
| any | scene `.active` | rescheduled, permission re-read | N4 |
| authorized | permission revoked in Settings | next `.active` cancels ours | N4 |
| any | custom reminder on a ticked task | skipped, value kept | the family's value is never rewritten |

No reachable invalid state found beyond product calls 3 to 5.

### SM3. Tasks and documents (`RequirementEngine`, `RequirementTask`, `DocumentItem`)

States per task: open / done (`completedAt`) / dismissed (`dismissedAt`) / retired (`deletedAt`, restorable). Per document: to find / in hand, identity = title within one child.

Invariants: T1 done and dismissed are exclusive (`setCompleted`, `setDismissed`); T2 the engine never rewrites completion, receipts or ticked documents; T3 a retired row is restored, never recreated; T4 ticking a document ticks every live row of that child with the same title.

| From | Event | To | Invariant |
|---|---|---|---|
| open | tick | done | T1 |
| done | untick | open | T1 |
| open | "does not apply" | dismissed | T1 |
| live | answer change stops the rule | retired, work kept | T2, T3 |
| retired | answer change restores the rule | live, work as left | T3 |
| (none) | answer change adds a rule | new row, documents all to find | **T4 broken (B1)** |
| to find | tick on Documents or task screen | in hand on every sibling row | T4 |
| any | failed save | rolled back, alert | `SaveFailureReporter` |

### SM4. Review ask (`ReviewPromptTracker`, `RootView`)

State: `appLaunchCount`, `firstAppOpenDate`, `lastRequestedDate`, `positiveMomentCount`, `hasPendingPositiveMoment`, `hasRequestedReviewThisSession`.

Invariants: R1 three launches and three days; R2 two deadlines beaten (B2, product call 1); R3 120-day cooldown in elapsed seconds; R4 never over the paywall or an incoming plan link; R5 suppressed in UI-test runs.

| From | Event | To | Invariant |
|---|---|---|---|
| idle | hard task ticked on time | moment pending, count + 1 | R2 |
| idle | same task unticked and ticked | count + 1 again | **R2 broken (B2)** |
| pending | 1.2 s later, gates pass | asked, cooldown stamped | R1, R3, R4 |
| pending | paywall or link sheet up | stays pending | R4 |

### SM5. First run and navigation (`AppNavigator`, `RootView`)

State: `isIntakeFinished`, `selectedTab`, `pendingSeed`, `seedFailed`, `pendingTaskID`, `isShowingPaywall`. Held by `IntakeGateTests` already; a plan imported over the intake ends it, a notification tap on a cold launch is held until the row exists and then cleared. No invalid transition found.

### SM6. Vault (`VaultStore`)

State: `isUnlocked` (reset on `.inactive` and `.background`), files on disk, `VaultDocument.pageFileNames`, tombstones. Face ID makes the scene inactive before `evaluatePolicy` returns, so `lock()` runs before `isUnlocked = ok`, which ends unlocked as intended. Orphan and tombstone sweeps are guarded by `VaultSweepTests`. No invalid transition found.
