# Baby Docs audit and product blueprint

Audit date: 2026-08-11

Repository: /Users/jackwallner/babydocs

Product: Baby Docs: Newborn Paperwork

## 1. Purpose of this document

This is a combined code audit, product audit, source-integrity review, release review, and forward product blueprint for Baby Docs.

It is written so a later agent can implement the next version without having to rediscover the product thesis, the current behavior, the failure modes, the missing coverage, or the order in which the work should happen.

The intended outcome is not a larger generic baby app. Baby Docs should remain a newborn administration concierge for United States families. It should help a tired parent answer five questions:

1. Does this apply to my household?
2. What is the next action?
3. When does the important window close?
4. What should I bring, save, or ask for?
5. How will I know the work actually went through?

The app must not file forms, make legal or tax decisions for a parent, store Social Security numbers, pretend that an agency accepted a submission, or turn into a feeding, sleep, growth, or health tracker.

## 2. Success criterion for the next implementation

The next implementation is successful when a parent can complete a trustworthy newborn-administration plan offline, understand which deadlines are statutory versus plan-specific versus suggested, preserve proof of every action without entering a Social Security number, recover safely from a bad edit or failed sync, and find the authoritative source for every rule. A second parent can be added only after account isolation, synchronization, invitations, and conflict resolution are demonstrably safe.

## 3. Audit method and evidence

The review covered:

- The XcodeGen project and build settings.
- SwiftUI screens and navigation.
- SwiftData models and persistence behavior.
- The pure rule catalog and reconciliation engine.
- Planning, deadline, export, notification, StoreKit, auth, family, and sync services.
- Supabase migrations and deployment scripts.
- Unit and UI tests.
- App Store metadata, landing pages, support, terms, privacy, and invitation pages.
- A headless iOS simulator build and screenshots of the main flows.
- Current official government source pages for the most consequential time windows.

Verification performed on 2026-08-11:

- xcodegen generate completed.
- A headless iPhone 17 Pro from the babydocs simulator pool was used. Simulator.app was not opened.
- xcodebuild test -project BabyDocs.xcodeproj -scheme BabyDocs -destination "id=2C7A80C1-1228-411A-B9AD-A7DEED683F79" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO passed.
- 62 unit tests passed across 5 suites.
- 3 UI tests passed.
- Screenshots were exported from the xcresult and visually inspected.
- The simulator lease was returned.
- The working tree was clean before this audit file was created.

Passing tests are useful evidence that the current intended happy paths work. They are not evidence that the sync, source stewardship, paywall, account isolation, accessibility, or edge-case paths are safe. Most of the serious findings below are exactly the kind of defects a narrow happy-path suite will miss.

Warnings observed during the simulator run were Xcode or simulator environment warnings about build numbers, Core Animation measurements, WebKit accessibility loader duplication, and debugger snapshots. They did not fail the build or tests. They should not be mistaken for application correctness.

## 4. Executive verdict

Baby Docs has a clear and valuable product thesis. The best existing choices are unusually disciplined:

- It refuses to become a baby tracker.
- It keeps all deadlines, documents, and official links in the free tier.
- It treats the rule catalog as the product rather than burying logic in views.
- It makes tasks pure functions of a small RuleInput.
- It derives task IDs deterministically from child and catalog key.
- It preserves family work when the rules change.
- It exposes the source URL and review date on the task.
- It stores Social Security status rather than the number.
- It distinguishes hard deadline reminders from general suggestions.
- It intentionally keeps sharing off while Supabase is not ready.
- It has a coherent local-only experience instead of presenting an empty shell.

The current build is not ready to switch on shared families or present itself as a fully trustworthy paperwork system. It is best described as a promising local-only prototype with a strong architecture, a useful first catalog, and production-level risks in four areas:

1. Sync and account isolation can lose or expose data.
2. The catalog contains source URLs that are technically government domains but semantically wrong for the rule they support.
3. The product model is too coarse for plan-specific deadlines, proof of submission, blocked work, corrections, and real-world follow-up.
4. Several current UI and entitlement details contradict the intended product promise.

The highest-value path is not “add twenty more tasks.” It is:

1. Make local persistence, rule reconciliation, export, and source provenance safe.
2. Turn a task from a Boolean checklist row into a small evidence-backed workflow.
3. Make the deadline engine explicit about certainty and jurisdiction.
4. Complete synchronization and account isolation before advertising family sharing.
5. Add only the newborn administration paths that reduce real missed-deadline risk.

## 5. Current product map

### 5.1 Runtime flow

The current flow is:

1. BabyDocsApp creates a SwiftData container, boots cached auth and family state, starts StoreKit, notifications, auth refresh, family refresh, and sync.
2. RootView shows onboarding when there is no child. Otherwise it presents Plan, Children, Family, and Settings tabs.
3. Onboarding collects one baby, residence state, birth state, parentage, insurance kind, dependent-care FSA, parental leave, passport, 529, and Trump Account preferences.
4. RequirementEngine reconciles RequirementCatalog rules into RequirementTask rows.
5. TaskPlanner buckets tasks and creates the home overview.
6. TaskDetailView exposes the description, deadline basis, documents, assignment, receipts, notes, official link, source footnote, and completion controls.
7. DeadlineReminderScheduler schedules local reminders only for employer coverage and Marketplace coverage hard windows.
8. PlanExporter creates a plain-text one-page summary.
9. FamilyView is a configured-backend path for sign-in, family creation, invitations, membership, and sync. In the current build, SupabaseConfig.isConfigured is false, so the app is intentionally local-only.
10. StoreService provides lifetime, yearly, and monthly Plus products, with the simulator using the StoreKit configuration file.

### 5.2 Current source map

| Area | Main files | Current role |
| --- | --- | --- |
| Domain model | Shared/Models/BabyModels.swift | SwiftData entities, enum inputs, documents, receipts, notes |
| Rule catalog | Shared/Rules/RequirementCatalog.swift | Twenty catalog rules, applicability, deadline, copy, docs, links, source citations |
| State vital records | Shared/Rules/StateVitalRecords.swift | One verified state entry, federal fallback |
| Reconciliation | Shared/Rules/RequirementEngine.swift | Deterministic task creation, updates, tombstones, document sync |
| Planning | Shared/Rules/TaskPlanner.swift | Buckets, overview counts, deadline wording |
| Persistence | Shared/Services/BabyModelStore.swift | Model container and fallback behavior |
| Sync | Shared/Services/SyncEngine.swift, SyncRemote.swift, SyncCoordinator.swift | Pull, push, cursors, outbox, merge |
| Auth and family | Shared/Services/AuthService.swift, FamilyService.swift | Cached session, membership, invites, roles |
| Reminders | Shared/Services/NotificationService.swift, DeadlineReminderScheduler.swift | Local deadline notifications and partial remote token setup |
| Export | Shared/Services/PlanExporter.swift | Plain-text plan summary |
| StoreKit | Shared/Services/StoreService.swift, BabyDocs/Services/Products.storekit | RevenueCat production path and simulator StoreKit path |
| UI | BabyDocs/Views | Onboarding, plan, task details, child editing, family, settings, paywall |
| Backend | supabase/migrations | Database schema, RLS, invites, billing entitlement |
| Deployment | scripts, fastlane, docs | TestFlight, database, functions, auth, metadata, support pages |

### 5.3 Current rule catalog

The catalog has 20 rules:

| Key | Area | Current applicability | Audit view |
| --- | --- | --- | --- |
| ssnCard | Identity | Every child | High-value, status-only is correct, follow-up should be explicitly non-statutory |
| birthCertificate | Identity | Every child | High-value, state source coverage is incomplete |
| birthRecordNameCheck | Identity | After certificate status | Good concept, needs correction and amendment branch |
| employerInsurance | Coverage | Employer plan | Critical, deadline must become plan-aware |
| marketplaceInsurance | Coverage | Marketplace | Critical, needs state Marketplace and payment follow-up |
| medicaidCHIP | Coverage | Medicaid, CHIP, or no insurance | Critical, should include state agency and WIC discovery |
| dependentCareFSA | Benefits | FSA enabled | High-value, current source URL is mismatched |
| hospitalBillCheck | Coverage | Every child | Useful, currently too generic and not evidence-oriented |
| parentageAcknowledgment | Parentage | Unmarried or unknown parentage | Important, current model is too narrow for family structures |
| parentalLeaveClaim | Work | Leave selected | Important, should split employer leave, FMLA, paid leave, and disability |
| w4Update | Taxes | Every child | Useful, needs tax-year versioning and less certainty in tax language |
| trumpAccount | Money | Citizen, selected, birth years 2025 through 2028 | Timely but needs current IRS form flow and no SSN-number prompt |
| taxDependent | Taxes | Every child | High-value, needs tax-year and preparer framing |
| plan529 | Money | Selected | Useful, should use state plan sources and avoid product recommendations |
| passport | Travel | Selected | Useful, needs a full newborn DS-11 and photo path |
| newbornScreeningResult | Health records | Every child | Useful but source is wrong and the task needs a safer medical boundary |
| beneficiaryUpdate | Household | Every child | Useful as a prompt, not currently a government-paperwork rule |
| guardianNomination | Household | Every child | Valuable but legal and state-specific; current source is not adequate |
| pediatricPortal | Health records | Every child | Useful administrative task, current source is wrong |
| childcareWaitlist | Childcare | Every child | Useful discovery task, current source is wrong and no jurisdiction logic exists |

## 6. Severity model

Use these labels in issues and implementation branches:

- P0: Can lose, expose, corrupt, or falsely represent user data, or can make a shared-family release unsafe. Fix before enabling the affected path.
- P1: High-impact correctness, legal, source, entitlement, or user-trust issue. Fix before broad App Store release or before expanding the affected feature.
- P2: Material usability, maintainability, accessibility, or product-quality issue. Fix in the next focused iteration.
- P3: Valuable refinement or differentiator. Schedule after correctness and core coverage.

## 7. Findings in implementation order

### P0: Sync and account safety

#### SYNC-01: A newer local child can be overwritten by an older server child

Location: Shared/Services/SyncEngine.swift, applyChild around lines 233 through 273.

The child merge path checks for a real conflict only when the server timestamp is newer than the local timestamp. It then writes the server DTO for every non-conflict branch. That means this sequence is possible:

1. Parent edits the child name or birth data offline.
2. The local row becomes dirty and has a newer updatedAt.
3. A stale server row arrives during pull.
4. The local row is treated as not being a conflict because the server is not newer.
5. The stale server value overwrites the local value.

The affected fields include the child name, birth date, birth state, county, citizenship, Social Security status, certificate status, notes, and color. A server tombstone can also hard-delete a local row without first proving that the server deletion is newer than the local edit.

