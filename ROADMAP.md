# MyFitPlate Roadmap — Single Point of Truth (SPOT)

A living, definitive roadmap and product vision for MyFitPlate.

Competitive thesis: MyFitPlate should not try to out-database MyFitnessPal, out-micronutrient Cronometer, or out-algorithm MacroFactor head-on. The wedge is **high-trust nutrition logging for people who train**, with Maia turning food, recovery, lifting, running, and real-world dining into one daily loop.

Current objective: move from "impressive broad feature set" to "obvious reason to switch and stay." Every sprint below should reduce daily logging friction, make trust visible, or connect nutrition to training outcomes.

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

## 🧭 Competitive Sprint Plan
The next several sprints are ordered to make the product competitive before expanding the surface area further. The first three sprints are conversion and retention work; the later sprints deepen the moat.

### Sprint 0 — Baseline, Positioning, and Release Readiness
Goal: establish the competitive scoreboard and make the product story sharper before building more.

- [ ] **Define the public promise**: "The food log you can trust, built for people who train." Use this across onboarding, App Store copy, screenshots, and Maia entry points.
- [ ] **Create a competitive KPI dashboard**: track first-food-log completion, time to first log, barcode hit/miss/recovery, AI estimate review/correction, MFP import starts/completions, D1/D7 return, weekly active loggers, and LLM cost per active user.
- [ ] **Refresh App Store story**: recapture screenshots around switcher import, Trust Cards, fast logging, Maia recovery/meal action cards, and training-to-nutrition loops. Avoid generic "whole day" framing unless the visible screen proves it.
- [ ] **Fix screenshot-visible polish**: resolve clipped workout controls, ensure no App Store shot has cropped labels, and keep Trust/Importer shots above generic dashboards.
- [ ] **Release gate**: `swift test --package-path MyFitPlateCore`, app simulator build, device smoke pass for log food -> trust card -> diary -> report.

Success signal: a new user can understand why MyFitPlate exists in 10 seconds, and the team has baseline numbers for the conversion funnel.

### Sprint 1 — Switcher and First-Log Conversion
Goal: beat the biggest incumbent weakness by making migration and first value immediate.

- [x] **Switch from MyFitnessPal entry point**: promote import during onboarding and Settings; include a concise "what imports / what never overwrites" trust explanation. MVP shipped: Welcome positioning, Settings importer, Home empty-day switcher prompt, and first-session import route.
- [x] **First-session guided path**: after signup, route users to either "Import history" or "Log first meal" with one clear primary action. MVP shipped: post-setup choice sheet opens `MFPImportView` or first-session food search and logs the choice.
- [x] **Simplify center quick log**: show 3 context-aware actions first (usually Search, Barcode, Describe/Camera) and move the rest behind "More." Keep Beat the buffet and Running discoverable but not competing with the first log. MVP shipped: Search, Scan barcode, and Describe stay primary; camera, exercise, recipes, buffet, and running expand behind More.
- [x] **Fast repeat loop**: surface Smart history, Yesterday, and saved foods higher once the user has history; optimize for "same breakfast in two taps." MVP shipped: Food Search now promotes Yesterday, Smart history, My foods, and Recent foods above secondary actions whenever history exists, with source-level telemetry for quick-log taps.
- [x] **Recovery for misses**: barcode miss should offer "Create from label," "Use camera," and "Search by name" with telemetry on which path saves the session. MVP shipped: Food Search and global quick-log scanner now share a guided barcode-miss recovery sheet with action telemetry.

Success signal: median first food log under 60 seconds for new users; MFP import completion rate is measured and improving.

### Sprint 2 — Trust Layer 2.0
Goal: make "nutrition you can trust" a visible product advantage, not an internal implementation detail.

