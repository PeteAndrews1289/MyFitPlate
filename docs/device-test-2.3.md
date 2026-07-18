# Live 2.2 Observation and Version 2.3 Device Closure

Version 2.2 went live on 2026-07-14. The first uploaded build was withdrawn before publication,
and build 2 was rejected during App Store processing because the embedded Watch app lacked
`NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`; the corrected replacement
passed processing. This checklist now tracks post-release observation and the physical gates for
version 2.3. The filename retains
the internal 2.3 milestone label so existing roadmap links and evidence remain stable. The
older 2.2 checklist is release history; do not rerun all of it unless a touched shared surface
regresses.

## Automated baseline

The following must be green on the release commit:

- MyFitPlateCore tests and the 80% line-coverage gate.
- MyFitPlate app unit tests and UI smoke tests.
- Strict SwiftLint, `git diff --check`, localization JSON validation, and privacy/secret review.
- Unsigned generic physical-iOS Release build with the companion Watch app embedded.
- Functions tests/build/audit, Firestore Rules emulator tests, and migration-runner tests when those folders changed.

Latest pre-closure evidence on 2026-07-12: Core 1,022/1,022 with 85.24% line coverage,
app 83/83, UI 15/15, Functions 11/11 with zero production dependency vulnerabilities,
strict lint/catalog/diff/plist/project checks, localization JSON validation, and the unsigned
generic physical-iOS Release build passed. A post-rejection generic physical-iOS Release build
also passed on 2026-07-12. The current product is version 2.2 build 3 across phone, widget,
Live Activity, and Watch; it embeds the companion with the correct identifiers, both required
HealthKit purpose strings, and arm64_32 plus arm64 architectures. Xcode's Watch/store and
embedded-binary validation passed. The main privacy manifest parses. App result:
`.codex_xcode/TestResults-2.2b2-app-final.xcresult`. UI result:
`.codex_xcode/TestResults-2.2b2-ui-final.xcresult`.

Latest version 2.3 local closure evidence on 2026-07-14: Core passed 1,102/1,102 at 84.24%
line coverage and the app target passed 110/110. The broad UI run passed 76/77 executions; its
single two-second legacy Workout Dashboard timeout passed 5/5 immediate repetitions, and a
final-source focused pass then passed 4/4. Strict lint, visual-system, diff, plist, project, and
privacy checks passed, as did the unsigned generic physical-iOS Release build. The packaged app,
widget, Live Activity, and Watch products are version 2.3 build 1. The Watch app contains both
HealthKit purpose strings and arm64_32 plus arm64, and the main privacy manifest parses. Physical
experience judgments and the signed archive remain open below.

Latest Gate 3 automated preflight on 2026-07-15: Core passed 1,134/1,134 and the app target passed
110/110. The definitive broad UI matrix passed 80 test methods / 83 executions with no failures or
skips. It covers the principal Home, Grocery, Meal Plan, Maia, Fast Food Builder, Reports, running,
strength, recovery, sharing, deep-link, dark-mode, and large-text journeys. The two interactions
that dropped taps in an earlier broad run each passed five focused repetitions after receiving a
narrow state-aware retry, then passed in the final full matrix. Focused coverage also proves that
stale meal-plan Grocery items are replaced without deleting manual entries and that an implausible
6,420 cal/day Adaptive TDEE remains visibly non-actionable. Strict SwiftLint, the visual-system
guard, `git diff --check`, and the complete unsigned Debug build with phone, Watch, widget, and Live
Activity targets passed. Results: `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate3-UI-Final.xcresult`,
`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate3-Robustness.xcresult`, and
`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate3-App-Tests.xcresult`. These deterministic
checks do not replace the physical acceptance steps below.

