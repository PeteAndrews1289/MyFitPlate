# Version 2.3 Analytics and Launch-Health Contract

This document is the source of truth for the 2.3 acquisition, activation, retention,
Trust, training, reliability, and AI-cost dashboards. It defines what each number means
before production data is used to make product decisions.

## Operating rules

- Compare MyFitPlate with its own clean 2.2 baseline. Do not invent an industry target.
- Segment by app version and `analytics_schema`. Version 2.3 emits schema `2.3.1`.
- Use distinct users unless a metric explicitly says events or attempts.
- Treat an event as evidence of the named behavior only. A screen view is not a success.
- Keep App Store acquisition totals separate from Firebase product behavior, then compare
  them by calendar week, territory, app version, and custom product page where available.
- Do not send account IDs, food names, journal content/categories, prompts, AI responses, raw
  barcodes, nutrition/body values, workout details, HealthKit values, or GPS routes to
  Analytics or Crashlytics.
- Do not tune the Trust model to make scores look better. Calibration requires later user
  correction outcomes grouped by model version, evidence class, and score band.

## Canonical product funnel

| Question | Metric | Definition |
|---|---|---|
| Did acquisition reach onboarding? | Onboarding starts/completions | App Store product-page views/downloads compared with distinct `onboarding_completed` users by week and version. |
| Did a new user log food? | First-food completion | Distinct `first_food_logged` users divided by distinct `onboarding_completed` users in the same install cohort. |
| Was first value fast? | Time to first food | Median and 75th percentile of `first_food_logged.elapsed_seconds`; exclude events without elapsed time from latency percentiles, but retain them in completion counts. |
| Does switching history work? | Import completion | Distinct `mfp_import_completed` users divided by distinct `mfp_import_started` users. Review `days`, `entries`, and `conflicts_skipped` only as operational counts. |
| Does barcode friction recover? | Barcode hit and recovery | Attempt count and distinct users for `barcode_lookup_outcome`, grouped by `result`, winning `source`, and `duration_bucket`; recovery actions come from `barcode_miss_recovery.action`. |
| Is Trust used, not merely shown? | Trust action rate | Distinct users with `food_trust_action` or `food_correction_action` divided by distinct users with `food_trust_card_viewed`. Segment by `trust_model_version`, `trust_level`, source, and correction requirement. |
| Did training become part of the loop? | First training completion | Distinct `first_workout_completed` users divided by onboarding completions, grouped by `training_mode`. Strength, recorded runs, and treadmill runs qualify; imported historical runs do not. |
| Did nutrition and training connect? | Loop completion | Distinct `nutrition_training_loop_completed` users divided by onboarding completions. This one-shot event requires both a successful food write and an in-app training completion. |
| Is logging becoming habitual? | Weekly active loggers | Distinct users with `logging_day_active` in a rolling seven-day window. The app emits at most one event per app instance and local day. |
| Are users returning? | D1/D7 return | Firebase retention for the onboarding cohort, segmented by app version. Use Firebase's app-instance identity; MyFitPlate account IDs remain disabled. |

## Training and fuel leading indicators

These events evaluate the 2.3 loop before waiting for D7 retention:

| Behavior | Events and dimensions |
|---|---|
| Training frequency | `training_session_completed`, grouped by `training_mode` |
| Existing daily fuel action | `today_fuel_plan_tapped`, grouped by `kind` and `action` |
| Recovery offer seen | `workout_recovery_handoff_viewed`, grouped by `kind` |
| Recovery action chosen | `workout_recovery_handoff_tapped`, grouped by `kind` and `action` |
| Recovery suggestion logged | `workout_recovery_handoff_logged` event count and distinct users |
| Meal-plan generation | `meal_plan_generated` distinct users and event count |

Calorie and macro values attached by older call sites are removed by the analytics privacy
sanitizer. The dashboard measures whether a user acted, not the contents of their plan.

## Acquisition and custom product pages

App Store Connect is authoritative for impressions, product-page views, downloads,
conversion, territory, source type, and custom product page. Firebase is authoritative for
what happens after launch.

Use `deep_link_opened.destination` as a routing integrity check for Food Search, Trust,
Fast Food Builder, Running, and Meal Plan. The old parameter name `route` is intentionally
blocked because it could also mean a GPS route; 2.3 uses the privacy-safe `destination` key.

For each weekly custom-page cohort, report:

1. Impressions and product-page views from App Store Connect.
2. Downloads and App Store conversion.
3. Matching destination opens in Firebase as a health check, not an attribution substitute.
4. First-food, first-training, and loop completion for the same release week/version.
5. D1 and D7 return once the cohort has matured.

Do not attach the exact destination links to live pages until the 2.3 binary is approved and
the five URLs pass signed-in and signed-out physical-device testing.

## Launch-health operating view

