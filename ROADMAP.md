# MyFitPlate Roadmap

This is the current release and decision view. Detailed execution evidence lives in
`docs/release-evidence-2.3.md`; accepted device journeys live in
`docs/physical-acceptance-2.3.md`.

Last updated: 2026-07-18

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
| `main` | Release source | PR #9 is the pending publication path for the complete 2.3 source |
| `codex/2.3-visual-unification` | Active 2.3 release branch | Final correction-safe app source is `fade6c07`; hosted verification and a fresh signed package remain |

All accepted product work now belongs to version 2.3. Tag `v2.3` only after Apple accepts the build,
then remove the 2.3 development branch when no longer needed.

## 2.3 Status

Version 2.3 is feature-complete and physically accepted. Both earlier signed packages are now
superseded: `39e3d1a2` predates Food Detail, while `6a5e535e` predates the final correction-draft
durability fix. Neither package should be uploaded.

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
| Signed package | Fresh `fade6c07` archive/export pending | Do not upload `6a5e535e` or `39e3d1a2` |

The original package audit found and fixed one release issue before submission: the USDA key
existed in Xcode settings but was not reaching the processed Info.plist. Final simulator closure
then found a second real issue: hiding the numeric keyboard could rebuild Food Detail and discard
an unsaved macro or micronutrient correction. Source `fade6c07` retains one draft for the complete
editor lifetime and proves the exact entered values survive keyboard dismissal.

## Release Gates

### Gate 1 - Candidate Integrity: Complete

- [x] Classify the complete working tree and exclude generated/local-only state.
- [x] Commit and push all intended app, backend, data, test, and release work.
- [x] Freeze the correction-safe app source at `fade6c07` after the accepted Food Detail merge.
  Deployed Functions source remains `0aa44de9`.
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

### Gate 4 - Exact Source Complete; Fresh Package Pending

- [x] Core: 1,223/1,223; the Core package is unchanged in final app source `fade6c07`.
- [x] App and correction closure: 118/118 on exact app source `fade6c07`, comprising all 116 app
  tests plus exact macro and micronutrient draft-retention journeys.
- [x] UI: accepted Food Detail 6/6; broad catalog 85/85 across the main run plus focused closure
  reruns, with both correction journeys repeated on `fade6c07`.
- [x] Address Sanitizer and Thread Sanitizer: 1,220/1,220 each.
- [x] Functions 33/33; Firestore Rules 33/33; migrations 10/10.
- [x] Strict lint, visual guard, privacy guard, dependency audits, exact-source Release build, and
  exact-source static analysis.
- [ ] Create a fresh signed archive and App Store export after `fade6c07` passes hosted verification
  and merges to `main`.
- [ ] Repeat deep signature, entitlements, profiles, architectures, Watch relationship, purpose strings,
  privacy manifests, release-key placement, and debug-hook inspection.
- [x] Food Detail store image 2 refreshed; the eight-image iPhone gallery at both Apple sizes and
  the existing Watch image are validated and staged under the replacement release artifact.
- [x] Metadata, review notes, privacy answers, public support/legal links, custom product page plans,
  and featuring nomination prepared.

Exact artifacts, hashes, and caveats are in `docs/release-evidence-2.3.md`.

## Peter: Submission Steps

1. Wait for the fresh archive/IPA identified in `docs/release-evidence-2.3.md`. Do not upload
   `6a5e535e`, `39e3d1a2`, or any older package.
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

## Final 2.3 Food Detail Addition

The next product bet should deepen the moat rather than widen the feature list:

**Food Detail and Nutrient Profile:** source, simulator, and physical acceptance are complete.
   Macros now lead the page, Food Trust is a compact evidence passport with
   its full receipt one tap away, and micronutrients have an always-visible preview plus a complete
   vitamins/minerals explorer. Missing fields remain unknown rather than silently becoming zero.
   The correction workspace now supports total fat, saturated fat, fiber, and all 22 vitamin and
   mineral fields. Peter accepted the complete six-item physical checklist on July 18, including
   correction persistence, physical keyboard dismissal, dark mode, and large text. The branch has
   no remaining Food Detail acceptance blocker.

   Final simulator closure subsequently caught a presentation-lifetime edge case that physical
   acceptance did not expose consistently: closing the numeric keyboard could reset an unsaved
   field. Food Detail now owns a durable correction draft across every entry route, keeps the
   underlying detail presentation stable, and disables gesture dismissal. Exact UI assertions
   verify entered total/saturated-fat and vitamin values after the keyboard closes.

   The July 18 nightly UI matrix executed 85 tests: 83 passed in the broad run, and both outliers
   then passed in focused closure runs. The specialist-source journey received one real fix: food
   search rows now expose stable button identities and complete source-aware accessibility labels,
   so Health Canada and NIH results cannot be confused with their visual Trust badges. The workout
   dashboard outlier passed unchanged and was classified as Xcode/simulator instability. The UI
   harness also stopped launching a redundant app session before every routed test.
## Post-2.3 Product Bets

1. **Recovery Continuum:** connect regional training load, recovery evidence, nutrition timing, and
   the next practical action without turning uncertainty into a single magical score.
2. **Voice logging:** reuse the review-before-write camera architecture for fast spoken meal entry.
3. **Trust at scale:** improve community consensus and source calibration only from measured
   production misses and corrections.
4. **Cost-aware growth:** establish free-tier AI economics from real route/model usage before a
   marketing push.
