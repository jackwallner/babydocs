# Baby Docs — Project Guide

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
- `BabyDocs` — `com.jackwallner.babydocs`
- `BabyDocsTests` — `com.jackwallner.babydocs.tests`
- `BabyDocsUITests` — `com.jackwallner.babydocs.uitests`
- RevenueCat app: `appl_LIrLhMIPlUeqSjOlWhYtkPSTvtP`
- No App Group (no widget or watch target in v1)
- Entitlements file is deliberately empty. See the comment in it before adding one.

## There is no server, and that is the architecture

Supabase, `AuthService`, `FamilyService`, `SyncEngine`, the outbox, the cursors
and four SQL migrations were deleted, not disabled. A project was never
provisioned, so nothing was ever hosted and no user was ever affected.

The reasoning is worth keeping because it is what stops it coming back. The
app's entire state is a dozen household answers plus a small amount of work the
family does to it. A plan is a *pure function* of those answers, so the second
parent does not need a replica of the first parent's rows, they need the
answers, and `PlanSeed` fits them in a link. Running Postgres, auth, RLS and a
conflict-resolving sync engine for a few kilobytes that matter for ninety days
was the wrong shape, and it made the app the custodian of newborn PII in
exchange for a one-time purchase.

If live two-way sync is ever genuinely wanted, CloudKit `CKShare` is the answer,
not a server: Apple hosts it in the users' own iCloud. Nothing is lost by having
waited, because `RequirementEngine` still derives row ids from (child, catalog
key), so two phones independently generate byte-identical rows, which is exactly
the property a merge needs.

## Architecture

`Shared/Rules/` is the product.

- `RequirementCatalog.swift` — twenty rules, each a value with an `applies`,
  a `deadline`, a `detail`, a document checklist, an official link and a
  **source citation with the date someone last read it**. Rules are pure
  functions of `RuleInput`, a plain struct, so the whole catalog is testable
  without SwiftData, a container or a network.
- `StateVitalRecords.swift` — per-state birth certificate offices, now all fifty
  states and DC rather than California alone. **Never bulk import a list of state
  URLs into here**: a generic-but-correct link beats a specific-but-guessed one,
  because a parent who follows a wrong link to a wrong office loses a fortnight.
  What made fifty possible without breaking that rule is admitting there are two
  depths and printing which is which. `check` is `.pageRead` where the office's
  own page was read end to end, and `.summaryChecked` where the address returned
  a live page on the state's own domain and every sentence of the note was
  confirmed against that office's published text without a full read. The UI
  says which; flattening them into one tick is the thing not to do. Fees and
  processing times stay out (same reason as the turnaround rule below), as does
  every office below state level: where a county or town office is faster the
  note says so in words and lets the parent find their own, because three
  thousand guessed county URLs is the failure this file exists to prevent. The
  five territories still fall back to the federal directory and say so.
- `USCounties.swift` — 3,110 county names from the Census, and *only* names.
  Same rule as above, harder: it routes nothing. It exists to spell a county
  correctly and to let CoreLocation prefill one. A generated list of three
  thousand county clerk URLs would be wrong often enough to cost somebody a
  fortnight, so the birth certificate link stays at state level.
- `RequirementEngine.swift` — reconciles the catalog into `RequirementTask`
  rows. Three rules, all load-bearing: the engine owns the rule and the family
  owns the work (completion, assignment, receipts and ticked documents are never
  rewritten); row ids are derived from (child, catalog key), which is what lets a
  rule that stops applying be retired and later *restored* with the family's work
  attached rather than reinserted as a duplicate; and a pass that changes nothing
  writes nothing.
- `TaskPlanner.swift` — bucketing, sorting, the home-screen overview and the one
  place a deadline is phrased in words.

`Shared/Services/`: `StoreService`, `NotificationService` (local only),
`DeadlineReminderScheduler`, `PlanExporter` (summary + employer packet),
`PlanSeed` (the shareable link), `VaultStore` (document photographs),
`LocationLookup` (one-shot state/county prefill), `BabyModelStore`.

