# MyFitPlate Roadmap — Single Point of Truth (SPOT)

A living, definitive roadmap and product vision for MyFitPlate.

Competitive thesis: MyFitPlate should not try to out-database MyFitnessPal, out-micronutrient Cronometer, or out-algorithm MacroFactor head-on. The wedge is **high-trust nutrition logging for people who train**, with Maia turning food, recovery, lifting, running, and real-world dining into one daily loop.

Current objective: move from "impressive broad feature set" to "obvious reason to switch and stay." Every sprint below should reduce daily logging friction, make trust visible, or connect nutrition to training outcomes.

---

## 🏁 Shipped Foundation (Versions 2.0 – 2.2)
- [x] **AYCE Challenge & Scoreboard**: 6-cuisine buffet tracker, sushi roll library (48 items), live value vs. price game, haptic kitchen wins, and persistent lifetime scoreboard ("kitchens defeated").
- [x] **Apple Health & Running Engine**: Bidirectional workout sync, GPS route mapping, false-start filtering (<100m/<2min), and parallel-watch calorie double-count protection.
- [x] **High-Trust Nutrition Logging**: GS1 barcode fallback, multi-database cross-verification (USDA, FatSecret, OpenFoodFacts), and 0–99 Trust Cards.
- [x] **Trust Score model v2 hardening**: independently validated source evidence, checksum-valid GTIN matching, exact USDA barcode identity, honest reviewed-estimate states, finite-value and nutrition-plausibility guards, model-versioned analytics, and a documented scoring contract in `docs/trust-score-model.md`.
- [x] **Maia Adaptive Coaching**: Daily strategy cards linking sleep, recovery, training, and nutrition adjustments.
- [x] **HealthKit Test Seams**: Protocol-abstracted seam (`HealthStoreScheduling`) with deep unit coverage across health and running services (package line coverage 84%).
- [x] **2.2 trust and privacy hardening**: explicit per-account AI data consent with optional Apple Health context, server-owned account deletion, privacy-safe analytics, App Check client support, serialized daily-log writes, and corrected USDA/Open Food Facts routing and serving math.
- [x] **2.2 activation and organic growth foundation**: elapsed onboarding-to-first-food/workout telemetry, a nutrition-plus-training loop milestone, a conservative StoreKit review request after sustained use, App Store-linked result sharing, and a structured feedback path in Settings.

---

## ✅ Shipped in Version 2.2 — Running Superpowers & Friction Killers
These items originally carried a 2.3 label while they were being built, but all shipped
inside the much larger 2.2 release. They remain here as release history, not future scope.

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

## 🎯 Version 2.3 — The Daily Training Loop (In Progress)

**Release thesis:** 2.2 established the moat: food data that shows its work, connected to
real training. Version 2.3 should turn that advantage into a repeatable habit by helping a
user decide what to eat before training, what to do after it, and whether the plan is
working. This is a retention release, not another inventory of unrelated features.

**Public promise:** "Know what to eat before and after training without losing sight of
your daily targets."

**Scope rule:** reserve roughly 25% of the release for 2.2 launch feedback, defects, and
accessibility/device findings. New work must improve the food -> train -> recover -> review
loop, remove logging friction, or make the Trust advantage easier to discover.

### Must Ship — 2.2 Signal and Release Health

- [x] **KPI contract and instrumentation foundation**: audited activation, Trust, logging,
  import, training, acquisition, reliability, and AI-cost signals; added schema-versioned
  analytics, one daily active-logger event, running-aware activation, exact deep-link
  destinations, barcode outcome latency, private server token totals, and the canonical
  metric definitions in `docs/analytics-dashboard-2.3.md`.
- [ ] **Competitive KPI dashboard rollout**: configure the Firebase/App Store operating view
  from the tracked contract, then join acquisition with first-food completion, time to first
  log, barcode recovery, import completion, Trust review/correction, first training,
  nutrition-plus-training loop completion, D1/D7 return, weekly active loggers, and aggregate
  AI cost per active user. Peter owns console access; final thresholds wait for clean traffic.
- [x] **Launch-health instrumentation foundation**: operation-tagged serialized diary failures,
  AI decode failures, account-deletion outcomes, end-to-end barcode latency/misses, build and
  startup context, and private AI request outcome/token/latency counters are implemented with
  privacy regression coverage.
