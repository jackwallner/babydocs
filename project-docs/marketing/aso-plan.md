# aso-plan.md — Baby Docs

> Written 2026-08-22. App: **Baby Docs: Newborn Paperwork** (ASC ID `6799785786`,
> bundle `com.jackwallner.babydocs`, repo `~/babydocs`). Pre-launch: 1.0 is in
> `PREPARE_FOR_SUBMISSION` and has never been searchable, so every ranking claim
> below comes from reading live SERPs rather than from this app's own data.

---

## 0. TL;DR

- **The only meaningful volume/difficulty exception is `social security`, at
  29/38.** The other terms with popularity at or above 25 either sit at
  difficulty 62 or higher or resolve to a neighboring field such as car
  insurance, private-photo vaults, or generic form editors. The right-intent
  newborn terms mostly sit at Astro's popularity floor of 5. That is the whole
  finding, and it is quantitative.
- **The two queries this app is named after both resolve to unrelated fields.**
  `newborn paperwork` returns baby trackers and registries; `birth certificate`
  returns certificate *design* apps and genealogy (popularity 5, difficulty 45).
- **`parental leave` is a right-intent term that is cheap:** difficulty **9**,
  with a top 8 that is corporate and abandoned. `fmla` is even cheaper at 5,
  but both have popularity 5, so winning either wins little.
- **The finding that matters is not a keyword.** `parental leave` surfaced
  **BenefitBump**, an employer-purchased new-parent benefits navigator. A
  company built a business on this exact problem and reaches the parent through
  HR, not through search. That is the channel, and it is what section 4 is about.

---

## 1. What the SERPs actually say (us store, read 2026-08-14)

| query | what ranks | verdict |
|---|---|---|
| `newborn paperwork` | Babylist (138k★), BabyCenter (295k★), Pampers, cry translators | **Dead field.** Not one result is administrative. Apple has no concept of this query and falls back to "baby". |
| `birth certificate` | Public Records App, Certificate Maker (312★), Ancestry (634k★), FamilySearch (498k★) | **False friend.** The searcher wants to order one; the store offers apps for *designing* certificates. |
| `baby documents` | Baby's Bounty, Baby Sticker (20k★), photo books, registries, a PDF signer | **False friend.** "Documents" collapses into scrapbooks. |
| `medicaid` | UnitedHealthcare (824k★), Your Texas Benefits (377k★), state portals | **Wall, and wrong intent.** These people are managing an existing case. |
| `new baby checklist` | Baby Checklist & Hospital Bag (101★), NOLU (18★), Babylist | Beatable head, **shopping intent**. A hospital-bag list, not a deadline. |
| `parental leave` | Parental Leave Toolkit (0★, 2018), RETAIN Coaching Hub (4★), **BenefitBump** (8★), then PTO trackers | **The one winnable field.** No incumbent, and the intent is right. |

The pattern is consistent: every query describing the *artifact* (certificate,
documents, paperwork) resolves to a field about making or scrapbooking that
artifact. Only the query describing the *situation* (`parental leave`) resolves
to apps about the administrative problem. Write metadata for the situation.

## 2. Keyword field

Astro placeholder app `128` ("Baby Docs (pre-launch research)") tracks 47 terms.
The original terms were read 2026-08-15; the added candidates were refreshed
2026-08-23 UTC.

| term | pop | diff | in field? | read |
|---|---|---|---|---|
| documents | 66 | 81 | yes | Highest volume available. Scanners and PDF editors, so the difficulty is honest, but it is the only real fuel there is. |
| baby | 60 | 78 | no | Correctly excluded: `Baby` is in the app name and already indexed. |
| vault | 58 | 68 | no | Private-photo vaults. The shipped feature is supporting proof, not the searcher's job. |
| passport | 57 | 62 | no | Passport-photo apps. One task out of twenty. |
| forms | 57 | 72 | no | Google Forms and document editors. The narrower government phrase is better. |
| medicaid | 32 | 67 | yes | **Wall.** UnitedHealthcare (824k★) and state portals; the searcher is managing an existing case. |
| social security | 29 | 38 | yes | Lowest difficulty of anything with real volume. Keep. |
| taxes | 25 | 70 | yes | **Wall.** Intuit and H&R Block, and this is not a tax product. |
| file storage | 15 | 70 | no | Cloud drives. |
| records | 14 | 51 | no | Replaced by the more specific `vital records` phrase. |
| newborn | 13 | 65 | no | In the app name already. |
| checklist | 9 | 63 | no | Poor trade: floor-adjacent volume at high difficulty. |
| organizer | 8 | 73 | no | |
| health insurance | 7 | 78 | no | The live insurance field is dominated by car insurance apps. |
| **parental leave** | 5 | **9** | yes | **Cheapest term in the set by a factor of four.** Right intent. Keep permanently. |
| **fmla** | 5 | **5** | yes | Exact employer-leave intent, with the lowest observed difficulty. |
| **enrollment** | 5 | **11** | yes | Names the health-plan action the app actually organizes. |
| **vital records** | 5 | **23** | yes | Directly names the birth-certificate office problem. |
| **government forms** | 5 | **9** | yes | The live results include government-form finders, not generic document editors. |
| **new parent** | 5 | **46** | yes | Audience qualifier, retained because it matches the product's one-time moment. |
| deadlines | 5 | 21 | no | In the subtitle already. |
| paperwork | 5 | 39 | no | In the app name already. |
| birth certificate | 5 | 45 | no | In the subtitle, and section 1 shows the field is certificate *makers*. |
| new parent checklist / baby checklist / new baby / important documents | 5 | 37-59 | no | Floor volume. |

