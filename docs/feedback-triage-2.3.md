# Version 2.3 Feedback Triage

This is the single severity-ranked ledger for review feedback, support messages,
device-only defects, and repeated friction during the live 2.2 follow-through and version 2.3
cycle. The filename remains stable for existing references. Add an item here before
starting a redesign or a release fix. Do not treat one preference as a trend unless it
also exposes a correctness, accessibility, or workflow failure.

## Severity and closure

| Level | Meaning | Response |
| --- | --- | --- |
| P0 | Data loss, privacy/security exposure, account deletion failure, or unusable release | Stop rollout and fix or roll back immediately |
| P1 | Core logging, Trust, training, Watch, or release workflow is broken with no reliable workaround | Block the release until fixed or explicitly removed from scope |
| P2 | Material friction, misleading output, accessibility failure, or degraded secondary workflow | Fix in the release when reproducible; otherwise document a bounded follow-up |
| P3 | Preference, polish, or isolated enhancement with a working path | Keep for pattern review; do not displace P0-P2 work |

An item is closed only when its outcome is named: fixed and regression-tested, validated
on the affected device, intentionally deferred with a reason, or rejected with evidence.
Code complete without required hardware validation is `Ready for device`, not `Closed`.

## Open ledger

| ID | Severity | Feedback or risk | State | Owner and next evidence |
| --- | --- | --- | --- | --- |
| FB-2303 | P1 | Signed-build App Check validity and final Store processing still require owner evidence | Ready to upload | Exact-candidate tests, signed archive, App Store export, production Functions, provider smoke, feature defaults, private rollback state, App Attest registration, public links, privacy package, and the final-source phone smoke are verified in `docs/release-evidence-2.3.md`. Peter must upload the exact package, repeat the short smoke on the processed TestFlight binary, inspect App Check validity, verify the review account, and pass App Store processing. |
| FB-2304 | P2 | KPI and launch-health views need real production traffic | Waiting for data | Firebase definitions, key events, explorations, and Crashlytics alerts are configured. Codex analyzes only clean versioned cohorts after 7-14 days; Trust reweighting requires the separate minimums in `docs/trust-calibration-2.3.md`. |
| FB-2305 | P2 | Community barcode aggregate has not completed an internal abuse/rollback soak | Intentionally gated | Keep `feature_communityBarcodeCorrections=false`. Use disposable accounts and the runbook in `docs/community-barcode-consensus-2.3.md`; this is not a version 2.3 public-release requirement. |
| FB-2306 | P2 | Exact custom-product-page routes were blocked until the replacement 2.2 binary was approved | Owner action | Version 2.2 is live. Peter can now publish the prepared Trust, Strength, Weight, Dining, Running, and Meal Plan pages and smoke-test their signed-in and signed-out routes. |
| FB-2309 | P2 | Maia's read-aloud voice and prose sounded robotic | Superseded by FB-2318 | The local voice ranking, speech formatting, and prose rules remain the offline fallback. FB-2318 tracks the higher-quality online option and final audio comparison. |
| FB-2318 | P2 | Even enhanced system voices still sound recognizably robotic for Maia | Post-release API access | Added and deployed `Maia Natural`, an AI-disclosed online speech route with a 30/day limit, bounded text, account-scoped hashed cache, independent feature flag, explicit AI-consent guard, full-response local fallback, and cleanup on sign-out/account deletion. Peter accepted the local/French choices, consent fallback, offline fallback, tone modes, and read-aloud behavior. The current API project cannot access the configured online speech model, so 2.3 ships the disclosed local fallback and makes no online-voice claim. |

## Closed feedback

