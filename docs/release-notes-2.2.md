# MyFitPlate 2.2 — Release Notes

Version 2.2, build 1 (fresh build reset with the new marketing version). All shipping targets (app, widget, Live Activity, watch) aligned.

## App Store "What's New" (paste-ready)

```
Our biggest update yet. Running, an all-you-can-eat game, and a one-tap move from MyFitnessPal — on top of a fresh look and food data you can trust.

RUNNING, DONE RIGHT
• Record a run with just your phone — live pace, distance, and splits, with a lock-screen Live Activity and an audio coach that calls out every mile.
• Already run with a watch? Garmin, Polar, Coros, Apple Watch and more sync in automatically through Apple Health — routes, splits, and heart rate included.
• Route map of everywhere you've run, personal records, weekly mileage, shoe mileage tracking, and instant post-run fueling targets.

BEAT THE BUFFET
• A game for all-you-can-eat sushi, KBBQ, hot pot, and more: log what you eat and watch the à-la-carte value climb past what you paid.
• See when you've out-eaten the kitchen's own ingredient cost, priced for your city. Scan your plate, keep a lifetime scoreboard.

SWITCHING FROM MYFITNESSPAL?
• Bring your history with you. Import your diary and weight in a few minutes — days you've already logged here are never touched.

AND A LOT MORE
• A fresh look: new app icon, one calm palette, and every screen redesigned to lead with what matters.
• Fast Food Builder: assemble chain meals, coffee orders, and quick picks before the final nutrition review.
• Weekly Recap, logging streaks, and confetti when you hit your protein goal or set a record.
• Food you can trust: every entry checked against nutrition math, cross-verified badges, fuller vitamins and minerals, and one-tap fixes that stick.
• Maia coaching that adapts to your sleep and recovery, fasting Live Activities, CSV export, voice logging, and accessibility improvements throughout.
```

## Internal changelog (2.1 archive → 2.2)

| Area | Change |
|---|---|
| **Running** | GPS recorder (live pace/distance/splits, background tracking, lock-screen Live Activity, audio split coach with mute); any-watch import via HealthKit (Garmin/Polar/Coros/Apple Watch) with parallel-device dedupe + energy double-count guard; route map (all routes, decimated); records (longest, best 5K/10K, ghost pace, negative-split/fastest-split); weekly mileage in Reports; runs in Weekly Recap; shoe mileage tracker + performance leaderboard; run→recovery fueling prompt |
| **Beat the buffet** | AYCE session game across 6 cuisines / 136 items; live menu-value vs. price + harder kitchen-ingredient-cost game; city pricing index (mid-market); plate scan → AI pricing; restaurant-ingredient-cost tier; lifetime scoreboard; buffet Live Activity + Dynamic Island |
| **Switcher** | Import from MyFitnessPal: tolerant CSV parser (both export shapes), diary + weight, merge policy that never overwrites logged days, preview + progress |
| Celebrations | Confetti/medal overlay on protein-goal hit (per-day guard), AYCE win, workout PR, recorded-run PR |
| Coaching | Maia adaptive coaching plan with HRV + sleep adaptation; Restaurant Value Radar (protein-per-dollar menu scanner) |
| Apple Health | Weight auto-import with per-day de-duplication; strength/run energy double-count protection |
| **Fast Food Builder** | Offline-ready 25-chain chain-meal builder and quick-pick catalog (`ChainMealBuilderData.swift` in Core + `ChainMealBuilderView.swift`) with version stamp `2026.07.V1`. Support for `.portion` food items, capped `.stepper` drink/packet/slice quantities, `.fixed` meals, deterministic ingredient notes, catalog provenance, and honest pre-review `chainBuilder` source metadata across Chipotle, Sweetgreen, Cava, Chick-fil-A, Taco Bell, McDonald's, In-N-Out, Panera, Burger King, Popeyes, Panda Express, Qdoba, Shake Shack, Subway, Starbucks, Dunkin', Jersey Mike's, Jimmy John's, Firehouse Subs, Wingstop, Culver's, Wendy's, Tropical Smoothie, Domino's, Five Guys |
| Logging | Voice "walk & talk" logging; repeat-yesterday; rapid barcode scan tray (batched review); 3-way concurrent search across FatSecret, USDA, and Open Food Facts |
| Food trust | FoodDataSanity checker + trust cards (0–99 score v2); cross-source agreement + Cross-Verified badge; GS1 barcode fallback + privacy-safe telemetry; AI-estimate refine; multi-database search; micronutrient ingestion fix (quick-log hydration, OFF potassium unit slip) |
| Weekly Recap | Core builder (PR/weight/volume math) + Your Week sheet, shareable card, Home entry; logging streak with grace day; fill-my-macros |
| Design | DESIGN.md system; new deep-green MFP icon (iOS 18 dark/tinted) + tuned one-family palette; app-wide restructure (Home, Food Search, quick-log, weight, Reports, Meal Plan, Maia, workout player); motion layer; compact centered Quick Log action with a neutral adaptive surface and outlined brand icon above five equal-width destinations; scrollable expanded actions on compact phones; final Train target, builder tray, Reports chart-label, Settings goal-method, and compact-device polish; accessibility-size layouts for Quick Log, Food Search, Fast Food Builder, Train, Maia context, Meal Plan metrics, and food-trust details |
| Data / infra | CSV export; fasting Live Activity; activation-funnel analytics with elapsed onboarding-to-first-food/workout and a combined nutrition-plus-training milestone; analytics off in DEBUG/CI; release-health non-fatals |
| Growth / support | Prefilled privacy-safe feedback email in Settings; direct App Store sharing from Settings and shareable progress surfaces; conservative StoreKit review request after three distinct fresh workout completions spanning at least three days, limited to once per version and a 120-day cooldown |
| Privacy / security | Explicit versioned AI consent before third-party processing; separate Apple Health sharing toggle; account identifiers removed from Analytics/Crashlytics; server-owned recursive account deletion; App Check client integration; expanded public privacy, terms, and support docs |
| Food providers | Open Food Facts v2 product lookups, required User-Agent, explicit-submit global search, correct per-serving scaling; USDA requires a dedicated key, preserves full descriptions, and ranks exact matches; provider IDs no longer fall through to FatSecret |
| Data integrity | Per-user/day serialized diary mutations prevent rapid logs, water, workouts, and deletes from overwriting one another; malformed Firestore logs surface an error instead of becoming a writable empty day |
| Quality | Core coverage ~84%; HealthKit + UNUserNotificationCenter test seams; CI now includes SwiftLint, Release build, sequential UI smoke tests, Functions build, and production dependency audit; production Functions audit reports zero vulnerabilities; deterministic Debug-only App Store screenshot fixtures contain no personal data or production service calls; Home owns Trust Hub presentation so asynchronous nutrition refreshes cannot discard a first tap, with UI regression coverage for dismissal and interactive food rows |

