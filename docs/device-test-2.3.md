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

## Version 2.3 Living Day owner gates

The implementation, deterministic rendering, simulator accessibility, privacy, performance, CI,
and rollback matrices are automated locally. These checks require Peter's physical device or a
signed production console and must remain open until they are directly observed:

- [ ] In Firebase Remote Config, confirm `feature_livingDayHome` evaluates to `true` for the intended
  2.3 audience. Temporarily set it to `false`, relaunch, and confirm the 2.2 Home returns as the
  rollback; restore `true` before archiving or distributing the intended 2.3 experience.
- [ ] On the smallest supported physical iPhone, enable Living Day and perform a five-second glance.
  Confirm you can identify what happened, what is planned, and the single next action without
  explanatory help. Repeat once in compact and once in detailed density.
- [ ] With Living Day enabled, switch Home -> Reports -> Home three times. Living Day must return
  every time without falling back to the 2.2 dashboard. Then fully relaunch once and confirm the
  tester override or Remote Config condition still selects the intended Home.
- [ ] Open Reports once immediately after launch and again after visiting another tab. The first
  load may show the full Week in Motion skeleton, but the controls and charts below it must not jump
  when data arrives; the return visit should reuse the completed weekly story without rebuilding it.
- [ ] With VoiceOver, traverse the Living Day heading, freshness, budget, current action, Maia
  annotation, transition status when present, chronological events, Show All, and Quick Actions.
  Confirm the spoken order is useful and no decorative content is announced.
- [ ] With Reduce Motion both off and on, log one food and complete or skip one Training Fuel
  session. Confirm the affected node stays visible, the result is announced, haptics feel
  restrained, and no animation delays the saved write or navigation.
- [ ] Add the medium and large widgets, refresh Home once, and confirm each shows the current coarse
  path segment and opens its existing destination. Disable Living Day or install a legacy payload
  and confirm the exact 2.2 widget body remains usable.
- [ ] Share Living Day and Week in Motion through one real share destination after changing the
  visible-section toggles. Confirm the exported image matches the preview; any daily budget values
  must match the selected preview, with no account ID, food/workout name, route, coordinate,
  item-level nutrition, or raw Health sample.
- [ ] Scroll Home repeatedly while data refreshes on the physical phone. Quick Log must remain
  reachable and responsive, and compact/detailed switching must not jump or obscure the current
  action.
- [ ] For release, archive the intended 2.3 commit, validate the signed archive, inspect the
  embedded phone/widget/Watch versions and privacy manifests, then upload that exact build.

### Version 2.3 visual-unification acceptance

These checks cover the remaining behavior that simulator snapshots and automation cannot judge
well. They replace a screen-by-screen manual retest:

- [ ] Confirm the centered Quick Log control is comfortable to reach, opens on the first tap, and
  never covers or crowds the five tab labels on the smallest supported phone.
- [ ] In Maia, review one structured food/workout action before confirming it. Confirm the action
  card reads naturally, the intended values remain editable or clearly disclosed, and no write
  occurs before confirmation. Complete the separate voice checks below during the same visit.
- [ ] In Grocery, check an item, hide completed items, restore them, leave the screen, and return.
  The checked state and visibility choice must remain coherent without a double tap. Then refresh
  or regenerate the current meal plan: old generated items must be replaced, manual items must
  remain, and singular/plural duplicates such as `Banana`/`Bananas` must collapse into one row.
- [ ] Open one saved recipe through detail and logging, then use Fast Food Builder to add and remove
  an ingredient before reviewing the meal. Search for a menu item rather than a chain, open several
  chains, and confirm each feels populated, its official nutrition source opens, primary actions
  remain obvious, and totals respond immediately.
- [ ] After deploying Functions, search `chicken breast` and inspect a Health Canada CNF result.
  Confirm its 100 g serving, broad micronutrient panel, source/release context, and government-
  composition Trust wording. It must not claim branded identity or independent USDA verification.
