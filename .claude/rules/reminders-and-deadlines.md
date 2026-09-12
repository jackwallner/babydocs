---
paths:
  - "Shared/Services/DeadlineReminderScheduler.swift"
  - "Shared/Services/NotificationService.swift"
  - "Shared/Services/ReminderPreferences.swift"
  - "Shared/Rules/RequirementCatalog.swift"
  - "BabyDocsTests/RemindersAndExportTests.swift"
  - "Shared/Models/BabyModels.swift"
---

# Baby Docs: hard deadlines and reminders

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

- **Two dates are hard, the rest are not.** Job-based health plans must allow at
  least 30 days after a birth; the Marketplace is 60. Those are the only
  deadlines `DeadlineReminderScheduler` warns about unprompted, and the warnings
  are **free forever**: a reminder for the two dates that legally close, behind a
  paywall, would make the app the cause of the miss. Everything else it can say
  is opt-in and comes with Plus (`Options`): the suggested dates three days out,
  a Sunday digest that stays silent on an empty week, and a reminder the parent
  set themselves. A suggestion that fires at 9am *unbidden* is what teaches
  someone to switch the whole category off, and then they miss the one that
  mattered.
  - Hard deadlines claim the platform's pending-notification budget first
    (`maxScheduled`). Sorting everything by date and taking the first two dozen
    looks fair and lets a fortnight of suggestions push the 60-day Marketplace
    warning off the end of the queue.
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
