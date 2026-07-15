# MyFitPlate 2.3 Roadmap

This file is the release and decision view for MyFitPlate. It intentionally contains only the
current objective, unresolved work, release gates, and evidence-gated follow-up. Completed
execution history belongs in Git, `AGENT_HANDOFF.local.md`, and the linked product contracts.

Last updated: 2026-07-15

## Product Direction

**Positioning:** The food log you can trust, built for people who train.

**2.3 promise:** See how food and training fit together, then act on what matters next.

**Product model:** Signal, evidence, action.

- Signal gives one fast interpretation of the current state.
- Evidence shows the source, amount, trend, uncertainty, or limitation behind it.
- Action offers one direct next step when an action is useful.

MyFitPlate should not try to beat incumbents through database size alone. Its advantage is the
combination of transparent food evidence, fast logging, training context, recovery context, and
reviewable coaching. Version 2.3 should make that advantage coherent and memorable without adding
friction to logging or workout execution.

## Branch And Release State

| Ref | Purpose | State |
| --- | --- | --- |
| `main` | Published product baseline | Live 2.2 code, with the exact release tagged `v2.2` |
| `codex/2.3-visual-unification` | Version 2.3 development | Active |

No other long-lived branches should exist. Short-lived release or repair branches must be deleted
after merge.

## Executive Status

| Area | Status | Remaining evidence |
| --- | --- | --- |
| Living Day and Week in Motion | Implemented | Final device comprehension, persistence, sharing, and rollout checks |
| Whole-app visual system | Implemented | Final representative device review and signed-build confirmation |
| Training and Recovery Field | Implemented | Focused strength, recovery-map, running, and Watch validation |
| Trust 3.0 | Implemented | Physical correction/source presentation checks and future production calibration |
| Health Canada and NIH sources | Implemented and deployed | Generic-food and supplement search/barcode acceptance |
| Trust-aware camera logging | Implemented and deployed | Fixed 20-30 photo benchmark and production cost/latency review |
| Local quality foundation | Green | Repeat release-only checks against the final committed candidate |
| App Store release | Candidate packaged | Physical acceptance, signed archive, metadata, screenshots, and submission |

Feature implementation is substantially complete. The critical path is now evidence, correction,
candidate integrity, and release preparation. New feature work is out of scope unless testing
reveals a data-integrity, privacy, crash, accessibility, or core-workflow failure.

## Completed 2.3 Foundation

- [x] Living Day is the default 2.3 Home direction with the 2.2 Home retained as a rollback path.
- [x] Reachable app, Watch, widget, and Live Activity surfaces use the shared visual and semantic
  signal system, with operational screens kept dense and predictable.
- [x] Food Detail and Trust Hub lead with field-level evidence, source lineage, findings, and a
  direct correction path; the numeric Trust index is secondary.
- [x] Training has a professional shared identity across programs, live workouts, history,
  analytics, running, Training Fuel, and the interactive Recovery Field.
- [x] Health Canada CNF and NIH DSLD extend generic-food micronutrients and supplement labels
  without overstating independence or inventing mass-based servings.
- [x] Camera logging uses purpose-specific server routing, bounded images, strict structured
  output, database grounding, visible uncertainty, review-before-write, quotas, and cost telemetry.
- [x] Health Canada, NIH, and all five camera routes have independent rollback controls. Camera
  requests are guarded in the current app and by a deployed server-side backstop that leaves
  general Maia available.
- [x] Home exposes consumed-versus-goal calorie and macro context, first-viewport water progress
  with a direct 8 oz action, and a goal-aware Daily Log using restrained semantic color roles.

## Definition Of Done

Version 2.3 is ready only when all four gates below are complete.

### Gate 1 - Candidate Integrity - Complete

- [x] Audit the complete 2.3 working tree and classify every modified and untracked file as
  intended product work, generated data, local-only state, or unrelated user state.
- [x] Commit the intended Trust, provider, camera, visual, test, documentation, and data-builder
  work in reviewable commits. Do not sweep unrelated project or localization changes into a commit.
