# aso-plan.md — Baby Docs

> Written 2026-08-14. App: **Baby Docs: Newborn Paperwork** (ASC ID `6799785786`,
> bundle `com.jackwallner.babydocs`, repo `~/babydocs`). Pre-launch: 1.0 is in
> `PREPARE_FOR_SUBMISSION` and has never been searchable, so every ranking claim
> below comes from reading live SERPs rather than from this app's own data.

---

## 0. TL;DR

- **There is no keyword with both real volume and winnable difficulty, and the
  numbers say so rather than the brief.** Every tracked term with popularity at
  or above 25 has difficulty at or above 62 *and* resolves to a field about
  something else. Every term whose intent is actually right sits at Astro's
  popularity floor of 5. That is the whole finding, and it is quantitative.
- **The two queries this app is named after both resolve to unrelated fields.**
  `newborn paperwork` returns baby trackers and registries; `birth certificate`
  returns certificate *design* apps and genealogy (popularity 5, difficulty 45).
- **`parental leave` is the one right-intent term that is cheap:** difficulty
  **9**, the lowest in the tracked set by a distance, with a top 8 that is
  corporate and abandoned. It is also popularity 5, so winning it wins little.
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

Astro placeholder app `128` ("Baby Docs (pre-launch research)") tracks 22 terms.
Popularity and difficulty below are its numbers, read 2026-08-15.

| term | pop | diff | in field? | read |
|---|---|---|---|---|
| documents | 66 | 81 | yes | Highest volume available. Scanners and PDF editors, so the difficulty is honest, but it is the only real fuel there is. |
| baby | 60 | 78 | no | Correctly excluded: `Baby` is in the app name and already indexed. |
| vault | 58 | 68 | yes | Password managers. Weak intent, but it names a shipped feature. |
| passport | 57 | 62 | yes | Passport-photo apps. One task out of twenty. |
| forms | 57 | 72 | no | Same tier as `documents` and not yet used. |
| medicaid | 32 | 67 | yes | **Wall.** UnitedHealthcare (824k★) and state portals; the searcher is managing an existing case. |
| social security | 29 | 38 | yes | Lowest difficulty of anything with real volume. Keep. |
| taxes | 25 | 70 | yes | **Wall.** Intuit and H&R Block, and this is not a tax product. |
| file storage | 15 | 70 | no | Cloud drives. |
| records | 14 | 51 | yes | Reasonable middle. |
| newborn | 13 | 65 | no | In the app name already. |
| checklist | 9 | 63 | yes | Poor trade: floor-adjacent volume at high difficulty. |
| organizer | 8 | 73 | no | |
| health insurance | 7 | 78 | ~ | Field carries bare `insurance`. |
| **parental leave** | 5 | **9** | yes | **Cheapest term in the set by a factor of four.** Right intent. Keep permanently. |
| deadlines | 5 | 21 | no | In the subtitle already. |
| paperwork | 5 | 39 | no | In the app name already. |
| birth certificate | 5 | 45 | no | In the subtitle, and section 1 shows the field is certificate *makers*. |
| new parent checklist / baby checklist / new baby / important documents | 5 | 37-59 | no | Floor volume. |

**Current (98 chars):**

```
documents,vault,passport,social security,medicaid,taxes,records,insurance,parental leave,checklist
```

**Proposed (97 chars), applied:**

```
documents,vault,records,forms,insurance,social security,parental leave,fmla,enrollment,new parent
```

| OUT | why |
|---|---|
| `medicaid` (32/67) | The SERP is UnitedHealthcare and six state benefit portals. Nothing this app does ranks there, at any difficulty. |
| `taxes` (25/70) | Intuit's field. The app has one tax-adjacent task and files nothing. |
| `passport` (57/62) | Real volume, but the field is passport photos and renewals, so a rank there converts to an uninstall. |
| `checklist` (9/63) | Floor volume at high difficulty. The word is doing no work the name is not. |

| IN | why |
|---|---|
| `forms` (57/72) | Straight swap for `passport`: same volume tier, and at least the intent is administrative. |
| `fmla` | Untracked, so this is a bet rather than a measurement. It names the situation exactly and nothing generic competes for an acronym. **Add it to app 128 to get a number.** |
| `enrollment` | Untracked. Both hard deadlines in the app are enrollment windows, and it is the BenefitBump adjacency. |
| `new parent` | Broad-match fuel that combines with `leave`, `forms` and the name's `newborn`. |

Name and subtitle already index `Baby`, `Docs`, `Newborn`, `Paperwork`, `Birth`,
`Certificate` and `Deadlines`. **None of those may appear in the field**, and the
proposed set keeps that discipline.

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

Tracked as placeholder app **`128`** ("Baby Docs (pre-launch research)"), 22 US
keywords, which is where section 2's popularity and difficulty numbers come from.

**Open, and it is the one gap in section 2:** `fmla`, `enrollment`, `new parent`
and `forms` went into the keyword field on the strength of an argument rather
than a number, because `add_keywords` returned `Failed to fetch keyword
popularity` on 2026-08-14. Retry:

```
mcp__astro__add_keywords(appId="128", store="us",
  keywords=["fmla","enrollment","new parent","forms","maternity leave",
            "family leave","open enrollment","life event","benefits"])
```

If any of them comes back at popularity 5 with difficulty above 60, it is
occupying characters for nothing and should give them back to `documents` or
`forms` combinations.

At launch, migrate off the placeholder:

```
mcp__astro__add_app(appStoreId="6799785786")
```

Rankings populate over 24 to 48 hours. The claim to test then is section 0's:
that the `parental leave` cluster ranks, that nothing else does, and that neither
fact moves installs, because the channel is section 4.
