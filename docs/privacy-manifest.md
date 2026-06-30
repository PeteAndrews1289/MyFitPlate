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
- **`NSPrivacyCollectedDataTypes`** — health, fitness, email, name, user content, product
  interaction, crash data, performance data, and device ID, with linked/purpose flags.

## Before each submission — verify

1. **Reconcile data types with App Store Connect.** The manifest's `NSPrivacyCollectedDataTypes`
   must match the privacy answers in App Store Connect (that questionnaire is authoritative for
   the public "nutrition label"). The set here is derived from a code scan — confirm the
   linked/tracking flags against how you actually use the data before you ship.
2. **Re-scan for new required-reason APIs** if you've added code that touches files, disk space,
   system uptime, or the active keyboard:
   ```bash
   grep -rlE "ModificationDate|creationDate|attributesOfItem|volumeAvailableCapacity|systemUptime" \
     CalorieBeta MyFitPlateCore/Sources --include="*.swift"
   ```
   Add the matching reason code (`C617.1`, `E174.1`, `35F9.1`, `54BD.1`) if anything turns up.
3. Third-party SDKs (Firebase, gRPC, DGCharts, …) ship their **own** manifests inside their
   bundles — you don't redeclare those here, only the app's first-party usage.

## Wiring
The file is a Copy-Bundle-Resources member of the `MyFitPlate` (CalorieBeta) target, so it ships
at the app bundle root. CI builds the app, so a broken reference would fail the build.