Required fix:

- Make the merge direction explicit for every timestamp relation: server newer, local newer, equal, and incomparable.
- If local is newer and dirty, keep local and leave the outbox entry intact.
- If both sides changed different fields, merge by field where safe.
- If both sides changed the same field, create a conflict case that the user can resolve.
- Never hard-delete a newer local row because a stale server tombstone arrived.
- Preserve the local timestamp and dirty state when local wins.
- Add a server revision or monotonic mutation token if timestamps are not sufficient.

Required regression tests:

- Local newer name versus stale server name.
- Local newer birth date versus stale server birth date.
- Local dirty row versus newer server tombstone.
- Equal timestamps with different values.
- Local newer row with a pending outbox entry after a pull-push cycle.

Acceptance criterion: pulling any stale server child never changes a newer local child, and the test proves the row and its outbox state remain intact.

#### DATA-01: Family cache is not scoped to the authenticated account

Locations:

- Shared/Models/BabyModels.swift, Family.
- Shared/Services/FamilyService.swift, loadFromCache, refresh, cache.
- Shared/Services/AuthService.swift, signOut and account transitions.

The local Family cache does not store an owning auth user ID. cachedFamily returns an arbitrary family row. If refresh finds no server membership, it returns without clearing the stale cache or activeGroupID. Sign-out clears the auth session but does not clear or isolate the family and child plan. A later account on the same device can therefore see the previous account’s family state or local plan.

This is especially serious once shared families are enabled, but it is also a local privacy issue on a shared device.

Required fix:

- Add an account scope key to every account-derived local record, or maintain explicit account-owned vaults.
- Store the authenticated user ID or a stable local account identity on Family and every syncable row.
- Never select an arbitrary family from SwiftData.
- When server membership is empty, clear active membership and mark the cached family as signed out or remove it from the active account view.
- On sign-out, provide a clear choice: keep this local plan on this device, export it, or erase it. The default must not expose it to another account.
- On sign-in as another account, show an explicit account transition screen before opening the plan.
- Ensure notification schedules and pending invites are account-scoped and cleared or rebuilt.
- Add a local wipe operation that covers profiles, children, tasks, documents, receipts, notes, outbox, cursors, conflicts, cached family, and reminders for the selected account.

Required regression tests:

- Account A signs out, Account B signs in, and Account B cannot query Account A’s children.
- Account A loses server membership, refresh runs, and the Family tab does not continue to present A as active.
- A stale outbox row from A is present when B signs in and is not pushed into B.
- Delete-account flow leaves no cached account identity or notification payload behind.

Acceptance criterion: switching accounts cannot display, sync, or notify about another account’s family data.

#### SYNC-02: Push trusts the current group instead of the row and outbox ownership

Location: Shared/Services/SyncEngine.swift, push(entry:) around lines 529 through 609.

The push operation receives a current group ID and builds DTOs using that group. It does not sufficiently validate that the outbox entry, the fetched model, the model’s group ID, and the current active family all agree. A stale outbox entry or a row retained across account or family transitions could be written under the wrong family.

Required fix:

- Validate entry.groupID equals the active group before fetching.
- Validate the fetched model’s groupID equals entry.groupID.
- Validate the DTO group ID equals the row’s stored group ID.
- Reject and quarantine mismatches instead of silently pushing them.
- Make an outbox entry immutable with entity type, entity ID, group ID, account ID, and mutation version.
- Do not mark a missing row as successfully synced. A missing row may represent a failed tombstone or a local persistence problem.
- Record a visible sync error with a recovery action.

Acceptance criterion: a row can only be pushed to the family and account that created the outbox entry, and a missing row never causes a pending mutation to disappear silently.

#### ENGINE-01: Reactivating a tombstoned deterministic task can create a duplicate persistent identity

Location: Shared/Rules/RequirementEngine.swift, existing task lookup and make path, especially lines 46 through 64 and 208 through 243.

The engine intentionally excludes tombstoned tasks from its live lookup. When a rule becomes inapplicable, an untouched task is tombstoned. If the inputs later make that rule applicable again, the engine creates a new task with the same deterministic UUID derived from child and catalog key.

The same risk exists for tombstoned documents in syncDocuments. SwiftData may reject the insert because the old tombstone still owns the persistent identifier, or a future migration may leave two rows that look like the same logical task. This is a classic edge case for a child whose insurance changes from employer to Marketplace and back, or for a passport preference toggled off and on.

Required fix:

- Treat the deterministic ID as the permanent logical identity.
- When a matching tombstone exists, restore it in place if the rule is applicable again.
- Preserve user work on restoration.
- If a rule is intentionally retired forever, use a catalog version or logical key migration rather than reusing the same persistent ID for a different meaning.
- Add a stable rule version to the task.
- Apply the same restore-or-migrate behavior to documents.

Required regression tests:

- Employer insurance to Marketplace to employer.
- Passport selected, deselected, selected.
- Trump Account eligibility toggled by birth-year or citizenship input.
- A task with completion, receipt, note, and assignment is tombstoned and then restored with all work intact.
- A task with a tombstoned document is restored without a duplicate document.

Acceptance criterion: repeated rule changes produce one logical row per child and catalog key, never a persistent identity collision or duplicated document.

### P0: Source and rule truth

#### RULE-01: Several source citations are formally valid but substantively wrong

Location: Shared/Rules/RequirementCatalog.swift.

The catalog has a good source citation shape, but a .gov host check is not enough. Several tasks point to a general birth-certificate page for subjects that are not birth certificates. One URL is plainly mismatched:

- dependentCareFSA labels an IRS Topic 602 source but uses https://www.irs.gov/taxtopics/tc313, which is a 529 and qualified tuition topic.
- newbornScreeningResult uses https://www.usa.gov/birth-certificate even though the task concerns newborn screening.
- beneficiaryUpdate, guardianNomination, pediatricPortal, and childcareWaitlist reuse the birth-certificate URL.
- Multiple rules have no official link at all, even though the UI and product promise imply that every rule has a useful source.
- Parentage has a broad HHS information page rather than the child’s state-specific acknowledgment or vital-records path.
- Parental leave mentions state paid leave but cites a federal FMLA page without a state program branch.
- Hospital bill review points to a Marketplace enrollment page, which does not explain claim review, EOBs, appeals, or billing corrections.

This is a product integrity defect, not merely a documentation defect. A parent may follow a link at the moment they are already stressed and lose days navigating the wrong office.

Required fix:

- Create a source manifest separate from the display copy. Each source should have a canonical URL, title, agency, jurisdiction, subject, page type, last human review date, and known limitations.
- Require a source-to-rule test that checks more than the host. At minimum, every source needs a manually approved subject key.
- Add a source status enum: verified, federal fallback, plan-specific, state pending, stale, broken, or intentionally absent.
- Do not show a specific state office as verified until a human has read that state’s page.
- For a missing or stale source, say so visibly and provide a safe federal directory or agency home page.
- Add an in-app “report a stale source” action with the rule key and source URL.
- Have a human review every source page before changing source status.

Acceptance criterion: every live rule either has a source that directly supports its statement or is clearly labeled as a general discovery prompt with no false official citation.

#### RULE-02: The two hard windows are correct in category, but the app does not collect the plan-specific facts that determine action

Current code correctly models:

- Employer group health plan special enrollment as a hard 30-day baseline.
- Marketplace special enrollment as a generally 60-day baseline.

The current app does not capture the employer plan administrator, the date the employer was notified, the plan’s stated deadline, whether enrollment was submitted, whether the effective date is retroactive to birth, or whether the first premium was paid. It also cannot distinguish “the parent reported the birth” from “the baby is actually enrolled.”

The UI should never imply that a generic 30 or 60 days is the parent’s exact plan deadline. The safe wording is:

“Federal rules generally give you at least 30 days for an employer plan. Your plan may allow longer. Confirm the exact window with your benefits administrator.”

For Marketplace:

“A birth generally opens a Special Enrollment Period. The Marketplace usually gives 60 days, and coverage may start on the date of birth if you enroll and complete the required payment steps. Confirm the exact state Marketplace instructions.”

The official anchors reviewed for this audit are:

- U.S. Department of Labor, Newborns and Mothers Health Protection Act and group-plan special enrollment: https://webapps.dol.gov/elaws/ebsa/health/72.asp
- U.S. Department of Labor, newborn special enrollment FAQ: https://www.dol.gov/node/25144
- HealthCare.gov, Special Enrollment Period glossary: https://www.healthcare.gov/glossary/special-enrollment-period/
- HealthCare.gov, Special Enrollment Period after a birth: https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/?os=av

Required fix:

- Keep the legal baseline as a source-backed fact.
- Add a parent-entered plan deadline override with the reason and who supplied it.
- Capture notice date, submission date, effective date, premium-paid status, and confirmation reference without storing account passwords.
- Add a “call benefits” script and a contact record.
- Make the task remain open until coverage status is confirmed, not merely until a form is marked complete.
- Treat a plan-specific date as more urgent than a generic baseline, while showing both.

Acceptance criterion: a parent can see both the official baseline and their plan-specific date, with no ambiguity about which one to prioritize.

#### RULE-03: The Trump Account rule needs a current-form flow and a safe document label

The current rule applies to U.S. citizen children born in 2025 through 2028 when selected. That is a useful, timely inclusion, but the document title currently says “The baby's Social Security number.” The app’s own product rules say never store a Social Security number. A tired parent can interpret that label as an invitation to place the number into a note or receipt.

Current IRS material reviewed on 2026-08-11:

- IRS Trump Accounts overview: https://www.irs.gov/trumpaccounts
- IRS Form 4547 instructions: https://www.irs.gov/instructions/i4547
- IRS About Form 4547: https://www.irs.gov/forms-pubs/about-form-4547

The current IRS material says a valid Social Security number is needed before the election, and the pilot contribution timing has a July 4, 2026 floor. The app should not invent a deadline when the current official instructions do not state one.

Required fix:

- Rename the document to “Proof the child has a valid Social Security number, if the official form requires it.”
- Add a persistent red warning beside the task: “Do not type the number into Baby Docs.”
- Add an eligibility explanation that is versioned by tax year or program year.
- Add the official Form 4547 and current instructions.
- Track “form prepared,” “election submitted,” “confirmation saved,” and “needs follow-up,” without capturing the number.
- If the IRS changes the program, show the source review date and a visible changed-rule notice.
- Add a regression test that scans every catalog document title and detail for a request to enter a Social Security number.

### P0: Backend readiness

#### BACKEND-01: Sharing and billing deployment is incomplete in the repository

The app deliberately keeps sharing disabled because Supabase is not configured. That decision is correct. The repository is not ready to turn the flag on:

- The deployment script references SupabaseFunctions/escalate-check-ins and SupabaseFunctions/revenuecat-webhook, but the SupabaseFunctions directory is absent.
- The deployment script mentions a migration 0007 while the repository currently has migrations 0001 through 0004.
- scripts/test-db.sh references supabase/tests/_stubs.sql and SQL tests, but supabase/tests is absent.
- scripts/configure-auth.sh contains an elderhub://auth callback instead of a Baby Docs callback.
- The billing migration expects a service-role RevenueCat webhook path, but no webhook implementation is present.
- There is no end-to-end two-account sync test.
- There is no CI build, test, migration, or RLS verification workflow.

Required fix before setting SupabaseConfig.isConfigured true:

- Add the actual edge functions or remove the deploy references until they exist.
- Add a complete SQL test suite under supabase/tests.
- Correct the auth callback script and verify the callback scheme against the app.
- Add a RevenueCat webhook implementation with signature verification, idempotency, event ordering, and family ownership checks.
- Add schema drift checks that run in CI and locally.
- Add a staging project and staging credentials path that can never use production data.
- Add a two-account, two-family integration test for create, invite, accept, pull, push, role change, leave, delete, and account switch.
- Do not add sharing or second-parent copy to a build before all of the above passes.

Acceptance criterion: a clean checkout can validate database schema, RLS, functions, auth callbacks, billing propagation, and a full two-family sync flow without hidden files on one developer’s machine.

#### BACKEND-02: Child, task, document, receipt, and note relationships are not protected across families

Location: supabase/migrations/0002.

RLS checks that a user belongs to the row’s family. The foreign keys connect task to child, document and receipt to task, and note to child, but they do not enforce that all referenced rows share the same family ID.

A malicious or malformed staff client could attempt to create a task in Family A that references a child in Family B, or a document in one family that references a task in another. The client should not be trusted to preserve relationship ownership.

Required fix:

- Add composite keys or database triggers that enforce same-family relationships.
- Validate the family ID of every parent entity in security-definer write RPCs.
- Add database constraints for enum-like values.
- Add RLS tests for cross-family inserts, updates, selects, and attempted foreign links.
- Test deleted and tombstoned parents.
- Test owner, staff, member, and removed-member behavior separately.

Acceptance criterion: no SQL request can create or read a cross-family graph, even when the client sends valid UUIDs from another family.

## 8. Current UI and interaction audit

### UI-01, P1: The persistent tab bar overlays content in Plan and Task Detail

The headless screenshots show the translucent bottom TabView bar over the scroll content:

- Plan content runs behind the tab bar.
- Task Detail content, including the documents and later task sections, is obscured at the bottom after scrolling.
- Settings content also approaches the tab bar and creates visual ambiguity.

This is a functional issue because a parent can miss the last document, note, or action. It also makes the screen look unfinished.

Required fix:

- Ensure every scroll view receives safe-area content inset for the tab bar.
- Test the longest task detail at the smallest supported device height.
- Test Dynamic Type sizes up to accessibility sizes.
- Add UI assertions that the final control can scroll fully above the tab bar.
- If a pushed detail should not show tabs, hide the tab bar on the navigation destination and restore it on pop.

Acceptance criterion: the last actionable control in every tab and pushed screen is fully visible without manual zooming or guessing.

### UI-02, P2: Long task titles are truncated in navigation

The detail screenshot shows “Order certified copies of the birth cer...” in the navigation title. The content title is readable, but the navigation bar title is not useful.

Required fix:

- Use a short navigation title such as “Birth certificates.”
- Keep the full title as the main heading and accessibility label.
- Use a category plus child name where helpful.

### UI-03, P1: The one-page summary appears available without enforcing the Plus gate

The product copy says Plus adds the one-page summary. PlanView and ChildDetail expose ShareLink actions without a visible store.isPro || family.hasPlus gate.

This creates a direct mismatch between what the paywall sells and what the app allows. It also makes the purchase decision less trustworthy.

Choose one product truth and implement it consistently:

- Preferred for the current business model: enforce the Plus gate and show the paywall when a free user selects the summary.
- Alternative: make the summary free, remove it from the Plus promise, and use a different Plus benefit that is already implemented.

Do not leave copy and capability divergent.

### UI-04, P1: The export can accidentally carry sensitive data

PlanExporter intentionally does not include an SSN number field, which is good. It cannot prevent a parent from putting sensitive values into:

- Parent notes.
- Child notes.
- Receipt values.
- Confirmation notes.
- Imported or copied document text if attachments are added later.

The Trump Account document wording makes this risk worse. The current receipt input accepts arbitrary text and the export includes receipt values.

Required fix:

- Add a clear no-sensitive-identifiers warning at every free-text entry point.
- Block or warn on SSN-shaped patterns, full bank account patterns, passwords, and insurance portal credentials. Do not claim that a heuristic is perfect.
- Add export modes: safe handoff, private archive, and review-before-sharing.
- Redact or omit free text by default in a handoff export.
- Show the exact fields and recipients in a preview before the share sheet.
- Add a post-export reminder that the share destination is outside Baby Docs.
- Keep the status-only SSN design.

Acceptance criterion: the default export cannot silently include arbitrary notes or receipt values, and a parent sees exactly what will leave the app.

### UI-05, P1: The paywall is not complete enough for a real purchase

StoreKit products include lifetime, yearly, and monthly plans with introductory trials for the recurring products. PaywallView displays product title and price but does not visibly explain:

- Billing period.
- Trial length and eligibility.
- Renewal behavior.
- How to cancel.
- Where to manage the subscription.
- Restore behavior and the current restore result.
- Terms and privacy in the purchase context.
- What happens if product loading fails.

The simulator purchase path also does not exercise a real purchase when the package is nil, so the UI test does not prove entitlement behavior.

Required fix:

- Use StoreKit product metadata to render localized price, period, introductory offer, and renewal copy.
- Show “one-time purchase” for lifetime.
- Add a clear restore control with success, no purchases, and failure states.
- Link Terms and Privacy from the purchase view.
- Include Apple’s required subscription disclosure language where applicable.
- Add product-loading error and retry states.
- Add StoreKit tests for purchase, cancel, restore, expired entitlement, and family entitlement.
- Verify the entitlement source is store.isPro || family.hasPlus everywhere.
- After auth refresh, explicitly identify the RevenueCat customer before reading entitlement. Do not rely on a launch race.

### UI-06, P1: Notification taps do not navigate to the task

NotificationService handles foreground presentation and local scheduling, but BabyDocsApp only handles URL opens. There is no notification payload route or task navigation handler.

A reminder that opens the app without opening the exact task spends the parent’s scarce attention budget and undermines the reminder.

Required fix:

- Include a stable child and task route in every local notification.
- Handle notification response in the app delegate or SwiftUI notification bridge.
- Store a pending route if the app is still booting or onboarding.
- Navigate to the task after the model is available.
- Add notification actions such as “Open task” and “Snooze until tomorrow” only if they can be implemented safely.
- Test cold launch, warm launch, locked device, and multiple children.

### UI-07, P1: Remote notification registration is incomplete

NotificationService can register an APNs token when configured, but:

- BabyDocs.entitlements does not contain aps-environment.
- The code does not appear to call registerIfAuthorized on every launch for users who already granted permission.
- Supabase is currently disabled, so remote push should remain dormant.

Required fix:

- Keep local reminders independent of APNs.
- If remote push is later enabled, add the entitlement, environment separation, token refresh, deletion on sign-out, and server-side permission checks.
- Call registration only after explicit authorization and a configured backend.
- Never send sensitive task text in a remote payload. Send a route and fetch local or authenticated content.

### UI-08, P2: “Answer the questions” can be a no-op action

PlanView’s empty state provides an “Answer the questions” action with an empty closure. Even if the empty plan is uncommon, a visible no-op is a trust defect.

Required fix:

- Navigate to a profile completion editor or onboarding review.
- If there is no missing answer, remove the action.
- Add a UI test that taps every empty-state action and confirms navigation or a meaningful alert.

### UI-09, P2: Destructive family actions lack visible confirmation

FamilyView exposes leave and delete flows while FamilyService contains destructive operations. These actions need confirmation, impact summary, and a recoverability statement.

Required fix:

- Explain what happens to the local plan, family data, invitations, and ownership.
- Require explicit confirmation for leave, delete family, transfer ownership, delete account, and local wipe.
- Disable destructive controls while the operation is running.
- Show the resulting membership state.
- Add owner transfer UI because the service supports transferOwnership but the view does not expose it.

### UI-10, P2: Delete-account copy conflicts with privacy expectations

Settings says deleting the account leaves the plan on the phone. That may be an intentional local-retention choice, but the current wording is too casual and can surprise a user who expects deletion to remove personal data.

Required fix:

- Separate server account deletion from local plan retention.
- Offer “delete account and erase this device,” “delete account and keep an offline export,” and any legally required alternative.
- Explain that a local plan is not synced after account deletion.
- Rebuild or clear reminders.
- Confirm that no family invite, auth token, or cached member data remains.

## 8.1 Current implementation scorecard by component

This section records the current behavior that a future agent should preserve or change. It is intentionally more concrete than the product vision.

### RootView and app lifecycle

What is good:

- Onboarding and the main plan have a clear split.
- The root reconciles the catalog when the child set changes and on scene activity.
- The local-only state is a complete experience when Supabase is not configured.
- Deep invite URLs are held as pending navigation instead of being discarded during launch.

Needs attention:

- A pending invite can arrive while onboarding is incomplete. The app needs a clear policy for whether the invite waits, is shown after intake, or can be accepted before a child exists.
- The root starts several services in parallel. Store identity, auth refresh, family refresh, and sync need an explicit order so billing and family state do not race.
- The app should show a durable boot state when the model store, auth state, or source bundle is still loading. A blank or partially populated plan can look like an empty household.
- Scene activation currently triggers useful reconciliation and reminders, but a long-running sync should not block the parent from using local data.

### Onboarding and profile input

What is good:

- The onboarding flow asks only a manageable number of questions.
- It supports unknown or optional answers in several areas.
- It asks about insurance early enough to generate important coverage work.
- It asks about reminders instead of silently requesting permission.

Needs attention:

- Birth state is required, but the model does not support all territories, international birth, or placement and adoption.
- Residence state is required even when the parent may be temporarily outside the United States.
- U.S. citizenship defaults to true. This must become an explicit answer or a neutral unknown.
- The first name is not the same as the legal name used on official records. Add a clear “name not final” path and avoid implying that the entered display name is legal identity.
- There is no birth registration status, hospital record status, placement date, adoption path, or expected travel date.
- Insurance input does not collect the plan-specific date or the person responsible for enrollment.
- Parentage input is too coarse for same-sex parents, assisted reproduction, surrogacy, adoption, court orders, or unsafe contact situations.
- Several preference toggles create tasks with no explanation of what happens if the answer is unknown. Every toggle should support “decide later.”
- Finish and edit paths use broad try? writes. The parent needs a visible save failure and a way to resume incomplete intake.

