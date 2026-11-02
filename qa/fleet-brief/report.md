# Release gate: babydocs-ship 733f83234a10

Verdict: **BLOCK** (2026-11-02T03:42:35+00:00)

Every finding blocks except legacy backlog. `qa-gate fix <repo>` fixes them. Motion candidates need a judgement in the ledger: `qa-gate ledger <repo> accept` for an intended change, or `add` a P1 when it is a real glitch.

## Blocking (9)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P0 | journey-broken | duo | testFirstPlanAndOptionalPlus /  | failed - Could not scroll the requested control into view: "US citizen" Button | `journey-broken|testFirstPlanAndOptionalPlus` |
| P0 | journey-broken | duo | testPlanDocumentsPlusAndReturn /  | failed - Could not scroll the requested control into view: "Order certified copies of the birth certificate, Sent, and past the date it was expected back, Identity. Identity · Assign someone · 3 to gather, Identity. Identity · Assign someone · 3 to gather" Button | `journey-broken|testPlanDocumentsPlusAndReturn` |
| P1 | fleetqa-stale |  |  /  | vendored FleetQA.swift differs from ~/ios/qa; rerun after install | `fleetqa-stale` |
| P2 | overlap | accessibility | testFirstPlanAndOptionalPlus / coverage | button "Not sure yet" overlaps "Continue" by 28% (AX3 text only) | `overlap|testFirstPlanAndOptionalPlus|coverage|continue / not sure yet` |
| P2 | overlap | accessibility | testPlanDocumentsPlusAndReturn / plan-after-task | button "Order certified copies of the birth certificate, Sent, and past the date it was expected back, Identity. Identity · Assign someone · 3 to gather, Identity. Identity · Assign someone · 3 to gat | `overlap|testPlanDocumentsPlusAndReturn|plan-after-task|order certified copies of the birth certificate, sent, and p` |
| P2 | a11y-contrast | accessibility | testPlanDocumentsPlusAndReturn / documents | Contrast failed: "Proof of the birth" | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|proof of the birth` |
| P2 | overlap | accessibility | testPlanDocumentsPlusAndReturn / plan-return | button "Order certified copies of the birth certificate, Sent, and past the date it was expected back, Identity. Identity · Assign someone · 3 to gather, Identity. Identity · Assign someone · 3 to gat | `overlap|testPlanDocumentsPlusAndReturn|plan-return|order certified copies of the birth certificate, sent, and p` |
| P2 | overlap | accessibility | testPlanDocumentsPlusAndReturn / plan-after-background | button "Order certified copies of the birth certificate, Sent, and past the date it was expected back, Identity. Identity · Assign someone · 3 to gather, Identity. Identity · Assign someone · 3 to gat | `overlap|testPlanDocumentsPlusAndReturn|plan-after-background|order certified copies of the birth certificate, sent, and p` |
| P1 | core-journey-missing |  |  /  | no testCoreLoop journey proves the core feature still works; write one (/Users/jackwallner/ios/qa/core-journey-brief.md) | `core-journey-missing` |

## Needs a judgement (0)

None.

## Legacy backlog, warns until fixed (162)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast nearly passed: "A tax-advantaged savings account for education. Most states run their own, several give residents a state tax deduction for paying into it, and you can use another state's if  | `a11y-contrast|testFirstPlanAndOptionalPlus|529|a tax-advantaged savings account for education. most states ` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast failed: "Add this to my plan" | `a11y-contrast|testFirstPlanAndOptionalPlus|529|add this to my plan` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|529|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast nearly passed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|529|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast nearly passed: "You can change this later in the household answers without redoing any of this." | `a11y-contrast|testFirstPlanAndOptionalPlus|529|you can change this later in the household answers without r` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / 529 | Contrast nearly passed: "Your answer" | `a11y-contrast|testFirstPlanAndOptionalPlus|529|your answer` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "A job-based plan must let you add the baby within 30 days of the birth. The Marketplace gives 60. Miss it and you usually wait for open enrollment. Covered both ways? Pick the job pl | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|a job-based plan must let you add the baby within # days of ` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "A separate election from the health plan, with its own window, and the one most often missed. Your employer sets that window rather than the law, so it is shown as a suggestion to co | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|a separate election from the health plan, with its own windo` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "Choose a coverage answer, including Not sure yet, to carry on." | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|choose a coverage answer, including not sure yet, to carry o` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast nearly passed: "This sets the only two dates in the app that legally close." | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|this sets the only two dates in the app that legally close.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast failed: "We have a dependent care FSA" | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|we have a dependent care fsa` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / coverage | Contrast nearly passed: "Where the coverage comes from" | `a11y-contrast|testFirstPlanAndOptionalPlus|coverage|where the coverage comes from` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast failed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast nearly passed: "Nothing is selected yet. Pick one and this will say what it puts on the plan." | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|nothing is selected yet. pick one and this will say what it ` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast nearly passed: "Paid or unpaid time off after the birth, from an employer, a state programme, or federal job protection." | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|paid or unpaid time off after the birth, from an employer, a` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast nearly passed: "Parental leave" | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|parental leave` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / leave | Contrast nearly passed: "Pick one to carry on. "Nobody" is a real answer here." | `a11y-contrast|testFirstPlanAndOptionalPlus|leave|pick one to carry on. "nobody" is a real answer here.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / newborn-account | Contrast nearly passed: "A one-time $1,000 federal contribution into an investment account for children born between 2025 and 2028. The IRS calls these Trump Accounts, which is the name you will see o | `a11y-contrast|testFirstPlanAndOptionalPlus|newborn-account|a one-time $# federal contribution into an investment accoun` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / newborn-account | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|newborn-account|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / newborn-account | Contrast nearly passed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|newborn-account|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / newborn-account | Contrast nearly passed: "You can change this later in the household answers without redoing any of this." | `a11y-contrast|testFirstPlanAndOptionalPlus|newborn-account|you can change this later in the household answers without r` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / newborn-account | Contrast nearly passed: "Your answer" | `a11y-contrast|testFirstPlanAndOptionalPlus|newborn-account|your answer` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "3 days free" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|# days free` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "3 days free, then $4.99 every 7 days. Renews automatically at $4.99 every 7 days until cancelled. Cancel any time in Settings." | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|# days free, then $# every # days. renews automatically at $` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "Continue with the free plan" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|continue with the free plan` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "every 7 days" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|every # days` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "For the weeks the paperwork is actually happening." | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|for the weeks the paperwork is actually happening.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "Get started" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|get started` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "If you would rather not think about it again this year." | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|if you would rather not think about it again this year.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "Keeps the document vault for good. No renewal." | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|keeps the document vault for good. no renewal.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "one-time payment" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|one-time payment` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "per year" | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|per year` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Contrast nearly passed: "The list of what applies to you is free, and so are both dates that legally close. Plus is the part that tells you when to do the rest, in what order, and says something befor | `a11y-contrast|testFirstPlanAndOptionalPlus|onboarding-paywall|the list of what applies to you is free, and so are both dat` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast nearly passed: "A US passport for a child under 16. Both parents have to appear in person with the child, or the absent one has to send a notarised consent form." | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|a us passport for a child under #. both parents have to appe` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast failed: "Add this to my plan" | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|add this to my plan` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast nearly passed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast nearly passed: "You can change this later in the household answers without redoing any of this." | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|you can change this later in the household answers without r` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / passport | Contrast nearly passed: "Your answer" | `a11y-contrast|testFirstPlanAndOptionalPlus|passport|your answer` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast failed: "1" | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|#` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast failed: "Change household answers" | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|change household answers` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast failed: "Coming up, not urgent yet." | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|coming up, not urgent yet.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast nearly passed: "Every closing window is behind you. What is left has no date attached to it." | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|every closing window is behind you. what is left has no date` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast nearly passed: "Next 31 days" | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|next # days` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast failed: "NOTHING CLOSING" | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|nothing closing` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-after-onboarding|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-ready | Contrast nearly passed: "11 tasks apply to your family." | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-ready|# tasks apply to your family.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-ready | Contrast nearly passed: "Baby Docs tracks paperwork. It is not legal, tax, medical or insurance advice, it does not file anything on your behalf, and deadlines set by your own plan or your own state o | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-ready|baby docs tracks paperwork. it is not legal, tax, medical or` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / plan-ready | Contrast nearly passed: "See my plan" | `a11y-contrast|testFirstPlanAndOptionalPlus|plan-ready|see my plan` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / welcome | Contrast nearly passed: "About a minute. Nothing is submitted anywhere." | `a11y-contrast|testFirstPlanAndOptionalPlus|welcome|about a minute. nothing is submitted anywhere.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / welcome | Contrast nearly passed: "Answer a few questions about your household and you get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each | `a11y-contrast|testFirstPlanAndOptionalPlus|welcome|answer a few questions about your household and you get the ` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / welcome | Contrast nearly passed: "Get started" | `a11y-contrast|testFirstPlanAndOptionalPlus|welcome|get started` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "Check the date of birth to carry on." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|check the date of birth to carry on.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast failed: "Citizenship" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|citizenship` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast failed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "Date of birth" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|date of birth` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "Every deadline counts from the date of birth, and the state that registered it issues the certificate." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|every deadline counts from the date of birth, and the state ` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast failed: "The certificate comes from where the birth was registered, not from where you live now." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|the certificate comes from where the birth was registered, n` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "The one answer worth double-checking, because every other date in the app is derived from it." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|the one answer worth double-checking, because every other da` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "Use my location to fill these in" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|use my location to fill these in` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-baby | Contrast nearly passed: "Where the birth was registered" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-baby|where the birth was registered` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast failed: "A neutral task will remind you to ask the birth registrar whether parentage paperwork applies. Baby Docs will not assume a legal situation or tell you to sign a form." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|a neutral task will remind you to ask the birth registrar wh` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast failed: "Back" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|back` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast failed: "Continue" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|continue` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast nearly passed: "Parents" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|parents` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast nearly passed: "Pick the state you live in to carry on." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|pick the state you live in to carry on.` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast nearly passed: "Sets your Medicaid and CHIP agency, and whether there is a state paid-leave programme to file with." | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|sets your medicaid and chip agency, and whether there is a s` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast nearly passed: "Where you live" | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|where you live` |
| P2 | a11y-contrast |  | testFirstPlanAndOptionalPlus / your-household | Contrast nearly passed: "Where you live helps route the agency. Leave rules also depend on the employer and the state where that parent works. Who is on the record decides one legally significant task | `a11y-contrast|testFirstPlanAndOptionalPlus|your-household|where you live helps route the agency. leave rules also depe` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "11 days old, born in California" | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|# days old, born in california` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "15 left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|# left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "A second baby inherits your household answers, so the questions are not asked twice. Every child is free." | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|a second baby inherits your household answers, so the questi` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "Add another child" | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|add another child` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "Household answers" | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|household answers` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast failed: "R" | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|r` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / children | Contrast nearly passed: "Where you live, how you are covered, whether you are taking leave. Changing an answer here rebuilds every child's plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|children|where you live, how you are covered, whether you are taking ` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast failed: "3" | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast nearly passed: "Add the baby to the Acme PPO plan" | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|add the baby to the acme ppo plan` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast failed: "Due Nov 20" | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|due nov #` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast nearly passed: "Most plans accept the hospital record while the certificate is still being issued." | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|most plans accept the hospital record while the certificate ` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast nearly passed: "Plans generally cannot refuse enrollment for a number that has not arrived. Tell them it is pending. Do not type the number into Baby Docs. Nothing here needs it, and receipts | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|plans generally cannot refuse enrollment for a number that h` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / documents | Contrast nearly passed: "What to take to each errand. Tick something and it ticks on every task that wants it." | `a11y-contrast|testPlanDocumentsPlusAndReturn|documents|what to take to each errand. tick something and it ticks on ` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast failed: "1" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast nearly passed: "Friday, Nov 20 · 19 days left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|friday, nov # · # days left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast nearly passed: "NEXT HARD DEADLINE" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|next hard deadline` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast failed: "Not arrived" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|not arrived` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast failed: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|past the date the office told you to expect it. nothing else` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast nearly passed: "Sent, and still not here" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|sent, and still not here` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-background | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-background|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast failed: "1" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast nearly passed: "Friday, Nov 20 · 19 days left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|friday, nov # · # days left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast nearly passed: "NEXT HARD DEADLINE" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|next hard deadline` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast failed: "Not arrived" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|not arrived` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast failed: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|past the date the office told you to expect it. nothing else` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast nearly passed: "Sent, and still not here" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|sent, and still not here` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-relaunch|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast failed: "1" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast nearly passed: "Friday, Nov 20 · 19 days left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|friday, nov # · # days left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast nearly passed: "NEXT HARD DEADLINE" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|next hard deadline` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast failed: "Not arrived" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|not arrived` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast failed: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|past the date the office told you to expect it. nothing else` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast nearly passed: "Sent, and still not here" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|sent, and still not here` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-after-task | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-after-task|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast failed: "1" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast nearly passed: "Friday, Nov 20 · 19 days left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|friday, nov # · # days left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast nearly passed: "NEXT HARD DEADLINE" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|next hard deadline` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast failed: "Not arrived" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|not arrived` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast failed: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|past the date the office told you to expect it. nothing else` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast nearly passed: "Sent, and still not here" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|sent, and still not here` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-launch | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-launch|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast failed: "1" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|#` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast nearly passed: "Friday, Nov 20 · 19 days left" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|friday, nov # · # days left` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast nearly passed: "NEXT HARD DEADLINE" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|next hard deadline` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast failed: "Not arrived" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|not arrived` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast failed: "Past the date the office told you to expect it. Nothing else in your life is going to mention this, which is why it is at the top." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|past the date the office told you to expect it. nothing else` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast nearly passed: "Sent, and still not here" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|sent, and still not here` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plan-return | Contrast nearly passed: "Update the answers that shape every deadline in this plan." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plan-return|update the answers that shape every deadline in this plan.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "3 days free" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|# days free` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "3 days free, then $4.99 every 7 days. Renews automatically at $4.99 every 7 days until cancelled. Cancel any time in Settings." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|# days free, then $# every # days. renews automatically at $` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "every 7 days" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|every # days` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "For the weeks the paperwork is actually happening." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|for the weeks the paperwork is actually happening.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "If you would rather not think about it again this year." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|if you would rather not think about it again this year.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "Keeps the document vault for good. No renewal." | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|keeps the document vault for good. no renewal.` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "one-time payment" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|one-time payment` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "per year" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|per year` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "Restore purchases" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|restore purchases` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "Start my free trial" | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|start my free trial` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / plus | Contrast nearly passed: "The list of what applies to you is free, and so are both dates that legally close. Plus is the part that tells you when to do the rest, in what order, and says something befor | `a11y-contrast|testPlanDocumentsPlusAndReturn|plus|the list of what applies to you is free, and so are both dat` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / settings | Contrast nearly passed: "A rule set is only as fresh as its stalest page, so the date above is the oldest of them. Every state and DC links to that state's own vital records office, and the list says  | `a11y-contrast|testPlanDocumentsPlusAndReturn|settings|a rule set is only as fresh as its stalest page, so the date` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / settings | Contrast nearly passed: "Baby Docs tracks paperwork. It is not legal, tax, medical or insurance advice, it does not file anything on your behalf, and deadlines set by your own plan or your own state o | `a11y-contrast|testPlanDocumentsPlusAndReturn|settings|baby docs tracks paperwork. it is not legal, tax, medical or` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / settings | Contrast nearly passed: "Sources" | `a11y-contrast|testPlanDocumentsPlusAndReturn|settings|sources` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / settings | Contrast nearly passed: "What this app is" | `a11y-contrast|testPlanDocumentsPlusAndReturn|settings|what this app is` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / task-detail | Contrast nearly passed: "Identity" | `a11y-contrast|testPlanDocumentsPlusAndReturn|task-detail|identity` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / task-detail | Contrast nearly passed: "No legal deadline. Ask the issuing office when the record and certified copies will be ready, because filing and processing times differ by jurisdiction." | `a11y-contrast|testPlanDocumentsPlusAndReturn|task-detail|no legal deadline. ask the issuing office when the record an` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / task-detail | Contrast nearly passed: "Timing" | `a11y-contrast|testPlanDocumentsPlusAndReturn|task-detail|timing` |
| P2 | a11y-contrast |  | testPlanDocumentsPlusAndReturn / task-detail | Contrast nearly passed: "Where to do it" | `a11y-contrast|testPlanDocumentsPlusAndReturn|task-detail|where to do it` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / 529 | Hit area is too small: "Question 6 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|529|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / coverage | Hit area is too small: "Question 3 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|coverage|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / leave | Hit area is too small: "Question 4 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|leave|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / newborn-account | Hit area is too small: "Question 5 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|newborn-account|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / onboarding-paywall | Hit area is too small: "Continue with the free plan" | `a11y-hit-region|testFirstPlanAndOptionalPlus|onboarding-paywall|continue with the free plan` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / passport | Hit area is too small: "Question 7 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|passport|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / plan-after-onboarding | Hit area is too small: "Progress" | `a11y-hit-region|testFirstPlanAndOptionalPlus|plan-after-onboarding|progress` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / your-baby | Hit area is too small: "Question 1 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|your-baby|question # of #` |
| P2 | a11y-hit-region |  | testFirstPlanAndOptionalPlus / your-household | Hit area is too small: "Question 2 of 7" | `a11y-hit-region|testFirstPlanAndOptionalPlus|your-household|question # of #` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plan-after-background | Hit area is too small: "Progress" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plan-after-background|progress` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plan-after-relaunch | Hit area is too small: "Progress" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plan-after-relaunch|progress` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plan-after-task | Hit area is too small: "Progress" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plan-after-task|progress` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plan-launch | Hit area is too small: "Progress" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plan-launch|progress` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plan-return | Hit area is too small: "Progress" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plan-return|progress` |
| P2 | a11y-hit-region |  | testPlanDocumentsPlusAndReturn / plus | Hit area is too small: "Restore purchases" | `a11y-hit-region|testPlanDocumentsPlusAndReturn|plus|restore purchases` |
| P2 | cta-jump |  | testFirstPlanAndOptionalPlus / coverage | the main button "Continue" is at y 596, 350 by 78; on "your-household" it was at y 636, 350 by 78 (AX3 text only) | `cta-jump|testFirstPlanAndOptionalPlus|coverage|continue` |
| P2 | cta-jump |  | testFirstPlanAndOptionalPlus / newborn-account | the main button "Continue" is at y 636, 350 by 78; on "leave" it was at y 596, 350 by 78 (AX3 text only) | `cta-jump|testFirstPlanAndOptionalPlus|newborn-account|continue` |
| P2 | overlap |  | testFirstPlanAndOptionalPlus / welcome | text "Answer a few questions about your household and you get the tasks that actually apply to you, the dates that actually close, and a link to the office that actually issues each thing." overlaps " | `overlap|testFirstPlanAndOptionalPlus|welcome|about a minute. nothing is submitted anywhere. / answer a fe` |
| P2 | overlap |  | testFirstPlanAndOptionalPlus / your-household | text "Where you live helps route the agency. Leave rules also depend on the employer and the state where that parent works. Who is on the record decides one legally significant task." overlaps "Pick t | `overlap|testFirstPlanAndOptionalPlus|your-household|pick the state you live in to carry on. / where you live hel` |
| P2 | overlap |  | testPlanDocumentsPlusAndReturn / documents | button "Proof of the birth, Most plans accept the hospital record while the certificate is still being issued." overlaps "gearshape" by 84% (AX3 text only) | `overlap|testPlanDocumentsPlusAndReturn|documents|proof of the birth, most plans accept the hospital record wh` |
| P2 | paywall-restore |  | testFirstPlanAndOptionalPlus / onboarding-paywall | no Restore Purchases control on the paywall (3.1.1) | `paywall-restore|testFirstPlanAndOptionalPlus|onboarding-paywall|` |
| P2 | truncated |  | testFirstPlanAndOptionalPlus / onboarding-paywall | button drawn as "Continue with the free..." but reads "Continue with the free plan" (AX3 text only) | `truncated|testFirstPlanAndOptionalPlus|onboarding-paywall|continue with the free plan` |

## Journeys

| Persona | Journey | Result | Seconds |
|---|---|---|---|
| newcomer | testFirstPlanAndOptionalPlus | Passed | 102.24159097671509 |
| newcomer | testPlanDocumentsPlusAndReturn | Passed | 113.23464703559875 |
| accessibility | testFirstPlanAndOptionalPlus | Passed | 126.80293798446655 |
| accessibility | testPlanDocumentsPlusAndReturn | Passed | 98.07093703746796 |
| reduce-motion | testFirstPlanAndOptionalPlus | Passed | 113.93956196308136 |
| reduce-motion | testPlanDocumentsPlusAndReturn | Passed | 88.73847603797913 |
| duo | testFirstPlanAndOptionalPlus | Failed | 75.83952796459198 |
| duo | testPlanDocumentsPlusAndReturn | Failed | 106.64433097839355 |

## Motion

| Persona | Motion s | Windows | Candidates | Gaps > 25 ms | 60 fps |
|---|---|---|---|---|---|
| newcomer | 30.729 | 32 | 6 | 56 | True |
| accessibility | 55.831 | 43 | 4 | 131 | True |
| reduce-motion | 24.432 | 32 | 3 | 54 | True |

## Launch entrances to look at

Each launch's frames after the springboard zoom, left to right then down, 4 frames per
row at the recorded rate. A blank stretch, text that reflows, or content that arrives and
pushes the layout is a finding: `qa-gate ledger <repo> add`.

- [entrance-01-testfirstplanandoptionalplus.png](/Users/jackwallner/babydocs-ship/build/qa/733f83234a10/newcomer/entrance-01-testfirstplanandoptionalplus.png)
- [entrance-01-testfirstplanandoptionalplus.png](/Users/jackwallner/babydocs-ship/build/qa/733f83234a10/accessibility/entrance-01-testfirstplanandoptionalplus.png)
- [entrance-01-testfirstplanandoptionalplus.png](/Users/jackwallner/babydocs-ship/build/qa/733f83234a10/reduce-motion/entrance-01-testfirstplanandoptionalplus.png)
- [entrance-13-testplandocumentsplusandreturn.png](/Users/jackwallner/babydocs-ship/build/qa/733f83234a10/reduce-motion/entrance-13-testplandocumentsplusandreturn.png)

Skipped personas: german (app not localized).