`BabyDocs/Views/` is the UI. `BabyDocs/Support/SampleData.swift` seeds previews
with a family whose answers switch on the awkward rules (unmarried parents not
yet on the record, a job-based plan, a birth in the one verified state, one
thing sent and overdue back) rather than one that triggers nothing.

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
- **Two dates are hard, the rest are not.** Job-based health plans must allow at
  least 30 days after a birth; the Marketplace is 60. Those are the
  only deadlines `DeadlineReminderScheduler` will schedule a notification for. A
  suggestion that fires at 9am is what teaches someone to switch the whole
  category off, and then they miss the one that mattered.
  - The rule is enforced at the catalog, not at the scheduler, because the
    scheduler schedules everything marked `hard`. The dependent care FSA broke
    it once: 30 days after the birth, drawn red, with a notification, while its
    own `basis` said the number belongs to the employer's plan document. A date
    is only `hard` if the app can name the authority that set it. `fsaWindowIsNotHard`
    holds the line.
  - **Where** the Marketplace family goes is a separate question from **when**,
    and it is asked (`MarketplaceKind`). The 60 days is the same for a state-run
    exchange; the site, the account and the documents are not, and HealthCare.gov
    tells a Californian it does not serve them. Unknown and state both route to
    HealthCare.gov's own state picker, which is the `StateVitalRecords` trade
    again: federal, read, and correct, over specific and guessed.
- **"Not sure" is an answer, everywhere it is offered.** Coverage and parentage
  both filtered their `.unknown` case out of the intake and blocked Continue
  until something was picked. That does not produce knowledge, it produces a
  guess, and a guess turns on the wrong hard deadline or turns off the
  legally significant parentage task. Unknown coverage generates
  `coverageUnknown` at the top of the plan instead: a real task about finding
  out, with no date the app invented.
- **A failed write is not allowed to look like a saved one.** Every save went
  through `try? context.save()`, on an app whose store is the only copy that
  will ever exist. `SaveFailureReporter` carries the error to a single alert in
  `RootView`, so a parent who ticks a task and sees it move is not being told
  something the disk disagreed with.
- **Every rule shows its working.** Each task carries the government URL its
  rule came from and the date it was last checked, visible on the task itself
  rather than behind an info button. A rules app whose rules quietly go stale is
  worse than no app, so `RequirementCatalog.reviewedOn` is surfaced in Settings.
- **No turnaround time is ever hardcoded.** Follow-up tracking asks the family
  what the office told them and nudges from that. Processing times move
  constantly and differ by county, so a bundled figure would be a citation the
  app cannot support, which is the same rule as `StateVitalRecords`.
- **Pricing: weekly leads, lifetime keeps.** 3-day trial into $4.99/week, with
  $29.99/year and $59.99 once. Weekly is unusual and deliberate: the need is
  intense for six to thirteen weeks and then genuinely over, so a weekly price is
  the honest one for a need that ends. Lifetime is the vault, which does not end.
  The yearly mostly exists to make the comparison legible.
  - The 3-day trial is against the benchmark: SOSA 2026 puts ≤4-day trials at
    25.5% trial-to-paid against 37.4% for 5-9 days, and this fleet's 7-day trials
    convert at 44.7%. It is shipped as a deliberate bet that a trial competing
    with a real deadline behaves differently. **Compute
    `conversions / (conversions + expirations)`** before comparing, because RC's
    headline number includes pending trials and understates by ~11pp.
- **Free is every deadline, every link, every document list, and sending the plan
  to the other parent.** A deadline behind a paywall is a deadline the app caused
  someone to miss. Plus is the work *around* the deadlines: the vault beyond the
  first twelve weeks, follow-up tracking, the employer packet, the printable
  summary, and further children.
- **Vault access survives a lapse.** Lapsing stops you *adding*; it never takes
  back a photograph already there. The paywall says so. Anything else is holding
  a parent's documents hostage, and Apple's refund team would agree.
