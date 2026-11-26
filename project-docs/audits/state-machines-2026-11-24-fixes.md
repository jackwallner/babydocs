# Fixes for the 2026-11-24 state machine audit

Fixes for the claims in `state-machines-2026-11-24.md`, after a skeptical re-read of each.

**Summary: 2 claims (repro written, not yet run). 1 fixed, 1 held for Jack, 0 skipped.** The fix is committed but unverified: no test in this run reached a GitHub Mac. The three code path items were not counted; two are closed by Rollout A, which shipped in the same run.

## Phase 2, skeptical review

- **B1 survives.** The route is the shipping UI end to end: `DocumentsView.setOnHand` ticks every live row of one child with the title, `HouseholdEditorView` (`:114-160`) edits coverage and leave and calls `RequirementEngine.reconcileAll` (`:34`), and the engine's `case (true, .none)` inserts the new task's rows through `syncDocuments`, which set `isOnHand` false. The test drives the engine, not a hand-built row, and its control shows an unrelated document on the same new task stays to find, so it does not prove a broken setup. "Not sure" coverage answered later is the route the app's own design expects.
- **B2 survives as a bug, but its fix is held.** `PlanView.toggle` and `TaskDetailView.toggleDone` call `recordCompletion` on every tick with no memory of the task, so the route is real. The repro's evidence test shows every coverage answer gives a child at most one hard deadline, so for a one-child family B2 is the only way the "two deadlines beaten" gate is ever met. Fixing B2 alone would make the rating ask unreachable for most families, which is a change to when the review ask happens; that is Rollout S's question and a product call.
- **C1 and C2 stay code path.** No RevenueCat seam exists to prove them headless. Both are covered by Rollout A (pending mapping, `PurchasesDelegate`).
- **C3 stays code path.** Whether `customerInfo()` can answer with pre-purchase info after the purchase applied newer info is SDK behaviour that was not shown. The delegate bounds it. Not fixed.

## Claims

| ID | Outcome | Commit | Regression test (`BabyDocsTests/StateMachineRegressionTests.swift`) | What changed |
|---|---|---|---|---|
| B1 | Fixed | `fix: a task added by a changed answer no longer asks for a document already in hand` | `newTaskInheritsDocumentAlreadyInHand` (the repro), `coverageAnsweredLaterInheritsDocument` (Not sure, then Marketplace), controls `untickedDocumentStaysToFind`, `tickStopsAtTheChild` (twins: one baby's certificate says nothing about the other's), upgrade `storedRowsAreUntouched` | `RequirementEngine.syncDocuments` gives a newly inserted `DocumentItem` the in-hand state (and its date) of a live sibling row of the same child with the same title, the identity the Documents tab and the task screen already use. Rows already in the store are never rewritten, and a pass over an unchanged family still writes nothing. |
| B2 | Held for Jack | none | none | See below. |
| C1 | Closed by Rollout A | `feat: show a pending Ask to Buy as waiting for approval` | `PurchaseFailureTests` | Pending maps to `PurchaseFailure.waitingForApproval`, shown inline, never the alert. |
| C2 | Closed by Rollout A | same | none (needs a RevenueCat seam) | `StoreService` is RevenueCat's `PurchasesDelegate`; customer info updates run the same `apply`. |
| C3 | Not fixed (code path) | none | none | Bounded by the delegate. |

## Held for Jack

- **B2 and product call 1: the review gate.** Decision: should the automatic rating ask follow one hard deadline met on time (count each task once, so a corrected tick cannot count twice), rather than two? Recommendation: yes, one, counted once per task, because a one-child family can only ever beat one hard deadline, so today's gate is reached only by ticking a task twice or by parents of twins. This changes when the review ask happens, so it belongs with Rollout S (out of scope for this run). The one-line change is `ReviewPromptTracker.minimumPositiveMoments = 1` plus a stored set of task ids in `recordCompletion`.

## Skipped

None.

## Tests

- **Not run.** The repro on the starting commit (`gh-sim test --scheme BabyDocs --only BabyDocsTests/StateMachineAuditRepro`, run `bd-start-imacb6ee-1125-152333-29059`, GitHub run `45721010315`) stayed queued for 60 minutes without starting and was cancelled. The full suite on the fixed branch was queued behind it and stopped before upload.
- Still to do on another Mac: run the repro on `8cf5b89` (B1 and B2 should fail, the controls pass), then the full suite on this branch (`gh-sim test --scheme BabyDocs`), where every `StateMachineRegressionTests` test should pass. If B1's repro passes on `8cf5b89`, the claim is wrong and the fix should be reverted.
