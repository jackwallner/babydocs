---
paths:
  - "Shared/Rules/*.swift"
  - "Shared/Services/LocationLookup.swift"
  - "BabyDocs/Views/HouseholdEditorView.swift"
  - "BabyDocs/Views/TaskDetailView.swift"
  - "BabyDocs/Views/SettingsView.swift"
  - "BabyDocsTests/RequirementCatalogTests.swift"
  - "BabyDocsTests/RequirementEngineTests.swift"
  - "BabyDocsTests/SourceIntegrityTests.swift"
  - "Shared/Models/BabyModels.swift"
---

# Baby Docs: the rules engine

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### Catalog files

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

### Rules about rules

- **Every rule shows its working.** Each task carries the government URL its
  rule came from and the date it was last checked, visible on the task itself
  rather than behind an info button. A rules app whose rules quietly go stale is
  worse than no app, so `RequirementCatalog.reviewedOn` is surfaced in Settings.

- **No turnaround time is ever hardcoded.** Follow-up tracking asks the family
  what the office told them and nudges from that. Processing times move
  constantly and differ by county, so a bundled figure would be a citation the
  app cannot support, which is the same rule as `StateVitalRecords`.
