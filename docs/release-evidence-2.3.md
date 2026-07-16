# Version 2.3 Release Evidence

This is the reproducible release record for the current version 2.3 candidate. It separates
evidence that can be established from source, automation, packaging, and production APIs from
evidence that still requires a person using the physical devices.

## Candidate

- Binary source commit: `a020e8d054dcfb52757dc571de097f92f9630073`
- Branch: `codex/2.3-visual-unification`
- Version: 2.3
- Build: 1
- Verification date: July 15-16, 2026
- Clean verification worktree:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseCandidate-2.3-a020e8d0`

The documentation commit that records this evidence does not change any shipping target. If a
physical acceptance finding changes app or backend source, replace this candidate and rerun the
affected release gates.

## Automated Quality

| Gate | Result | Evidence |
| --- | --- | --- |
| MyFitPlateCore | 1,134/1,134 passed | 83.80% line coverage; 80% floor passed |
| App unit tests | 110/110 passed | 7.63% app-target line coverage; 1% floor passed |
| UI matrix | 80 methods / 83 executions passed | Zero failures and zero skips |
| Functions | 25/25 passed | TypeScript build passed; production dependency audit found zero vulnerabilities |
| Firestore Rules | 23/23 passed | Fresh test-harness install; full audit found zero vulnerabilities |
| Migrations | 10/10 passed | Idempotence, dry-run, failure, and private-barcode migration coverage |
| SwiftLint | Passed | Strict mode |
| Visual system guard | Passed | Phone and Watch source boundaries |
| Diff and structured files | Passed | Diff whitespace, plists, localization catalog, and screenshot manifest |

Result bundles:

- App:
  `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate4-Final-App-a020e8d0.xcresult`
- UI:
  `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Gate4-Final-UI-a020e8d0.xcresult`

Coverage compilation continues to report the documented Swift 6 migration warnings in
`HealthKitManager.swift`. They are warnings in the shipping language mode, not current test or
archive failures. Resolve them before enabling Swift 6 language mode.

## Release Products

The unsigned generic-device Release build passed from the exact candidate. The signed archive also
completed, and Xcode successfully exported it for App Store Connect using the cloud-managed Apple
Distribution certificate.

| Product | Identifier | Version | Architectures |
| --- | --- | --- | --- |
| iPhone app | `MyFitPlate.CalorieBeta` | 2.3 (1) | arm64 |
| Widget | `MyFitPlate.CalorieBeta.CalorieWidget` | 2.3 (1) | arm64 |
| Live Activity | `MyFitPlate.CalorieBeta.LiveActivity` | 2.3 (1) | arm64 |
| Watch app | `MyFitPlate.CalorieBeta.watchkitapp` | 2.3 (1) | arm64_32, arm64 |

Packaging checks:

- The Watch companion identifier is `MyFitPlate.CalorieBeta`.
- Both Watch HealthKit purpose strings are present and user-facing.
- All 34 bundled privacy manifests parse.
- Tracking is false and no tracking domains are declared.
- App Store entitlements have `get-task-allow=false`.
- App Attest uses the production environment.
- HealthKit and the shared app group survive App Store re-signing.
- The app, widget, Live Activity, and Watch bundles satisfy their code-signing requirements.

Artifacts:

- Signed archive:
  `/Volumes/T7 Developer/MyFitPlate/Xcode/Archives/2026-07-16/MyFitPlate 2.3 a020e8d0.xcarchive`
- App Store export:
  `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/AppStoreExport-a020e8d0/MyFitPlate.ipa`
- IPA SHA-256:
  `822761585c1f01ce459305efc506066456e4b261e08546002b5d1c286fa00b91`

The local App Store export is not an upload or App Store processing result. Upload only after the
physical acceptance checklist passes.

## Production State

Read-only production checks on July 16 established:

- All ten current `us-central1` MyFitPlate Functions are active on Node.js 22.
- The candidate contains no Functions changes after deployed Functions commit `345d5dfe`.
- A disposable authenticated account successfully queried:
  - Health Canada chicken breast: five results; the first carried 30 populated nutrients.
  - Health Canada cooked ground beef: five results; the first carried 30 populated nutrients.
  - Health Canada boiled egg: one result; it carried 30 populated nutrients.
  - NIH multivitamin search: three results; the first retained a one-tablet label serving and
    15 populated nutrients.
- The disposable account was deleted through the production `deleteUserData` callable.
- Firebase Remote Config currently has no remote parameters. Reviewed compiled defaults therefore
  enable Living Day, the five camera workflows, Health Canada, and NIH while keeping public
  community barcode corrections disabled.
- `internalConfig/aiRoutes` is absent, so no camera workflow is unexpectedly disabled.
- `internalConfig/communityBarcodeAggregation` is absent, so contributions, aggregation, and
  public reads fail closed.
- App Attest is registered with a 3,600-second token lifetime.
- App Check enforcement remains off for Authentication, Firestore, and Storage. Do not enable it
  until a signed/TestFlight build produces clean validity metrics.
- Cloud Function and Cloud Run logs contained zero severity-error entries in the final six-hour
  inspection window.

The legacy `us-east1` `testConnectivity` diagnostic remains in a failed state and is not referenced
by current app or repository source. It does not block 2.3, but delete it in a separate explicit
operator cleanup after confirming it is no longer wanted. The active legacy `api` and `searchFood`
services remain outside the 2.3 Functions codebase.

## Store Package

- Sixteen deterministic screenshots are ready in `tools/screenshots/output/`.
- Eight are 1320x2868 and eight are 1284x2778.
- Combined screenshot-manifest SHA-256:
  `fcbbf26f35ab50e44d8bf9e8dcb6ea3875757456a7a59cce7c4c6dbc5dd6ad13`
- Default metadata, What's New, review notes, five custom product page plans, public URLs, and the
  featuring nomination are in `docs/app-store-metadata-2.3.md`.
- Privacy, Support, and Terms URLs are publicly reachable while signed out.
- The 2.3 branch updates the public policy and terms for Health Canada and NIH. Those documents must
  reach `main` before selecting the 2.3 build for review because the public URLs point to `main`.

Regenerate screenshots only if a physical finding changes a captured surface. Do not claim improved
camera accuracy until the fixed benchmark passes.

## Remaining Human Evidence

Only these categories remain:

1. The fixed 25-image camera benchmark and subjective correction-burden review.
2. Physical iPhone, Watch, GPS, heart-rate, speech, haptic, widget, Live Activity, notification,
   sharing, accessibility, persistence, and denied-permission behavior.
3. App Check validity from the signed/TestFlight candidate.
4. App Store Connect paste, review-account verification, upload, processing, and submission.
5. Merge the accepted source to `main`, confirm the legal documents are public there, and tag
   the shipped release `v2.3`.

Use `docs/physical-acceptance-2.3.md` for the ordered device script.
