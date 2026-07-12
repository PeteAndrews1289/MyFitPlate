# App Privacy Manifest

`CalorieBeta/PrivacyInfo.xcprivacy` is the app's Apple privacy manifest. Apple requires it
for App Store submissions, and rejects builds that use "required-reason" APIs without
declaring them (the `ITMS-91053: Missing API declaration` email).

## What it declares

- **`NSPrivacyTracking` = false**, no tracking domains — the app does not track users across
  other companies' apps/websites for advertising. (If you ever add an ad/attribution SDK or
  use IDFA, flip this to true and list the domains.)
- **`NSPrivacyAccessedAPITypes`** — the only required-reason API the app's own code uses is
  **`NSPrivacyAccessedAPICategoryUserDefaults`**, reason **`CA92.1`** (storing user preferences
  accessible only to the app). A code scan found no file-timestamp, disk-space, or boot-time
  API usage in the app or Core.
- **`NSPrivacyCollectedDataTypes`** — health, fitness, precise route location, Analytics-derived
  coarse location, user-submitted photos, email, user/account ID, user content, product
  interaction, crash/performance/other diagnostics, and device ID, with linked/purpose flags.

Analytics and crash reporting do not receive the Firebase Auth UID. The shared analytics
sanitizer also removes nutrition, body, HealthKit, workout, distance, sleep, hydration, and
related values from event parameters. The manifest remains conservative: health/fitness and
account content are linked for app functionality; coarse location and product interaction are
conservatively linked for Analytics; crash/performance/other diagnostics and device ID are
declared unlinked. None are used for tracking.

## Before each submission — verify

1. **Reconcile data types with App Store Connect.** The manifest's `NSPrivacyCollectedDataTypes`
   must match the privacy answers in App Store Connect (that questionnaire is authoritative for
   the public "nutrition label"). The set here is derived from a code scan — confirm the
   linked/tracking flags against how you actually use the data before you ship.
2. **Re-scan for new required-reason APIs** if you've added code that touches files, disk space,
   system uptime, or the active keyboard:
   ```bash
   rg -l "ModificationDate|creationDate|attributesOfItem|volumeAvailableCapacity|systemUptime" \
     CalorieBeta MyFitPlateCore/Sources -g '*.swift'
   ```
   Add the matching reason code (`C617.1`, `E174.1`, `35F9.1`, `54BD.1`) if anything turns up.
3. Third-party SDKs (Firebase, gRPC, DGCharts, …) ship their **own** manifests inside their
   bundles. Inspect the archive's complete manifest set as well as this first-party manifest;
   overlap is intentional where both app instrumentation and an SDK collect the same category.

## Wiring
The file is a Copy-Bundle-Resources member of the `MyFitPlate` (CalorieBeta) target, so it ships
at the app bundle root. CI builds the app, so a broken reference would fail the build.
