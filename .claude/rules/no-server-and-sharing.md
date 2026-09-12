---
paths:
  - "Shared/Services/PlanSeed.swift"
  - "Shared/Services/BabyModelStore.swift"
  - "BabyDocs/Views/Sharing/*.swift"
  - "BabyDocs/PrivacyInfo.xcprivacy"
  - "BabyDocs/Views/PlusPurchaseView.swift"
  - "docs/**/*"
  - "fastlane/**/*"
  - "BabyDocsTests/VaultAndSharingTests.swift"
---

# Baby Docs: no server, sharing, and what the copy may claim

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here.

### Why there is no server

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

### What the copy may claim

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

- **`docs/plan.html` is part of the app, not the marketing site.** Every shared
  plan link points at it (`PlanSeed.webBase`), and those messages sit in inboxes
  longer than the build that wrote them, so the page has to stay published at
  that exact path and no build whose share link is live may ship before the page
  is. The payload rides in the URL *fragment*, which browsers never send to a
  server, so the page receives nothing about the family. Do not move it into the
  query string.