Latest unattended Gate 4 rehearsal on 2026-07-15: Core passed 1,134/1,134 at 83.80% line coverage;
the app passed 110/110 at 7.63% line coverage; Functions passed 25/25 with zero production
dependency vulnerabilities; Firestore Rules passed 23/23 with zero test-harness vulnerabilities;
and migrations passed 10/10. The unsigned generic-device Release build passed. Its phone, widget,
Live Activity, and Watch bundles are version 2.3 build 1 with coherent identifiers and expected
device architectures. The embedded Watch app has the correct companion identifier plus both
HealthKit purpose strings, and every bundled privacy manifest parses. The deterministic 2.3 Store
gallery was regenerated and visually checked in all 16 required 6.9-inch and 6.5-inch outputs.
Result: `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate4-App-Coverage.xcresult`; release
product: `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/.codex_gate2_xcode/Build/Products/Release-iphoneos/MyFitPlate.app`.
This was rehearsal evidence and is superseded by the exact-candidate closure below.

Exact-candidate Gate 4 closure on July 15-16: binary source commit `a020e8d0` passed Core
1,134/1,134 at 83.80%, app 110/110 at 7.63%, and the complete UI matrix at 80 methods / 83
executions with no failures or skips. Functions passed 25/25, Firestore Rules 23/23, migrations
10/10, strict lint, visual guard, audits, privacy checks, and the generic Release build. Xcode
created the signed archive and successfully exported a 62 MiB App Store Connect IPA with
cloud-managed distribution signing. All four products remain 2.3 build 1, `get-task-allow` is
false, App Attest is production, Watch purpose strings and architectures are correct, and all 34
privacy manifests parse. Production provider smoke and fail-safe configuration checks also passed.
See `docs/release-evidence-2.3.md`. The remaining hands-on work is condensed into
`docs/physical-acceptance-2.3.md`; use that script instead of reconstructing a test order from this
historical document.

Physical feedback on July 16 superseded that archive as the final release candidate. The current
source fixes Reports date/icon clarity, durable Meal Plan persistence, stale generated Grocery
replacement, generic-food source agreement disclosure, NIH multivitamin ranking and Opti-Men UPC
recovery, and an optional higher-quality Maia voice. Focused Core tests pass 63/63, Functions pass
28/28, the live NIH library resolves UPC `748927052497` with 19 mapped nutrients, and the complete
unsigned physical-iOS Debug build passes with phone, Watch, widget, and Live Activity. The affected
physical checks below, Functions deployment, final full gate rerun, and a replacement archive are
required before submission.

Five-star closure evidence on July 16: MyFitPlateCore passes 1,143/1,143 tests, Functions pass
28/28, SwiftLint reports zero violations across the 214 Swift files in the shipping lint scope,
and the complete simulator Debug build passes with phone, Watch, widget, and Live Activity
validation. A focused UI test also passes the live-workout and Recovery Field journey, including
tapping Core and observing the evidence panel update. Settled captures are under
`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/FiveStarFoundation-Captures-20260716`; the focused
UI result is
`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/FiveStarRecovery-UI-20260716-1547.xcresult`.
The dark Accessibility XXXL recovery/workout result is
`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/FiveStarRecovery-A11y-UI-20260716-1610.xcresult`.
These checks close source and simulator recommendations but do not convert the physical items below
into passes.

Final unattended current-source rehearsal on July 17: MyFitPlateCore passed 1,218/1,218 tests at
83.59% line coverage, app tests passed 115/115 at 8.48%, Functions passed 33/33, Firestore Rules
passed 33/33, and migrations passed 10/10. Core also passed full Address Sanitizer and Thread
Sanitizer runs. The broad UI catalog recorded 79 direct passes. Its Maia action path and launch
path each completed the required state/assertions before an iOS simulator interaction/teardown
interruption, then each passed five consecutive isolated repetitions. Strict lint, visual and
privacy guards, credential/structured-file checks, unsigned Release build, and static analysis all
passed. The Watch simulator completed Today, stale-sync explanation, next action, queued repeat
meal, water, and weight journeys. Physical disconnected/reconnect behavior remains open because a
simulated paired Watch continued reporting the phone reachable after the phone simulator stopped.

This rehearsal also caught and fixed two real regressions: Home's Workouts quick action now changes
tabs directly instead of depending on transient view state, and Home's protein target/remaining
copy now shares nearest-gram rounding so the same value no longer differs by one gram. Both are
regression-tested.

