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
- SwiftData as the local mirror, plus Supabase for shared families. No CloudKit.
- XcodeGen (`project.yml`). Targets: iOS 17+
- RevenueCat, entitlement `BabyDocs+`, resolved as `store.isPro || family.hasPlus`

## Targets / bundle IDs
- `BabyDocs` — `com.jackwallner.babydocs`
- `BabyDocsTests` — `com.jackwallner.babydocs.tests`
- `BabyDocsUITests` — `com.jackwallner.babydocs.uitests`
- RevenueCat app: `appl_LIrLhMIPlUeqSjOlWhYtkPSTvtP`
- No App Group (no widget or watch target in v1)

## Architecture

`Shared/Rules/` is the product. Everything else is plumbing ported from `~/aging`.

- `RequirementCatalog.swift` — twenty rules, each a value with an `applies`,
  a `deadline`, a `detail`, a document checklist, an official link and a
  **source citation with the date someone last read it**. Rules are pure
  functions of `RuleInput`, a plain struct, so the whole catalog is testable
  without SwiftData, a container or a network.
- `StateVitalRecords.swift` — per-state birth certificate offices. A state is
  only ever presented as *verified* when a human has read that state's own page
  and stamped the date. Everything else falls back to the federal directory,
  which carries a state picker. **Never bulk import a list of state URLs into
  here**: a generic-but-correct link beats a specific-but-guessed one, because a
  parent who follows a wrong link to a wrong office loses a fortnight.
- `RequirementEngine.swift` — reconciles the catalog into `RequirementTask`
  rows. Three rules, all load-bearing: the engine owns the rule and the family
  owns the work (completion, assignment, receipts and ticked documents are never
  rewritten); row ids are derived from (child, catalog key) so both parents'
  phones generate the same plan offline; and a pass that changes nothing writes
  nothing, or every launch would put the whole plan in the outbox.
- `TaskPlanner.swift` — bucketing, sorting, the home-screen overview and the one
  place a deadline is phrased in words.

`Shared/Services/` is the ported infrastructure: `AuthService` (offline-session
rules), `FamilyService` (membership, roles, invites, all through security-definer
RPCs), `SyncEngine`/`SyncRemote`/`SyncCoordinator` (offline-first two-way sync
with an outbox, a compound server-time cursor and per-entity conflict rules),
`StoreService`, `NotificationService`, `DeadlineReminderScheduler`,
`PlanExporter`.

`BabyDocs/Views/` is the UI. `BabyDocs/Support/SampleData.swift` seeds previews
with a family whose answers switch on the awkward rules (unmarried parents not
yet on the record, a job-based plan, a birth in the one verified state) rather
than one that triggers nothing.

## App-specific notes

- **The app never files anything.** Drafts, checklists, calendar-shaped
  reminders, and deep links to official pages. Nothing is submitted on a user's
  behalf, and the copy says so at the point of every link. This is not caution
  for its own sake: automatic filing of a parentage, IRS or insurance form is a
  liability the app cannot carry and a promise it cannot keep.
- **No Social Security number is ever stored.** `Child` tracks the *status* of
  the SSN, never the number, and `supabase/migrations/0002` has a comment saying
  so where the column would go. `PlanExporter` prints the status and never a
  number, and a test asserts it.
- **Two dates are hard, the rest are not.** Job-based health plans must allow at
  least 30 days after a birth; the Marketplace is generally 60. Those are the
  only deadlines `DeadlineReminderScheduler` will schedule a notification for. A
  suggestion that fires at 9am is what teaches someone to switch the whole
  category off, and then they miss the one that mattered.
- **Every rule shows its working.** Each task carries the government URL its
  rule came from and the date it was last checked, visible on the task itself
  rather than behind an info button. A rules app whose rules quietly go stale is
  worse than no app, so `RequirementCatalog.reviewedOn` is surfaced in Settings.
- **Retention is the business risk, not acquisition.** The need is intense for
  30 to 90 days and then genuinely over, so the paywall leads with a one-time
  purchase and treats the subscriptions as alternates. Selling a subscription
  here sells a cancellation.
- **Free tier is one child.** Every deadline, document list and official link is
  free. A deadline behind a paywall is a deadline the app caused someone to miss.
- **Sales copy may only promise what `SupabaseConfig.isConfigured` can deliver.**
  While sharing is off, no paywall bullet, App Store description, landing-page
  card or in-app footer may promise the second parent; Plus sells further
  children and the one-page summary instead. The two in-app strings that mention
  the other parent (`ChildrenView`, `TaskDetailView`) are gated on that flag so
  they come back on their own. `FamilyView` already explains the state rather
  than hiding it. Put the sharing copy back when the backend ships, and not a
  build before.
- Free keyword-field notes and the acquisition plan are in `aso-plan.md` once
  that exists. Assume App Store search is not the channel until proven
  otherwise: the audience is reachable through employers, hospitals, OB
  practices and benefits platforms, and that is what the research says.
- **Supabase is not provisioned yet.** `SupabaseConfig.isConfigured` is false
  while `SUPABASE_ANON_KEY` in `Info.plist` is empty, and the whole app is a
  complete local-only tracker in that state, not a degraded one. The migrations
  in `supabase/` are written and ready. To switch sharing on: create the
  project, put the ref and publishable key in `Info.plist`, write
  `~/.babydocs_credentials` with `BABYDOCS_SUPABASE_PROJECT_REF` and
  `BABYDOCS_SUPABASE_ACCESS_TOKEN`, then `./scripts/db-apply.sh`.
  `scripts/testflight.sh` skips its schema-drift check until that file exists.
- **Every local write goes through `SyncableRecord`.** After a create or an
  edit, call `recordLocalChange()`; to delete, call `tombstone()`. Never
  `context.delete` a synced row: the push reads the row to build its DTO, so a
  row removed outright can never be sent and the delete dies on that one phone.
  Tombstones live in the store until `markSynced` purges them, which is why
  reads go through `child.liveTasks` and friends rather than the raw
  relationship. (The one legitimate hard delete is
  `FamilyService.forgetFamilyLocally`, which is a wipe, not a delete.)
- **Task ids are derived from (child, catalog key), so a regenerated plan must
  reuse its rows.** Anything that creates a generated task goes through
  `RequirementEngine`, never by hand. Two rows with one server key is the
  failure this avoids.
- Roles are cached in `Family` so gating works offline. The UI mirrors the RLS
  policies; it never is the enforcement.
- **`docs/join.html` is part of the app, not the marketing site.** Every
  invitation message points at it (`InviteLink.webBase`), and those messages sit
  in inboxes longer than the build that wrote them, so the page has to stay
  published at that exact path and no build whose invite link is live may ship
  before the page is.
- Migrations are append-only once applied. Fix forward, never edit a shipped file.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.

After any app-code push, run `./scripts/testflight.sh`.
