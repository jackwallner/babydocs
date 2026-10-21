# Baby Docs: Google Play listing (en-US)

Source of truth for the Play Console store listing, adapted from
`fastlane/metadata/en-US/` for Android: Google Play billing and cancellation
wording, no Apple EULA, no prices in copy (Play shows them), no em dashes, and
the same Plus boundary the binary charges for (see `.claude/rules/plus-pricing-and-review.md`).

## Listing text

`metadata/android/en-US/` (fastlane supply layout):

- `title.txt` "Baby Docs: Newborn Paperwork" (28/30), the App Store name.
- `short_description.txt` (78/80).
- `full_description.txt` (3,419/4,000).

The launcher label is "Baby Docs", as on iOS.

## Graphics

- `icon-512.png` 512 x 512, no alpha, from the iOS `AppIcon` 1024 (`sips -z 512 512`, re-encoded rgb24).
- `feature-graphic.png` 1024 x 500, no alpha: the icon on its own navy (#031336)
  beside a crop of the real Plan capture (ffmpeg composite; ffmpeg on jmbp has
  no drawtext, so there is no rendered headline).
- `screenshots/` five 1080 x 1920 PNGs (no alpha): raw 1080 x 2400 debug
  captures from `agent-emu-1` on jmbp (status bar demo mode, 09:41), scaled to
  1920 high and centred on the page colour. Free state only (no Plus unlock, no
  paywall): Plan, the Job-based plan task, Documents, Children, the intake
  welcome. Raw captures in `raw/`. The sample family is `SampleData`.

## Products (to create in Play Console)

| Play product | Type | Base plan / offer | RevenueCat package |
|---|---|---|---|
| `com.jackwallner.babydocs.pro.weekly` | Subscription | base plan `weekly` (P1W), offer `trial-3d` (P3D free, new customers) | `$rc_weekly` |
| `com.jackwallner.babydocs.pro.yearly` | Subscription | base plan `yearly` (P1Y), no trial (iOS has none) | `$rc_annual` |
| `com.jackwallner.babydocs.pro.lifetime` | One-time product | buy option `lifetime` | `$rc_lifetime` |

iOS US prices: $4.99/week with a 3-day trial, $29.99/year, $59.99 once. The
fleet rule puts Android about 20% under iOS ($3.99 / $23.99 / $47.99); the
Android US price is a decision for Jack. The RevenueCat `default` offering also
carries `$rc_monthly`, which iOS does not sell; leave it unmapped on Play.
iOS prices, the `BabyDocs+` entitlement and the `default` offering are untouched.

## Policy answers (from the code)

- Ads: none. Account: none. App access: everything without a login. Reviewer
  access to Plus: Settings, long-press the Version line, enter the code
  (`PLAY_REVIEW_CODE` in `~/.babydocs_credentials`, created on jmbp 2026-10-20),
  tap Unlock. Only its SHA-256 ships (`PLAY_REVIEW_CODE_SHA256` in ignored
  `android/local.properties`).
- Target audience: 18+ (parents). Not directed at children.
- Content rating: reference/productivity; no violence, sexuality, gambling,
  user-generated content shared with others, or location.
- Health: not a medical app; newborn screening is a records errand and the app
  never reads or interprets a result. No Health Connect.
- Financial features: none (links to IRS and benefits pages only; no money moves).
- Permissions: INTERNET (RevenueCat), POST_NOTIFICATIONS (local deadline
  reminders), RECEIVE_BOOT_COMPLETED (re-arm reminders). No location, camera,
  contacts or storage permission: the vault uses the system photo picker.
- Data Safety: collected by the RevenueCat SDK only. Financial info > Purchase
  history; App activity > App interactions (paywall view counts and app-open
  count as subscriber attributes); Device or other IDs (RevenueCat's anonymous
  app user ID, not an advertising ID). Purposes: app functionality and
  analytics. Encrypted in transit. Not shared. Deletion on request through
  support. Household answers, tasks, notes and vault photos are device-only and
  are not collected. A shared plan link is sent by the user to a person of
  their choice; it is not transmitted to the developer.