- **Sales copy may only promise what the build does.** There is no live sync and
  there is not going to be one, so no paywall bullet, App Store description or
  landing-page card may imply two phones staying in step. Sending the plan is
  real, and it is free, so it is not sold either.
- **"No server" is a claim about household data, never about the purchase.**
  RevenueCat receives an anonymous app user ID and purchase history, so any copy
  that says *nothing* is uploaded or that only the person holding the iPhone can
  see anything is false, and a privacy policy that is false about a payment
  processor is the kind of false App Review reads carefully. The honest form is
  the one in `docs/privacy-policy.html`: no account and no household-data
  backend, purchases go to Apple and RevenueCat, and the vault, the answers, the
  notes and the plan go nowhere. `PrivacyInfo.xcprivacy` declares purchase
  history, not linked, not tracking, for app functionality **and analytics**,
  the last because the RevenueCat dashboard is looked at.
- Keyword-field notes and the acquisition plan are in `aso-plan.md`. App Store
  search is not the channel, and the numbers now say so rather than the brief:
  every tracked term with popularity at or above 25 has difficulty at or above
  62 and resolves to somebody else's field, while every right-intent term sits
  at Astro's floor. The audience is reachable through employers, hospitals, OB
  practices and benefits platforms, and through the free shared plan link.
- **The review ask is `requestReview()` with nothing in front of it, and the
  only thing the app decides is when.** `ReviewPromptTracker` chooses the
  moment: a task with a **hard** deadline ticked **before** that deadline closed
  (`recordCompletion`), two of them plus three launches and three days, then a
  120-day cooldown. The window is six to thirteen weeks, so there is time for
  about one ask, and spending it during the fortnight a birth certificate has
  not arrived buys a one-star review. App Store ID `6799785786`.
  - **Never put a question in front of it again.** This shipped for a while as
    an enjoyment gate: "is this helping?", yes to a Write-a-review button, no to
    a mail draft. That is the custom prompt App Review forbids, and the reason
    is not pedantry: a branch that only sends happy people to the store is the
    thing ratings are supposed to measure. `FeedbackSheet` is what survived, and
    it is support, open to everyone from Settings at any time, leading nowhere
    near the App Store.
- **What Plus gates lives in four places that drift apart.** The binary
  (`SummaryShareControl`, `TaskDetailView`, `DocumentsView.addButton` and
  `ChildrenView`) charges for follow-up tracking, further children, the vault
  after twelve weeks, the printable summary and the employer packet. The
  description and the App Review notes have to say the same thing, and both
  once said the summary and the packet were free. `asc-readiness.py` now asserts
  it, because nothing recompiles when a `.txt` file changes.
- **A ticked document does not disappear.** The Documents tab was one list,
  "still to find", so ticking a row was indistinguishable from deleting it. That
  is the worst possible feedback for the one gesture the screen exists for: the
  question at the counter is not "what is left" but "did I already deal with
  this one", and a list that only answers the first makes a parent re-check the
  drawer. Ticked items move, visibly, into "In hand", they can be unticked from
  there, and every row links through to the task that asks for it.
- **The intake fits on one screen and unfurls the rest.** Every question used to
  carry its explanation as a form footer and its Continue button as the last row
  of the form, so on most phones at most text sizes the way forward was below
  the fold: an intake that looks like a dead end on question two is abandoned on
  question two. `OnboardingFooter` pins Continue to the bottom of every step and
  `OnboardingDisclosure` folds the paragraph away behind "Why we ask". The copy
  is not cut, it is collapsed, and the same shape carries the four explained
  choices.
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
- **`docs/plan.html` is part of the app, not the marketing site.** Every shared
  plan link points at it (`PlanSeed.webBase`), and those messages sit in inboxes
  longer than the build that wrote them, so the page has to stay published at
  that exact path and no build whose share link is live may ship before the page
  is. The payload rides in the URL *fragment*, which browsers never send to a
  server, so the page receives nothing about the family. Do not move it into the
  query string.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.

After any app-code push, run `./scripts/testflight.sh`.