- [x] Confirm phone, Watch, widget, and Live Activity targets all carry version 2.3, build 1.
- [x] Review the final diff against `v2.2` for accidental secrets, disabled safeguards, dormant
  prototypes, unreachable controls, debug fixtures, and release-only behavior changes.
- [x] Ensure production Functions and data assets match the candidate commit. Redeploy only if the
  final committed backend differs from what is currently live.

Candidate-integrity evidence: 1,128 Core tests, 109 app XCTest cases plus one Swift Testing smoke
test, 20 Functions tests, strict lint, the visual-system guard, complete Debug target build, and
diff checks all pass. The production inventory contains every expected 2.3 Function. The generated
CNF artifact contains 5,993 foods and is reproducible from its checked-in builder. The existing
localization catalog, Xcode project ordering change, and shared-scheme launch arguments remain
deliberately outside the candidate commits because they predated this normalization pass.

### Gate 2 - Trust And Camera Acceptance

- [ ] Run the fixed camera benchmark in `docs/camera-logging-2.3.md` against 20-30 representative
  meal, label, receipt, recipe, and menu images.
- [ ] Record correction size, confidence/range usefulness, inappropriate reference matches,
  malformed responses, latency, and token cost. Do not claim improved accuracy without the result.
- [ ] Validate ordinary-food searches that should benefit from Health Canada micronutrients and
  confirm source attribution remains visible.
- [ ] Validate NIH supplement search plus one real supplement barcode, including non-mass serving
  language and missing-nutrient behavior.
- [ ] Recheck the complete correction loop: barcode or photo result, field edit, before/after
  evidence, save, Trust refresh, and saved-food reuse without duplicates or stale nutrients.
- [x] Confirm each new provider and camera route can be disabled independently through its intended
  rollback or kill switch.

### Gate 3 - Physical Device Acceptance

Use `docs/device-test-2.3.md` as the detailed script. The release decision needs concise evidence
for these journeys:

- [ ] Living Day appears on launch and after tab round-trips; calorie/protein totals remain clear,
  water logs from the first viewport, the Daily Log stays readable, and Week in Motion does not
  insert late or move the Reports layout.
- [ ] Grocery refreshes stale meal-plan items while preserving manual entries; Meal Plan, its
  generator, and generated grocery output remain coherent.
- [ ] Fast Food Builder search, source links, choices, customization, totals, and logging work for
  representative burger, chicken, coffee, pizza, Mexican, sandwich, and dessert chains.
- [ ] Adaptive TDEE explains sparse or implausible logging instead of presenting a confident but
  misleading estimate.
- [ ] Maia tone, action cards, French/system voice choices, and Read Aloud are understandable and
  do not speak structured action payloads.
- [ ] Strength workout controls, progression, supersets, RPE/RIR, rest, completion, and recovery
  handoff remain fast and stable.
- [ ] Recovery Field has acceptable proportions, selectable regions, matching evidence, cautious
  language, dark-mode contrast, and large-text/VoiceOver reachability.
- [ ] Complete one guided outdoor interval, one Watch-imported run with heart-rate series, one
  phone-only run without heart rate, and one weak-GPS or corrected historical-route review.
- [ ] Confirm Watch context sync and offline replay, widgets, Live Activities, notifications,
  exact deep links, and privacy-safe sharing from the candidate build.

Only P0/P1 correctness, privacy, crash, accessibility, and core-workflow findings block release.
Cosmetic preferences that do not impair understanding or use move to the post-2.3 queue.

### Gate 4 - Release And Store

- [ ] Run the final Core, app, UI, Functions, Firestore Rules, migration, strict lint, visual guard,
  privacy, coverage, and Release-build checks against the exact candidate commit.
- [ ] Create and validate a signed archive from that commit, including the embedded Watch app,
  HealthKit purpose strings, entitlements, privacy manifests, and required architectures.
- [ ] Capture the final 2.3 App Store screenshots from deterministic, representative data. The
  first three should communicate trusted logging, the food-training loop, and the next action.
- [ ] Update App Store description, promotional text, What's New, review notes, privacy answers,
  support/legal links, feature nomination, and custom product pages where appropriate.