Final candidate closure on July 17: app commit `39e3d1a2` is committed and pushed; the deployed
Functions remain at matching backend commit `0aa44de9`. Core passes 1,220/1,220 at 83.69%, exact-
candidate app tests pass 115/115, the production-equivalent UI catalog passes 81/81, and the full
sanitizer, Functions, Rules, migration, lint, privacy, Release build, and analysis evidence remains
green. Xcode created and exported the signed 2.3 (1) archive. The final package restores direct
USDA access, excludes provider secrets, validates all four product signatures and 39 privacy
manifests, and has `get-task-allow=false`. Peter accepted the physical sections 1-9 on July 17.
Peter accepted the final-source upgrade, five-tab, disposable-log, and Watch-refresh smoke on July
18. Only processed-build/App Store console actions and deliberately post-release evidence remain.

## Version 2.3 Living Day owner gates

The implementation, deterministic rendering, simulator accessibility, privacy, performance, CI,
and rollback matrices are automated locally. Peter directly accepted the completed physical items
below on July 17; the remaining unchecked entries require a processed App Store build or retained
post-release calibration evidence:

- [x] In Firebase Remote Config, confirm `feature_livingDayHome` evaluates to `true` for the intended
  2.3 audience. Temporarily set it to `false`, relaunch, and confirm the 2.2 Home returns as the
  rollback; restore `true` before archiving or distributing the intended 2.3 experience.
- [x] Confirm the five camera Remote Config keys are `true`: `feature_mealPhotoLogging`,
  `feature_nutritionLabelScanner`, `feature_menuScanner`, `feature_receiptScanner`, and
  `feature_recipePhotoScanner`. In a non-production test window, set one route to `false` and verify
  only that workflow returns the temporary-unavailable state while general Maia still works.
- [x] Confirm `internalConfig/aiRoutes` is absent or contains no false values for release. Test one
  server field set to `false`, allow up to 60 seconds for cache expiry, and verify the matching route
  is blocked without consuming vision quota. Restore or remove the field immediately afterward.
- [x] On the smallest supported physical iPhone, enable Living Day and perform a five-second glance.
  Confirm you can identify what happened, what is planned, and the single next action without
  explanatory help. Repeat once in compact and once in detailed density.
- [x] With Living Day enabled, switch Home -> Reports -> Home three times. Living Day must return
  every time without falling back to the 2.2 dashboard. Then fully relaunch once and confirm the
  tester override or Remote Config condition still selects the intended Home.
- [x] Open Reports once immediately after launch and again after visiting another tab. The first
  load may show the full Week in Motion skeleton, but the controls and charts below it must not jump
  when data arrives; the return visit should reuse the completed weekly story without rebuilding it.
- [x] In Week in Motion, confirm the header clearly says `Last 7 days`, each node has the expected
  numeric date, Today is the final/current node rather than tomorrow, and tapping strength, run,
  mixed, rest, food, or flame evidence opens a readable explanation sheet.
- [x] With VoiceOver, traverse the Living Day heading, freshness, budget, current action, Maia
  annotation, transition status when present, chronological events, Show All, and Quick Actions.
  Confirm the spoken order is useful and no decorative content is announced.
- [x] With Reduce Motion both off and on, log one food and complete or skip one Training Fuel
  session. Confirm the affected node stays visible, the result is announced, haptics feel
  restrained, and no animation delays the saved write or navigation.
- [x] Add the medium and large widgets, refresh Home once, and confirm each shows the current coarse
  path segment and opens its existing destination. Disable Living Day or install a legacy payload
  and confirm the exact 2.2 widget body remains usable.
- [x] Share Living Day and Week in Motion through one real share destination after changing the
  visible-section toggles. Confirm the exported image matches the preview; any daily budget values
  must match the selected preview, with no account ID, food/workout name, route, coordinate,
  item-level nutrition, or raw Health sample.
- [x] Scroll Home repeatedly while data refreshes on the physical phone. Quick Log must remain
  reachable and responsive, and compact/detailed switching must not jump or obscure the current
  action.
