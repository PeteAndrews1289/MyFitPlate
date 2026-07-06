# MyFitPlate Roadmap — Single Point of Truth (SPOT)

A living, definitive roadmap and product vision for MyFitPlate. Designed around unique, gamified real-world experiences and high-trust nutrition tracking.

---

## 🏁 Shipped Foundation (Versions 2.0 – 2.2)
- [x] **AYCE Challenge & Scoreboard**: 6-cuisine buffet tracker, sushi roll library (48 items), live value vs. price game, haptic kitchen wins, and persistent lifetime scoreboard ("kitchens defeated").
- [x] **Apple Health & Running Engine**: Bidirectional workout sync, GPS route mapping, false-start filtering (<100m/<2min), and parallel-watch calorie double-count protection.
- [x] **High-Trust Nutrition Logging**: GS1 barcode fallback, multi-database cross-verification (USDA, FatSecret, OpenFoodFacts), and 0–99 Trust Cards.
- [x] **Maia Adaptive Coaching**: Daily strategy cards linking sleep, recovery, training, and nutrition adjustments.
- [x] **HealthKit Test Seams**: Protocol-abstracted seam (`HealthStoreScheduling`) with deep unit coverage across health and running services (package line coverage 84%).

---

## 🚀 Version 2.3 — Running Superpowers & Friction Killers (Completed)
Focusing on running gear management, immediate post-run recovery nutrition, and effortless daily logging.

### Running Engine & Recovery
- [x] **Shoe Mileage Tracker (Core Engine)**: Added `RunningShoe` struct, `shoeID` tagging on runs, and `RunningShoeStore` for local gear persistence and wear calculations.
- [x] **Shoe Mileage Tracker (UI)**: Built gear management screens (`ShoeGearManagerView`) and run tagging UI (`RunHistoryView`, `RunDetailView`).
- [x] **Run-to-Fuel Recovery Prompts (Core Engine)**: Built `RunRecoveryRules` with dynamic carb/protein formula scaling and integrated `currentRunRecoveryPrompt` into `InsightsService`.
- [x] **Run-to-Fuel Recovery Prompts (UI)**: Display immediate post-run recovery banner cards in Home/Insights views.
- [x] **Route Personal Records ("Ghost Pace")**: Track and highlight fastest average paces and PRs across familiar GPS routes and loops (`GhostPaceComparison` in `RunStats`, UI card in `RunDetailView`).

### Effortless Logging Polish
- [x] **1-Tap Quick Logging (Core Engine)**: Implemented `repeatMeal`, `fetchYesterdayMeal`, and `repeatYesterdayMeal` in `DailyLogService` and `DailyLogRules`.
- [x] **1-Tap Quick Logging (UI)**: Added "Repeat Yesterday" action button in logging screens (`CalorieLogView`).
- [x] **Photo Library Logging (Core & UI)**: Implemented `AICameraService` for image preparation and payload scaling; `imageSourceDialog` integrated in UI.
- [x] **"Walk & Talk" Voice Logging (Core Engine)**: Implemented `VoiceLoggingService` async state machine (`idle`, `recording`, `transcribing`, `completed`).
- [x] **"Walk & Talk" Voice Logging (UI)**: Added mic button and live recording status banner in daily log view (`FoodSearchView`).

---

## 🌟 Version 2.4 / 3.0 — Gamified Lifestyle & Advanced Dining
Expanding the unique gamification architecture that makes MyFitPlate stand out from generic calorie counters.

### Gamified Dining & Nutrition
- [ ] **Restaurant Value Radar**: AI menu scanner that analyzes restaurant menus or photos and ranks dishes by Protein-to-Dollar and Protein-to-Calorie ratios with a live "Value Score".
- [ ] **Legendary Refeed Mode**: Anabolic carb-cycling and glycogen supercompensation tracking for heavy leg days or endurance runs, replacing standard guilt-based calorie overage alerts.

### Platform Expansion & Community
- [ ] **Apple Watch Standalone App**: Build out the dedicated wrist UI (`watchkitapp` target) for quick-logging and real-time workout tracking.
- [ ] **Social AYCE & Step Challenges**: Friend scoreboards, shared buffet challenges, and weekly running/step competitions.
- [ ] **Data Export & Reporting**: Comprehensive PDF and CSV export for medical or personal coaching review.

---

## 🛠️ Always-On — Ops, Quality & Health
- [x] Wire release-health instrumentation and Crashlytics/Analytics dashboards.
- [ ] Monitor LLM / AI call frequencies against cost estimates.
- [ ] Keep package test coverage at 80%+ with behavior tests on every core engine and data calculation path.

---
_Living document — Single Point of Truth. Last updated: 2026-07-05._