- [ ] Confirm launch-health dashboards, Crashlytics alerts, App Check state, provider flags, camera
  flags, community-consensus kill switch, and rollback ownership.
- [ ] Upload and submit the exact candidate. After acceptance, merge that source to `main` and tag
  the published release `v2.3`.

## Ordered Work Queue

1. [x] Normalize and commit the current 2.3 working tree without disturbing unrelated user files.
2. [ ] Complete the specialist-source and correction-loop physical checks.
3. [ ] Complete the fixed Trust-aware camera benchmark and evaluate the results.
4. [ ] Run the focused device checklist, fixing only release-blocking findings.
5. [ ] Rerun the full quality suite on the final candidate and produce the signed archive.
6. [ ] Produce screenshots and App Store metadata, then submit 2.3.

This order is deliberate. Screenshots and Store copy should represent the tested candidate, and a
signed archive should not be made from an uncommitted or differently deployed source state.

## Peter-Owned Actions

Peter is required for:

- physical iPhone, Apple Watch, GPS, heart-rate, speech, haptic, widget, and Live Activity checks;
- the fixed camera photo set and subjective review of correction burden;
- App Store Connect metadata, signing, archive upload, and final submission approval;
- production console decisions that require the owner account;
- any decision to expose community-contributed barcode data publicly.

Codex can independently handle source audits, implementation fixes, deterministic tests, CI,
documentation, screenshot fixtures, release diffs, backend verification, and candidate packaging.

## Evidence-Gated Follow-Up

These items are worthwhile, but they do not block 2.3.

- [ ] Calibrate Trust weighting only after at least 14 days of meaningful production correction,
  abandonment, reuse, provider, and score-band outcomes.
- [ ] Keep community barcode consensus private until abuse, conflict, moderation, cost, rollback,
  and aggregate-quality evidence passes an internal soak.
- [ ] Remove legacy Home only after Living Day has proven stable and its rollback is no longer
  needed.
- [ ] Expand the visual source guard to raw type, spacing, and radius drift after legitimate
  exceptions are normalized.
- [ ] Evaluate GS1 identity access or another commercial food provider only after measured misses
  show a specific identity, regional, restaurant, or coverage failure and the contract permits the
  required saved-food behavior.
- [ ] Consider richer Watch workout controls, polished PDF/coach export, and arbitrary report date
  ranges only after production use shows demand.

## Explicit Non-Goals For 2.3

- Public social feeds, friend graphs, public challenges, or coach groups
- iPad redesign, Android expansion, or a new subscription system
- A new readiness composite, food-morality score, ornamental 3D body, or decorative animation
- Autonomous AI changes to calorie or macro goals
- Another broad food database without measured evidence that it solves a real gap
- New running modes, workout types, or large feature families before the current candidate ships

## Post-Release Measures

Metrics are directional until MyFitPlate has enough real users for meaningful cohorts.

- Median time to the first successful food log remains under 60 seconds.
- Trust review opens increasingly reach a persisted correction or explicit acceptance.
- Lower evidence bands predict more later corrections than higher bands.
- More active users complete both a nutrition and training action in the same week.
- Living Day produces useful next actions without slowing successful food writes.
- Crash-free use, diary integrity, provider recovery, notification opt-out, and AI cost remain
  inside the documented launch-health guardrails.

## Source Contracts

- [2.3 device acceptance](docs/device-test-2.3.md)
- [Living Day experience](docs/living-day-experience-2.3.md)
- [Visual unification](docs/visual-unification-roadmap.md)
- [Design direction and Recovery Field](docs/design-direction-2.3.md)
- [Trust Score model](docs/trust-score-model.md)
- [Trust calibration](docs/trust-calibration-2.3.md)
- [Food provider strategy](docs/food-data-provider-strategy-2.3.md)
- [Camera logging contract](docs/camera-logging-2.3.md)
- [Micronutrient data contract](docs/micronutrient-data-2.3.md)
- [Analytics and launch health](docs/analytics-dashboard-2.3.md)
- [Feedback triage](docs/feedback-triage-2.3.md)
- [Security and privacy review](docs/security-privacy-review.md)