- [x] Archive the intended 2.3 commit, validate the signed archive, and inspect the embedded
  phone/widget/Watch versions and privacy manifests.
- [ ] Upload the exact `39e3d1a2` package and complete the processed-build smoke in section 10 of
  `docs/physical-acceptance-2.3.md`.

### Version 2.3 visual-unification acceptance

These checks cover the remaining behavior that simulator snapshots and automation cannot judge
well. They replace a screen-by-screen manual retest:

- [x] Confirm the centered Quick Log control is comfortable to reach, opens on the first tap, and
  never covers or crowds the five tab labels on the smallest supported phone.
- [x] In Maia, review one structured food/workout action before confirming it. Confirm the action
  card reads naturally, the intended values remain editable or clearly disclosed, and no write
  occurs before confirmation. Complete the separate voice checks below during the same visit.
- [x] In Grocery, check an item, hide completed items, restore them, leave the screen, and return.
  The checked state and visibility choice must remain coherent without a double tap. Then refresh
  or regenerate the current meal plan: old generated items must be replaced, manual items must
  remain, and singular/plural duplicates such as `Banana`/`Bananas` must collapse into one row.
- [x] Repeat the exact Meal Plan survey that previously failed: Chicken, Beef, Fish, Eggs; Rice,
  Potatoes, Oats; Broccoli, Bell peppers, Onions; Yogurt and Fruit; Italian; Daily Fresh. Accept the
  success alert, confirm all seven days appear, force-quit and relaunch, revisit several dates, and
  confirm the same plan remains. A failed write must show an error instead of claiming the plan is
  ready. Then add one manual grocery item, use Meal Plan tools > Discard meal plan, confirm the
  seven-day plan and its Living Day entries disappear, and verify the manual grocery item remains.
- [x] Open one saved recipe through detail and logging, then use Fast Food Builder to add and remove
  an ingredient before reviewing the meal. Search for a menu item rather than a chain, open several
  chains, and confirm each feels populated, its official nutrition source opens, primary actions
  remain obvious, and totals respond immediately.
- [x] Search `chicken breast` and open the strongest ordinary-food result even if FatSecret remains
  primary. In Trust Receipt, expand `Sources in agreement` and confirm any genuinely agreeing USDA
  or Health Canada record is named with lineage/date context. Also inspect a Health Canada result's
  100 g serving and broad micronutrient panel. The receipt must not claim branded identity,
  laboratory verification, or independent upstream lineage.
- [x] Explicitly submit a multivitamin search. Confirm the separate Supplements section says the
  values are manufacturer label claims, a serving such as two capsules logs as one label serving,
  the leading results contain a useful vitamin/mineral panel, and missing/ambiguous nutrients are
  not invented. Scan Optimum Nutrition Opti-Men UPC `748927052497`; confirm NIH resolves it only
  after ordinary food providers miss and shows the label serving with the mapped micronutrients.
- [x] After deploying Functions, photograph one simple plate and one mixed plate. Confirm the meal
  review shows overall and per-item confidence, honest portion ranges, hidden-ingredient risks or
  useful clarification questions, and whether each composition came from USDA/Health Canada or is
  still model-estimated. Nothing may enter the diary before the final confirmation.
- [x] In the mixed-plate review, edit one item and remove another before logging. Reopen the saved
  food and confirm Trust retains photo-estimate lineage, the user review, and any secondary
  composition reference without calling it independent cross-database verification.
- [x] Try one large portrait-oriented library photo and a poor/unusable image. The large image must
  upload without corruption or an unbounded payload; the unusable image must fail cleanly without
  invented food. Also smoke-test nutrition-label, menu, receipt, and recipe-photo extraction after
  the model-routing deployment.
- [ ] Run each fixed camera comparison with a dedicated temporary account and no unrelated AI
  calls. In Firestore, filter `aiUsageBreakdown` by that account's UID and UTC day; record workflow,
  model, success/failure counts, token totals, and mean latency, then delete the account.
- [x] Open Settings > Nutrition data sources in light/dark mode and large text. Confirm the Health
  Canada Open Government Licence attribution and NIH explanation are fully reachable.