| ID | Original feedback | Outcome |
| --- | --- | --- |
| FB-2291 | Quick Log was visually crowded and displaced after adding Train | Centered compact outlined action above five equal-width tabs; expanded actions remain reachable on compact phones and UI tests protect first-tap behavior. |
| FB-2292 | Trust warned that saturated fat exceeded total fat, but the correction sheet could not edit both fields and a label rescan retained stale values | Both editors expose Total fat and Saturated fat, contradictory saves are blocked, label replacement clears stale detail nutrition, and barcode correction updates rather than duplicates the saved food. |
| FB-2293 | Many foods appeared to lack micronutrients despite multiple databases | Provider units, nil-versus-zero semantics, exact-product enrichment, recipe retention/scaling, and daily/report coverage were corrected and documented in `docs/micronutrient-data-2.3.md`. |
| FB-2294 | The Watch target built but did not arrive with the phone app | The Watch product is embedded in the phone bundle, companion identities are corrected, and the context handshake retries activation/reachability/state changes. Physical replacement is tracked separately as FB-2301. |
| FB-2295 | A food database outage left search at a dead end | Search now keeps local history available, uses nontechnical failure copy, and offers Try again plus Create food. A deterministic UI regression test covers the recovery state. |
| FB-2301 | Watch app said to open the phone but never received context | The companion is embedded, the activation/reachability handshake recovers, and Peter physically validated initial context, current values, offline exactly-once water/meal replay, reconnect, and account-scoped clearing on 2026-07-12. |
| FB-2307 | Simulator accessibility coverage did not replace physical VoiceOver and device-size checks | Peter physically validated VoiceOver, largest text, dark mode, Increase Contrast, widget destinations, notification routing, and real offline/online Food Search recovery on 2026-07-12. |
| FB-2308 | Supersets/rest and advanced set effort/type persistence required hardware input | Peter physically validated adjacent supersets, rest behavior, warmup/drop/failure types, RPE/RIR persistence, and warmup exclusion from analytics on 2026-07-12. |
| FB-2310 | App Store processing rejected build 2 because the embedded Watch plist lacked both HealthKit purpose strings | The corrected Watch purpose strings passed processing and the replacement version 2.2 release went live on 2026-07-14. |
| FB-2320 | Home's Workouts quick action could drop navigation because it depended on temporary child-view state | The action now sends a direct tab-selection callback from Home; the journey passed five consecutive repetitions. |
| FB-2321 | Home could show a protein target and remaining amount that differed by one gram | Daily action and Living Day calculations now share nearest-gram rounding, with focused regressions for the original mismatch. |
| FB-2302 | Three running sensor/data paths still needed physical validation | Peter accepted the guided GPS interval, Watch-imported heart-rate run, phone-only run without heart rate, and weak-GPS historical review on 2026-07-17. |
| FB-2311 | A weak-GPS interval produced irreconcilable historical splits and a misleading Negative Split badge | The elapsed-gap fix and badge suppression passed focused tests and Peter's physical route review on 2026-07-17. |
| FB-2312 | Living Day disappeared after leaving and returning to Home | The persistent shell fix passed automated round trips and Peter's physical tab/relaunch checks on 2026-07-17. |
| FB-2313 | Week in Motion inserted late and moved the Reports layout | Reserved loading geometry and loader reuse passed automated coverage and Peter's first/return physical visits on 2026-07-17. |
| FB-2314 | Week in Motion's dates and symbols were unclear | Explicit rolling-window dates and the day explanation sheet passed focused UI coverage and Peter's physical comprehension check on 2026-07-17. |
| FB-2315 | A generated Meal Plan did not remain saved or visible | Durable seven-day persistence, reload, Grocery refresh, and discard behavior passed regressions and Peter's physical generation/relaunch flow on 2026-07-17. |
| FB-2316 | Trust hid useful agreement across generic-food providers | Supporting-source convergence and identity caveats passed deterministic coverage and Peter's physical Health Canada/control checks on 2026-07-17. |
| FB-2317 | Multivitamin results lacked micronutrients and Opti-Men UPC did not resolve | Micronutrient-aware NIH ranking and exact UPC normalization passed backend checks and Peter's physical search/barcode acceptance on 2026-07-17. |
| FB-2319 | Camera routing could fail when the preferred model was unavailable | The July 17 deployment recognized Terra's `model_not_found`, switched to `gpt-4o-mini`, and completed an authenticated meal-photo request; strict route schemas and Functions tests remain green. |

## Intake template

For each new report record: date/build, device and OS, source, expected result, actual
result, reproduction rate, data/privacy impact, workaround, severity, owner, and the exact
evidence required to close it. Never include passwords, API keys, barcodes, food names,
account identifiers, Health samples, prompts, or other user content in this ledger.