| Signal | Source | Breakdown | Escalation rule |
|---|---|---|---|
| Crash-free users/sessions | Crashlytics | Version, build, OS | Investigate any material drop from the clean 2.2 baseline; halt staged rollout for a reproducible launch/data-loss crash. |
| Startup completion | Analytics + Crashlytics | `duration_bucket`, build | Review a sustained shift toward `over_4s`; correlate with crash and network changes. |
| Non-fatal failures | Analytics + Crashlytics | `area`, `operation`, build | Every repeated operation needs an owner, user impact statement, and rollback or repair path. |
| Diary write failures | `nonfatal_error_recorded` | `area=nutrition`, `operation=daily_log_mutation`; Crashlytics also carries safe `stage` | Treat repeated persistence failures as data-loss severity even when the UI shows an error. |
| Barcode lookup health | `barcode_lookup_outcome` | `result`, winning `source`, `duration_ms`, `duration_bucket` | Watch hit rate and p50/p75 latency. A miss represents the complete provider chain, not one provider. |
| AI response decoding | `nonfatal_error_recorded` | `area=ai`, decode operation | A repeated decoder operation means a feature contract is broken even if the model request succeeded. |
| AI request success and latency | Server `aiUsage` documents and Functions logs | Day, model, outcome, latency | Investigate failure-rate or latency changes before increasing AI exposure. |
| App Check validity | Firebase App Check metrics | Function, app version | Do not enable enforcement until valid 2.2+ traffic is consistently accepted and rollback is ready. |
| Account deletion | Analytics + Functions logs | Started, completed, failed reason | Any server-data deletion failure is release-critical; never report success before server and Auth deletion finish. |

The launch view should show the current build beside the previous production build. Red means
an owner is actively investigating; it must never mean merely "a number moved."

## AI cost per active user

The callable Function already keeps a private per-user/day quota document. Schema 1 now adds:

- `count`: valid requests admitted by the daily limiter.
- `successfulCount` and `failedCount`.
- `inputTokens`, `outputTokens`, and `totalTokens` from successful OpenAI responses.
- `totalLatencyMs`, `lastLatencyMs`, `lastModel`, and `lastOutcome`.
- `uid`, `day`, and `updatedAt` for quota enforcement and account deletion.

Prompts and responses are never written to this document. These documents remain server-owned
and are deleted by the existing account-deletion Function.

Calculate weekly AI cost per active user as:

`provider cost for the week / distinct app_session_started users for the week`

Use the OpenAI invoice as the financial source of truth. Token totals explain which model and
usage changes moved cost, but the app must not hardcode provider pricing that can change without
an app release. Because Analytics deliberately has no account ID, use aggregate totals over the
same period rather than joining server UIDs to Firebase users.

## Firebase setup checklist

Peter must complete the console-side setup after the instrumented build produces data:

1. Register useful custom dimensions: `analytics_schema`, `destination`, `entry_source`,
   `training_mode`, `result`, `source`, `duration_bucket`, `trust_model_version`,
   `trust_level`, `action`, `area`, `operation`, and deletion `reason`.
2. Register numeric metrics where Firebase requires it: `elapsed_seconds`, `duration_ms`,
   `trust_score`, and operational import counts.
3. Mark `first_food_logged`, `first_workout_completed`,
   `nutrition_training_loop_completed`, and `mfp_import_completed` as key events.
4. Build one Activation exploration and one Launch Health exploration from the definitions
   above. Do not create several dashboards with slightly different denominators.
5. Add Crashlytics alerts for new fatal issues and repeated `daily_log_mutation` operations.
6. Review App Check request metrics by callable before proposing enforcement.
7. Export a weekly App Store Connect acquisition report and place its totals beside, not
   inside, Firebase's app-instance funnel.
8. After 7-14 clean days, record the 2.2 baseline and set alert thresholds in this document.

## Ownership and rollout

- **Codex:** event contracts, instrumentation, tests, dashboard definitions, privacy checks,
  query recipes, and regression analysis.
- **Peter:** App Store Connect export, Firebase/Crashlytics/App Check console configuration,
  production access decisions, and response to real support/review feedback.
- **Rollback:** disable or revert the offending feature path first. Analytics must never be
  allowed to block logging, training completion, account deletion, barcode results, or AI
  responses. Server usage telemetry failures are logged but do not fail a successful AI call.

## Known boundaries

- Firebase Analytics identifies an app instance, not a MyFitPlate account. This is intentional.
- `logging_day_active` is once per app instance/day, so two accounts sharing one device still
  count as one active analytics user.
- Barcode duration is end-to-end user-perceived lookup time. Concurrent provider-specific
  timing is not exposed as separate events.
- Imported HealthKit history does not qualify as an in-app training completion.
- Console configuration, production baselines, and thresholds cannot be declared complete
  until the instrumented binary has real traffic.