- [x] Open Adaptive Metabolism with real account data. It must say `Adaptive TDEE estimate`, show
  plausible finite values and the 21-day evidence requirement, and keep its apply action disabled
  when there is not enough valid evidence. If several days are only partially logged, it must say
  that explicitly instead of presenting the implausible estimate as actionable.
- [x] Cold-launch once and confirm the current dark-green/mint MyFitPlate mark appears instead of
  the retired white wordmark. Open Meal Plan and confirm its summaries, meal rows, pantry access,
  loading state, empty state, and six-step generator match the flatter 2.3 operational design.
- [x] Repeat a short Home, Maia, Train, Meal Plan, and Reports sweep in dark mode and at the largest
  practical text size. Look only for clipped text, unreachable actions, unexpected nested cards,
  or a page that still feels visually unrelated to the rest of the app.
- [x] Open Trust Hub with at least three foods. Confirm the Evidence Map is understandable in a
  five-second glance, its weakest layer matches the underlying foods, and VoiceOver reads Product
  Identity, Serving, Core Nutrition, and Detailed Nutrition in a useful order without treating
  source documentation as independent agreement.
- [x] On the smallest phone, confirm all seven Meal Plan dates are visible without a clipped final
  day. At a large accessibility size, horizontally move through the dates and confirm the selected
  day still says its full planned-meal count.
- [x] Open the first-run Feature Tour on the smallest phone and at the largest practical text size.
  The product preview, explanation, Skip, and Next must remain reachable without preview labels
  growing into the instructional copy.
- [x] Add a shoe in both mile and metric modes. Confirm Brand, Model, Current Mileage, Replacement
  Range, and Save Shoe remain clear; metric replacement starts at 560 km; saving returns the new
  shoe to the gear list.
- [x] Start a disposable strength workout, force-quit, and reopen within a few minutes. Confirm the
  elapsed timer resumes. Finish or discard it, relaunch again, and confirm the old timer does not
  return as an abandoned multi-hour session.
- [x] Refresh the Watch after the phone's Living Day changes, then share one Living Day and one Week
  in Motion image through a real destination. Confirm the Watch context is current and the exports
  match their previews without private food, route, account, coordinate, or Health-sample detail.

### Five-star closure physical delta

This is the shortest direct check of the final cross-surface work:

- [x] Cold-launch through the OS launch frame, account loading, and Home. Confirm the dark-green
  frame does not flash to the retired mark or an unrelated color.
- [x] Open AI consent, suggestion preferences, Add Exercise, caloric calculator, one run editor,
  and one workout target editor. With the keyboard visible, confirm the primary action remains
  reachable, validation is inline, and dismissing an edited form warns before losing work.
- [x] In Food Trust, confirm the compact evidence fingerprint matches the detailed receipt,
  freshness reads naturally, missing data is not shown as zero, and partial provider failure still
  leaves usable local or successful-provider results.
- [x] In the exercise picker, filter by muscle and equipment, choose a target preset, then swap an
  exercise. Confirm the reason is understandable and every existing set value survives the swap.
- [x] In Recovery Field, switch Front and Back, tap at least three regions, and compare each
  selected card with its color and evidence. Then use VoiceOver's list alternative and confirm the
  same regions and states are reachable without relying on the body drawing.
- [x] Let phone data age or disconnect the Watch, then inspect Watch Home, one widget, and any
  available Live Activity. Confirm current, stale, disconnected, queued, saved, failed, and empty
  states never collapse into the same wording.

No Firebase deployment is required for Living Day, the Reports explanation sheet, Meal Plan
persistence, Grocery synchronization, generic-food agreement display, sharing, widgets, or visual
density. Peter deployed the reviewed Functions source at `0aa44de9`, including the camera fallback,
strict route schemas, NIH matching, Maia speech route, and account-cleanup counters. A real
authenticated request proved that unavailable `gpt-5.6-terra` falls back to `gpt-4o-mini` and
completes. The current API project still cannot access the preferred camera models or configured
online speech model, so `Maia Natural` uses the accepted local fallback and no 2.3 copy claims that
the online voice is active. No new Rules, indexes, or migrations are required. Re-run
`npm run preflight:openai-models -- --firebase-project caloriebeta-d28de` from `functions/` after
any future credential change.