- [x] **Trust Card redesign**: show source, confidence, cross-verification, sanity checks, and what the user can do next in one compact card. MVP shipped: the food-detail trust card now includes explicit Source, Check, Review, and Sanity rows alongside the score, summary, reasons, and correction action.
- [x] **Trust Hub / audit screen**: give users a daily list of entries that need review, entries that are cross-verified, and entries fixed by them. MVP shipped: the nutrition audit sheet is now a Trust Hub with review, cross-verified, and reviewed-by-you sections, reachable from the nutrition card whenever foods are logged.
- [x] **Community barcode rollout**: keep the feature flag, add health metrics for contribution eligibility, rejection reasons, and successful future matches. MVP shipped: contribution remains feature-flagged, contribution decisions now emit eligible/reason metrics, and community matches continue through barcode lookup telemetry as `community_barcode` hits.
- [x] **Label scan correction flow**: after a barcode miss or low-trust result, let users scan a nutrition label, review fields, and save the corrected barcode. MVP shipped: barcode-miss manual creation now shows an explicit correction card, tracks label-scan start/result, saves a private My Foods barcode correction after logging, and evaluates eligible corrections for the community pool.
- [x] **Trust telemetry**: measure suspicious food rate, correction rate, cross-verified rate, raw barcode miss rate, and saved-correction reuse. MVP shipped: Trust Hub snapshots log review/cross-verified/suspicious counts, food-detail trust cards log score/source/review state, and existing barcode/correction events cover misses and correction reuse.

Success signal: users can see why an entry is trusted or not, and the app improves after every correction.

### Sprint 3 — Maia as Action Cards, Not Chat
Goal: make Maia feel like a coach that does work, not a general chatbot.

- [x] **Card-based Maia responses**: meal suggestions, recovery prompts, macro fill-ins, and training adjustments should render as auditable cards with "why this," confidence/estimate labels, edit, and log actions. MVP shipped: the Maia tab now opens with action cards for Fill macros, recovery/protein, trust/today read, and hydration; Fill macros uses the existing meal suggestion service and logs AI-estimated meals from the detail sheet, while the other cards route into structured Maia prompts or direct actions with telemetry.
- [x] **Pantry + remaining macro meal builder**: turn the current suggestion sheet into structured ingredients, substitutions, macro fit, and one-tap logging. MVP shipped: Fill macros now opens a structured review sheet with remaining calorie/macro fit, pantry match vs. optional ingredients, substitution guidance, instructions, and one-tap estimate logging from Home or Maia.
- [x] **Weekly adaptive goal proposal**: build deterministic rules that compare weight trend, logged intake, adherence, and training load, then propose calorie/macro changes for user approval. MVP shipped: adaptive check-ins now build a deterministic `WeeklyGoalProposal` from 21-day intake, smoothed weight trend, usable log adherence, and workout count; the check-in screen shows hold/raise/lower recommendation, proposed calories, macro impact, reasons, and accept/keep-current telemetry.
- [x] **Maia memory boundaries**: clearly separate local daily context, imported history, HealthKit signals, and AI-generated estimates. Do not send more data than needed for the task. MVP shipped: Maia now uses a shared `MaiaContextContract` per action type, filters prompt sections to the allowed scopes, includes the context boundary in the system prompt, and logs privacy-safe scope telemetry for action cards and chat requests.
- [x] **Failure states**: no silent `try?` decode paths; every AI card has a graceful retry or manual fallback. MVP shipped: malformed Maia action-card JSON and decoded-but-incomplete action payloads now remove broken JSON from the visible answer, preserve Maia's readable text, show an "Action needs retry" fallback card, and emit `maia_action_payload_failed`.

Success signal: Maia produces loggable, editable actions that save time weekly and are safer than free-form chat.

### Sprint 4 — Training-to-Nutrition Loop
Goal: own the daily loop for lifters and runners: train, recover, eat, repeat.

