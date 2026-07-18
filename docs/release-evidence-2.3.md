# Version 2.3 Release Evidence

This is the reproducible release record for MyFitPlate 2.3. It separates source and automated
evidence, signed-package evidence, production evidence, physical acceptance, and the small set of
App Store Connect actions that still require Peter.

Last verified: July 18, 2026

> **Superseded package notice (July 18):** Peter accepted the nutrition-first Food Detail and full
> Nutrient Profile for inclusion in version 2.3. The `39e3d1a2` archive and IPA below predate that
> work and must not be uploaded. They remain documented as historical baseline evidence; the
> replacement `6a5e535e` package is the only package approved below.

## Replacement Source Candidate

- App source commit: `6a5e535e705d66bf81f18ebd732adac99fda8a06`
- Deployed Functions source commit: `0aa44de980025185e86800b353b3fba8064f0632`
- Branch: `codex/2.3-visual-unification`
- Version/build: 2.3 (1)
- State: app source frozen and pushed; signed archive/export, deep package audit, and refreshed
  gallery are complete

The accepted Food Detail and Nutrient Profile work is now part of version 2.3. It presents macros
first, keeps Food Trust compact with a full evidence receipt one tap away, exposes reported
micronutrients without turning missing values into zero, and expands the correction workspace to
the complete supported nutrient set.

| Gate | Replacement result |
| --- | --- |
| MyFitPlateCore | 1,223/1,223 passed on exact source `6a5e535e` |
| App unit tests | 116/116 passed, with zero failures or skips, on exact source `6a5e535e` |
| Food Detail UI | 6/6 focused journeys passed on the accepted product source |
| Broad UI catalog | All 85 journeys closed by the broad run plus two focused simulator-stability reruns |
| Static checks | Strict SwiftLint, visual-system guard, privacy guard, structured metadata checks, and Release static analysis passed |
| Release build | Passed on exact source `6a5e535e` for phone, widget, Live Activity, and Watch |
| Package inspection | All products report 2.3 (1); Watch purpose strings/architectures and all 39 privacy manifests passed |

Replacement evidence:

- App tests:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-AppTests-20260718.xcresult`
- Core-test log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-Core-20260718.log`
- App-test log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-AppTests-20260718.log`
- Release build log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-Release-20260718.log`
- Static-analysis log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-Analyze-20260718.log`
- Unsigned inspected products:
  `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/Final23Merge-AppTests-20260718/Build/Products/Release-iphoneos`

The replacement Release bundle contains no UI-test or screenshot-fixture marker. The phone app,
widget, and Live Activity are arm64; the Watch app contains arm64_32 and arm64. Both Watch Health
purpose strings are user-facing, the companion identifier is correct, and every embedded privacy
manifest parses. These checks validate source/package structure but do not replace the final signed
archive and exported-IPA audit.

Replacement store images:

- `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-6a5e535e/Screenshots`
- iPhone: eight 1320x2868 and eight 1284x2778 opaque RGB PNGs.
- Watch: one 416x496 opaque RGB PNG.

Food Detail image 2 was recaptured from the merged Debug-only deterministic fixture, visually
inspected at full resolution, and recomposed at both Apple sizes. The remaining seven approved
captures and the Watch capture are unchanged; all 17 final outputs passed dimension, color-space,
and alpha checks.

### Replacement Signed App Store Package

- Signed archive:
  `/Volumes/T7 Developer/MyFitPlate/Xcode/Archives/2026-07-18/MyFitPlate 2.3 6a5e535e.xcarchive`
- App Store export:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-6a5e535e/Export/MyFitPlate.ipa`
- IPA SHA-256:
  `947088d0f2fb5160e1dc9c34006d6c6c12ea0e5e78e11024bae8a7799fbef04c`
- IPA size: 66,580,982 bytes (63 MiB on disk)
- Complete package checksum manifest:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-6a5e535e/SHA256SUMS.txt`
- Checksum-manifest SHA-256:
  `eb804e39eccf415b2918186f625ab3c9de68acbd7b4020cda903c0f62ddbe92a`
- Archive log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-Archive-20260718.log`
- Export log:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Final23Merge-6a5e535e-Export-20260718.log`

The exported IPA passes deep strict code-sign verification. Every product uses an App Store
distribution profile through June 24, 2027 and reports version 2.3 build 1. `get-task-allow` is
false throughout; the phone app keeps production App Attest, HealthKit, and the shared app group.
The Watch companion relationship, both Health purpose strings, and arm64_32/arm64 architectures
are correct. All 39 privacy manifests parse, none declares tracking, the configured USDA release
key is present, OpenAI/FatSecret credentials are absent, and non-exempt encryption is false. No
UI-test or screenshot-fixture marker appears in the exported phone binary.

Xcode's verbose packaging log prints nine non-fatal `Upload Symbols Failed` lines while processing
prebuilt third-party frameworks, then completes the App Store export successfully. The same nine
lines occur in the prior successful baseline export. The app, widget, Live Activity, and both Watch
architectures each have an archive dSYM whose UUID exactly matches its executable, so MyFitPlate's
first-party crash symbolication evidence is complete.

## Prior Candidate (Superseded)

- App source commit: `39e3d1a219029db16c7e0b9bc18f4be378adeea3`
- Deployed Functions source commit: `0aa44de980025185e86800b353b3fba8064f0632`
- Branch: `codex/2.3-visual-unification`
- Version/build: 2.3 (1)
- Clean verification worktree:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseCandidate-2.3-0aa44de9`
- State: historically validated but superseded by the accepted Food Detail addition; do not upload

