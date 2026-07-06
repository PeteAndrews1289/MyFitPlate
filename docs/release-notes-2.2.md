# MyFitPlate 2.2 — Release Notes

Version 2.2, build 4. All shipping targets (app, widget, Live Activity, watch) aligned.

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
| Logging | Voice "walk & talk" logging; repeat-yesterday; rapid barcode scan tray (batched review) |
| Food trust | FoodDataSanity checker + trust cards (0–99 score v2); cross-source agreement + Cross-Verified badge; GS1 barcode fallback + privacy-safe telemetry; AI-estimate refine; USDA-blended search; micronutrient ingestion fix (quick-log hydration, OFF potassium unit slip) |
| Weekly Recap | Core builder (PR/weight/volume math) + Your Week sheet, shareable card, Home entry; logging streak with grace day; fill-my-macros |
| Design | DESIGN.md system; new deep-green MFP icon (iOS 18 dark/tinted) + tuned one-family palette; app-wide restructure (Home, Food Search, quick-log, weight, Reports, Meal Plan, Maia, workout player); motion layer |
| Data / infra | CSV export; fasting Live Activity; activation-funnel analytics; analytics off in DEBUG/CI; release-health non-fatals |
| Quality | Core coverage ~84%; HealthKit + UNUserNotificationCenter test seams; agent-batch review fixes (audio-session leak, Value-Radar fabricated-data guard, AYCE diary write race, daily-briefing landmine, shoe-tag retroactivity) |

_Full commit history on `main` from the 2.1 archive point. Core: 746 tests, 0 failures. App suite green._

## Before archive
1. **Watch Gemini key — ask the contributor to revoke.** Every Gemini reference is gone from the codebase (all AI runs through Firebase Functions + the OpenAI server secret); the only exposure is the contributor's own Google quota. Have them delete the key in their AI Studio.
2. **Recapture App Store screenshots** on-device with the current build (accents + new features) and rerun `tools/screenshots/compose.py`, then upload. The switcher and running screens are strong new additions to the six-shot set.
3. **Device pass** — run `docs/device-test-2.2.md` end to end. Highest-value: record a run (GPS + Live Activity + Health round-trip, parallel-watch energy not doubled), a full Beat-the-buffet session, a MyFitnessPal import (incl. re-import idempotency), voice logging, and the celebration triggers.
4. Confirm version/build (2.2 / 4) still aligned across app + extensions after any Xcode changes.

## Post-release checklist
1. Flip `feature_communityBarcodeCorrections` → `true` in Firebase Console → Remote Config (kill switch: set back to `false`).
2. Watch Firebase → Analytics: activation funnel, `weekly_recap_viewed`, `mfp_import_completed`, `food_data_suspicious`, `food_correction_action`.
3. Watch Crashlytics non-fatals for `operation`-tagged failures (data layer + `decode_meal_suggestion`).
4. gcloud scheduled Firestore backups; branch-protection ruleset; ASC privacy-label reconciliation for any new data use (location for runs, HealthKit weight/HRV).