## Peter: physical release blockers

### Phone and Watch

- [x] Install the newest phone build and confirm the companion MyFitPlate Watch app updates.
- [x] Open the phone app, then Watch. Confirm calories, macros, water, weight units, next action, and last-sync state populate without a stale `Open the phone app to sync` loop.
- [x] Put the phone out of reach. Queue water and one recent-meal repeat on Watch, reconnect, and confirm exactly one write on the intended day.
- [x] Sign out on the phone and confirm account-scoped Watch context clears.
- [x] Add/tap each widget family after an app-group refresh and confirm its exact destination.
- [x] Enable one training-fuel reminder, receive it from the Lock Screen, and confirm the tap opens Training Fuel rather than a neighboring tab.

Peter physically validated all four Watch checks against the replacement 2.2 candidate on
2026-07-12. The missing-Watch-product defect remains specific to the withdrawn 2.2 build 1;
the current Release product embeds and syncs the companion correctly.

### Running and strength

- [x] Complete one real guided interval run. Confirm step transitions, spoken/haptic cues, pause/resume, target text, GPS distance, final step review, Live Activity, and Health save.
- [x] Open one Watch-imported run with heart-rate samples and confirm real time-in-zone appears without duplicate distance/calories.
- [x] Open or record one phone-only run without heart-rate data and confirm HR cards remain unavailable rather than showing zero.
- [x] Reopen a route after a long stop or weak-GPS interval and confirm displayed split times
  reconcile with the workout duration without a misleading Negative Split badge. Build 3 changes
  historical route replay only; live pace still caps long signal gaps.
- [x] Run adjacent supersets through both exercises and confirm rest behavior does not break pairing.
- [x] Edit warmup/drop/failure set types plus RPE/RIR, finish, reopen history, and confirm values persist while warmups stay out of volume/PR totals.

Peter physically validated the two advanced strength checks on July 12 and accepted all four
running paths, including the corrected weak-GPS review, on July 17.

### Accessibility and resilience

- [x] With VoiceOver, traverse Home, Quick Log, Food Search, Trust, Training Fuel, Train, and Reports. Icon-only controls must have useful names and decorative emoji must not be announced.
- [x] At the largest accessibility text size, confirm controls remain reachable on the smallest supported phone. Pay special attention to Home support cards, Quick Log, Trust facts/actions, Fast Food Builder's bottom tray, Train Start/Skip, and report sharing.
- [x] Repeat a glance through dark mode and Increase Contrast.
- [x] Disable Wi-Fi/cellular during Food Search. Saved/recent foods must remain usable; remote failure must show Try again and Create food without a raw networking error.
- [x] Restore connectivity, tap Try again, and confirm results recover without relaunching.

Peter physically validated the widget, notification, accessibility, appearance, and real
connectivity recovery checks on 2026-07-12.

### Maia voice and conversation

- [ ] After the API project receives access to the configured online speech model, open Settings >
  Maia and select `Maia Natural`. Confirm
  it is explicitly labeled online/AI-generated, sounds materially more natural, Stop Preview
  works, and other audio resumes afterward. Existing testers who previously chose a system voice
  must select Maia Natural manually because explicit voice choices are preserved.
- [x] Turn off AI data sharing and try Maia Natural again. The app must request consent and use the
  local iPhone fallback without sending speech text. Restore consent, then disable connectivity and
  confirm the same local fallback works without a raw error.
- [x] Preview at least one French or French-Canadian local alternate. Confirm the displayed accent
  and quality match the selection.
- [x] If the phone offers only Standard voices, download an Enhanced or Premium French voice in
  Settings > Accessibility > Spoken Content > Voices, reopen MyFitPlate Settings, and confirm it is
  available to select and preview. Third-party apps cannot use Siri's private voice; the higher-
  quality system speech voices are the closest supported option.