- [ ] **Launch-health operating view rollout**: configure crash-free comparisons, non-fatal
  operation alerts, callable/provider trends, AI cost, and App Check validity by production
  build. Every red metric needs an owner and rollback path; enforcement waits for clean data.
- [x] **Quick Log first-interaction hardening**: opening is idempotent, the dismissal backdrop
  cannot consume the opening touch, idle notification UI is not mounted over Home, direct
  Simulator clicks open on the first attempt, and the complete UI suite is green.
- [x] **Structured feedback triage**: `docs/feedback-triage-2.3.md` is the single
  severity-ranked ledger for review feedback, support messages, device-only defects, and
  repeated friction. It separates code complete from device validated, names closure evidence,
  and keeps one preference from becoming a redesign unless it exposes a correctness,
  accessibility, or workflow fault.
- [x] **Trust correction-loop feedback closure**: label-photo replacement no longer carries
  stale saturated fat, optional nutrients, or serving weight from an older combined/barcode
  item. Label parsing now captures the printed serving description and gram weight. Both food
  editors expose clearly labeled Total fat and Saturated fat fields, block contradictory saves,
  and overwrite an existing My Foods barcode correction instead of creating a duplicate.
- [x] **Watch companion delivery and sync recovery**: the Watch product is now embedded in the
  iPhone bundle instead of merely building beside it. The phone retains the latest account-scoped
  context until WatchConnectivity is activated, paired, and installed; activation, reachability,
  Watch-state changes, and an explicit Watch sync request all replay it. The embedded generic-iOS
  product and companion identifiers are verified. Peter also physically validated companion
  installation, initial/current context, account clearing, and offline exactly-once water/meal
  replay on 2026-07-12.
- [x] **Micronutrient integrity and coverage closure**: USDA now uses Vitamin A RAE and converts
  copper to the app's established unit, FNDDS prepared foods join text search, Open Food Facts
  maps all 22 supported vitamins/minerals with correct per-serving conversions, and FatSecret no
  longer turns absent detail fields into zero. Agreeing exact-barcode records can fill only a
  primary record's missing nutrients, richer exact-name search records can replace sparse
  previews, and recipes retain/scale the full panel. Daily and historical reports distinguish
  unavailable data from reported zero and show their food/day coverage instead of false 0% intake.
  The durable provider/unit/presentation contract is `docs/micronutrient-data-2.3.md`.
- [ ] **Known device closures**: only three running paths remain: one guided interval on real
  GPS, one Watch-imported run with heart-rate series, and one phone-only run without HR. Watch
  sync/offline replay, workout supersets/rest, RPE/RIR/set types, widgets, notification routing,
  accessibility, appearance, and real connectivity recovery are physically closed. The concise
  remaining sequence and release-stop conditions are in `docs/device-test-2.3.md`.
- [ ] **Organic acquisition follow-through**: submit the 2.2 featuring nomination, publish
  Trust/Strength/Weight/Dining custom product pages after 2.2 approval, and add exact app
  routes plus deterministic screenshot fixtures for Food Search, Trust, Fast Food Builder,
  Runs, and Meal Plan. Started: 2.3 now queues exact routes through login/onboarding and has
  deterministic CPP aliases plus a HealthKit-free Running history fixture; publication and
  signed-in/signed-out device checks remain.

### Must Ship — Training Fuel Planner v1

- [x] **Deterministic allocation engine (Core)**: strength/run type, expected duration,
  intensity, lower/full-body demand, time until training, today's verified log, remaining
  calorie/macro targets, and pre/post preference now produce bounded allocations. The engine
  never raises the daily target, spends tomorrow's budget, or turns an overage into a refeed.
  Its transparent contract is `docs/training-fuel-planner-2.3.md`.
- [x] **Planned-session adapter**: the Home planner derives the current routine, schedule,
  estimated duration, effort, and strength focus from the active program; built-in/custom run
  plans can also be selected. Distance-only run plans and manual sessions require review
  instead of receiving invented timing.
- [x] **User control and honest uncertainty**: the review sheet exposes session type, source,
  start time, duration, effort, strength focus, and independent before/after choices. Estimated
  inputs are labeled, and optional Maia food ideas remain separate from the deterministic
  calorie/protein/carb budget.
