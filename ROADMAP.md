# MyFitPlate Roadmap

This is the current release and decision view. Detailed execution evidence lives in
`docs/release-evidence-2.3.md`; accepted device journeys live in
`docs/physical-acceptance-2.3.md`.

Last updated: 2026-07-17

## Product Direction

**Positioning:** The food log you can trust, built for people who train.

**Product model:** Signal, evidence, action.

- Signal gives one fast interpretation of the current state.
- Evidence shows the source, amount, trend, uncertainty, or limitation behind it.
- Action offers one direct next step when an action is useful.

MyFitPlate's advantage is not database size alone. It is the combination of transparent food
evidence, fast reviewable logging, training and recovery context, and coaching that shows its work.

## Branch And Release State

| Ref | Purpose | State |
| --- | --- | --- |
| `main` | Release source | 2.3 source ready for submission; the public Store remains on tagged 2.2 until approval |
| `codex/2.3-visual-unification` | 2.3 release branch | Binary source frozen at `39e3d1a2`; retained until the main merge is confirmed |

Only these long-lived branches should exist during submission. The exact 2.3 source is being merged
to `main` before upload at Peter's direction. Tag `v2.3` only after Apple accepts the build, then
remove the development branch when no longer needed.

## 2.3 Status

Version 2.3 is feature-complete, physically accepted, signed, exported, and ready to upload.

| Area | Status | Follow-up |
| --- | --- | --- |
| Living Day and Week in Motion | Complete and physically accepted | Production observation |
| Whole-app visual system | Complete and physically accepted | Resist palette/component drift |
| Trust Receipt and correction loop | Complete and physically accepted | Calibrate from real outcomes |
| Health Canada and NIH | Complete and physically accepted | Measure production hit rate |
| Camera logging | Review-first safety accepted | Run fixed comparative benchmark post-release |
| Fast Food Builder | 25-chain release scope complete | Maintain menus and measure misses |
| Strength, running, Recovery Field | Complete and physically accepted | Production observation |
| Maia | Context/actions and local voices accepted | Online speech awaits API model access |
| Watch, widgets, Live Activities | Complete and physically accepted | Test processed build once |
| Signed package | Complete at `39e3d1a2` | Upload and App Store processing |

The final package audit found and fixed one release issue before submission: the USDA key existed
in Xcode settings but was not reaching the processed Info.plist. Candidate `39e3d1a2` now injects
it explicitly, verifies it in source and package checks, and keeps OpenAI/FatSecret credentials out
of the exported app.

## Release Gates

### Gate 1 - Candidate Integrity: Complete

- [x] Classify the complete working tree and exclude generated/local-only state.
- [x] Commit and push all intended app, backend, data, test, and release work.
- [x] Freeze app source at `39e3d1a2` and deployed Functions source at `0aa44de9`.
- [x] Confirm phone, widget, Live Activity, and Watch are all version 2.3 build 1.
- [x] Inspect the final diff for secrets, disabled safeguards, debug fixtures, dormant prototypes,
  and release-only behavior changes.
- [x] Verify production backend source did not change after the deployed Functions commit.

### Gate 2 - Trust, Providers, And Camera: Release Scope Complete

- [x] Physically validate Health Canada ordinary-food attribution and micronutrients.
- [x] Physically validate NIH supplement search, label-serving language, and a real barcode.
- [x] Validate primary/supporting source convergence and lineage in Trust Receipt.
- [x] Harden and physically validate correction persistence and saved-food reuse.
- [x] Confirm each provider and camera route has an independent fail-closed switch.
- [x] Physically validate review-before-write, edit/remove, large-image, unusable-image, and denied-
  permission camera behavior.
- [ ] Run the fixed 25-image comparative scorecard after release. Until then, make no camera-
  accuracy improvement claim.

The camera compatibility route is live. The API project cannot access the preferred GPT-5.6 model,
so production attempts that route and falls back to `gpt-4o-mini` under the strict server schema.
This is recorded honestly in `docs/camera-benchmark-2.3.md`.

### Gate 3 - Physical Acceptance: Complete

Peter accepted sections 1-9 of `docs/physical-acceptance-2.3.md` on July 17, including:

- launch, Living Day, Daily Log, water, Reports, and persistence;
- Trust, corrections, specialist sources, supplement barcode, and camera safety;
- Meal Plan, discard, Grocery, recipes, and Fast Food Builder;
- Maia actions, local/system voices, and offline/consent fallback;
- strength, Recovery Field, running, Watch sync/offline replay, widgets, Live Activities, links,
  notifications, sharing, accessibility, denied permissions, and account deletion.

Preferred online Maia Natural speech remains unavailable to the current API project. The accepted
local fallback ships without an online-quality claim.

### Gate 4 - Local Release Package: Complete

- [x] Core: 1,220/1,220; 83.69% line coverage.
- [x] App: 115/115 on exact candidate `39e3d1a2`.
- [x] UI: 81/81 on the production-equivalent UI commit.
- [x] Address Sanitizer and Thread Sanitizer: 1,220/1,220 each.
- [x] Functions 33/33; Firestore Rules 33/33; migrations 10/10.
- [x] Strict lint, visual guard, privacy guard, dependency audits, Release build, and analysis.
- [x] Signed archive and App Store export from `39e3d1a2`.
- [x] Deep signature, entitlements, profiles, architectures, Watch relationship, purpose strings,
  privacy manifests, release-key placement, and debug-hook inspection.
- [x] Eight-image iPhone gallery at both Apple sizes plus a Watch image, all visually approved.
- [x] Metadata, review notes, privacy answers, public support/legal links, custom product page plans,
  and featuring nomination prepared.

Exact artifacts, hashes, and caveats are in `docs/release-evidence-2.3.md`.

## Peter: Submission Steps

1. Upload the `39e3d1a2` archive or IPA and wait for processing.
2. The local final-source section-10 smoke is accepted. After processing, repeat its two-minute
   upgrade/tab/Watch check on the exact TestFlight binary.
3. Check App Check validity, Crashlytics, and launch health. Keep enforcement off unless valid
   traffic is consistently clean.
4. Verify the dedicated review account on a fresh install.
5. Select the exact build, attach the approved screenshots, paste the prepared metadata/review
   notes, recheck privacy answers and public links, then submit.
6. The release source is merged to `main` before submission. After acceptance, tag `v2.3` and
   monitor the first 24 hours and 7-14 days.

## Post-2.3 Evidence Queue

Do not reopen 2.3 for these unless production reveals a release-blocking defect.

1. Run the fixed 25-image camera benchmark and establish a real correction-burden baseline.
2. Measure barcode misses, search-no-result rate, source convergence, provider latency, and
   micronutrient coverage before buying or integrating another broad database.
3. Calibrate Trust only after the cohort minimums in `docs/trust-calibration-2.3.md` are met.
4. Enable App Check gradually after signed-build validity is understood.
5. Move USDA lookup behind an authenticated backend before meaningful provider scale.
6. Delete the obsolete unreferenced `us-east1` `testConnectivity` diagnostic in a separate operator
   cleanup.

## 2.4 Candidate Direction

The next product bet should deepen the moat rather than widen the feature list:

1. **Recovery Continuum:** connect regional training load, recovery evidence, nutrition timing, and
   the next practical action without turning uncertainty into a single magical score.
2. **Voice logging:** reuse the review-before-write camera architecture for fast spoken meal entry.
3. **Trust at scale:** improve community consensus and source calibration only from measured
   production misses and corrections.
4. **Cost-aware growth:** establish free-tier AI economics from real route/model usage before a
   marketing push.