**Previous (98 chars):**

```
documents,vault,records,forms,insurance,social security,parental leave,fmla,enrollment,new parent
```

**Current (98 chars), applied:**

```
documents,social security,parental leave,fmla,enrollment,vital records,government forms,new parent
```

| OUT | why |
|---|---|
| `insurance` (41/86) | The live SERP is dominated by car insurance apps. The app organizes health-plan enrollment, not insurance policies. |
| `vault` (58/68) | The live SERP is dominated by private-photo vaults. The feature is supporting proof, not the searcher's job. |
| `forms` (57/72) | The live SERP is Google Forms and document editors. The narrower government phrase is a better intent match. |
| `records` (14/51) | Replaced by the more specific `vital records` phrase. |

| IN | why |
|---|---|
| `vital records` (5/23) | Direct birth-certificate intent at a low difficulty. |
| `government forms` (5/9) | More specific and more honest than generic `forms`. |
| `new parent` (5/46) | Audience fuel that combines with `leave` and the name's `newborn`. |

The refresh tracked 47 US terms in Astro. `benefits` tested at 40/62, but its
live results are workplace and public-benefits portals, so it stays out of the
field until the product has ranking data. `family leave` tested at 5/5 and is a
strong alternative, but it repeats the `leave` token already carried by
`parental leave`; the current field preserves more distinct tokens.

Name and subtitle already index `Baby`, `Docs`, `Newborn`, `Paperwork`, `Birth`,
`Certificate` and `Deadlines`. **None of those may appear in the field**, and the
current set keeps that discipline.

**Do not chase:** `baby` (60/78), `pregnancy`, or `tracker` in any combination.
Those are category heads defended by six-figure rating counts, and the app is
deliberately not a tracker (see CLAUDE.md), so ranking there would buy installs
from people looking for the thing it refuses to be.

## 3. Product page

- **Screenshots 1 to 3 have to survive being shown alone**, because that is how
  search results render them. They are currently the deadline list, the "why it
  applies and where to do it" detail, and the document checklist, which is the
  right order: it is the three questions a parent arrives with.
- **The subtitle is doing the search work the keyword field cannot.** `Birth
  Certificate & Deadlines` at 29 characters is well used. Leave it this cycle.
- The description opens on the problem rather than the product ("nobody tells
  you what applies to you"), which is right for a page most visitors will reach
  from a link rather than from a query.

## 4. The channel, which is not search

Search volume for this problem is close to zero **and that is not a failure of
the metadata**. The need appears once, lasts about twelve weeks, and nobody
knows the app category exists, so nobody types a query for it. People in this
situation are reached where they already are:

- **Employers and benefits platforms.** BenefitBump is the proof: it sells to
  HR, not to parents. Baby Docs already exports an employer packet built around
  the qualifying life event, which is the artifact an HR team recognises.
- **Hospitals and OB practices.** The discharge packet is the single highest
  intent moment there is, and it is currently a photocopied sheet.
- **The second parent.** `PlanSeed` makes every user a distribution channel by
  design, the share is free, and the receiving parent lands in the app already
  set up. This is the only loop in the product, and it is the reason "send the
  plan" must never move behind the paywall.

Measure the loop before spending anything on search: if the shared link does not
convert, no keyword will.

## 5. Astro

Tracked as placeholder app **`128`** ("Baby Docs (pre-launch research)"), 47 US
keywords. The real ASC record cannot be added until the app is searchable, so
Astro cannot report a Baby Docs ranking before launch.

The refresh succeeded on 2026-08-22. The terms that moved into the field now
have measured scores: `fmla` 5/5, `enrollment` 5/11, `vital records` 5/23,
`government forms` 5/9, and `new parent` 5/46. The removed terms were also
measured rather than guessed: `insurance` 41/86, `vault` 58/68, and `forms`
57/72, with live results that do not match the product.

At launch, migrate off the placeholder:

```
mcp__astro__add_app(appStoreId="6799785786")
```

Rankings populate over 24 to 48 hours after the app becomes searchable. The
claim to test then is section 0's:
that the `parental leave` cluster ranks, that nothing else does, and that neither
fact moves installs, because the channel is section 4.