- [x] **Actionable handoff**: each phase carries its exact live target into Search and Recent
  Foods, Fast Food Builder, Meal Plan, or a target-specific Maia idea. The generic whole-day
  Fill My Macros prompt is suppressed while a confirmed plan exists so the two budgets cannot
  compete.
- [x] **Post-session reconciliation**: confirmed plans are account scoped, subtract food logged
  after confirmation, separate before/after by timestamp, cap every next action to the live
  daily goals and diary, and become neutral for over-target or invalid data. Recovery now opens
  only after an explicit completion from the strength player, exact selected run, treadmill run,
  or manual confirmation; program/manual skips close every target. Unconfirmed elapsed sessions
  wait for an outcome instead of inferring recovery. Food logged during training consumes the
  budget without being mislabeled, and sessions that legitimately finish after midnight create
  a fresh recovery allocation from the next day's real diary and goals before any target appears.
- [x] **Rules and safety coverage (Core)**: 23 adversarial tests cover hard leg days, easy
  sessions, long/short runs, late-night training, fasting, missing/defaulted inputs, historical
  diary state, tiny or exhausted budgets, over-target days, stale/tomorrow workouts, invalid
  values, extreme finite corruption, and explicit pre/post choices. A 1,344-combination grid
  also enforces the calorie, macro, phase, and minimum-action invariants. Language remains
  general fitness coaching. Twenty-nine integration tests now cover active-program/run adapters,
  exact routine and run-plan identity, explicit completion/skipping, actual finish time,
  account isolation, diary attribution, live-budget recapping, stale storage, phase timing,
  overnight recovery, same-plan edits, and fail-closed reconciliation. AI meal ideas also pass
  a local finite-value, nutrition-consistency, and live-budget gate before they can be shown.

### Must Ship — Training and Fuel Report

- [x] **One weekly story**: Home and Reports now open one deterministic seven-day report answering
  what the user trained, how consistently it was fueled, and what changed. Sparse data stays
  explicit, source read failures do not masquerade as an empty week, and every rate shows its
  eligible denominator.
- [x] **Running summary**: weekly/prior mileage, distance-weighted pace, running and comparable-
  distance records, confirmed outdoor routes, real HR-series time in zone, guided step results,
  shoe wear, and timestamped recovery follow-through now share one surface. An open recovery
  window remains pending instead of being scored as a miss.
- [x] **Strength summary**: session frequency, working-set count/volume, prior-history PRs,
  working-set RPE trend, demanding days, and demanding-day calorie/protein consistency are
  reported with warmups excluded.
- [x] **Outcome context**: EMA-smoothed weight trend, nutrition adherence, training-day diary
  coverage, and Trust review rate sit beside training without an invented composite score.
  Invalid nutrition or HR values fail closed as unavailable instead of becoming false zeros.
- [x] **Share/export foundation**: one share menu produces a rendered summary image and a clean,
  aggregate CSV that excludes account IDs, food/routine names, routes/coordinates, and raw HR
  samples. Polished PDF export remains a stretch goal rather than a 2.3 requirement.

### Should Ship — Next Action Beyond the Phone App

- [x] **Widget: next move**: shared widget data now carries one deterministic action: pre-workout
  fuel, recovery meal, protein catch-up, Trust review, or steady day. Small/medium/large and
  accessory layouts expose it, interactive water remains, and the widget routes directly to
  Food Search, Trust, Home, or the exact Training Fuel Planner. Historical diary browsing can
  no longer overwrite today's widget state.
- [x] **Watch quick actions**: the existing daily glance, water, and weight tools remain. Watch
  now shows the same next action, a compact training/recovery target review, and a two-step
  recent-meal repeat. Requests use a durable deduplicated inbox, fresh food identities, random
  per-account scopes instead of user IDs, success-only acknowledgement, and offline-safe
  `transferUserInfo`; oversized or invalid meals fail closed. Full Watch food search remains out.
- [x] **Notifications that earn permission**: Settings has independent opt-in controls for
  pre-session fuel, explicit-completion recovery, and one meaningful evening protein catch-up,
  plus quiet hours and the evening time. Deterministic rules cap the day at two, stable IDs and a
  local ledger prevent stacking/replay, taps open the exact route, and scheduled/opened telemetry
  carries only reminder type. The old background AI engagement nudge is removed and canceled.
