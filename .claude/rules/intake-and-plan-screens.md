---
paths:
  - "BabyDocs/Views/Onboarding/*.swift"
  - "BabyDocs/RootView.swift"
  - "BabyDocs/Views/PlanView.swift"
  - "BabyDocs/Views/DocumentsView.swift"
  - "BabyDocs/Views/TaskDetailView.swift"
  - "Shared/Rules/TaskPlanner.swift"
  - "Shared/Services/PlanExporter.swift"
  - "BabyDocsUITests/OnboardingUITests.swift"
  - "BabyDocsTests/TaskPlannerTests.swift"
---

# Baby Docs: the intake and the plan screens

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here.

- **"Not sure" is an answer, everywhere it is offered.** Coverage and parentage
  both filtered their `.unknown` case out of the intake and blocked Continue
  until something was picked. That does not produce knowledge, it produces a
  guess, and a guess turns on the wrong hard deadline or turns off the
  legally significant parentage task. Unknown coverage generates
  `coverageUnknown` at the top of the plan instead: a real task about finding
  out, with no date the app invented.

- **A ticked task stays where it is.** It used to drop out of its section into a
  collapsed disclosure at the bottom of the plan, which makes ticking
  indistinguishable from deleting: the row a parent just dealt with vanishes
  from the only place they would look for it. `TaskPlanner.CompletedPlacement`
  is `.inPlace` for the screen and `.ownBucket` for the exporter, where a flat
  DONE list at the end is the right shape for a page read start to finish.
  Ticked rows bucket by `completedAt`, **not** by today, or a task finished
  comfortably inside its window reappears weeks later under "Past due" and tells
  a parent they missed something they did not. Dismissed is different and does
  leave the plan: "does not apply to us" is a statement about the rule.

- **Every question in the intake is the same shape.** `OnboardingStep` is hero
  (icon, question, one line), form, pinned footer, and `OnboardingFooter` holds
  two footnote lines of space open whether or not there is a note. Half the
  questions used to open with a hero and half straight into a form header, which
  moved the first row about eighty points between screens, and the note
  appearing with a validation error moved Continue *within* one screen. What
  should move between two questions is the words and the glyph.
  - `RootView` keeps the intake on screen until `OnboardingFlow` says it is
    finished, rather than until a child exists. The child is written by
    `finish()`, so the root used to swap itself for the tab bar in the same
    instant: the plan-is-ready page and the one prompt for notification
    permission were drawn for a fraction of a frame and never seen by anybody.

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