- [ ] Explicitly submit a multivitamin search. Confirm the separate Supplements section says the
  values are manufacturer label claims, a serving such as two capsules logs as one label serving,
  and missing/ambiguous nutrients are not invented. Scan a real supplement UPC when available and
  confirm NIH is only the fallback after ordinary food providers miss.
- [ ] After deploying Functions, photograph one simple plate and one mixed plate. Confirm the meal
  review shows overall and per-item confidence, honest portion ranges, hidden-ingredient risks or
  useful clarification questions, and whether each composition came from USDA/Health Canada or is
  still model-estimated. Nothing may enter the diary before the final confirmation.
- [ ] In the mixed-plate review, edit one item and remove another before logging. Reopen the saved
  food and confirm Trust retains photo-estimate lineage, the user review, and any secondary
  composition reference without calling it independent cross-database verification.
- [ ] Try one large portrait-oriented library photo and a poor/unusable image. The large image must
  upload without corruption or an unbounded payload; the unusable image must fail cleanly without
  invented food. Also smoke-test nutrition-label, menu, receipt, and recipe-photo extraction after
  the model-routing deployment.
- [ ] Open Settings > Nutrition data sources in light/dark mode and large text. Confirm the Health
  Canada Open Government Licence attribution and NIH explanation are fully reachable.
- [ ] Open Adaptive Metabolism with real account data. It must say `Adaptive TDEE estimate`, show
  plausible finite values and the 21-day evidence requirement, and keep its apply action disabled
  when there is not enough valid evidence. If several days are only partially logged, it must say
  that explicitly instead of presenting the implausible estimate as actionable.
- [ ] Cold-launch once and confirm the current dark-green/mint MyFitPlate mark appears instead of
  the retired white wordmark. Open Meal Plan and confirm its summaries, meal rows, pantry access,
  loading state, empty state, and six-step generator match the flatter 2.3 operational design.
- [ ] Repeat a short Home, Maia, Train, Meal Plan, and Reports sweep in dark mode and at the largest
  practical text size. Look only for clipped text, unreachable actions, unexpected nested cards,
  or a page that still feels visually unrelated to the rest of the app.
- [ ] Refresh the Watch after the phone's Living Day changes, then share one Living Day and one Week
  in Motion image through a real destination. Confirm the Watch context is current and the exports
  match their previews without private food, route, account, coordinate, or Health-sample detail.

No Firebase deployment is required for the Living Day, Maia annotation, share image, widget
payload, density work, tab-lifecycle fix, or Reports loading stability work. Health Canada CNF,
NIH DSLD, and the trust-aware camera model routes are the exceptions: deploy Functions before
testing them. They use the existing `OPENAI_API_KEY` and require no new Rules, indexes, migrations,
or API keys. Confirm that the OpenAI project behind the existing key can call the selected models.
The new Firebase custom definitions in `docs/analytics-dashboard-2.3.md` should be created only
after DebugView or signed-build traffic confirms their parameters.

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

- [ ] Complete one real guided interval run. Confirm step transitions, spoken/haptic cues, pause/resume, target text, GPS distance, final step review, Live Activity, and Health save.
- [ ] Open one Watch-imported run with heart-rate samples and confirm real time-in-zone appears without duplicate distance/calories.
- [ ] Open or record one phone-only run without heart-rate data and confirm HR cards remain unavailable rather than showing zero.
- [ ] Reopen a route after a long stop or weak-GPS interval and confirm displayed split times
  reconcile with the workout duration without a misleading Negative Split badge. Build 3 changes
  historical route replay only; live pace still caps long signal gaps.
- [x] Run adjacent supersets through both exercises and confirm rest behavior does not break pairing.
- [x] Edit warmup/drop/failure set types plus RPE/RIR, finish, reopen history, and confirm values persist while warmups stay out of volume/PR totals.

Peter physically validated the two advanced strength checks on 2026-07-12. The remaining work in
this section is limited to the three running sensor/data paths and one corrected stop/weak-GPS
historical-route replay; none requires stressing an injured knee before it is sensible to do so.

### Accessibility and resilience

