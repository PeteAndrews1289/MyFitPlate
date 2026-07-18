# App Privacy Manifest

`CalorieBeta/PrivacyInfo.xcprivacy` is the phone app's Apple privacy manifest, and
`MyFitPlateCore/Sources/MyFitPlateCore/PrivacyInfo.xcprivacy` travels with the shared dynamic
package product used by the phone, widget, Live Activity, and Watch targets. Apple requires these
manifests for App Store submissions and rejects builds that use "required-reason" APIs without
declaring them (the `ITMS-91053: Missing API declaration` email).

## What it declares

- **`NSPrivacyTracking` = false**, no tracking domains — the app does not track users across
  other companies' apps/websites for advertising. (If you ever add an ad/attribution SDK or
  use IDFA, flip this to true and list the domains.)
- **`NSPrivacyAccessedAPITypes`** — the app's own code declares all three required-reason API
  categories currently in use:
  - **`NSPrivacyAccessedAPICategoryUserDefaults`**, reason **`CA92.1`**, for preferences that
    are accessible only to the app.
  - **`NSPrivacyAccessedAPICategoryFileTimestamp`**, reason **`C617.1`**, for reading the
    modification dates of speech-cache files inside the app container when pruning the cache.
  - **`NSPrivacyAccessedAPICategorySystemBootTime`**, reason **`35F9.1`**, for measuring elapsed
    time between Trust-provider request events with `ProcessInfo.systemUptime`.
- **`NSPrivacyCollectedDataTypes`** — health, fitness, precise route location, Analytics-derived
  coarse location, user-submitted photos, email, user/account ID, user content, product
  interaction, crash/performance/other diagnostics, and device ID, with linked/purpose flags.

Analytics and crash reporting do not receive the Firebase Auth UID. The shared analytics
sanitizer also removes nutrition, body, HealthKit, workout, distance, sleep, hydration, and
related values from event parameters. The manifest remains conservative: health/fitness and
account content are linked for app functionality; coarse location and product interaction are
conservatively linked for Analytics; crash/performance/other diagnostics and device ID are
declared unlinked. None are used for tracking.

The Watch app also ships a first-party bundle manifest at
`MyFitPlateWatch Watch App/PrivacyInfo.xcprivacy`. Both the shared-package and Watch manifests
declare the same three required-reason API categories but no collected-data categories: those
products do not independently collect or transmit the phone app's declared analytics and account
data. Apple evaluates required-reason API use by product and framework, so these declarations must
remain present even when the implementation is shared.

## Before each submission — verify

1. **Reconcile data types with App Store Connect.** The manifest's `NSPrivacyCollectedDataTypes`
   must match the privacy answers in App Store Connect (that questionnaire is authoritative for
   the public "nutrition label"). The set here is derived from a code scan — confirm the
   linked/tracking flags against how you actually use the data before you ship.
2. **Re-scan for new required-reason APIs** if you've added code that touches files, disk space,
   system uptime, or the active keyboard:
   ```bash
   rg -n "contentModificationDateKey|contentCreationDateKey|creationDate|modificationDate|attributesOfItem|volumeAvailableCapacity|systemUptime" \
     CalorieBeta MyFitPlateCore/Sources -g '*.swift'
   ```
   Reconcile every result with the declared categories and an Apple-approved reason. The current
   expected hits are the speech-cache modification date (`C617.1`) and Trust request timing
   (`35F9.1`); disk-space and active-keyboard API use should remain absent.
3. **Validate all first-party manifests and their compiled products.** Lint the phone, Core, and
   Watch source files. Then confirm the phone and embedded Watch roots contain their manifests and
   that the shared package privacy resource is present everywhere Xcode embeds the Core product,
   including extensions. A valid source plist is not sufficient evidence that Xcode copied it.
4. Third-party SDKs (Firebase, gRPC, DGCharts, …) ship their **own** manifests inside their
   bundles. Inspect the archive's complete manifest set as well as this first-party manifest;
   overlap is intentional where both app instrumentation and an SDK collect the same category.

## Wiring
The phone manifest is a Copy-Bundle-Resources member of the `MyFitPlate` (CalorieBeta) target. The
Core manifest is a Swift Package resource copied with the dynamic package product. The Watch
manifest lives in the Watch target's file-system-synchronized group and is copied as a target
resource. A release-product inspection must still confirm the files appear in their expected
compiled products; a successful compile alone does not prove resources landed correctly.

## Version 2.3 package verification

Candidate `39e3d1a2` was inspected after App Store export. The phone and Watch roots contain their
first-party manifests, and the shared Core manifest is embedded with the phone, Watch, widget, and
Live Activity products. The complete embedded manifest set parses successfully; tracking remains
false with no tracking domains. This verifies packaging for the exact candidate, while App Store
Connect's published questionnaire remains the public disclosure source of truth.
