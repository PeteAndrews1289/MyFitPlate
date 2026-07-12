# Replacement Version 2.2 Release Closure

The first uploaded 2.2 build was withdrawn before publication. This checklist now closes the
integrated replacement 2.2 candidate, which must use build 2 or later. This filename retains
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
generic physical-iOS Release build passed. The Release product is version 2.2 build 2 across
phone, widget, Live Activity, and Watch; it embeds the companion with the correct identifiers
and arm64_32 plus arm64 architectures. The main privacy manifest parses. App result:
`.codex_xcode/TestResults-2.2b2-app-final.xcresult`. UI result:
`.codex_xcode/TestResults-2.2b2-ui-final.xcresult`.

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
- [x] Run adjacent supersets through both exercises and confirm rest behavior does not break pairing.
- [x] Edit warmup/drop/failure set types plus RPE/RIR, finish, reopen history, and confirm values persist while warmups stay out of volume/PR totals.

Peter physically validated the two advanced strength checks on 2026-07-12. Only the three
running sensor/data paths above remain open in this section.

### Accessibility and resilience

- [x] With VoiceOver, traverse Home, Quick Log, Food Search, Trust, Training Fuel, Train, and Reports. Icon-only controls must have useful names and decorative emoji must not be announced.
- [x] At the largest accessibility text size, confirm controls remain reachable on the smallest supported phone. Pay special attention to Home support cards, Quick Log, Trust facts/actions, Fast Food Builder's bottom tray, Train Start/Skip, and report sharing.
- [x] Repeat a glance through dark mode and Increase Contrast.
- [x] Disable Wi-Fi/cellular during Food Search. Saved/recent foods must remain usable; remote failure must show Try again and Create food without a raw networking error.
- [x] Restore connectivity, tap Try again, and confirm results recover without relaunching.

Peter physically validated the widget, notification, accessibility, appearance, and real
connectivity recovery checks on 2026-07-12.

### Maia voice and conversation

- [ ] In Settings > Maia, preview the default spoken voice and at least one alternate if the
  phone has more than one regular US English voice. Confirm Stop Preview works and other audio
  resumes afterward.
- [ ] If the phone offers only Standard voices, download an Enhanced or Premium English voice
  in the iPhone's Accessibility speech settings, reopen MyFitPlate Settings, and confirm it is
  available to select and preview. This is optional quality polish, not a release blocker.
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

- [ ] Verify production Functions, Rules, and indexes match the intended release commit. No
  backend redeploy is required for Watch, micronutrient, search-recovery, Maia prompt, or
  on-device Maia voice changes alone.
- [x] Apply or reconcile `.github/rulesets/main-branch-protection.json` in GitHub so Unit tests, UI smoke tests, Firebase Functions, Firebase Rules, and Data migrations are required on `main`.
- [x] Register App Attest for the production app. The Release client and production entitlement
  are present.
- [ ] Verify App Check validity metrics from the signed/TestFlight build and do not enable
  enforcement until valid production traffic is clean.
- [x] Configure the KPI and launch-health views from `docs/analytics-dashboard-2.3.md`, including
  custom definitions/metrics, four key events, Activation and Launch Health explorations, and
  Crashlytics email/velocity alerts. Assign an owner and rollback response to each red live metric.
- [x] Confirm Privacy Policy, Terms, and Support URLs are publicly reachable from a signed-in and signed-out browser.
- [ ] Reconcile App Store privacy answers with `docs/data-safety.md` and `docs/security-privacy-review.md`.
- [x] Keep the app, widget, Live Activity, and Watch targets on marketing version 2.2 and set
  their build number to 2. The withdrawn build 1 cannot be reused.
- [ ] Create a signed Archive, run Validate App, inspect the archive for the Watch companion and privacy manifests, then upload.
- [ ] Complete the replacement 2.2 metadata, screenshots, review notes, phased-release choice,
  and exact custom-product-page links after binary approval.

## Post-release observation

- [ ] For the first 24 hours, compare crash-free users, launch failures, diary write failures, provider/callable outcomes, App Check validity, and aggregate AI cost against the previous stable build.
- [ ] Pause promotion or phased rollout for a new fatal crash, account/data integrity failure, material App Check rejection, or sustained provider/callable regression.
- [ ] After 7-14 clean days, evaluate activation, weekly loop completion, D1/D7 retention, and notification opt-out against MyFitPlate's own baseline.
- [ ] Run Trust calibration only after the cohort minimums in `docs/trust-calibration-2.3.md`; never tune scores merely to raise them.