### RequirementCatalog

What is good:

- Rules are pure and independently testable.
- The catalog key is stable and suitable for deterministic task identity.
- Each rule carries applicability, copy, documents, a source label, a source URL, and a review date.
- Hard deadline kinds are separated from recommendations.

Needs attention:

- All entries sharing one reviewedOn date makes the catalog look reviewed as a batch even when individual pages may have been checked at different times.
- The source URL field permits a rule to pass a host-only test while pointing to the wrong subject.
- A nil official link is not explained in the task UI. The parent should know whether there is no safe link, a link is pending verification, or the task is intentionally a household prompt.
- Catalog copy contains assumptions that should become parameters, including the number of birth-certificate copies and the meaning of an SSN follow-up interval.
- The catalog has no rule version. A copy or source update needs to be distinguishable from a task-level user edit.
- State-specific applicability and source selection are largely absent. The single verified state entry is a good stewardship start, but the UI needs to say what “federal fallback” means.

### RequirementEngine

What is good:

- The engine owns generated rule work while preserving family-owned fields.
- Deterministic IDs make offline generation by two parents converge.
- No-op reconciliation is intentionally quiet, which avoids an outbox write on every launch.
- Worked tasks that become inapplicable are preserved rather than erased.

Needs attention:

- Tombstoned rows are excluded before matching, which creates the reactivation identity problem described in ENGINE-01.
- Existing rows are grouped by catalog key and the first one is used. A duplicate created by an earlier bug can therefore be silently ignored rather than surfaced and repaired.
- Fingerprint comparison does not include all rule-owned metadata, especially source review changes.
- The engine’s async outbox calls can run after the surrounding reconciliation has moved on. Save, enqueue, and reconciliation completion need a single transactional boundary or explicit durable queue.
- The engine does not model dependencies. A certificate name check can appear without a clear relationship to the certificate order, and an insurance follow-up does not depend on an enrollment submission event.
- The current rule retirement behavior needs catalog versioning so a removed rule can be explained to a parent rather than simply disappearing.

### TaskPlanner

What is good:

- The planner gives the app a single place for date phrasing.
- It separates open work from the done and dismissed disclosure.
- It brings future hard deadlines into the overview.

Needs attention:

- Overview.doneCount includes dismissed tasks. The UI partially explains this, but a progress metric should distinguish completed, not applicable, dismissed, and unresolved.
- hardDeadlineCount counts future hard deadlines but does not separately show overdue hard deadlines. An overdue coverage task should be more visible, not disappear from the hard-deadline count.
- “This month” is implemented as 31 days rather than the calendar month. The label and behavior disagree around short months and month boundaries.
- Bucketing is date-only and cannot prioritize a plan-specific deadline over a later generic baseline unless deadline provenance is introduced.
- The planner has no blocked or waiting bucket, so a parent can mark a task done to make it disappear even though the external office has not confirmed the result.
- The duePhrase implementation relies on static DateFormatter and current-calendar assumptions. Make date formatting injectable and testable.

### StateVitalRecords

What is good:

- The code refuses to guess specific state URLs.
- The federal directory fallback is safer than a made-up office link.
- The verified-state distinction is visible in the source stewardship concept.

Needs attention:

- Only California is verified. That is acceptable for an early build, but the task detail should make the fallback status prominent.
- orderingNote is shown in child editing but is not carried into the task detail where the parent is most likely to need it.
- Unknown state codes fall back to the code string. This should be a visible unsupported-jurisdiction state, not a plausible-looking office label.
- Territories, foreign birth, adoption, and records held by a consulate need separate routing.

### FamilyService and AuthService

What is good:

- Security-definer RPCs are used for family mutations.
- Roles are cached so offline gating does not depend on a network response.
- The service has explicit leave, ownership, invite, delete, and local-forget concepts.
- Auth classification is conservative for network failures, which supports offline use.

Needs attention:

- Membership absence does not clear stale local state.
- Cached family selection is not account-scoped.
- Sign-out does not clear or quarantine the local plan, notifications, or pending family data.
- Apple display-name persistence can fail silently.
- There is no account-switch screen or reauthentication state that explains which local plan is active.
- Delete-account server work and local wipe are not one clearly defined user operation.
- A family invite acceptance path needs explicit handling for an existing local child plan. It must not silently merge or overwrite local data.
- Family member and pending invite views do not expose a conflict center, owner transfer, or removal consequences.

### SyncRemote, SyncEngine, and SyncCoordinator

What is good:

- The system has an outbox and compound cursor concept.
- Pull order reflects profile, child, task, document, receipt, and note dependencies.
- Task merge logic recognizes that completion and family-owned work need special treatment.
- Rejected versus transient server errors are partially classified.

Needs attention:

- Child merge direction is unsafe, as described in SYNC-01.
- Task merging can resolve a completion agreement by taking the server row and unintentionally clobbering local notes, assignee, receipts, or document state.
- Pull deletions hard-delete local rows, which can invalidate a pending local mutation or relationship.
- A missing row during push is treated like success, which can lose a tombstone or local change.
- Outbox coalescing and conflict lookup need entity type and account scope, not only UUID.
- The sync cursor and last status are mostly in memory, so the app cannot reliably explain what happened after relaunch.
- No conflict UI exists. A count of changes needing review without a way to inspect and resolve them is a dead end.
- The coordinator starts unstructured tasks. A single actor-owned queue should serialize sync, enqueue, and settlement.
- There is no background task strategy. Foreground-only sync is acceptable for the current local-only build, but shared-family copy must not imply instant synchronization.

### BabyModelStore

What is good:

- The schema is local-first and does not depend on CloudKit.
- File protection is enabled until first user authentication.
- The debug wipe and seed path is useful for development.

Needs attention:

- Destructive deletion of the store on container failure is not safe in production.
- There is no explicit migration history for the SwiftData schema.
- Directory creation and save errors are swallowed.
- A recovery export and repair path are missing.
- The store needs tests for protected data availability before first unlock and for an interrupted migration.

### Notifications

What is good:

- Only the two hard coverage windows are scheduled by default.
- Reminder scheduling is rebuilt from the current plan, which avoids stale notifications after rule changes.
- Local reminders work without Supabase.

Needs attention:

- Notification taps do not route to a task.
- Existing notification authorization does not appear to trigger remote token registration on every relevant launch.
- No notification category or action is implemented.
- The reminder copy uses deadlineBasis, which may be too long or too legalistic for a notification.
- Reminder dates and rule dates need one explicit civil-date and time-zone policy.
- A reschedule wholesale operation should preserve a pending tap route and avoid notification churn when nothing changed.

### PlanExporter

What is good:

- It includes the source URL and disclaimer.
- It prints status rather than a stored SSN.
- It is useful without an account or network.

Needs attention:

- It includes free-text receipt and note content without a preview or redaction mode.
- It does not distinguish a private archive from a handoff packet.
- It has no export audit record, which makes it impossible to explain later what was shared.
- It should have a synthetic sensitive-content test suite.
- A task document title itself can contain unsafe wording even if no number is printed.

### StoreService and PaywallView

What is good:

- Production RevenueCat configuration is skipped on the simulator.
- The entitlement concept correctly combines local StoreKit or RevenueCat state with family entitlement.
- Lifetime is the lead purchase, consistent with short retention.

Needs attention:

- StoreService can identify RevenueCat before AuthService has refreshed the current session.
- Simulator package purchase and restore are not a complete entitlement test.
- Product loading has no durable error or retry state.
- Subscription disclosures are too sparse at the purchase decision.
- Free summary availability contradicts the Plus promise.
- Restore and family entitlement need relaunch and account-switch tests.

### FamilyView and SettingsView

What is good:

- The current disabled-sharing screen is honest.
- Settings surfaces disclaimer, source review, reminders, legal links, and account state.
- The UI avoids promising the second parent while the backend is off.

Needs attention:

- FamilyView has no conflict resolution.
- Destructive membership actions need confirmation and outcome states.
- Settings has no local-data wipe or account-switch management.
- Rules reviewedOn is surfaced, but there is no way to see which rule changed or report a bad source.
- Support does not yet explain the most likely real-world failures.

### Tests that currently pass, and tests that are missing

The current suite proves useful pure behavior:

- Catalog applicability and selected happy paths.
- Deterministic task generation and work preservation.
- Planner buckets.
- Reminder filtering.
- Export’s explicit no-SSN field behavior.
- Invite-link parsing and pure sync merge helpers.
- Basic onboarding and screen launch.

It does not currently prove:

- Actual SyncEngine child merge direction.
- Account isolation or stale family cache clearing.
- Task and document reactivation after tombstone.
- Store failure recovery.
- Source subject correctness.
- Export redaction.
- Paywall purchase and restore.
- Notification response routing.
- Accessibility and Dynamic Type.
- Supabase RLS, same-family constraints, invites, billing, or account deletion.

This gap is why the passing test count should be treated as a baseline, not a release certification.

## 9. Current data model and persistence audit

### MODEL-01, P1: The model is a checklist model where the product needs a workflow model

RequirementTask currently combines:

- Rule-generated copy.
- Deadline fields.
- Completion and dismissal.
- Assignee.
- Parent notes.
- Documents.
- Receipts.

This is a reasonable first model, but it cannot represent the real state of newborn administration:

- Preparing.
- Waiting for an employer.
- Submitted.
- Confirmation received.
- Agency rejected it.
- Correction requested.
- Follow-up due.
- Not applicable after review.
- Completed by someone outside the household.

A Boolean completed flag causes important distinctions to disappear. It also makes “dismissed” count as done in TaskPlanner.

Recommended state machine:

| State | Meaning | Can have a follow-up date |
| --- | --- | --- |
| Not started | Parent has not begun | No or optional |
| Preparing | Parent is gathering information or documents | Optional |
| Ready to submit | The packet is ready | Optional |
| Submitted | Parent says it was sent or completed | Yes |
| Waiting | Parent is waiting for an office, employer, or agency | Yes |
| Received | Parent has proof the result arrived | No, unless another action follows |
| Needs correction | The result or application needs repair | Yes |
| Blocked | Missing information or an external dependency prevents progress | Yes |
| Not applicable | Parent deliberately ruled it out | No |
| Archived | Historical record retained for reference | No |

