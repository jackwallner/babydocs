# Baby Docs Project Guide

A newborn administrative concierge for US families: what paperwork applies to
*this* household, when each window closes, what documents to bring, and a link
to the official office that issues it. XcodeGen project/scheme: `BabyDocs`, sim
lease owner `babydocs`.

Working App Store name **Baby Docs: Newborn Paperwork**, home-screen name
**Baby Docs**. It is not a baby tracker: there is no feed log, no weight, no
growth chart, and adding one would put it in a category with fifty better-funded
competitors and no reason to pick this.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency)
- SwiftData, on one device. **No backend, no accounts, no CloudKit.**
- XcodeGen (`project.yml`). Targets: iOS 17+
- RevenueCat, entitlement `BabyDocs+`, resolved as `store.isPro`

## Targets / bundle IDs
- `BabyDocs`: `com.jackwallner.babydocs`
- `BabyDocsTests`: `com.jackwallner.babydocs.tests`
- `BabyDocsUITests`: `com.jackwallner.babydocs.uitests`
- RevenueCat app: `appl_LIrLhMIPlUeqSjOlWhYtkPSTvtP`
- No App Group (no widget or watch target in v1)
- Entitlements file is deliberately empty. See the comment in it before adding one.

## There is no server, and that is the architecture

Supabase, `AuthService`, `FamilyService`, `SyncEngine`, the outbox, the cursors
and four SQL migrations were deleted, not disabled. A project was never
provisioned, so nothing was ever hosted and no user was ever affected.

## Architecture

`Shared/Rules/` is the product.

- `RequirementCatalog.swift`: twenty-three rules, each a value with an `applies`,
  a `deadline`, a `detail`, a document checklist, an official link and a
  **source citation with the date someone last read it**. Rules are pure
  functions of `RuleInput`, a plain struct, so the whole catalog is testable
  without SwiftData, a container or a network.
- `TaskPlanner.swift`: bucketing, sorting, the home-screen overview and the one
  place a deadline is phrased in words.
- `PlanTimeline.swift`: the same tasks read as an order rather than as dates.
  Pure, and deliberately separate: `TaskPlanner` answers "when does this close",
  which is always somebody else's date, and this answers "what should I do this
  week", which is the app's own opinion and is labelled as one.

`Shared/Services/`: `StoreService`, `NotificationService` (local only),
`DeadlineReminderScheduler`, `ReminderPreferences` (what else may speak, Plus
only), `PlanExporter` (summary + employer packet), `CalendarExporter` (the dates
as an `.ics`, and nothing a parent typed), `PlanSeed` (the shareable link),
`VaultStore` (document photographs), `LocationLookup` (one-shot state/county
prefill), `BabyModelStore`.

`BabyDocs/Views/` is the UI. `BabyDocs/Support/SampleData.swift` seeds previews
with a family whose answers switch on the awkward rules (unmarried parents not
yet on the record, a job-based plan, a birth in the one verified state, one
thing sent and overdue back) rather than one that triggers nothing.

## Rules that hold everywhere
Condensed from the deep notes below; the reasoning behind each one lives there.
- No backend and no accounts. If live sync is ever genuinely wanted, the answer is CloudKit `CKShare`, not a server.
- Never bulk import state or county office URLs into `StateVitalRecords` or `USCounties`: a generic-but-correct link beats a specific-but-guessed one. No fee, processing time or turnaround is ever hardcoded.
- `RequirementEngine` owns the rule and the family owns the work: completion, assignment, receipts and ticked documents are never rewritten.
- A date is `hard` only if the app can name the authority that set it. Hard-deadline warnings are free forever and claim the pending-notification budget first.
- Free is every deadline, every link, every document list, every child, the two hard-window warnings and sending the plan. Further children must never be gated again. Vault access survives a lapse.
- What Plus gates lives in the binary (`SummaryShareControl`, `TaskDetailView`, `DocumentsView.addButton`, `PlusToolsView`, `DeadlineReminderScheduler.Options`), and those places drift apart. `asc-readiness.py`'s `PAID_FEATURES` is the check that the description and the App Review notes still say what the binary charges for.
- Never put a question in front of `requestReview()`.
- Sales copy may never imply live sync, and "no server" is a claim about household data, never about the purchase.
- `docs/plan.html` must stay published at that exact path, and the plan payload stays in the URL fragment, never the query string.
- `design.md` is the design system: run `scripts/design-audit.py` before a release. `AppTheme.margin` is the only horizontal inset.