- [x] **Exact deep links**: `food-search`, `trust`, `builder`, `runs`, `meal-plan`, and
  `training-fuel` parse,
  queue through signed-out/onboarding blockers, and present their exact destinations from the
  stable app shell. Core and cold-launch UI regression tests are green. Keep the 2.2 custom
  pages link-free until this 2.3 binary is approved.

### Internal 2.3 Work — Trust Calibration and Community Safety

- [ ] **Trust calibration report**: compare score band/provider/evidence with later edits,
  correction findings, saved-correction reuse, and abandonment. Reweight only after real
  outcomes show a consistent error, never to make scores look higher. Instrumentation and the
  reproducible report contract are ready in analytics schema 2.3.2: correction opens,
  abandonment, submission, persistence success/failure, coarse changed fields, resulting sanity,
  and cohort-level saved-barcode reuse are measurable without food/account identifiers. The item
  stays open until at least 14 days of adequately sized production cohorts exist.
- [x] **Private contribution model**: submissions now use an authenticated App Check callable,
  live under private per-user ownership, expose no contributor IDs in published data, and have a
  backup-first migration from the denied legacy pool.
- [x] **Server-owned aggregate**: Functions now require 3+ distinct contributors and at least
  two-thirds agreement, resolve conflicts deterministically, recheck the median output, retain
  private provenance snapshots, and publish aggregate-only records.
- [x] **Moderation and rollback**: per-user and per-barcode work limits, private aggregate health
  counters, quarantine/release, strict Rules, and a global kill switch now fail closed. Killing or
  disabling aggregation also deletes materialized results so stale consensus cannot reappear.
- [ ] **Internal soak only**: `feature_communityBarcodeCorrections` remains `false` publicly.
  Public community corrections are explicitly not a 2.3 release requirement.

### Explicit Non-Goals for 2.3

- Public community barcode data before the server aggregate and moderation gates pass.
- Social feeds, public challenges, or friend graphs.
- A broad Maia/chat rewrite, new AI surfaces without a structured user action, or autonomous
  changes to calories/macros.
- iPad redesign, Android expansion, a new food provider, or a new subscription system.
- More running workout types before real-device interval behavior is validated.

### Provisional Success Measures

Set final targets after 7–14 days of clean 2.2 data; compare against MyFitPlate's baseline,
not an invented industry benchmark.

- Median first food log remains under 60 seconds and completion improves from the 2.2 cohort.
- Weekly `nutrition_training_loop_completed` rate improves by at least 20% relative.
- D7 retention improves by at least 15% relative without higher notification opt-out.
- Training-active users repeatedly act on the fuel plan; views without action are treated as
  a product failure signal, not engagement.
- Lower Trust bands predict more later corrections than higher bands; if they do not, the
  scoring model needs calibration before broader claims.
- Crash-free use, AI cost per active user, and provider recovery remain within agreed launch
  guardrails.

### Immediate Build Queue

1. [x] Add exact deep-link routes and custom-product-page screenshot fixtures.
2. [x] Audit activation/Trust/training events, close the release-health gaps, and define the
   external KPI dashboard contract.
3. [x] Build the deterministic fuel-plan model and adversarial Core test matrix.
4. [x] Add the Home planner/review flow and connect it to existing logging destinations.
5. [x] Build the unified Training and Fuel report from existing running, lifting, and nutrition
   engines before adding new data collection.
6. [x] Extend widget shared data, then deliver the narrow Watch and notification slices.
7. [x] Develop the community aggregate behind a server-only flag; do not couple it to 2.3 launch.
8. [x] Close the Watch companion packaging/sync defect surfaced by physical-device testing.
9. [x] Make micronutrient ingestion, recipe retention, and report coverage honest end to end.
10. [x] Close local release-readiness gaps: resilient food-search recovery, accessibility-size
    Home copy, Node 22 Functions CI, an enforced 80% Core coverage floor, current branch checks,
    and one feedback/device closure ledger.

### Ownership and Dependencies

**Codex can execute independently:** architecture, deterministic engines, tests, app UI,
widgets, Watch code, deep links, screenshot fixtures, analytics contracts, Functions/rules
implementation, accessibility sweeps, docs, and CI verification.

**Peter is required for:** real-user feedback and priority calls, physical iPhone/Watch/GPS
validation, App Store Connect publishing, production dashboard/console access where login is
required, notification-policy approval, and any decision to expose community-contributed data.

---