Keep a separate completion notion if needed for progress, but do not overload one Boolean.

### MODEL-02, P1: Deadlines need provenance, confidence, and parent-specific override

Current deadline kinds are a good start, but a deadline is more than a Date:

- The governing rule.
- The jurisdiction.
- The source page.
- The event that starts the clock.
- The date the event occurred.
- The plan-specific date supplied by a human.
- The confidence of the date.
- Whether it is legally hard, plan-specific, agency-estimated, or a suggestion.
- Whether the date is retrospective, unknown, or already expired.

Recommended deadline fields:

- deadlineKind: statutory, planSpecific, agencyEstimate, parentSelected, suggested.
- startEvent: birth, placement, notice, leaveStart, enrollmentWindow, receiptDate, other.
- startDate.
- dueDate.
- sourceURL.
- sourceReviewedOn.
- jurisdiction.
- planName or agencyName when relevant.
- confidence.
- enteredBy.
- enteredAt.
- explanation.
- supersedesDeadlineID when a plan-specific date replaces a baseline.

The UI should show:

“Federal baseline: at least 30 days after birth.”

“Your benefits administrator told you the deadline is August 24.”

“We are using August 24 because plan-specific information is more precise than the federal baseline.”

### MODEL-03, P1: SwiftData fallback can silently discard the durable store

BabyModelStore deletes the store, WAL, and shared memory files when model-container creation fails, then falls back to an in-memory container. This may be acceptable during development when changing an unfinished schema, but shipping the behavior can destroy a parent’s plan after a migration or disk problem.

Required fix:

- Remove destructive store deletion from production.
- Add explicit SwiftData schema versions and migration plans.
- On failure, present a recovery screen rather than pretending the app is empty.
- Offer a safe export from any recoverable store.
- Copy the damaged store to a timestamped recovery location before any repair attempt.
- Log only non-sensitive diagnostics.
- Test low-storage, locked-device, migration, and corrupted-store scenarios.

Acceptance criterion: a persistence failure cannot turn an existing plan into a blank in-memory plan without an unmistakable warning and recovery path.

### MODEL-04, P1: All local writes swallow persistence errors

Several writes use try? around context.save or recordLocalChange. SyncableRecord records an asynchronous outbox change after a save attempt, but the save result is not surfaced. A parent can see a changed screen while the durable write failed.

Required fix:

- Make local write APIs return a typed result.
- Show a non-blocking but persistent “Not saved” state when the store is unavailable.
- Do not enqueue an outbox mutation unless the model save succeeded.
- Centralize save and enqueue ordering.
- Add a retry queue for transient disk errors.
- Add tests that inject save failures.

### MODEL-05, P2: Source review changes do not affect the task fingerprint

RequirementEngine’s fingerprint excludes sourceVerifiedOn. That may be intentional to avoid rewriting family work when only a citation date changes, but the result is that a source review update may not be synchronized to another device.

Choose explicitly:

- Store source metadata as rule metadata that is pulled independently of the family task, or
- Include source revision in the generated task fingerprint while preserving user-owned fields.

A source review update must reach every device without generating a false outbox storm.

### MODEL-06, P2: Date and time semantics are not explicit

The catalog uses Calendar.current for due dates and age. Families can travel, use different device time zones, or have a birth date recorded in a hospital time zone. A due date must be a civil date with a chosen jurisdiction, not an accidental instant derived from whichever phone calculated it.

Recommended policy:

- Store date-only events as local civil dates with an explicit calendar and time-zone policy.
- Use the birth location or residence jurisdiction for rule calculations where required.
- Store notification fire times separately from due dates.
- Test daylight saving transitions, time-zone changes, birthdays around midnight, and a device traveling across states.

### MODEL-07, P1: The country and territory model is too narrow

USState contains the 50 states, District of Columbia, and Puerto Rico, but not Guam, American Samoa, Northern Mariana Islands, or U.S. Virgin Islands. The UI requires a birth state and a residence state, and the fallback language assumes a state or federal office.

Decide the product boundary explicitly:

- If v1 is the 50 states plus DC only, say that in onboarding and do not call the model “state or territory.”
- If the product includes all U.S. jurisdictions, add territories and jurisdiction-specific source states.
- Add “born outside the United States,” “living outside the United States,” and “unknown or not sure” paths.
- Do not default an international or territorial family into the federal state directory.

### MODEL-08, P1: Adding a second child inherits residence state as birth state

ChildrenView uses the family residence state as the default birth state for a new child. The comment notes that this is often right, but it is a risky default for families who move, travel, use a different hospital, or adopt.

Required fix:

- Ask “Where was this child born or placed?” explicitly.
- Offer the residence state as a suggestion only, never as a silent value.
- Preserve per-child birth jurisdiction.
- Add adoption and placement date paths.

## 10. Current rules and coverage audit

### 10.1 Rules that should remain in the first release

The following are the strongest parts of the current catalog and should remain central:

- Birth certificate ordering.
- Social Security status follow-up.
- Employer insurance enrollment.
- Marketplace coverage enrollment.
- Medicaid and CHIP discovery.
- Hospital bill and claim review.
- Parentage acknowledgment where relevant.
- Leave and tax prompts.
- Passport preparation.

The rules should become richer workflows, not be removed merely because their current copy is incomplete.

### 10.2 Rules that need source or scope repair before release

#### Birth certificate

Good current behavior:

- The app distinguishes verified state sources from the federal fallback.
- It does not bulk-import guessed state URLs.
- It preserves the rule’s document list.

Needs:

- A birth registration or hospital submission status before the parent is told to order copies.
- State-specific ordering method, cost, identity requirements, processing estimate, correction procedure, and acceptable requester.
- Separate “order a certified copy,” “check the legal name,” “request an amendment,” and “replace a lost copy.”
- A source card showing whether the state page was human-verified.
- A safe generic fallback when a state is not verified.

#### Social Security

Good current behavior:

- Status only, no number.
- The rule is a follow-up suggestion rather than a false legal deadline.

Needs:

- Distinguish hospital enumeration, direct application, card mailed, and card not received.
- Capture request date and follow-up date without the number.
- Use the official SSA process source rather than relying on a generic task.
- Tell the parent not to upload or type the number.

#### Employer coverage

Needs:

- Benefits administrator contact.
- Plan name and group identifier only if safe and useful, never portal passwords.
- Exact employer deadline override.
- Notice, submission, effective date, first premium, and confirmation states.
- A path for a spouse’s plan, COBRA or continuation questions, and coverage from multiple employers.
- A “call now” script.

#### Marketplace coverage

Needs:

- State versus federal Marketplace routing.
- Application submitted, eligibility decision, plan selected, first premium paid, and effective date.
- The possibility of retroactive coverage from the birth event should be explained without promising approval.
- Medicaid or CHIP referral if Marketplace screening suggests it.

#### Medicaid and CHIP

The current rule has no deadline, which is safe but incomplete. Add:

- State Medicaid and CHIP agency source.
- Medicaid for the baby versus Medicaid for the birthing parent.
- Newborn automatic eligibility or continuity questions where the state agency supports them.
- WIC discovery as a separate optional branch.
- Application started, submitted, case number saved, decision received, and renewal reminder states.

Do not store a full case number if it can identify a household unless the user explicitly wants it and the privacy model supports it. A safer first version lets the parent store “case reference saved elsewhere” and a reminder.

#### Dependent-care FSA

The source must be corrected. The workflow should ask:

- Is the baby eligible under the plan’s definition?
- Is there a qualifying life event election window?
- Is an employer form required?
- Does a dependent-care account require care expenses and a provider tax ID?
- What is the exact plan deadline?

Do not present a generic IRS education page as the plan’s enrollment deadline.

#### Hospital bills

Replace the generic enrollment source with a claim-review workflow:

- Hospital bill received.
- Insurance claim submitted.
- Explanation of Benefits received.
- Baby and parent claims separated.
- Duplicate or unexpected charge flagged.
- Financial assistance or payment plan requested.
- Appeal deadline captured if applicable.

Give the parent a question script and tell them to use the number on the bill or EOB. Do not claim that Baby Docs reviewed the claim.

#### Parentage

The current three-value parentage model is not sufficient. Add a private, nonjudgmental branching interview:

- Married or presumed parentage.
- Unmarried parents.
- Same-sex parents.
- Assisted reproduction.
- Gestational carrier or surrogacy.
- Donor conception.
- Adoption.
- Court order or acknowledgment already completed.
- Parent not present or situation is unsafe.
- User does not want to answer.

The rule should route to state-specific instructions only after knowing the jurisdiction and situation. It must not imply that a marriage status always resolves legal parentage.

#### Parental leave

Split the current task into:

- Employer leave or PTO request.
- FMLA eligibility and notice.
- State paid family leave.
- Short-term disability or pregnancy recovery claim where relevant.
- Benefits continuation and premium payments.
- Return-to-work plan.

Each branch needs its own source and deadline basis. The current generic 30-day suggestion is too vague.

#### W-4 and tax dependent

Add a tax-year field and label every tax rule with the relevant filing year. Use language such as “may qualify” and “confirm with a tax professional” for fact patterns that depend on custody, residency, citizenship, filing status, or the year’s law.

Separate:

- Update withholding.
- Claim child as a dependent.
- Child Tax Credit eligibility.
- Dependent-care benefits and credit.
- Keep birth certificate and SSN status ready for tax preparation.

Do not mix childcare receipts into a task unless the task explains why.

#### 529

Keep the task as an information and preparation prompt. Add:

- State-specific plan link.
- State tax deduction or credit source where applicable.
- A neutral explanation that Baby Docs does not recommend an investment or plan.
- Beneficiary identity and account confirmation states without storing financial credentials.

#### Passport

The current task is valuable but too thin. Add:

- DS-11 path.
- In-person appointment requirement for a minor.
- Parent or guardian consent path.
- Proof of citizenship and relationship.
- Photo guidance appropriate for an infant.
- Processing speed selection and travel date.
- Emergency or expedited path only with official source confirmation.
- Child passport renewal reminder based on the official validity period, if this belongs in scope.

Do not state a photo rule such as “eyes open” without checking the current official requirements and exceptions for infants.

#### Newborn screening and pediatric records

Replace the birth-certificate source. Make the task an administrative record follow-up:

- Screening completed or unknown.
- Result received.
- Result sent to pediatrician.
- Repeat screening requested.
- Hearing, metabolic, and other screening categories shown only where the official state or hospital source supports them.

The app should never interpret a medical result. It should say to contact the pediatrician or hospital for clinical questions.

#### Beneficiary and guardian prompts

These can be valuable, but they should not masquerade as government paperwork. Treat them as “household planning prompts” with:

