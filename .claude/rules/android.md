---
paths:
  - "android/**"
  - "scripts/android-*"
  - "scripts/sync-android-*"
---

# Baby Docs Android rules

## Product

- Native port in `android/`: Kotlin, Compose, Gradle Kotlin DSL, JDK 17,
  minSdk 26, target/compile 36. Package and namespace `com.jackwallner.babydocs`
  (permanent once uploaded), launcher label "Baby Docs", Play title
  "Baby Docs: Newborn Paperwork". versionName follows iOS `MARKETING_VERSION`
  (1.1.2), versionCode 1 (bump before every upload).
- Screen for screen with iOS: the intake (welcome, baby, household, coverage,
  leave, newborn account, 529, passport, plan ready with the one notification
  prompt, then the Plus offer with "Continue with the free plan") and the five
  tabs Plan / Children / Documents / Plus / Settings. Pushed screens and sheets
  are an overlay stack in `AppGraph.Navigator`.
- The rules are not transcribed. `scripts/sync-android-parity.sh` compiles the
  Swift sources (`Shared/Rules`, the enums of `BabyModels.swift`, `DateOnly`,
  `PlanSeed`, `DeterministicID`) with `scripts/android-export/main.swift` and writes:
  - `app/src/main/resources/babydocs-reference.json`: states, the catalog's
    static rule fields and document lists, the source manifest, the 51 vital
    records offices and 3,110+ county names, loaded by `rules/Reference.kt`.
  - `app/src/test/resources/babydocs-parity.json`: all 23 rules evaluated over
    240 households. `PortParityTest` compares applies, title, detail, date,
    kind, basis and link (5,520 comparisons), plus DeterministicID v5 bytes,
    the SSN pattern, county matching and a Swift-made plan link.
  Only the rule closures (`applies`, `detail`, `deadline`, `link`, the two
  `titleForFamily`) are Kotlin, in `rules/RequirementCatalog.kt`; a Swift rule
  with no Kotlin logic fails at startup. Rerun the script whenever any of those
  Swift files change, then run the unit tests.
- Storage is one JSON file in app-private storage (`BabyStore`), the SwiftData
  equivalent. Every change goes through `BabyStore.commit`, which reconciles
  every plan, rolls back and alerts on an SSN-shaped string or a failed write.
  Tombstones, deterministic task/document ids and "engine owns the rule, family
  owns the work" are ported from `RequirementEngine.swift`.
- Records are plain mutable objects behind `BabyStore.revision`. Every lazy
  item and `TaskRow`/`ChildCard` reads the revision itself: strong skipping
  otherwise keeps a row whose captured record is the same instance and draws it
  stale (it hid a just-set reminder in testing). Keep that read in new items.
- Intentional differences from iOS: no location helper (no location
  permission; state and county are picked); the vault adds photos through the
  system photo picker (no camera permission) and unlocks with BiometricPrompt
  (biometric or screen lock, once per foreground session; a phone with no
  screen lock opens it directly); Play In-App Review with no question first
  (Settings has separate Rate and Send feedback rows); Play cancellation
  wording; no Apple EULA link; reminders use inexact `AlarmManager.setWindow`
  (no exact-alarm declaration). Shared plan links open through the
  `babydocs://plan?d=` deep link that `docs/plan.html` already emits.
- Paid boundary = iOS: free is every task, deadline, link, document list, every
  child, the two hard-window warnings (7 and 1 days, 9am) and sending the plan
  link. Plus gates suggested-date reminders, the Sunday digest, the parent's own
  reminder, the timeline, calendar export, follow-up tracking, the vault after
  84 days (vault reading survives a lapse), the printable summary and the
  employer packet.
- Billing: RevenueCat project `proj1aaf9104` (shared with iOS). Debug uses the
  Test Store app `appddec789928` (key in ignored `local.properties`
  `REVENUECAT_TEST_KEY`), offering `default`. Plus is entitlement `BabyDocs+`
  or the legacy `pro` / `BabyDocsPro`, as on iOS. Release needs a `goog_` key:
  no RevenueCat Play app exists yet, so release builds fail
  `validateReleaseConfiguration` by design.
- Reviewer access: Settings, long-press the Version line, code
  `PLAY_REVIEW_CODE` in `~/.babydocs_credentials` (created on jmbp
  2026-10-20; copy it and `PLAY_REVIEW_CODE_SHA256` to the Air before the
  release build).
- Debug launch extras (debug only, `src/debug/.../DebugLaunchOptions.kt`):
  `uiTest`, `resetAll`, `seed` (the iOS `SampleData` family), `demoPro`,
  `previewStore`, `previewTrialUsed`, `tab plan|children|documents|plus|settings`,
  `screen paywall|household|sources|timeline|task-<catalogKey>`.

## Build and test (fleet Pro, jmbp)

- `fm-gradle clean assembleDebug assembleDebugAndroidTest assembleQa lintDebug testDebugUnitTest`
  from `android/` (runs on jmbp; never `./gradlew` on the Air). Lint has 0 errors; the warnings are dependency bumps, `toUri`
  style hints and the legacy round-icon shape.
- Connected tests: boot a leased AVD headless (`emulator -avd agent-emu-1
  -port 5556 -no-window -no-audio -no-boot-anim -no-metrics -gpu host -cores 3
  -no-snapshot-save`), then `ANDROID_SERIAL=emulator-5556
  scripts/android-connected-tests.sh [--no-build]`. It runs each UI Automator
  test with `pm clear` between, passes the reviewer code as an instrumentation
  argument, writes `android/app/build/outputs/androidTest-results/connected/TEST-babydocs-smoke.xml`,
  and fails on any failure or a zero count. Dialogs are their own window:
  give every new dialog `DialogTags` or its test tags are invisible. Stop the
  AVD with `adb -s emulator-5556 emu kill`. Never touch `small_phone` or
  another agent's device.
- jmbp is an Intel i7-5557U: interaction video records at about 4 fps, so
  native 60 fps cannot be proven there. Motion review belongs on the Air.

## Release state (2026-10-20)

- Build and test acceptance on jmbp (run shift-android-babydocs-1-1792552123):
  32 JVM tests (5,520 Swift parity comparisons), 9/9 device tests on
  agent-emu-1 (API 36 Play image), lint clean, QA build ignores debug hooks and
  runs without a store key. No Play app, upload key, RevenueCat Play app, Play
  products or upload yet.
- Remaining, in order (Air release worker / Console):
  1. Decide the Android US price (fleet rule $3.99 / $23.99 / $47.99, or iOS parity).
  2. Create the upload keystore `~/.android/keystores/babydocs-upload.p12` and
     `PLAY_UPLOAD_*` in `local.properties`; build signed AAB/APK; verify 16 KB
     alignment of the RevenueCat native libs.
  3. Create the Play app (E3 Apps) and the three products (`trial-3d` on weekly).
  4. Add a RevenueCat Play app to `proj1aaf9104`, attach the Play products to
     the `default` offering's `$rc_weekly` / `$rc_annual` / `$rc_lifetime`
     packages and the `BabyDocs+` entitlement, put its `goog_` key in
     `local.properties`, and register it in `~/.rc-clean/apps.json` (android
     block plus `"ios": {"filter_platform": "iOS"}`) the same day.
  5. Listing, graphics and policy answers from `android/play-assets/listing-en-US.md`;
     publish the updated `docs/privacy-policy.html` (Android section).
  6. Internal track upload, licensed-tester purchase and restore, then a
     production draft. Production send waits for its pacing slot.
