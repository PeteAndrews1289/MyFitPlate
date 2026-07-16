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
| FB-2302 | P1 | Three running sensor/data paths still need physical validation | Ready for device | Peter: complete one guided GPS interval, inspect one Watch-imported run with HR, and inspect or record one phone-only run without HR using `docs/device-test-2.3.md`. |
| FB-2303 | P1 | Signed-build App Check validity and final Store processing still require owner evidence | Ready for signed build | Exact-candidate tests, signed archive, App Store export, production Functions, provider smoke, feature defaults, private rollback state, App Attest registration, public links, and privacy package are verified in `docs/release-evidence-2.3.md`. Peter must inspect App Check validity from the signed/TestFlight candidate, verify the review account, upload, and pass App Store processing. |
| FB-2304 | P2 | KPI and launch-health views need real production traffic | Waiting for data | Firebase definitions, key events, explorations, and Crashlytics alerts are configured. Codex analyzes only clean versioned cohorts after 7-14 days; Trust reweighting requires the separate minimums in `docs/trust-calibration-2.3.md`. |
| FB-2305 | P2 | Community barcode aggregate has not completed an internal abuse/rollback soak | Intentionally gated | Keep `feature_communityBarcodeCorrections=false`. Use disposable accounts and the runbook in `docs/community-barcode-consensus-2.3.md`; this is not a replacement 2.2 public-release requirement. |
| FB-2306 | P2 | Exact custom-product-page routes were blocked until the replacement 2.2 binary was approved | Owner action | Version 2.2 is live. Peter can now publish the prepared Trust, Strength, Weight, Dining, Running, and Meal Plan pages and smoke-test their signed-in and signed-out routes. |
| FB-2309 | P2 | Maia's read-aloud voice and prose sounded robotic | Ready for device | Maia now ranks regular downloaded voices deterministically, uses neutral prosody, strips hidden action payloads and markdown from speech, exposes voice selection/preview, and has explicit natural-conversation rules. Peter completes the three Maia checks in `docs/device-test-2.3.md`. |
| FB-2311 | P2 | A long supermarket/weak-GPS interval made historical split times total far less than the workout duration and produced a misleading Negative Split badge | Ready for device | Historical route replay now retains elapsed gaps while live pace keeps its signal-loss cap; stop-heavy split variance suppresses the badge. Focused Core tests pass. Peter reopens one comparable route on build 3. |
| FB-2312 | P2 | Living Day appeared at launch but Home fell back to the 2.2 dashboard after leaving and returning to the tab | Ready for device | The persistent app shell now owns one launch/Remote Config decision and passes it into every Home reconstruction. A Home -> Reports -> Home UI regression passes. Peter repeats the tab cycle on the physical build. |
| FB-2313 | P2 | Week in Motion inserted about one second after opening Reports and visibly moved the rest of the page | Ready for device | Reports now reuses one account/day-scoped loader across tab reconstruction and holds the complete weekly-story footprint with a redacted loading sequence. A render-height guard and full visual attachment pass. Peter checks first and return visits on the physical build. |

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

## Intake template

For each new report record: date/build, device and OS, source, expected result, actual
result, reproduction rate, data/privacy impact, workaround, severity, owner, and the exact
evidence required to close it. Never include passwords, API keys, barcodes, food names,
account identifiers, Health samples, prompts, or other user content in this ledger.