- A clear statement that the app is not a lawyer or financial adviser.
- State-specific official information only where available.
- A suggestion to review existing documents with the appropriate professional.
- A “save this question for your lawyer” script rather than a generated legal instrument.

#### Pediatric portal and childcare waitlist

These are useful administrative prompts, but the current source mapping is wrong and the tasks need a different product treatment:

- Pediatric portal: contact the chosen office, add the child, request records, save the first appointment date.
- Childcare: identify desired start date, provider type, waitlist contact, deposit, tour, immunization record requirements, and backup options.

These should be categorized as external coordination tasks, not government paperwork. They may be optional in a focused v1.

### 10.3 Missing high-value rules

The first expansion should cover the following gaps, in this order:

1. Birth registration confirmation and certified-copy ordering.
2. Baby coverage enrollment confirmation, not just application.
3. Medicaid, CHIP, and WIC state routing.
4. Employer and state paid leave branches.
5. EOB and hospital claim follow-up.
6. Parentage and birth-record correction paths.
7. Passport and travel document packet.
8. Childcare subsidy and childcare paperwork discovery.
9. Adoption, guardianship, surrogacy, and international birth branches.
10. Military, tribal, and federal employee benefit branches where demand justifies them.

### 10.4 Edge cases the intake must eventually support

Do not make these all mandatory questions on day one. Use a “does any of this apply?” branch so the default experience stays calm.

- Twins or multiples.
- Adoption or foster placement.
- Gestational carrier or surrogacy.
- Same-sex parents.
- Unmarried parents.
- Parentage not yet established.
- Baby born in a different state from the family residence.
- Baby born outside the United States.
- Family living outside the United States.
- Non-U.S.-citizen child or parent.
- Military family.
- Federal employee.
- Tribal enrollment.
- NICU or extended hospital stay.
- Home birth or birth outside a hospital.
- Missing or incorrect hospital paperwork.
- Baby name not final.
- Multiple last names or diacritics.
- Child born near a move or change of employer.
- More than one possible health plan.
- Parent cannot safely contact the other parent.
- Stillbirth, loss, or urgent bereavement path.

The loss path requires special care. It should not dump active newborn tasks onto a bereaved parent. If the app asks about this, it must be optional, quiet, and designed with a separate review by a bereavement-informed specialist. Do not add it casually.

## 11. Product vision: the newborn administration control tower

### 11.1 Product promise

“Baby Docs turns the first 90 days of newborn administration into a calm, source-backed plan. It tells you what applies, what to do next, what to bring, and what to save, without filing anything for you or storing your Social Security number.”

The core experience should feel like a control tower, not a pile of articles:

- One current next action.
- One visible hard deadline.
- A short explanation of why it matters.
- A small document packet.
- A place to record what happened.
- A reliable source and review date.

### 11.2 Three clocks

The home screen should separate three kinds of time:

1. Clock: a legal or plan-specific window that can close.
2. Queue: work that should happen soon but has no universal deadline.
3. Trail: proof and follow-up after something was submitted.

This prevents a long list of suggestions from visually competing with the one action that could cause a coverage gap.

### 11.3 A better first-session interview

The current onboarding is clean, but it asks several preferences before it knows which facts are highest risk. Reorder the interview around consequences:

1. Where and when was the child born or placed?
2. Is the legal name final?
3. Which health coverage could cover the baby?
4. When did the parent or guardian notify the plan or agency?
5. Is there another parent or legal parentage path that needs attention?
6. Does any leave or employer benefit window apply?
7. Is there an upcoming travel date?
8. Which optional money and childcare tasks matter to this household?

Ask one question at a time. Explain why a question matters before asking a sensitive one. Let the parent say “not sure” and create a research task rather than forcing a guess.

Never default U.S. citizenship to true in a way that silently controls eligibility. Use:

- U.S. citizen.
- Not a U.S. citizen.
- Not sure or prefer not to say.

Only show citizenship-dependent rules when the answer supports them.

### 11.4 “Today in three minutes”

The home screen should have a compact mode for a sleep-deprived parent:

- “Do this next.”
- “You need these two things.”
- “Save this confirmation.”
- “You are safe for today.”

The full plan remains available, but the default screen should not require scanning 20 cards.

### 11.5 Missing-information concierge

Instead of asking for every possible field up front, the engine should ask the one missing fact that unlocks the most valuable rule:

- “Do you know whether the baby is already on a health plan?”
- “Did your benefits team give you an exact deadline?”
- “Is the baby’s legal name final?”
- “Do you need a passport before a specific date?”

Each question should have a “not sure” answer that creates a low-pressure research action. This makes the app useful even when the parent does not have paperwork nearby.

### 11.6 Explain mode

Every rule should have a compact explanation mode:

- Why this appears.
- What fact made it apply.
- What is universal.
- What may vary by state or plan.
- What the app does not know.
- Which source was reviewed and when.
- What to ask the office.

This is a major trust differentiator. A parent should never have to wonder whether a task was generated randomly.

## 12. Creative and innovative features worth building

These ideas are deliberately specific. Each one is tied to a real parent problem rather than novelty.

### 12.1 Newborn admin flight plan

Generate a 0 to 90 day timeline with three lanes:

- Hospital and identity.
- Coverage and benefits.
- Household, tax, travel, and care.

The first screen shows only the next three actions. The timeline can expand for a parent who wants the whole map.

Smart behavior:

- Reorders when a deadline is near.
- Pulls a task forward when another task is blocked by it.
- Distinguishes a missed deadline from a completed task.
- Preserves the original plan so the parent can see what changed.

### 12.2 Deadline radar

Show the next hard or plan-specific deadline as a radar card:

- “16 days left.”
- “This is based on your employer’s 30-day special enrollment window.”
- “Your plan may allow longer. You entered August 24 as the plan’s stated date.”
- “Call the benefits administrator if the date is unclear.”

If the window has passed:

- Do not show a red failure state that implies the situation is hopeless.
- Show “The general window may have passed. Contact the plan today and ask about late enrollment, coverage effective date, and appeal options.”
- Create a follow-up task.

### 12.3 Proof chain

Turn each important task into a timeline:

- Needed.
- Prepared.
- Submitted.
- Confirmation received.
- Result received.
- Follow-up or correction.

Each event can have:

- Date.
- Person or office contacted.
- Method, such as phone, portal, mail, or in person.
- Safe reference label.
- Optional receipt type.
- Follow-up date.

This is more useful than a green checkmark because parents frequently need to prove that they acted.

### 12.4 Bureaucracy packet

Generate a task-specific packet that can be printed or shown at an office:

- Child name as entered.
- Date of birth.
- State or jurisdiction.
- Checklist of documents.
- Questions to ask.
- Empty fields for an office to complete.
- Source URL and review date.
- “Baby Docs does not submit this for you.”

Offer a privacy-safe version that omits notes and receipt values. The packet should never include a Social Security number field.

### 12.5 Handoff mode

Many newborn tasks are completed by a partner, grandparent, doula, HR representative, or trusted helper. Create a local handoff card:

- Task title.
- Why it matters.
- Three steps.
- Documents to bring.
- Exact question to ask.
- What proof to return.
- Deadline and source.

The first version can be a safe text or PDF-like export. It should not require backend sharing. Later, configured family sharing can offer role-scoped access.

Roles should be narrower than “family member”:

- Owner.
- Parent or guardian.
- Helper.
- Read-only viewer.
- Benefits coordinator, if ever supported.

Never give a helper access to all notes or receipts by default.

### 12.6 Coverage verification cockpit

Instead of one insurance task, give the parent a small state machine:

1. Which coverage path applies?
2. Who must be notified?
3. What is the exact deadline?
4. Was the request submitted?
5. What effective date was confirmed?
6. Was the first premium or payroll change completed?
7. Did the baby’s claims route correctly?

The cockpit should support employer, Marketplace, Medicaid, CHIP, dual coverage, and “still figuring it out.” It should ask for the minimum information and never request portal credentials.

### 12.7 State and jurisdiction mesh

Many rules depend on more than the child’s birth state. Model:

- Place of birth.
- Residence.
- Employer location.
- Work location.
- Health plan jurisdiction.
- Marketplace jurisdiction.
- Parentage jurisdiction.
- Planned travel destination.

The rule engine should explain which jurisdiction drives each task. If the app cannot verify the right office, it should route to a federal directory or official agency finder rather than guess.

### 12.8 Source change ledger

When a rule changes:

- Show the old source review date.
- Show the new review date.
- Explain what changed in plain language.
- Identify affected tasks.
- Ask the parent to recheck only the affected steps.

Example:

“The IRS instructions changed the way this form is submitted. Your saved status is still preserved. Recheck the submission step.”

This makes review work visible and turns source stewardship into a user benefit.

### 12.9 Rule confidence and deadline provenance

Give every deadline a visual confidence tag:

- Official deadline.
- Plan-specific deadline.
- Agency estimate.
- Parent-entered date.
- Suggested follow-up.

Never use a single red color for all five. Parents need to know whether the app is quoting law, quoting their employer, or offering a reminder.

### 12.10 Office call scripts

For every external agency task, generate a short script:

“I am calling about adding a newborn after a birth on [date]. What is the exact deadline, what documents do you need, when will coverage be effective, and how will I receive confirmation?”

The script should use known facts, omit sensitive values, and include a blank to write down the representative’s name and a safe reference label.

### 12.11 Identity consistency check

A parent can lose time when a name, date, or parent detail differs across documents. Add a local comparison checklist:

- Baby legal name.
- Spelling and diacritics.
- Birth date.
- Birth location.
- Parent names.
- Relationship or parentage status.

The app should flag differences for review, not decide which document is correct. It should never ask the parent to paste a Social Security number.

### 12.12 Safe document locker, only after a threat model

A future document feature could allow a parent to photograph a birth certificate order receipt or insurance confirmation, but only with strict boundaries:

- Local-only by default.
- iOS file protection.
- Explicit per-file delete.
- No cloud sync until encrypted attachment sync is designed and reviewed.
- No OCR of Social Security numbers.
- Automatic redaction preview before export.
- A visible “this photo contains sensitive information” warning.
- No camera or photo permission until the feature actually exists.

The current Info.plist includes camera and photo usage strings even though the app does not implement attachment capture. Remove unused permission strings now, or implement the full secure feature later. Do not request trust for a capability that is not present.

### 12.13 Hard-deadline calendar bridge

Offer an optional calendar event only for:

- Employer coverage deadline.
- Marketplace coverage deadline.
- A user-entered plan-specific deadline.
- A confirmed follow-up date.

Do not fill a parent’s calendar with every suggestion. The default should be one reminder and one follow-up, not 20 notifications.