## Deep notes (load on demand)
These files load automatically when you read a file matching their `paths:`. Agents that do not auto-load rules (Codex, Cursor) should open the file for the area they are touching. Record new area-specific learnings in the matching file, not here.

| File | Covers | Read when |
|---|---|---|
| `.claude/rules/rules-engine.md` | `StateVitalRecords`, `USCounties`, `RequirementEngine`, rules showing their working, no turnaround times | The catalog, office links, the engine |
| `.claude/rules/reminders-and-deadlines.md` | Two dates are hard, the rest are not | Reminders, the notification budget, `hard` deadlines |
| `.claude/rules/plus-pricing-and-review.md` | Pricing, free vs Plus, vault lapse, the review ask, where Plus gates drift, the pitch tab | `StoreService`, the paywall, Plus tools, review prompt, metadata about paid features |
| `.claude/rules/intake-and-plan-screens.md` | "Not sure" answers, ticked tasks and documents, the intake's shape and footer | Onboarding, the plan, documents, task rows |
| `.claude/rules/design-system.md` | `design.md` and the audit, one margin and one colour system, the tab-bar inset | Any view or layout work |
| `.claude/rules/no-server-and-sharing.md` | Why there is no server, what sales copy may claim, the privacy claim, `docs/plan.html` | Sharing, `PlanSeed`, privacy copy, the site, anything tempting you to add sync |

## App-specific notes

- **The app never files anything.** Drafts, checklists, calendar-shaped
  reminders, and deep links to official pages. Nothing is submitted on a user's
  behalf, and the copy says so at the point of every link. This is not caution
  for its own sake: automatic filing of a parentage, IRS or insurance form is a
  liability the app cannot carry and a promise it cannot keep.
- **No Social Security number is ever stored as data, and no vault image ever
  leaves the device.** `Child` tracks the *status* of the SSN, never the number.
  The vault is the one place an SSN can exist here at all, as pixels in a
  photograph, and that is contained rather than forbidden: files live in the app
  container under `.completeFileProtection`, excluded from every backup, and
  `VaultDocument` holds filenames only. `VaultStore` deliberately exposes no API
  returning a `URL`, so no share sheet or exporter can reach an image even by
  accident. `PlanExporter` (summary *and* employer packet) prints the status and
  never a number, and `SourceIntegrityTests` asserts it.
- **A failed write is not allowed to look like a saved one.** Every save went
  through `try? context.save()`, on an app whose store is the only copy that
  will ever exist. `SaveFailureReporter` carries the error to a single alert in
  `RootView`, so a parent who ticks a task and sees it move is not being told
  something the disk disagreed with.
- Keyword-field notes and the acquisition plan are in `aso-plan.md`. App Store
  search is not the channel, and the numbers now say so rather than the brief:
  every tracked term with popularity at or above 25 has difficulty at or above
  62 and resolves to somebody else's field, while every right-intent term sits
  at Astro's floor. The audience is reachable through employers, hospitals, OB
  practices and benefits platforms, and through the free shared plan link.
- **Every local write goes through `LocalRecord`.** After a create or an edit,
  call `recordLocalChange()`; to delete, call `tombstone()`. Reads go through
  `child.liveTasks` and friends rather than the raw relationship. With sync gone
  the reason changed but the rule did not: a tombstone is what makes a mis-swipe
  on a task carrying six months of receipts recoverable. The one hard delete is
  vault image files, which are removed immediately on request rather than left
  orphaned on disk.
- **Task ids are derived from (child, catalog key), so a regenerated plan must
  reuse its rows.** Anything that creates a generated task goes through
  `RequirementEngine`, never by hand.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): the global agent rules + the `ios-dev` skill.