_Full commit history on `main` from the 2.1 archive point. Latest local verification: Core 858 tests and the complete app unit target passed with 0 failures. The complete UI suite passed after adding first-tap Trust Hub regression coverage; the formerly order-dependent Home-to-Trust sequence also passed two repeated fresh-process runs, and the isolated Trust flow passed three repeated launches. The largest accessibility text size was visually checked on iPhone 17e across Trust detail, Food Search, Fast Food Builder, Train, Maia, Meal Plan, Quick Log, and Settings. Strict SwiftLint, privacy-manifest validation, `git diff --check`, and a fresh unsigned generic-device Release build are green. Standard-size App Store gallery composition is unchanged._

## Before archive
1. **Publish legal/support docs.** Commit and push the updated `docs/privacy_policy.md`, `docs/terms_of_service.md`, and new `docs/support.md` to `main`. The remote privacy page is public but still contains the older policy until this happens; Support does not exist remotely yet.
2. **Configure production keys/services.** Put the dedicated USDA FoodData Central key in ignored `secrets.xcconfig`; deploy the updated Firebase Functions; register App Attest and the development debug token in Firebase App Check. Leave callable enforcement off until App Check metrics show production clients are ready.
3. **App Store Connect.** Set the Privacy Policy and Support URLs, reconcile privacy labels with `PrivacyInfo.xcprivacy`, review export-compliance answers, confirm account deletion instructions, and paste/review the prepared subtitle, promotional text, keywords, and description from `docs/app-store-metadata-2.2.md`.
4. **Watch Gemini key — ask the contributor to revoke.** Every Gemini reference is gone from the codebase (all AI runs through Firebase Functions + the OpenAI server secret); the only exposure is the contributor's own Google quota. Have them delete the key in their AI Studio.
5. **Upload the completed App Store screenshots** from `tools/screenshots/output/`. The eight-shot 1320x2868 and 1284x2778 galleries were generated from deterministic local fixtures, visually reviewed, and contain no personal account data. See `docs/app-store-screenshots.md` for ordering and reproducible recapture instructions.
6. **Device pass** — run `docs/device-test-2.2.md` end to end. Highest-value: AI consent/Health toggle, account deletion with a throwaway account, record a run (GPS + Live Activity + Health round-trip), a full Beat-the-buffet session, MFP import idempotency, Fast Food Builder, and Value Radar.
7. Confirm version/build (2.2 / 1, or higher if a 2.2 build was already uploaded) still aligned across app + extensions after any Xcode changes, then validate the signed archive.

## Post-release checklist
1. Flip `feature_communityBarcodeCorrections` → `true` in Firebase Console → Remote Config (kill switch: set back to `false`).
2. Watch Firebase → Analytics: activation funnel (including `elapsed_seconds` and `nutrition_training_loop_completed`), `weekly_recap_viewed`, `mfp_import_completed`, `food_data_suspicious`, `food_correction_action`, share-open events, feedback-email opens, and review-request moments.
3. Watch Crashlytics non-fatals for `operation`-tagged failures (data layer + `decode_meal_suggestion`).
4. gcloud scheduled Firestore backups; branch-protection ruleset; ASC privacy-label reconciliation for any new data use (location for runs, HealthKit weight/HRV).