### 12.14 Sleep-deprived and one-handed mode

Design for the parent who has one hand free:

- Large next-action button.
- Short paragraphs.
- No critical action hidden behind a menu.
- VoiceOver labels that include status and deadline.
- Dynamic Type support.
- Reduced motion support.
- High contrast.
- No reliance on color alone.
- One-tap “not sure.”
- Undo after completion.

Add an optional read-aloud action for the current task. The read-aloud text must not include free-form sensitive notes.

### 12.15 Family admin relay

Later, with safe sync, allow a parent to assign one bounded task to another person:

- “Please call HR and ask these four questions.”
- “Please order two certified copies.”
- “Please save the confirmation date.”

The helper sees only the task packet. Completion comes back as a proposed update that the owner accepts, rather than silently changing the owner’s record.

### 12.16 Repair mode

Paperwork often goes wrong. Add a “Something is wrong” button to important tasks:

- Wrong name.
- Wrong birth date.
- Missing document.
- Agency says no record.
- Insurance denied.
- Application rejected.
- Office did not respond.

Repair mode should branch to the appropriate correction, appeal, or follow-up workflow, preserve the original evidence, and never reset the parent to a blank checklist.

### 12.17 Benefit discovery waterfall

Ask high-yield questions that identify programs without claiming eligibility:

- Could the household qualify for Medicaid or CHIP?
- Is WIC worth checking?
- Is there state paid leave?
- Is dependent-care assistance available?
- Is there a childcare subsidy or local waitlist?
- Is the family military, tribal, or federal employee eligible for a different route?

Every result should be “check this official source,” not “you qualify.”

### 12.18 New-child setup reuse

For a second child, offer to reuse:

- Parent contact preferences.
- Residence.
- Common employer and benefits contacts.
- Preferred pediatrician.
- Export style.

Do not reuse:

- Birth state.
- Birth date.
- Citizenship.
- Insurance status without confirmation.
- Child-specific documents.
- Prior task completion.

This can extend retention without becoming a baby tracker.

## 13. Recommended future architecture

### 13.1 Separate generated rule data from family-owned work

Preserve the current principle:

- The engine owns applicability, explanation, source, baseline deadline, and generated document suggestions.
- The family owns status, actual dates, assignments, notes, evidence, and confirmations.

Implement this as two conceptual layers even if they remain in one SwiftData model initially:

1. Rule projection: what the current catalog says.
2. Work record: what the family has done and what happened.

A catalog update must update the projection without deleting or rewriting family work.

### 13.2 Use a task workflow and event log

Recommended entities:

| Entity | Purpose |
| --- | --- |
| RuleDefinition | Stable key, version, applicability, jurisdiction, source, copy |
| RuleSource | URL, title, agency, subject, review date, status, reviewer |
| RequirementProjection | Current generated explanation, deadline candidates, document suggestions |
| TaskWork | User-owned state, assignment, actual dates, follow-up |
| TaskEvent | Immutable-ish timeline of status changes and external contacts |
| Deadline | Baseline, plan-specific, parent-entered, provenance, confidence |
| EvidenceItem | Receipt metadata or local attachment reference |
| Contact | Office, employer, agency, person, phone, safe label |
| ConflictCase | Local and server values, field, timestamps, resolution |
| RuleFeedback | Source issue, broken link, suggested correction, status |

Do not add every entity in one migration. A minimal next step is TaskWork fields and TaskEvent, then Deadline provenance, then EvidenceItem.

### 13.3 Source manifest design

For each source:

- Stable source key.
- Canonical URL.
- Display title.
- Agency.
- Subject key.
- Jurisdiction type: federal, state, county, employer, plan, agency, other.
- Jurisdiction code.
- Last human review date.
- Reviewer identity or review note.
- Status: verified, fallback, pending, stale, broken.
- Allowed claims.
- Explicit limitations.

The catalog should reference source keys, not repeat raw URLs and labels in every rule. This makes wrong URL reuse harder to introduce.

### 13.4 Sync design

Before enabling shared families:

- Use durable account-scoped local storage.
- Make every mutation carry account, family, entity, entity version, and client mutation ID.
- Use a server mutation sequence or opaque version token.
- Pull and push idempotently.
- Apply field-level or domain-specific merges.
- Keep unresolved conflicts visible.
- Never discard an outbox entry because a fetched row is missing.
- Keep tombstones until the server confirms they are durable and no device cursor can miss them.
- Add a durable sync cursor, not only an in-memory lastSyncedAt.
- Redact payload logs.

### 13.5 Backend integrity design

Every child graph row must have a family ID that is enforced by database constraints. If a task references a child, the child’s family must equal the task’s family. Repeat for every descendant.

Use security-definer RPCs for:

- Create family.
- Create child graph rows.
- Accept invite.
- Leave family.
- Transfer ownership.
- Delete family.
- Apply billing.

Keep direct table writes disabled unless there is a strong reason and complete RLS coverage.

### 13.6 Offline design

The local-only experience should remain complete:

- Rules and sources are bundled.
- Plan generation works without network.
- Local reminders work without network.
- Export works without network.
- Sharing screens clearly state when backend features are unavailable.
- Sync is an enhancement, not a prerequisite for the parent to know what to do.

## 14. Implementation roadmap

### Phase 0: Correctness and safety foundation

Do this before adding product breadth:

- Fix child merge direction.
- Scope family cache to authenticated user and active family.
- Validate group and account IDs on every push.
- Restore tombstoned deterministic tasks and documents.
- Remove destructive production store fallback.
- Stop swallowing local persistence failures.
- Gate or remove the Plus summary mismatch.
- Fix the bottom tab bar safe-area overlay.
- Rename the Trump Account SSN document and add no-number warnings.
- Correct or remove wrong source URLs.
- Add exact source subject tests.
- Add account-switch, stale-sync, tombstone-reactivation, and export-redaction tests.

Acceptance criteria:

- All existing unit and UI tests pass.
- New regression tests cover every P0 finding.
- A simulated persistence failure does not blank the plan.
- The summary capability and paywall copy agree.
- The longest task detail scrolls fully above the tab bar.

### Phase 1: Make the local app a trustworthy workflow

Implement:

- Task state machine.
- Deadline provenance and plan-specific override.
- Task event log.
- Follow-up date.
- Notification tap routing.
- Safe export modes and preview.
- Undo after completion.
- Explicit “not applicable” semantics.
- Source manifest and source report action.
- Dynamic Type and accessibility audit.
- Remove unused camera/photo permission strings.

Acceptance criteria:

- A parent can record submitted, waiting, received, correction needed, and follow-up.
- A generic 30-day baseline and a plan-specific 24-day deadline can coexist with clear provenance.
- Export preview shows exactly what will be shared.
- Notification tap opens the exact task on cold launch.

### Phase 2: High-value rule expansion

Implement in this order:

1. Birth record confirmation and correction.
2. Coverage verification cockpit.
3. Medicaid, CHIP, WIC discovery, and state sources.
4. Employer and state leave branches.
5. EOB and hospital claim follow-up.
6. Parentage branching.
7. Passport packet.
8. State 529 source routing.
9. Childcare and subsidy discovery.

Acceptance criteria:

- Every new rule has a manually reviewed source manifest entry.
- Every rule declares what it does not know.
- Every deadline has a provenance class.
- Every task has a completion state that reflects external confirmation when needed.

### Phase 3: Backend and shared family release

Do not turn on the feature flag until:

- Account-scoped local storage exists.
- The sync P0 fixes are merged.
- RLS and same-family constraints pass.
- Edge functions exist and deploy.
- RevenueCat webhook is idempotent and verified.
- Conflict UI exists.
- Invite acceptance has a two-device test.
- Account delete, leave, and ownership transfer have tested semantics.
- Production copy accurately describes what sharing does.
- docs/join.html is published at the exact invite path.

Acceptance criteria:

- Two parents can use one family on two devices without duplicate tasks.
- Offline edits do not overwrite newer edits.
- A removed member cannot pull or push after removal.
- An invite cannot be reused or brute-forced.
- Billing entitlement is family-scoped and correct after relaunch.

### Phase 4: Evidence and handoff

Only after the data and privacy model is stable:

- Safe local receipt attachments.
- Handoff packets.
- Role-scoped family assignments.
- Optional encrypted attachment sync.
- Source change ledger.
- Repair mode.

Acceptance criteria:

- No attachment is uploaded without explicit user consent.
- Export redaction is tested with synthetic sensitive values.
- A helper cannot see unrelated family notes or receipts.

### Phase 5: Distribution and retention

Keep acquisition aligned with the product:

- Employer benefits teams.
- Hospitals and discharge packets.
- OB and pediatric practices.
- Midwives and doulas.
- Health plans and benefits platforms.
- Parent organizations.

Do not make App Store keyword stuffing the product strategy. Maintain the existing anti-tracker positioning.

Retention should come from:

- The next child setup.
- Source-backed archive.
- Tax-year handoff.
- Passport renewal or later life-event paperwork only if it remains in scope.

Do not manufacture recurring health or child-tracking engagement.

## 15. Detailed test strategy

### 15.1 Rule catalog tests

For every rule:

- Applicability true path.
- Applicability false path.
- Unknown-input path.
- Birth date boundary.
- State boundary.
- Citizenship boundary.
- Insurance boundary.
- Parentage boundary.
- Preference toggle boundary.
- Source key and subject key.
- Official link or intentional no-link status.
- Deadline kind.
- Deadline explanation.
- Document titles and details contain no instruction to enter an SSN.

Specific boundary tests:

- Birth on December 31 and January 1 around Trump Account eligibility years.
- Citizen, non-citizen, and unknown.
- Employer, Marketplace, Medicaid/CHIP, none, and unknown insurance.
- Parentage state changes.
- Passport selected then deselected.
- FSA selected then deselected.
- Child birth state different from residence state.
- Unsupported territory and foreign birth.

### 15.2 Source integrity tests

Add a source test that rejects:

- Wrong source key reused for an unrelated subject.
- A source host that is not approved.
- A broken or empty URL.
- A link that does not match the rule’s declared subject.
- A source with no review date.
- A state-specific claim backed only by a federal fallback.

The test should not attempt to prove page semantics from HTML alone. Use a manually approved subject key and a review checklist.

### 15.3 RequirementEngine tests

Add:

- No-op reconciliation does not save.
- Generated task IDs are stable.
- Work fields remain unchanged after catalog copy changes.
- Source metadata updates without rewriting user work.
- Inapplicable untouched task tombstones.
- Inapplicable worked task remains visible and open.
- Tombstoned task restores in place.
- Tombstoned document restores in place.
- Rule version migration preserves receipts and notes.
- Two children with the same name and date still have distinct task IDs.
- Two devices generate the same logical task ID.

