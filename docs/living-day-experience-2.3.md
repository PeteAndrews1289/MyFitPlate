# Version 2.3 Experience Roadmap: The Living Day

Status: active implementation on `codex/2.3-living-day`

Working release name: **The Living Day**

Flagship interaction: **Fuel Path**

## Release thesis

Version 2.2 made MyFitPlate functionally credible across trusted food logging, strength,
running, recovery, meal planning, reporting, Maia, Watch, widgets, and real-world dining.
Version 2.3 should make that breadth feel like one product rather than several capable tools.

The release should not win by adding the longest feature list. It should give MyFitPlate one
recognizable interaction that competitors cannot reproduce without also owning food provenance,
training execution, recovery timing, and a live nutrition diary.

**Public promise:**

> See how food and training fit together, then act on what matters next.

**Product outcome:** a user should be able to open Home, understand the shape of today in five
seconds, and take the next useful action without translating several cards, rings, or scores.

## Why this is the opportunity

The 2.2 gallery is polished and consistent, but most primary screens use the same visual recipe:
white canvas, pale mint rounded cards, large rounded headings, and stacked summaries. The app is
friendly, yet its most differentiated ideas are still presented using category-default dashboard
patterns.

Current category leaders tend to own one central visual or mental model:

| Product | Visual or product territory it owns | MyFitPlate opportunity |
| --- | --- | --- |
| [MyFitnessPal Today](https://support.myfitnesspal.com/hc/en-us/articles/39985611667341-Introducing-the-brand-new-Today-tab) | Diary-first calories, macros, meals, habits, and logging shortcuts | Do not build another card-based Today dashboard |
| [Cronometer](https://cronometer.com/features/) | Detailed nutrient coverage and accuracy reporting | Make evidence legible without becoming a dense nutrient spreadsheet |
| [MacroFactor](https://macrofactor.com/dashboard-revamp/) | Energy balance, expenditure, weight trend, and coached adjustments | Connect nutrition to actual training timing rather than competing on expenditure modeling |
| [Gentler Streak](https://docs.gentler.app/understanding-your-activity-path/interpret-the-activity-path) | One memorable Activity Path for training balance | Own a food-and-training path grounded in logged events, not a readiness score |
| [Hevy](https://www.hevyapp.com/features/) | Fast lifting workflow, muscle maps, progress, and social proof | Keep workout operations quiet while making the cross-domain story distinctive |

The whitespace is not another recovery ring. It is a day-level view where every meal can carry
evidence, every workout changes the timing context, and every recommendation remains bounded by
the user's real targets.

## North-star experience: Fuel Path

Fuel Path is an unframed, interactive day surface on Home. It combines actual meals, planned
meals, training, recovery windows, remaining targets, Trust state, and the current next action
on one time-based path.

It is a visual index into existing functionality, not a new scoring algorithm and not another
data store.

### First-viewport anatomy

1. **Compact day header**
   - Date, logging streak, and one privacy-safe sync state.
   - Previous/next-day navigation stays available but visually secondary.

2. **Daily budget ribbon**
   - Calories plus protein, carbs, and fat use separate stable colors.
   - The ribbon shows consumed, planned, and remaining without implying that exercise erases food.
   - Invalid or incomplete data becomes unavailable, never a false zero.

3. **The path**
   - A time rail spans the meaningful portion of the day rather than showing all 24 hours equally.
   - Logged meals are filled nodes; planned meals are outlined nodes.
   - Strength, outdoor run, treadmill, and imported training events use distinct familiar icons.
   - The current time has a persistent marker and accessible text equivalent.
   - Future events may be shifted by the user only when the source is an editable plan.

4. **Training and recovery window**
   - A confirmed Training Fuel plan appears as a bounded before/after band around the exact session.
   - Completion, skipping, over-target, midnight, and unavailable-diary rules continue to come from
     the deterministic 2.2 engine.
   - The visual cannot invent fuel needs or increase a daily target.

5. **Current next action**
   - One action attaches to the current-time marker: log food, review Trust, fuel training,
     recover, catch up protein, or hold steady.
   - Tapping it routes to the exact existing destination.
   - Maia may add one short annotation, but the deterministic action remains primary.

### Trust on the path

Every logged meal node carries a small evidence treatment:

- solid ring plus check shape: independently supported and sane;
- segmented ring: one reliable source or partial evidence;
- amber notch plus review label: useful but worth reviewing;
- red break plus fix label: contradictory data that requires correction.

Color is never the only signal. VoiceOver receives the same source class, evidence state, and
required action in plain language. The ring represents the food data, not whether eating the meal
was good or bad.

### Interaction model

- **Tap a node:** open a compact event summary, then Food Detail, Meal Plan, workout, or run detail.
- **Tap empty time:** open Quick Log with that time and the likely meal preselected.
- **Tap the current marker:** perform the current next action.
- **Swipe the path:** move through earlier and later events without changing the selected day.
- **Long press a planned node:** reschedule or remove it when its source is editable.
- **Log successfully:** the Quick Log control resolves into the new path node with a short haptic.
- **Finish training:** the active band closes and the recovery target becomes the current action.
- **Correct a food:** the node's evidence treatment updates only after persistence succeeds.

No core workflow should require a gesture with no visible alternative.

### Sparse, exceptional, and honest states

- Empty day: show one open path with direct Search, Barcode, and Import actions.
- No training: the path remains useful as a meal and Trust timeline.
- No timestamps: place legacy entries in their meal period and label the timing as approximate.
- Over target: show a neutral review state; never display punishment, debt, or a negative path.
- Missing micronutrients: omit unsupported detail and link to coverage rather than showing zero.
- Provider outage: local meals remain on the path and remote logging exposes recovery actions.
- Stale sync: retain the last known state with an explicit timestamp and retry action.

## Supporting signature surfaces

### Trust Receipt

Food Detail should replace the large nested Trust card with a compact provenance receipt:

- identity and serving at the top;
- source sequence and cross-check relationship as a readable vertical trace;
- nutrition sanity findings beside the fields they affect;
- user review and saved-correction state as the final step;
- one primary correction action;
- advanced details disclosed on demand.

The existing Trust score remains available, but evidence should lead and the number should follow.
The receipt must remain export-safe and must never expose private contributor identity.

### My Foods Library

The personal food library closes the correction loop and gives the new visual system practical
depth:

- search and sort saved foods;
- filter barcode corrections, manual foods, recipes, recent foods, and items needing review;
- edit or delete an entry;
- merge true duplicates without silently combining different servings;
- inspect and remove a barcode association;
- show last used and coarse Trust state;
- confirm exactly what future scans will reuse.

Destructive operations require confirmation and must not alter already-logged historical entries.

### Week in Motion

The unified report should gain one editorial, shareable seven-day story:

1. training rhythm;
2. fuel timing and eligible recovery follow-through;
3. Trust and diary coverage;
4. weight/nutrition trend;
5. one evidence-based next-week observation.

This is a sequence of full-width bands, not a stack of miniature dashboard cards. Existing detailed
charts and CSV export remain available below it.

### Maia in context

Maia should feel woven into the day rather than duplicating the dashboard:

- one short annotation can attach to the current action;
- a generated food idea must retain its deterministic calorie/macro envelope;
- tapping the annotation opens the existing structured action or conversation;
- hidden JSON, raw Health values, prompts, and account content remain excluded from speech and
  analytics;
- the Maia tab remains the full conversation destination.

## Visual language for 2.3

### Keep

- rounded system typography;
- evergreen brand identity;
- macro colors already learned by users;
- familiar SF Symbols and existing haptic vocabulary;
- fast sheets for logging and operational tasks.

### Evolve

- use color for information, not as a pale tint behind every section;
- reduce large corner radii and material layers on primary screens;
- remove card-inside-card composition;
- let Home, Trust, and Reports use unframed full-width visual structures;
- use stronger black/white hierarchy with evergreen, blue, gold, purple, orange, and cyan signals;
- reserve capsules for status and segmented choices, not ordinary labels;
- standardize spacing, chart strokes, icon containers, selected states, and dividers.

### Motion

Motion should explain state changes:

- node insertion after a successful log;
- path progression at the current time;
- planned-to-completed transition;
- Trust evidence resolving after a saved correction;
- training-to-recovery handoff.

There are no ambient particles, decorative blobs, endless pulses, or celebration for eating less.
Reduce Motion replaces spatial transitions with opacity and content changes. Motion can never delay
logging, correction, workout completion, or navigation.

## Technical shape

### Deterministic presentation model

Create a Core `LivingDaySnapshot` assembled from existing inputs:

- selected-day diary and goals;
- Food Trust evaluations and coverage;
- active program and exact workout state;
- recorded/imported runs;
- confirmed Training Fuel plan and outcome;
- Meal Plan entries;
- current next action;
- sync freshness and source-read failures.

The snapshot should be immutable, finite-value checked, account scoped, and renderable with no
network access. It should expose explicit unavailable and approximate states.

### Rendering boundary

- SwiftUI renders the snapshot without fetching repositories from individual nodes.
- Deterministic screenshot fixtures cover empty, ordinary, training, recovery, over-target,
  low-Trust, offline, and accessibility layouts.
- The path has a semantic list representation used by VoiceOver and large accessibility sizes.
- iOS 17 remains supported; later APIs require graceful fallbacks.

### Rollout boundary

- Ship behind `feature_livingDayHome` until device validation is complete.
- Keep the 2.2 Home available as an immediate fallback for at least one release cycle.
- The first implementation is read-only navigation over existing data.
- Add rescheduling and inline actions only after read-only rendering is stable.
- No backend schema migration is required for Fuel Path v1.

## Scope

### Must ship

- [ ] Living Day visual tokens and reusable path primitives.
- [x] `LivingDaySnapshot` deterministic Core model and initial adversarial test matrix.
- [ ] Fuel Path read-only Home experience with exact navigation.
- [ ] Quick Log insertion and training-to-recovery transitions.
- [ ] Trust Receipt on Food Detail.
- [ ] My Foods Library with safe edit/delete/barcode management.
- [ ] Week in Motion opening report sequence.
- [ ] VoiceOver, Dynamic Type, Reduce Motion, contrast, dark mode, and compact-device closure.
- [ ] Feature flag, old-Home fallback, deterministic screenshots, analytics, and rollback runbook.
- [ ] Two reserved slots for the largest repeated 2.2 friction or correctness findings.

### Should ship

- [ ] Contextual Maia annotation on the current next action.
- [ ] Medium/large widget adaptation of the current Fuel Path segment.
- [ ] Shareable Living Day and Week in Motion images with no private raw data.
- [ ] User-selectable compact or detailed path density.
- [ ] CI upgrades away from official Actions that target deprecated Node 20.

### Conditional on evidence

- [ ] Trust model reweighting after the cohort minimums in `trust-calibration-2.3.md`.
- [ ] Limited community barcode rollout after private abuse, conflict, cost, and rollback soak.
- [ ] New Training Fuel actions only when 2.2 handoff telemetry identifies a repeated unmet need.
- [ ] Expanded Watch actions only when phone/Watch usage shows a clear repeated workflow.

## Explicit non-goals

- A decorative app-wide reskin with no workflow improvement.
- Another generic Home dashboard made from customizable cards.
- A readiness, wellness, or food-morality composite score.
- Replacing the fast Food Search, builder, workout player, or run recorder with editorial layouts.
- Public social feeds, public challenges, or friend graphs.
- A broad Maia rewrite or autonomous goal changes.
- New food providers, new running modes, iPad redesign, Android, or a new subscription system.
- 3D scenes, ornamental gradients, or motion that competes with repeated logging.

## Phased build plan

### Phase 0: 2.2 observation and visual prototype

- Record the submitted 2.2 baseline and collect launch feedback.
- Prototype three renderings from the same deterministic snapshot: compressed horizontal rail,
  vertical living timeline, and plate-clock overview.
- Default direction is the horizontal/vertical hybrid Fuel Path described above.
- Select the rendering by five-second comprehension, exact-action discoverability, compact-phone
  fit, and accessibility behavior, not visual novelty alone.

Exit gate: one direction is clearly understandable without explanatory copy and has a complete
semantic fallback.

Implementation checkpoint (2026-07-12): all three directions render from the same immutable
fixture in a Debug/screenshot-only gallery. Launch with `-ui-testing -screenshot-mode` and one of
`-screenshot-screen living-day-rail`, `living-day-timeline`, or `living-day-clock`. The vertical
timeline is the engineering recommendation because it keeps event order, exact/approximate timing,
Trust evidence, the current-time break, future training, and the current action visible together.
The clock is the strongest secondary summary; the rail is the densest but gives adjacent future
events the least room. Standard light, dark, and accessibility-extra-extra-extra-large Simulator
captures are clean. Peter still selects the production direction after hands-on review.

### Phase 1: experience system and snapshot

- Add spacing, shape, stroke, color, chart, and motion tokens.
- Build `LivingDaySnapshot`, fixtures, and Core tests.
- Render the path in a developer-only gallery with no navigation or writes.

Exit gate: all edge-state fixtures render without overlap in light/dark and standard/accessibility
sizes; snapshot invariants fail closed.

### Phase 2: read-only Home integration

- Add Fuel Path behind the feature flag.
- Connect nodes and current action to exact existing destinations.
- Preserve current Home as fallback.
- Add first-use orientation through progressive disclosure, not a feature-tour wall of text.

Exit gate: no regression in time to Quick Log, Home task completion, startup, or diary freshness.

### Phase 3: action transitions and Trust

- Integrate Quick Log insertion, planned/completed transitions, and recovery handoff.
- Ship Trust Receipt and evidence-state updates after successful correction persistence.
- Add privacy-safe analytics for path exposure, node action, current action, and fallback use.

Exit gate: actions remain exactly-once, account scoped, and consistent across midnight/offline
recovery; Trust never changes before persistence succeeds.

### Phase 4: personal library and weekly story

- Ship My Foods Library with safe management actions.
- Add Week in Motion above the detailed report.
- Add share renderers and selected widget adaptation.

Exit gate: duplicate management cannot mutate history; shares contain no names, account IDs,
routes, coordinates, or raw Health samples unless the user explicitly selected visible content.

### Phase 5: release closure

- Resolve the two reserved live-feedback slots.
- Run screenshot, UI, device, accessibility, privacy, and performance matrices.
- Compare the feature-flag cohort with the 2.2 Home baseline.
- Keep community publication and Trust reweighting out unless their independent evidence gates pass.

## Success measures

Final numeric targets should be set after clean 2.2 production data exists. The 2.3 comparison
must use MyFitPlate's own baseline.

Primary measures:

- more Home sessions produce one meaningful action;
- Training Fuel views more often reach a saved plan or exact handoff;
- time from app open to successful food write does not regress;
- Trust review opens more often reach a persisted resolution;
- corrected barcode foods are reused and manageable without duplicates;
- more weekly active loggers complete both nutrition and training in the same week;
- D1/D7 return improves without higher reminder opt-out or support friction.

Experience guardrails:

- five-second tests correctly identify what happened, what is planned, and what to do next;
- no primary task requires interpreting color alone;
- largest Dynamic Type and VoiceOver expose the complete path in a useful order;
- Reduce Motion is fully functional;
- startup, scrolling, and log insertion remain responsive on the smallest supported phone;
- crash-free use, diary integrity, AI cost, and App Check validity do not regress.

## Build queue

1. [x] Lock the Living Day information hierarchy with deterministic 2.2 fixtures.
2. [x] Build and compare the three Fuel Path prototypes; retain Peter's on-device selection as the
   final direction gate.
3. [ ] Add the 2.3 visual token layer without changing operational screens.
4. [x] Implement and test `LivingDaySnapshot`.
5. [ ] Ship read-only Fuel Path behind `feature_livingDayHome`.
6. [ ] Connect exact navigation and Quick Log insertion.
7. [ ] Build Trust Receipt.
8. [ ] Build My Foods Library.
9. [ ] Add Week in Motion, sharing, and the selected widget slice.
10. [ ] Fill the two evidence-reserved slots from 2.2 feedback.
11. [ ] Close accessibility, device, privacy, performance, and rollback gates.

## Ownership

**Codex:** prototypes, visual system, Core snapshot model, SwiftUI implementation, fixtures,
tests, accessibility, analytics contract, rollback path, and documentation.

**Peter:** visual-direction preference after hands-on prototypes, real-device comprehension and
motion feedback, production cohort review, user-feedback priority, App Store story, and any
decision to expose community-contributed data.