## 🧭 Long-Term Competitive Backlog
The next several sprints are ordered to make the product competitive before expanding the surface area further. The first three sprints are conversion and retention work; the later sprints deepen the moat.

### Sprint 0 — Baseline, Positioning, and Release Readiness
Goal: establish the competitive scoreboard and make the product story sharper before building more.

- [x] **Define the public promise**: "The food log you can trust, built for people who train." The onboarding, Maia entry state, and final App Store gallery now consistently lead with trusted nutrition built for training.
- [ ] **Create a competitive KPI dashboard**: track first-food-log completion, time to first log, barcode hit/miss/recovery, AI estimate review/correction, MFP import starts/completions, D1/D7 return, weekly active loggers, and LLM cost per active user. The app now emits elapsed onboarding-to-first-food/workout and nutrition-plus-training loop events; the external dashboard, retention cohorts, and cost joins remain open.
- [x] **Refresh App Store story**: created an eight-shot deterministic gallery covering Home, Trust, fast repeat/search, the 25-chain meal builder, Train, Maia action coaching, Meal Plan, and Reports. The first three images carry the positioning and conversion story.
- [x] **Fix screenshot-visible polish**: corrected clipped Train targets and Reports chart labels, rebuilt the builder's bottom tray, centered a compact outlined Quick Log action above five equal-width destinations, made the expanded action list reachable on compact phones, and visually checked both required phone-size galleries. A final accessibility-size sweep also corrected clipping in Trust details, Food Search, Fast Food Builder, Train, Maia, Meal Plan, and Quick Log, and hardened Trust Hub presentation against asynchronous Home refreshes.
- [x] **Add a release feedback and referral loop**: Settings now provides a prefilled privacy-safe feedback email and direct App Store sharing; recap, achievement, run-story, and workout-summary shares point back to the live listing; review requests are limited to fresh workout completions after three distinct sessions across at least three days, once per version with a 120-day cooldown.
- [ ] **Release gate**: Core 1,016/1,016 with 85.24% coverage, app 83/83, UI 14/14,
  Functions 11/11 with zero production dependency vulnerabilities, strict lint/catalog/diff
  checks, and the unsigned physical-iOS Release build are green locally. CI now matches the
  Functions Node 22 runtime and requires the 80% Core floor; the checked branch ruleset includes
  app UI and Functions checks. Peter deployed the then-current production Functions on
  2026-07-11. Remaining owner gates are the physical checklist, production/branch-console
  reconciliation, App Check, public legal links, privacy labels, version/build increment, and a
  signed archive validation/upload in `docs/device-test-2.3.md`.

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

- [x] **Trust Card redesign**: show source, confidence, cross-verification, sanity checks, and what the user can do next in one compact card. Shipped: the card separates Source, Verification, Your Review, and Nutrition Check; uncertainty is orange, actual correction states are red, resolved reviews do not loop, and VoiceOver retains the action as a separate control.
- [x] **Trust Hub / audit screen**: give users a daily list of entries that need review, entries that are cross-verified, and entries fixed by them. MVP shipped: the nutrition audit sheet is now a Trust Hub with review, cross-verified, and reviewed-by-you sections, reachable from the nutrition card whenever foods are logged.
- [ ] **Community barcode public rollout**: the flag, contribution metrics, GTIN/data gates, Firestore validation, conservative Review cap, and final-fallback lookup are implemented. Keep `feature_communityBarcodeCorrections` off until contributions are private, a server-owned aggregate provides consensus/conflict handling, published documents omit contributor IDs, and moderation/abuse rollback has soaked internally.
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
- [x] **Training fuel guardrails**: the confirmed Training Fuel Planner budgets carbs/protein
  before and after demanding strength or running sessions without raising the chosen calorie
  target. Live diary reconciliation, explicit completion/skipping, overnight recovery, and
  neutral over-target states prevent planned fuel from disguising an overage.
