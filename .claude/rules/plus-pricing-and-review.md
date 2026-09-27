---
paths:
  - "Shared/Services/StoreService.swift"
  - "Shared/Services/ReviewPromptTracker.swift"
  - "Shared/Services/VaultStore.swift"
  - "BabyDocs/Views/PaywallView.swift"
  - "BabyDocs/Views/PlusPurchaseView.swift"
  - "BabyDocs/Views/PlusView.swift"
  - "BabyDocs/Views/FeedbackSheet.swift"
  - "BabyDocs/Views/DocumentsView.swift"
  - "BabyDocs/Views/TaskDetailView.swift"
  - "BabyDocs/Services/Products.storekit"
  - "scripts/asc-readiness.py"
  - "scripts/asc-set-iap-prices.py"
  - "scripts/rc-setup.py"
  - "fastlane/**/*"
  - "BabyDocsTests/PlusTierTests.swift"
  - "BabyDocsTests/ReviewPromptTests.swift"
  - "BabyDocsTests/PaywallFunnelTests.swift"
  - "Shared/Services/DeadlineReminderScheduler.swift"
  - "Shared/Rules/PlanTimeline.swift"
  - "BabyDocs/Views/Components/HubComponents.swift"
  - "Shared/Rules/RequirementCatalog.swift"
---

# Baby Docs: pricing, free vs Plus, and the review ask

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

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

- **Free is every deadline, every link, every document list, every child, the
  warnings for the two windows that legally close, and sending the plan to the
  other parent.** A deadline behind a paywall is a deadline the app caused
  someone to miss. **Plus is timing and order**: reminders for the dates the app
  suggests, a reminder the parent sets, the Sunday digest, the timeline
  (`PlanTimeline`), and a calendar export. It also keeps the older gates: the
  vault beyond the first twelve weeks, follow-up tracking, the employer packet
  and the printable summary.
  - **Further children were gated once and must not be again.** Twins are one
    birth, one household and one set of answers, so the bill landed on the
    family that had the harder delivery. It is a fact about the household rather
    than a moment of value, and a paywall in front of a fact reads as a toll.
  - The timeline is the app's *own* opinion and says so. `StartAdvice` on a rule
    produces sequencing and nothing else: it never sets `dueAt`, never makes a
    suggestion `hard`, and phrases itself in words ("once the certified copy
    arrives") rather than in a date nobody's name is on. The blocked cases are
    the point: the passport is the birth certificate wearing a hat, and the
    $1,000 election is the Social Security card wearing one.

- **Vault access survives a lapse.** Lapsing stops you *adding*; it never takes
  back a photograph already there. The paywall says so. Anything else is holding
  a parent's documents hostage, and Apple's refund team would agree.

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

- **What Plus gates lives in several places that drift apart.** The binary
  (`SummaryShareControl`, `TaskDetailView`, `DocumentsView.addButton`,
  `PlusToolsView` and `DeadlineReminderScheduler.Options`) charges for the
  suggested-date reminders and the digest, the parent's own reminders, the
  timeline, the calendar export, follow-up tracking, the vault after twelve
  weeks, the printable summary and the employer packet. The description and the
  App Review notes have to say the same thing, and both once said the summary
  and the packet were free. `asc-readiness.py` asserts it, because nothing
  recompiles when a `.txt` file changes, and its `PAID_FEATURES` list is also
  where "further children" is documented as deliberately absent.

- **The pitch is a tab, not only a locked door.** `PlusPurchaseView` is one view
  shown in three places (`PaywallView`'s sheet, the Plus tab, the last page of
  the intake), because three copies of a benefit list is how a paywall ends up
  promising something the build does not do. The tab is the offer before
  purchase and the tools after it: a customer who has paid should not watch a
  fifth of their tab bar keep advertising what they own.
  - The intake's offer comes **after** the plan is built, never before the
    questions: a pitch in front of an empty app sells a promise rather than a
    thing. Its button says "Get started" because in the intake the trial is the
    way forward, with the price, period and renewal printed directly above it
    and Apple's own sheet still to confirm. "Continue with the free plan" is
    always there.