- [x] With VoiceOver, traverse Home, Quick Log, Food Search, Trust, Training Fuel, Train, and Reports. Icon-only controls must have useful names and decorative emoji must not be announced.
- [x] At the largest accessibility text size, confirm controls remain reachable on the smallest supported phone. Pay special attention to Home support cards, Quick Log, Trust facts/actions, Fast Food Builder's bottom tray, Train Start/Skip, and report sharing.
- [x] Repeat a glance through dark mode and Increase Contrast.
- [x] Disable Wi-Fi/cellular during Food Search. Saved/recent foods must remain usable; remote failure must show Try again and Create food without a raw networking error.
- [x] Restore connectivity, tap Try again, and confirm results recover without relaunching.

Peter physically validated the widget, notification, accessibility, appearance, and real
connectivity recovery checks on 2026-07-12.

### Maia voice and conversation

- [ ] In Settings > Maia, preview the default spoken voice and at least one French or French-
  Canadian alternate. Confirm the displayed accent and quality match the selection, Stop Preview
  works, and other audio resumes afterward.
- [ ] If the phone offers only Standard voices, download an Enhanced or Premium French voice in
  Settings > Accessibility > Spoken Content > Voices, reopen MyFitPlate Settings, and confirm it is
  available to select and preview. Third-party apps cannot use Siri's private voice; the higher-
  quality system speech voices are the closest supported option.
- [ ] Ask one practical nutrition question in Balanced, Coach, and Analyst modes. Confirm Maia
  answers first, avoids canned praise or dashboard recitation, and each tone remains useful
  rather than theatrical.
- [ ] Read aloud a response that contains an action card. Confirm Maia reads only the visible
  response, expands common nutrition units naturally, never narrates the hidden JSON, and
  changes the active control to Stop Reading.

An audio crash, hidden-payload narration, or failure to restore other audio blocks release.
Preference between otherwise functional system voices is polish feedback, not a release stop.

Any data loss, account deletion failure, incorrect diary day, duplicate Watch write,
privacy-sensitive telemetry, crash, or unreachable primary action is release-blocking.
Record findings in `docs/feedback-triage-2.3.md`.

## Peter: console and App Store gates

- [ ] Deploy and verify production Functions from the intended release commit. This deployment is
  required for Health Canada CNF, NIH DSLD, and the purpose-routed camera models; Rules and indexes
  do not change for those features, and the existing OpenAI secret remains sufficient. Watch,
  existing on-device micronutrient math, search recovery, and Maia voice changes alone still do not
  require a backend deployment. Run the fixed-photo benchmark in `docs/camera-logging-2.3.md`
  before treating the stronger model as a measured accuracy improvement.
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
- [ ] Confirm the app, widget, Live Activity, and Watch shipping targets all use marketing version
  2.3 and one unused matching build number before the final archive.
- [x] Create a signed Archive, run Validate App, inspect the archive for the Watch companion and
  privacy manifests, upload, and pass App Store processing.
- [ ] Publish and smoke-test the prepared exact custom-product-page links now that version 2.2 is
  live. The replacement metadata, screenshots, review notes, and release choice are closed.

## Post-release observation

- [ ] Install or update from the public App Store listing, confirm existing account data appears,
  open all five tabs, use Quick Log for one disposable entry, remove it again, and confirm the
  Watch receives a fresh context. This is the only immediate live-2.2 smoke pass; do not repeat the
  full pre-release matrix.
- [ ] For the first 24 hours, compare crash-free users, launch failures, diary write failures, provider/callable outcomes, App Check validity, and aggregate AI cost against the previous stable build.
- [ ] Pause promotion or phased rollout for a new fatal crash, account/data integrity failure, material App Check rejection, or sustained provider/callable regression.
- [ ] After 7-14 clean days, evaluate activation, weekly loop completion, D1/D7 retention, and notification opt-out against MyFitPlate's own baseline.
- [ ] Run Trust calibration only after the cohort minimums in `docs/trust-calibration-2.3.md`; never tune scores merely to raise them.