Do not submit `a020e8d0`, `bea943c5`, or `39e3d1a2`. Candidate `39e3d1a2` remains the baseline that
introduced the final USDA Info.plist substitution found during exported-package inspection.

## Automated Quality

| Gate | Result | Candidate relationship |
| --- | --- | --- |
| MyFitPlateCore | 1,220/1,220 passed | `bea943c5`; 83.69% line coverage and 80% floor passed |
| App unit tests | 115/115 passed | Exact final candidate `39e3d1a2` |
| UI catalog | 81/81 passed | `9cd29b60`; later app commits change only DEBUG test recorders and release plist packaging |
| Address Sanitizer | 1,220/1,220 passed | `bea943c5`; no sanitizer finding |
| Thread Sanitizer | 1,220/1,220 passed | `bea943c5`; no sanitizer finding |
| Functions | 33/33 passed | Deployed backend source `0aa44de9`; TypeScript build passed |
| Firestore Rules | 33/33 passed | Firebase emulator suite |
| Migrations | 10/10 passed | Idempotence, dry-run, failure, and private-barcode coverage |
| Static checks | Passed | Strict SwiftLint, visual guard, privacy guard, plist parsing, dependency audits, and diff checks |
| Release build | Passed | Exact final candidate `39e3d1a2`, all embedded products |
| Static analysis | Passed | Production source graph |

The final two Core commits after the full UI result only make DEBUG-only test recorders thread-safe
and add their concurrency regressions. The last candidate commit adds the release-key placeholder
and a source guard. None changes a Release UI implementation. The exact final app tests and Release
build therefore close the commit-sensitive portion without obscuring where the 81-test UI evidence
was produced.

Primary evidence:

- Core coverage:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-bea943c5-Core-Coverage-20260717.log`
- Core Address Sanitizer:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-bea943c5-Core-ASan-20260717.log`
- Core Thread Sanitizer:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-bea943c5-Core-TSan-20260717.log`
- Exact final app tests:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-39e3d1a2-AppTests-Retry-20260717.xcresult`
- Full UI catalog:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-9cd29b60-UITests-20260717.xcresult`
- Exact final Release build:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-39e3d1a2-Release-20260717.log`
- Exact final archive/export logs:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-39e3d1a2-Archive-20260717.log`
  and `/Volumes/T7 Developer/MyFitPlate/TestResults/RC-39e3d1a2-Export-20260717.log`

The first app-test launch encountered an Xcode simulator runner-attach stall before tests
materialized. After a clean simulator restart, the same built test products completed 115/115 with
zero failures or skips. The successful result bundle above is authoritative.

## Signed App Store Package

- Signed archive:
  `/Volumes/T7 Developer/MyFitPlate/Xcode/Archives/2026-07-17/MyFitPlate 2.3 39e3d1a2.xcarchive`
- App Store export:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-39e3d1a2/Export/MyFitPlate.ipa`
- IPA SHA-256:
  `74cf55786665febc7d7a35b9e344b41311bbe99747bb419b93acf42de9f7d8dd`