- [x] **Workout completion meal handoff**: after a completed lift/run, present a Maia recovery card with carb/protein targets and a search/quick-log path. MVP shipped: today's workout summary shows a budget-aware recovery handoff with protein/carb targets, "Find food" search, Fill macros meal generation, and over-target Review today fallback.
- [x] **Lifting workout quality foundation**: bring the workout player closer to Strong/Hevy parity with warmup/drop/failure set types, RPE/RIR effort capture, warmups excluded from volume/1RM analytics, adjacent supersets, and an autoregulated progression coach based on the previous top working set.
- [x] **Running effort detail**: Run Detail shows average-HR zone plus a real time-in-zone card computed from the HealthKit heart-rate series for the run window. The card only appears when HR data exists and skips long sample gaps instead of fabricating effort.
- [x] **Indoor / treadmill support**: Apple Health indoor runs already import; MyFitPlate now also has a manual treadmill log path from Start Run that writes an indoor HealthKit run with distance, duration, estimated calories, generated splits, and no route.
- [x] **Structured interval workouts**: the workout-step model, built-in and saved custom
  templates, arbitrary step editor, recorder state, live pace/distance/time guidance, haptics,
  spoken cues, Live Activity state, and persisted plan-vs-actual review are implemented with
  Core coverage. Real-GPS validation remains explicitly open under Known device closures.
- [x] **Running recovery polish**: the unified Training & Fuel report now combines weekly mileage,
  weighted pace, route/distance PRs, shoe wear, real HR time in zone, guided-step results, and
  timestamped recovery follow-through in one seven-day story.
- [x] **Strength progression nutrition**: the unified report now shows working sets/volume,
  prior-history PRs, working-set RPE trend, demanding days, and calorie/protein consistency on
  those demanding days.

Success signal: MyFitPlate feels more useful after a workout than a generic calorie counter.

### Sprint 5 — Platform Polish and Daily Retention
Goal: make the Apple ecosystem experience feel first-class and repeatable.

- [x] **Apple Watch standalone quick logging**: water, weight, a two-step recent-meal repeat,
  and compact training/recovery review are complete with offline-safe delivery. Workout
  start/finish remains a later Watch expansion and is not required for 2.3. Installation,
  paired-device context, account clearing, and offline exactly-once replay are physically
  validated.
- [x] **Widget and Live Activity refinement**: every widget family now answers "what should I do
  next?" with the deterministic Training Fuel, Trust, protein, or steady-day action while
  retaining the calorie glance and interactive water action. Live Activity already carries
  structured guided-run step/target state.
- [x] **Notifications that earn trust**: three independently opt-in, deterministic reminder
  types use quiet hours, a two-per-day cap, stable IDs, exact routes, and privacy-safe outcome
  telemetry. The generic AI engagement nudge is retired.
- [x] **Reports and export polish**: the unified report exports a privacy-safe rendered image
  and aggregate CSV for a selected seven-day period. Polished PDF output and arbitrary date
  ranges remain later work rather than 2.3 requirements.
- [x] **Accessibility/device pass**: the complete deterministic UI suite and a light/dark
  accessibility-XXXL matrix are green; Home support copy grows rather than truncates and Food
  Search has visible retry/manual recovery during provider outages. Peter physically validated
  VoiceOver, largest text, dark mode, Increase Contrast, widgets, notification routing, Watch,
  and offline/online recovery. Running sensor validation remains a separate Known device closure.

Success signal: users can interact with the app without opening the phone every time, and weekly retention has a clear habit loop.

### Sprint 6 — Differentiated Growth Bets
Goal: add memorable features only after the core competitive loop is strong.

### Gamified Dining & Nutrition
- [x] **Restaurant Value Radar MVP**: AI menu scanner ranks dishes by Protein-to-Dollar and Protein-to-Calorie using only prices visibly printed on the menu; nutrition remains reviewable AI estimate data, fictional demo data is labeled, and demo logging is disabled. Future work: OCR confidence, multi-page menus, and verified restaurant nutrition sources.
- [x] **Training fuel planner**: confirmed pre/post carb and protein allocations now stay inside
  the user's live target, distinguish planned timing from diary intake, reconcile explicit
  workout outcomes, and become neutral when the budget is exhausted or over target.
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
- [ ] Keep package test coverage at 80%+ with behavior tests on every core engine and data
  calculation path. The enforced floor is now 80%; the 2026-07-12 measured baseline is 85.24%.
- [ ] Keep `AGENT_HANDOFF.local.md` updated after meaningful roadmap, architecture, or code changes so future agents know the intent, verification, and risks.
- [ ] Every sprint must include user-facing copy review, privacy review for new data flows, and a rollback/feature-flag plan for risky launches.

---
_Living document — Single Point of Truth. Last updated: 2026-07-12._