### 15.4 SwiftData and persistence tests

Use an injectable model context or store abstraction to test:

- Save failure.
- Outbox enqueue failure.
- Store migration.
- Corrupt store recovery.
- Locked device before first unlock.
- Low-storage response.
- Local wipe completeness.
- Account switch isolation.

### 15.5 Sync tests

Test actual SyncEngine behavior, not only pure merge helpers:

- Local newer child versus stale server child.
- Server newer child versus local dirty child.
- Same field changed by both sides.
- Different fields changed by both sides.
- Server tombstone versus local newer edit.
- Push row group mismatch.
- Outbox entry for a missing row.
- Duplicate outbox entries.
- Cursor resume after interruption.
- Pull then push idempotency.
- Tombstone retention.
- Removed family member.
- Family switch with stale outbox.
- Conflict case creation and resolution.

### 15.6 Supabase tests

Create supabase/tests and cover:

- Anonymous cannot read family data.
- Member can read permitted family graph.
- Member cannot write staff-only fields.
- Removed member loses access.
- Cross-family foreign links are rejected.
- Invite code is one-time.
- Invite code expires.
- Invite acceptance is rate-limited.
- Owner transfer works and is audited.
- Delete family only works for owner.
- Billing webhook requires verified service identity.
- Billing event is idempotent.
- Account deletion removes or anonymizes all server data required by policy.

### 15.7 UI tests

Add UI coverage for:

- Complete onboarding with every major insurance and parentage branch.
- Birth state different from residence state.
- Add second child without inheriting the wrong birth state.
- Plan list at the smallest device height.
- Long task detail at large Dynamic Type.
- Completion, undo, dismissal, and not-applicable states.
- Add receipt with a synthetic SSN-shaped string and verify the warning or block.
- Export preview and Plus gate.
- Paywall product load failure and retry.
- StoreKit purchase and restore.
- Notification cold-launch route.
- Invite link when sharing is disabled.
- Account deletion confirmation.
- Family leave and ownership transfer.

### 15.8 Accessibility and visual QA

Verify:

- VoiceOver reads task title, state, deadline kind, due date, and source.
- Buttons have labels that include their effect.
- Picker values are announced.
- Color is not the only status signal.
- Dynamic Type does not truncate critical copy.
- Reduced motion works.
- Contrast meets platform guidance.
- Tap targets are comfortably large.
- Scroll content clears the tab bar.
- Long navigation titles have short alternatives.

## 16. Release and operations checklist

### Before any local-only App Store build

- [ ] No wrong source URLs remain in live catalog rules.
- [ ] No copy asks for an SSN number.
- [ ] No export path silently includes arbitrary notes.
- [ ] Paywall benefits match actual gates.
- [ ] StoreKit disclosure and restore behavior are complete.
- [ ] Store failure does not blank the plan.
- [ ] Task detail clears the tab bar.
- [ ] Notification taps route to tasks.
- [ ] Accessibility and Dynamic Type pass.
- [ ] Metadata says sharing is unavailable while Supabase is off.
- [ ] docs/join.html is not advertised as an active sharing path if no backend exists.
- [ ] Camera and photo permission strings are removed if unused.

### Before enabling Supabase

- [ ] Account-scoped local data model is shipped.
- [ ] Sync child merge is fixed and tested.
- [ ] Push group validation is fixed and tested.
- [ ] Tombstone restoration is fixed and tested.
- [ ] Family cache clearing is fixed and tested.
- [ ] RLS and same-family relationship constraints pass.
- [ ] SQL tests exist and run in CI.
- [ ] Edge functions exist and deploy.
- [ ] RevenueCat webhook is verified and idempotent.
- [ ] Auth callback script is Baby Docs-specific.
- [ ] Invite page is live at the exact URL.
- [ ] Conflict resolution UI exists.
- [ ] Two-device tests pass with staging data.
- [ ] Sharing copy is restored only after the feature works.

### Before every app-code push

- [ ] Run the project’s required TestFlight script after app-code changes.
- [ ] Verify the build number and marketing version.
- [ ] Verify the source review date policy.
- [ ] Verify no production RevenueCat key is used in simulator runs.
- [ ] Verify the working tree contains only task-owned changes.
- [ ] Commit with a conventional commit and no Co-Authored-By line.

## 17. App Store, web, and support audit

### Metadata

Current en-US metadata is coherent with the local-only build:

- Name: Baby Docs: Newborn Paperwork.
- Subtitle: Deadlines, documents, done.
- The description presents the product as a paperwork concierge.
- The current copy does not promise second-parent sharing while the backend is disabled.
- Plus copy focuses on further children and the one-page summary.

Needs:

- Add a clear “does not submit forms for you” line near the top.
- Add a clear “does not store Social Security numbers” line.
- Keep legal, tax, health, and insurance language framed as information and preparation.
- Keep all prices out of description copy. Prices belong in the StoreKit UI and App Store pricing configuration.
- Add screenshots that show a source date, deadline provenance, and proof chain once those features exist.
- Do not show a screenshot of a sharing flow until sharing actually works.

### Landing page

docs/index.html correctly emphasizes deadlines, documents, official links, extra children, and summary rather than promising sharing. It includes structured price figures that can drift from StoreKit. Keep marketing price data synchronized or remove hardcoded prices from structured data.

### Invitation page

docs/join.html is a product dependency, not a marketing extra. Every old invite must continue to resolve there. Before an invite link is sent:

- The exact page must be published.
- The custom scheme and page code flow must agree.
- The code must expire and be one-time.
- The page must explain what information the recipient will see.
- A user should not be asked to install a build that cannot accept the invite.

Consider universal links only after the backend and Associated Domains setup are complete. A custom URL scheme is sufficient for a controlled TestFlight phase, but it is more susceptible to app collisions and less discoverable.

### Privacy policy

The privacy page is directionally aligned with the app, but its claims must follow actual deletion and sync behavior. Once sync is enabled, document:

- Which rows sync.
- How tombstones work.
- How long server data remains after deletion.
- What happens to local data on account deletion.
- How RevenueCat identity and family entitlement are connected.
- Whether push tokens are stored.
- Whether attachments are ever uploaded.

Do not promise that deletion removes data everywhere until local wipe, server delete, tombstone cleanup, backups, and cached notifications have been tested.

### Support

Add support topics for:

- A deadline that already passed.
- Employer plan says a different date.
- Baby’s name is wrong.
- The birth certificate source is not verified.
- A task is not applicable.
- A notification opened the wrong task.
- A sync conflict.
- Account switch and local data.
- Export privacy.
- StoreKit restore.

## 18. What the next agent should implement first

This is the shortest safe implementation brief:

1. Read the P0 findings in this document.
2. Fix SyncEngine.applyChild so stale server data cannot overwrite newer local child data.
3. Add account and family ownership to local cache and clear active family state on sign-out, no-membership refresh, and account switch.
4. Validate outbox group and account ownership before every push.
5. Restore deterministic tombstoned tasks and documents instead of inserting duplicate IDs.
6. Correct every mismatched source citation, starting with dependentCareFSA, newbornScreeningResult, beneficiaryUpdate, guardianNomination, pediatricPortal, and childcareWaitlist.
7. Rename any SSN document wording that could invite number entry and add export warnings or redaction.
8. Enforce the Plus summary gate or change the product promise.
9. Fix the tab bar overlay and notification task routing.
10. Add regression tests before expanding the catalog.
11. Build the source manifest and deadline provenance model.
12. Turn the current checklist into an evidence-backed workflow.
13. Only then add coverage, leave, Medicaid, WIC, EOB, parentage, passport, and edge-case branches.
14. Keep Supabase disabled until the backend and two-device tests exist.

Do not start by adding more cards to RequirementCatalog. The product needs truth, proof, and recovery more than it needs more surface area.

## 19. Decisions to preserve

These are deliberate strengths, not accidental omissions:

- No baby tracking.
- No automatic filing.
- No Social Security number storage.
- No deadline paywall.
- No guessed state-specific links.
- No sharing promises while the backend is disabled.
- Free local plan is useful without an account.
- Hard reminders only for genuinely consequential windows.
- Source and review date visible on tasks.
- Deterministic generated task IDs.
- Family work survives rule changes.
- Local-first architecture.
- Plain-language copy.
- Official links instead of invented advice.
- A one-time purchase as the lead Plus option.

## 20. Anti-goals

Do not implement:

- Feed, diaper, sleep, weight, growth, or milestone tracking.
- Medical diagnosis or treatment advice.
- Automated legal parentage filing.
- Automated insurance enrollment.
- Automated tax filing.
- A financial product marketplace.
- A generic article feed.
- Gamified streaks for paperwork.
- Notification spam for every suggestion.
- A subscription wall around a deadline.
- An opaque AI answer that has no source or review date.
- A cloud document vault before attachment privacy is designed.
- A requirement to enter an SSN to make the plan useful.

## 21. Official verification anchors

These are the official pages read for the current audit. They are anchors, not a substitute for a per-rule human source review.

### Health coverage windows

- U.S. Department of Labor, group health plan special enrollment after birth: https://webapps.dol.gov/elaws/ebsa/health/72.asp
- U.S. Department of Labor, newborn special enrollment FAQ: https://www.dol.gov/node/25144
- U.S. Department of Labor, Newborns and Mothers Health Protection Act FAQ PDF: https://www.dol.gov/sites/dolgov/files/EBSA/about-ebsa/our-activities/resource-center/faqs/newborns-mothers-health-protection-act-faqs.pdf
- HealthCare.gov, Special Enrollment Period glossary: https://www.healthcare.gov/glossary/special-enrollment-period/
- HealthCare.gov, Special Enrollment Period after a birth: https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/?os=av

### Trump Accounts

- IRS Trump Accounts overview: https://www.irs.gov/trumpaccounts
- IRS Form 4547 instructions: https://www.irs.gov/instructions/i4547
- IRS About Form 4547: https://www.irs.gov/forms-pubs/about-form-4547

When a source changes, update the source manifest and the affected rule’s review record. Do not silently change user-facing deadline language without a source change note.

## 22. Final implementation posture

Baby Docs can become unusually good because it is willing to be narrow. The winning product is not the app with the most newborn tasks. It is the app that is willing to say:

- “This is the one deadline that can hurt you.”
- “This is only a suggestion.”
- “This varies by your plan.”
- “We do not know yet.”
- “Here is exactly why we think this applies.”
- “Here is what to bring.”
- “Here is how to record proof.”
- “We did not submit anything for you.”
- “Do not put your Social Security number here.”

Build that trust layer first. Then add breadth one verified jurisdiction and one recoverable workflow at a time.