- IPA size: 66,388,497 bytes (63 MiB on disk)
- Complete package checksum manifest:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-39e3d1a2/SHA256SUMS.txt`
- Checksum-manifest SHA-256:
  `4f4c65fdaf9e16c479fc9deeec2582aa86564ae47b873857fccc966f69ad4b98`

| Product | Identifier | Version | Architectures |
| --- | --- | --- | --- |
| iPhone app | `MyFitPlate.CalorieBeta` | 2.3 (1) | arm64 |
| Widget | `MyFitPlate.CalorieBeta.CalorieWidget` | 2.3 (1) | arm64 |
| Live Activity | `MyFitPlate.CalorieBeta.LiveActivity` | 2.3 (1) | arm64 |
| Watch app | `MyFitPlate.CalorieBeta.watchkitapp` | 2.3 (1) | arm64_32, arm64 |

Exported-package checks:

- Deep strict code-sign verification passes.
- Every product uses the expected App Store distribution profile through June 24, 2027.
- `get-task-allow=false` on the phone, widget, Live Activity, and Watch products.
- App Attest is `production`; HealthKit and the shared app group survive export.
- The Watch companion identifier is `MyFitPlate.CalorieBeta`.
- Both Watch HealthKit purpose strings are present and user-facing.
- All 39 embedded privacy manifests parse; tracking is false and no tracking domains are declared.
- The configured USDA key is present and matches ignored local release configuration.
- The OpenAI credential and FatSecret proxy configuration are absent from the exported app.
- No `-ui-testing`, screenshot-mode, demo-data, or UI-test marker appears in the Release binary.
- Non-exempt encryption is declared false.

The USDA key is intentionally compiled for direct FoodData Central access in this release. It can
be extracted from any distributed app, so provider restrictions and a future authenticated proxy
remain the scale-safe follow-up.

## Store Images

- Final release directory:
  `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-39e3d1a2/Screenshots`
- iPhone: eight 1320x2868 and eight 1284x2778 RGB PNGs, all without alpha.
- Watch: one 416x496 RGB PNG without alpha.
- iPhone-set aggregate SHA-256:
  `c3655fdfb63be5305c8cddccb0ef6cf129bc5b67622824efb814106c39697076`

All images were freshly captured from deterministic local demo data, visually inspected at full
size, and contain no personal account, health, route, or nutrition history. The ordered story is
Living Day, Trust Receipt, Maia, review-before-log, Fast Food Builder, strength, Recovery Field,
and Reports.

## Production State

- Peter deployed the current backend before candidate freeze. No Functions source changed after
  backend commit `0aa44de9`.
- The 11 current `us-central1` Functions are active on Node.js 22.
- Health Canada and NIH production searches, a real supplement barcode, camera compatibility
  routing, saved corrections, and account deletion were physically accepted.
- A production meal-photo smoke attempted unavailable `gpt-5.6-terra`, received
  `model_not_found`, then succeeded with `gpt-4o-mini` under the strict schema.
- The observed successful request used 26,025 input and 179 output tokens, took 3,323 ms, and had a
  calculated token charge of about $0.004011 at the recorded standard-model rates. This is fallback
  evidence, not Terra-quality evidence.
- The current OpenAI API project does not expose the preferred GPT-5.6 camera models or configured
  online speech model. Maia Natural therefore uses the accepted local voice fallback.
- Remote Config is empty, `internalConfig/aiRoutes` is absent, and
  `internalConfig/communityBarcodeAggregation` is absent. Reviewed compiled defaults apply and
  public community barcode consensus remains fail-closed.
- App Attest is registered. App Check enforcement remains off until this exact signed/TestFlight
  build produces clean validity metrics.

The obsolete `us-east1` `testConnectivity` diagnostic remains a separate cleanup item. It is not
referenced by the current app or repository source and does not block 2.3.

## Physical Acceptance

Peter accepted sections 1-9 of `docs/physical-acceptance-2.3.md` on July 17. That includes launch,
Living Day, Reports, Trust and corrections, ordinary camera safety, specialist sources, Meal Plan,
Grocery, Fast Food Builder, Maia fallback voices, strength, Recovery Field, running, Watch,
widgets, Live Activities, links, sharing, accessibility, denied permissions, resilience, and
account deletion. On July 18 he also installed the final source over the public version and accepted
the section-10 data-preservation, five-tab, disposable-log, and Watch-refresh behavior.

Two evidence items remain deliberately outside the 2.3 claim set:

- The fixed 25-image comparative camera benchmark has not been run. Store copy does not claim
  improved camera accuracy; the benchmark remains post-release calibration work.
- Preferred online Maia Natural speech is unavailable to the current API project. The accepted
  local/system fallback ships; no claim says the online voice is active.

## Public Package

- Metadata and review notes: `docs/app-store-metadata-2.3.md`
- App Store privacy reconciliation: `docs/app-store-privacy-2.3.md`
- Privacy Policy:
  `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md`
- Support:
  `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/support.md`
- Terms:
  `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md`

The public legal/support updates are already on `main`. They should be checked while signed out
immediately before submission.

## Remaining Owner Actions

1. Generate and upload the replacement archive/IPA from the final merged 2.3 source; do not upload
   `39e3d1a2`.
2. Repeat the accepted two-minute upgrade/tab/Watch smoke once on the App Store-processed
   TestFlight binary; the July 18 local final-source install already passed it.
3. Check App Check validity and Crashlytics/launch health from that processed build. Keep App Check
   enforcement off unless valid traffic is consistently clean.
4. Verify the dedicated App Review account on a fresh install and enter its credentials only in
   App Store Connect.
5. Select the processed build, paste the prepared metadata/review notes, attach the approved image
   set, recheck the 13 privacy answers and public links, and submit.
6. The accepted source is merged to `main` before submission at Peter's direction. After Apple
   accepts 2.3, tag `v2.3` and run the short post-release observation checklist.