- [x] Ask one practical nutrition question in Balanced, Coach, and Analyst modes. Confirm Maia
  answers first, avoids canned praise or dashboard recitation, and each tone remains useful
  rather than theatrical.
- [x] Read aloud a response that contains an action card. Confirm Maia reads only the visible
  response, expands common nutrition units naturally, never narrates the hidden JSON, and
  changes the active control to Stop Reading.

Peter accepted the local voice, consent/offline fallback, tone, and read-aloud paths on July 17.
The online Maia Natural quality check remains post-release because the current API project does not
expose the configured speech model. An audio crash, hidden-payload narration, or failure to restore
other audio blocks release. Preference between otherwise functional system voices is polish
feedback, not a release stop.

Any data loss, account deletion failure, incorrect diary day, duplicate Watch write,
privacy-sensitive telemetry, crash, or unreachable primary action is release-blocking.
Record findings in `docs/feedback-triage-2.3.md`.

## Peter: console and App Store gates

- [x] Deploy and verify production Functions from the intended release commit. The July 16 delta
  specifically requires `generateAIResponse`, `nihSupplementSearch`,
  `nihSupplementBarcodeLookup`, and `generateMaiaSpeech`, plus the updated `deleteUserData` cleanup
  for Maia speech counters. The existing OpenAI secret is sufficient only for the camera
  compatibility model; Maia Natural and the preferred camera models require API-project model
  access. No Rules or indexes change. Run the fixed-photo benchmark in
  `docs/camera-logging-2.3.md` before treating the stronger camera model as a measured accuracy
  improvement.
- [x] Apply or reconcile `.github/rulesets/main-branch-protection.json` in GitHub so Unit tests, UI smoke tests, Firebase Functions, Firebase Rules, and Data migrations are required on `main`.
- [x] Register App Attest for the production app. The Release client and production entitlement
  are present.
- [ ] Verify App Check validity metrics from the signed/TestFlight build and do not enable
  enforcement until valid production traffic is clean.
- [x] Configure the KPI and launch-health views from `docs/analytics-dashboard-2.3.md`, including
  custom definitions/metrics, four key events, Activation and Launch Health explorations, and
  Crashlytics email/velocity alerts. Assign an owner and rollback response to each red live metric.
- [x] Confirm Privacy Policy, Terms, and Support URLs are publicly reachable from a signed-in and signed-out browser.
- [x] Reconcile App Store privacy answers with `docs/data-safety.md` and
  `docs/security-privacy-review.md`. The published 13-type summary has linked account/run data,
  unlinked diagnostics plus Device ID, and no tracking.
- [x] Confirm the app, widget, Live Activity, and Watch shipping targets all use marketing version
  2.3 and one unused matching build number before the final archive.
- [x] Create and locally validate a signed Archive, export the App Store IPA, and inspect the
  package for the Watch companion, entitlements, architectures, purpose strings, and privacy
  manifests.
- [ ] Upload the exact `39e3d1a2` package and pass App Store processing.
- [ ] Publish and smoke-test the prepared exact custom-product-page links now that version 2.2 is
  live. The replacement metadata, screenshots, review notes, and release choice are closed.

## Post-release observation

- [ ] Install or update version 2.3 from the public App Store listing, confirm existing account data appears,
  open all five tabs, use Quick Log for one disposable entry, remove it again, and confirm the
  Watch receives a fresh context. This is the only immediate live-2.2 smoke pass; do not repeat the
  full pre-release matrix.
- [ ] For the first 24 hours, compare crash-free users, launch failures, diary write failures, provider/callable outcomes, App Check validity, and aggregate AI cost against the previous stable build.
- [ ] Pause promotion or phased rollout for a new fatal crash, account/data integrity failure, material App Check rejection, or sustained provider/callable regression.
- [ ] After 7-14 clean days, evaluate activation, weekly loop completion, D1/D7 retention, and notification opt-out against MyFitPlate's own baseline.
- [ ] Run Trust calibration only after the cohort minimums in `docs/trust-calibration-2.3.md`; never tune scores merely to raise them.