- [x] **Today fuel plan**: Home shows one training-aware nutrition target for the next meaningful event: run recovery, lift recovery, protein catch-up, dinner planning, or a neutral over-target review. MVP shipped: `TodayFuelPlanRules` chooses one priority, clamps recovery macro targets inside remaining calories, routes actions to recovery search / Fill macros / Trust Hub review, and replaces the old standalone run-recovery banner.
- [ ] **Training fuel guardrails**: help users budget carbs/protein before heavy leg days, long runs, or hard sessions while preserving the chosen calorie target. If a user goes over, respond with a neutral review and next-step plan; do not reframe the overage as a win. Started: Today fuel plan and workout-completion handoff now prioritize neutral review when calories are already over target, and recovery targets are bounded by remaining calories.
- [x] **Workout completion meal handoff**: after a completed lift/run, present a Maia recovery card with carb/protein targets and a search/quick-log path. MVP shipped: today's workout summary shows a budget-aware recovery handoff with protein/carb targets, "Find food" search, Fill macros meal generation, and over-target Review today fallback.
- [x] **Lifting workout quality foundation**: bring the workout player closer to Strong/Hevy parity with warmup/drop/failure set types, RPE/RIR effort capture, warmups excluded from volume/1RM analytics, adjacent supersets, and an autoregulated progression coach based on the previous top working set.
- [x] **Running effort detail**: Run Detail shows average-HR zone plus a real time-in-zone card computed from the HealthKit heart-rate series for the run window. The card only appears when HR data exists and skips long sample gaps instead of fabricating effort.
- [x] **Indoor / treadmill support**: Apple Health indoor runs already import; MyFitPlate now also has a manual treadmill log path from Start Run that writes an indoor HealthKit run with distance, duration, estimated calories, generated splits, and no route.
- [ ] **Structured interval workouts**: add a workout-step model, saved interval templates, recorder step state, and live pace/distance/time guidance for workouts like warmup -> 5x400m -> cooldown. Started: built Core step/plan/tracker rules, built-in templates, saved custom repeat templates, a Start Run picker, live recorder step guidance with progress, haptics, audio step cues, effort/pace-target capable steps, Live Activity step/target text, persisted plan-vs-actual step reviews on run summary/detail, manual pace-range targets for custom repeat workouts, and a saved step-by-step editor for arbitrary run workouts. Still open: device validation on real GPS guided runs.
- [ ] **Running recovery polish**: make shoe mileage, route PRs, recovery fuel, weekly mileage, HR zones, and time-in-zone form one clear story in Reports.
- [ ] **Strength progression nutrition**: surface protein consistency, calories around hard training days, and PR weeks in Weekly Recap.

Success signal: MyFitPlate feels more useful after a workout than a generic calorie counter.

### Sprint 5 — Platform Polish and Daily Retention
Goal: make the Apple ecosystem experience feel first-class and repeatable.

- [ ] **Apple Watch standalone quick logging**: wrist-first water, weight, recent foods, workout start/finish, and recovery prompt review.
- [ ] **Widget and Live Activity refinement**: widgets should answer "what should I do next?" rather than only display totals.
- [ ] **Notifications that earn trust**: smart nudges must be sparse, contextual, and measurable; include opt-out and notification type controls.
- [ ] **Reports and export polish**: finish PDF/CSV export for coaching/medical review, with clean date ranges and privacy-safe sharing.
- [ ] **Accessibility/device pass**: Dynamic Type, VoiceOver labels, dark mode, low-connectivity behavior, and full device checklist.

Success signal: users can interact with the app without opening the phone every time, and weekly retention has a clear habit loop.

### Sprint 6 — Differentiated Growth Bets
Goal: add memorable features only after the core competitive loop is strong.

### Gamified Dining & Nutrition
- [ ] **Restaurant Value Radar**: AI menu scanner that analyzes restaurant menus or photos and ranks dishes by Protein-to-Dollar and Protein-to-Calorie ratios with a live "Value Score".
- [ ] **Training fuel planner**: pre-plan carbs/protein for heavy leg days or endurance runs inside the user's target, with clear labels for planned fuel vs. accidental overage.
- [ ] **Beat the buffet 2.0**: manual off-catalog entries, scanned item review, better city pricing confidence, and a clear "estimate" trust label on every price.

### Platform Expansion & Community
- [ ] **Social AYCE & Step Challenges**: Friend scoreboards, shared buffet challenges, and weekly running/step competitions.
- [ ] **Small-group accountability**: private groups for friends/coaches with opt-in weekly recap sharing.
- [ ] **Creator/coaching export pack**: weekly nutrition/training summary designed for a coach, dietitian, or accountability partner.

Success signal: users can name a MyFitPlate feature they cannot get from MyFitnessPal, Cronometer, MacroFactor, Lose It, or Noom.

---

## 🛠️ Always-On — Ops, Quality & Health
- [x] Wire release-health instrumentation and Crashlytics/Analytics dashboards.
- [ ] Monitor LLM / AI call frequencies against cost estimates.
- [ ] Keep package test coverage at 80%+ with behavior tests on every core engine and data calculation path.
- [ ] Keep `AGENT_HANDOFF.local.md` updated after meaningful roadmap, architecture, or code changes so future agents know the intent, verification, and risks.
- [ ] Every sprint must include user-facing copy review, privacy review for new data flows, and a rollback/feature-flag plan for risky launches.

---
_Living document — Single Point of Truth. Last updated: 2026-07-07._
