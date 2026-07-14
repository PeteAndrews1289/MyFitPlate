# Whole-App Visual Unification

Status: active for version 2.3 on `codex/2.3-visual-unification`, based on the 2026-07-13
light/dark simulator audit. Version 2.2 remains pending in App Store review and is untouched by
this branch; `main` remains the source rollback boundary.

This program is version 2.3 and must not be folded into the pending 2.2 submission. It remains a
staged migration so each feature family can be reviewed, tested, and reverted independently.

## Implementation Progress

### Batch 1 - Foundation, Tab Bar, and Quick Log (complete)

- Added named typography, spacing, radius, motion, semantic palette, surface, action, icon-button,
  row, header, and sheet-scaffold primitives in `MyFitPlateCore`.
- Added a deterministic Debug component gallery so the system can be reviewed without depending
  on account data or network state.
- Rebuilt the five-destination tab bar with stable geometry, quieter transient chrome, a compact
  outlined Quick Log control, and a clear selected-state underline.
- Replaced the layered Quick Log overlay with a native, scrollable sheet. All existing food,
  barcode, description, camera, exercise, recipe, buffet, and running destinations remain
  available without extra workflow steps.
- Added deterministic UI coverage for the gallery and dark accessibility-size Quick Log, while
  retaining the existing food-search navigation check.
- Verified the batch in light and dark appearance, standard and accessibility Dynamic Type, and on
  both standard and compact phone sizes. Focused UI tests passed 3/3, design-system tests passed
  10/10, strict lint passed with zero violations, and Debug plus unsigned Release builds passed.

### Batch 2 - Train and Meal Plan (complete)

- Applied one shared primary-tab header and action grammar to Train and Meal Plan without changing
  their destinations, data stores, or logging/workout behavior.
- Rebuilt Train's first viewport around one emphasized next-step progression surface, a direct
  `Start` action, a quieter `Skip`, an unframed program-week rhythm, and flat readiness/action rows.
- Rebuilt Meal Plan around an unframed seven-day selector, one daily summary band, aligned metrics
  and progress, one day-level logging action, and quieter planned-meal rows.
- Added a reusable metric strip that changes from aligned columns to full-width rows at
  accessibility text sizes.
- Added dedicated large-text layouts: Train removes low-priority exercise previews so names and
  actions remain readable, while Meal Plan turns the compressed week into horizontally scrolling
  full-size day cards.
- Corrected compact-width exercise targets so values retain their natural width and names wrap,
  instead of targets collapsing into columns of individual letters.
- Added deterministic Train and Meal Plan hierarchy tests plus a combined dark, largest-Dynamic-
  Type clipping audit. Focused UI checks passed 3/3, design-system tests passed 10/10, strict lint
  passed with zero violations, the unsigned Release build passed, and standard/compact phone
  captures were reviewed.

### Batch 3 - Maia and Reports (complete)

- Gave both tabs the same stable, pinned primary-screen header so scrolling evidence no longer
  passes visibly behind the status bar.
- Rebuilt Maia around a concise `Today in context` summary and one deterministic `Best next step`.
  Trust mismatches, workout recovery, remaining macros, hydration, and the daily read now resolve
  to one recommendation with three quiet alternatives instead of competing dashboard cards.
- Added explicit evidence labels for Today, Goals, optional HealthKit and pantry context, and
  estimates. The untouched conversation no longer repeats the same macro numbers in an opening
  bubble, keeping the recommendation visible on compact phones.
- Kept Maia's conversation in one scrollable timeline with a pinned composer, while preserving
  existing prompts, meal generation, hydration, chat history, speech, consent, and logging paths.
- Preserved Week in Motion as Reports' opening story, then separated the trend window, weight
  evidence, at-a-glance summary, wellness, workout, metabolism, sleep, and health cards into quiet
  responsive surfaces without adding navigation steps.
- Corrected zero-of-N recovery language so a week with no completed recovery targets reads
  literally instead of saying both targets were met.
- Focused UI checks passed 3/3 on a standard phone, 2/2 on an iPhone SE, and the final compact Maia
  hierarchy check passed after removing the duplicate opening bubble. The standard run includes
  dark mode at accessibility XXXL and text-clipping audits. Design-system and Week in Motion tests
  passed 16/16, and strict lint passed with zero violations.

### Batch 4 - Home and Living Day shell (complete)

- Added the same stable, pinned primary-screen header used by the other four tabs, with direct
  profile and settings actions that remain reachable without scrolling.
- Replaced the material date capsule with quiet, unframed date navigation. The layout remains
  centered on standard phones and stacks its date and controls at accessibility text sizes.
- Kept Living Day's evidence-led timeline, budget, recommendation, Maia annotation, action routes,
  share selection, density controls, selected-date behavior, feature decision, and legacy Home
  rollback path unchanged.
- Aligned Living Day's local title, freshness label, and utility controls with the shared text,
  palette, and icon-button grammar instead of introducing a second visual system inside Home.
- Added regression coverage for the shared shell, previous-day legacy fallback, Reports tab return,
  explicit sharing, density controls, dark mode, and the largest accessibility text size.
- The consolidated device-level run passed 4/4 on an iPhone 17 Pro Max, the compact shell check
  passed on an iPhone SE, and standard, compact, and dark accessibility captures were reviewed.
  Living Day, sharing, and design-system tests passed 26/26.

### Batch 5 - Food Search and Fast Food Builder (complete)

- Rebuilt Food Search around its primary job: search first, meal destination second, repeat logging
  next, and alternate entry methods after that. The meal destination uses a standard segmented
  control at regular sizes and a compact menu when accessibility text needs the space.
- Replaced mint page washes and scattered tinted cards with neutral controls, grouped result rows,
  quiet loading/error/empty states, and complete history cards that adapt from two columns to one
  on narrow or accessibility layouts.
- Kept quick logging direct while making success legible to VoiceOver and slower devices. The
  completed state now remains available long enough to be announced instead of disappearing during
  an accessibility focus transition.
- Increased Fast Food Builder density without hiding evidence: restaurant identity now carries the
  catalog date and review caveat, brand color marks the selected restaurant, and ingredient color is
  reserved for actual selection rather than washing every row.
- Preserved one persistent review action and a compact calorie/macro summary. Accessibility layouts
  reduce the footer to `Review order`, move totals into its accessibility value, hide decorative
  search chrome, and use responsive ingredient identity, nutrition, and portion controls.
- All five focused standard/dark/largest-text scenarios passed in their final executions. Food
  Search and builder also passed their compact iPhone SE workflows, including direct selection and
  sticky-total state changes. Focused Core food-search/catalog/display tests passed 26/26, strict
  lint passed with zero violations on the structured changed files, and the unsigned Release build
  passed for the full app and extensions.

### Batch 6 - Food Detail and Trust Receipt (complete)

- Made food identity neutral so source quality and correction state, rather than the food itself,
  carry semantic color. The identity reflows at accessibility sizes and its decorative glyph keeps
  stable geometry.
- Kept Trust Receipt unframed and first in the evidence hierarchy, while moving the numeric score
  into the visible header with an explicit VoiceOver label and value.
- Replaced four large nutrition tiles with one responsive neutral metric strip. It uses a compact
  two-column summary at standard sizes and full-width rows at accessibility sizes.
- Flattened serving and nutrition-detail controls into shared quiet surfaces without changing
  quantity, serving selection, correction, label scan, save, or logging behavior.
- Replaced the glowing gradient logging footer with the shared flat primary action. Trust repair
  remains destructive only when correction is actually required.
- Added deterministic hierarchy, score-contract, action, dark-mode, and largest-text coverage. The
  final focused run passed 2/2, its largest-text clipping audit passed unfiltered, full SwiftLint
  reported zero violations, and the standard and dark captures were reviewed.

### Batch 7 - Running History and Detail (complete)

- Preserved the direct Start action while replacing the legacy dashboard tiles with one emphasized
  weekly metric strip, one quiet records surface, and one continuous source-labeled run list.
- Made history rows, record values, heart-rate zones, splits, gear, and guided-workout results
  responsive instead of relying on single-line compression at accessibility sizes.
- Rebuilt Run Detail around one responsive summary, quiet recovery evidence with one direct action,
  readable splits and gear, and explicit recording-source attribution. Recovery copy now says the
  target supports recovery rather than promising glycogen supercompensation.
- Kept route, HealthKit import/write, run calculations, workout guidance, and recorder behavior
  unchanged. The recorder's saved workout-result card only adopted the shared surface grammar.
- Added deterministic history-to-detail and dark accessibility-XXXL coverage. The final standard
  journey and corrected dark artifact run passed, clipping audits passed, the full simulator build
  passed with the embedded Watch app, and final light/dark captures were reviewed.

### Batch 8 - My Foods and Manual Food Editor (complete)

- Rebuilt My Foods around one Saved/Barcode/Review summary, compact filter and sort controls, one
  grouped duplicate-review surface, and one continuous saved-food list. Search, edit, merge,
  barcode detachment, deletion, source detail, and review state behavior are unchanged.
- Rebuilt Add/Edit Food as a responsive operational form with a clear identity, a compact macro
  section, serving controls, optional nutrition details, preview, and one pinned primary action.
  Total and saturated fat remain independently editable and label scanning retains its existing
  correction behavior.
- Accessibility layouts stack identity, macro, and serving controls and combine field titles with
  their units so labels can grow naturally. Normal layouts retain the denser two-column form.
- Fixed a pre-existing presentation defect across Food Search, Quick Log, recipes, and calorie-log
  entry points: every manual-food sheet now owns a navigation stack, so its title, Cancel action,
  and saved-food control cannot disappear.
- Added deterministic My Foods and Add Food routes plus four focused UI scenarios covering visual
  order, active controls, the restored toolbar, dark mode, scrolling, and accessibility XXXL. All
  four passed in their final executions; 18 focused library/correction unit and rendering tests
  passed; the full build linted 232 files with zero violations; and final light/dark captures were
  reviewed.

### Batch 9 - Recipe Workflows (complete)

- Rebuilt Recipe Library around one Saved/Ingredients/Calories summary, direct search and refresh,
  one continuous saved-recipe list, and an explicit delete confirmation while preserving edit,
  detail, refresh, and deletion behavior.
- Rebuilt Recipe Detail around responsive identity and nutrition summaries, continuous ingredient
  and instruction sections, optional micronutrients, and direct pinned actions for logging and meal
  planning. The meal-plan sheet retains add/replace behavior and adapts its meal control at large
  text sizes.
- Unified Create/Edit Recipe across Maia, pasted text, URL, and manual methods with one creation
  selector, shared operational sections, a stable Cancel action, and a pinned manual Save action.
- Rebuilt Recipe Logging around a responsive summary, meal destination, editable ingredients, and
  one stable Log Recipe action. Removing every ingredient from a detailed recipe now produces zero
  totals and disables logging instead of restoring the recipe's stale original totals.
- Added deterministic recipe fixtures and four focused standard/dark accessibility UI scenarios.
  The final run passed 4/4; 37 focused Core recipe tests passed; the full simulator build embedded
  Watch, widgets, and Live Activity; SwiftLint reported zero violations across 232 files; and all
  final light and dark accessibility captures were reviewed.

### Batch 10 - Grocery List (complete)

- Rebuilt Grocery around one responsive shopping summary, direct Add and Scan actions, a compact
  checked-item control, and canonical aisle groups that stay easy to scan during a shopping run.
- Made row editing discoverable through a visible item menu while preserving one-tap checking,
  swipe actions, clear-list confirmation, and the existing manual editor workflow.
- Applying Imperial or Metric now converts the current visible list immediately instead of only
  affecting future lists. Legacy Protein, Grains, Dairy, and Other categories normalize into the
  current aisle vocabulary without dropping or duplicating items.
- Added an eight-item deterministic grocery fixture plus standard hierarchy/editor, check-and-hide,
  and dark accessibility-XXXL UI scenarios. Thirteen focused Core grocery tests, the fixture test,
  the full simulator build, and the final corrected UI executions passed; SwiftLint reported zero
  violations across 232 files and the final captures were reviewed.

### Batch 11 - Nutrition Confirmation Workflows (complete)

- Rebuilt Quick Add around responsive nutrition inputs, a live entry summary, automatic
  macro-derived calories when calories are left blank, and one stable Add to Meal action.
- Unified Maia text entry, text results, photo estimates, and rapid-barcode estimates around one
  explicit review model. Source/review status, nutrition totals, edit affordances, swipe removal,
  and final confirmation now follow the same hierarchy.
- Fixed a pre-existing state defect in Maia result sheets: callers previously supplied immutable
  bindings, so an apparent edit or deletion could fail to persist in the confirmation list. Each
  review now owns its working item state and recomputes its total and action label immediately.
- Added a deterministic Maia meal fixture and four focused UI scenarios covering Quick Add, Maia
  input, editable removal, and dark accessibility-XXXL layouts. The final run passed 4/4, the
  fixture test and full simulator build passed, SwiftLint reported zero violations across 232
  files, and all retained light/dark captures were reviewed.

### Batch 12 - Settings, Account, Import, and Legal (complete)

- Replaced the Personal Settings dashboard treatment with a targets-first configuration screen:
  one compact nutrition summary followed by native grouped rows for goals, display and units,
  integrations, notifications, training, Maia, support, account, and legal controls.
- Kept configuration icons mostly neutral, reserved semantic color for state, and aligned switches,
  menus, destructive actions, and completion controls with the shared app tint and action grammar.
- Rebuilt calorie and macro goals, height, water, health disclaimer, and AI-data consent around
  responsive native forms and quiet surfaces without changing goal calculations, persistence,
  HealthKit behavior, consent, account deletion, or support links.
- Rebuilt MyFitnessPal import as a full-height staged workflow with explicit evidence, conflict
  language, progress, success, and recovery states. Its primary action remains reachable in every
  actionable stage, including the largest accessibility text size.
- Added deterministic routes and focused coverage for the targets-first hierarchy, six Settings
  destinations, feedback/share reachability, notification controls, Maia voice controls, dark
  mode, and accessibility XXXL. The final hierarchy and destination run passed 2/2, the strict
  dark accessibility journey passed, the full app build passed, and SwiftLint reported zero
  violations across 232 files.

### Batch 13 - Workout Program and Routine Editors (complete)

- Rebuilt Saved Plans around one training-library header, a compact plan count, and responsive
  active/status/actions while preserving activation, deletion, start dates, routine order, and
  progress.
- Rebuilt program creation and editing around plan identity, a concise routine/set summary,
  ordered routine rotation, schedule selection, and one persistent save action. Adding a routine
  opens its editor immediately, and reopening that editor no longer resets in-progress changes.
- Rebuilt routine creation and editing around identity, workload summary, details, fast-start
  templates, exercise planning, movement selection, set targets, and one persistent save action.
  Dense exercise-row actions now live in a discoverable menu without removing edit, move,
  duplicate, or delete behavior.
- Replaced the compact weekday control with full labeled, accessible day buttons shared by the
  program editor, AI workout generator, and schedule editor.
- Added deterministic Saved Plans, Program Builder, and Routine Builder routes. Standard and dark
  accessibility-XXXL journeys verify hierarchy, stable save/close controls, screen bounds, and
  text clipping. Twenty-eight focused routine/program rule tests and both final UI journeys pass;
  the full simulator target compiles including Watch, widgets, and Live Activity.

### Batch 14 - Training Evidence and Review (complete)

- Rebuilt Program Detail around one program identity, progress and workload summary, a responsive
  schedule editor, the existing next-step control, a quiet training calendar, and one routine
  rotation. Program scheduling, progression, skipping, editing, and session review behavior remain
  unchanged.
- Rebuilt Workout History around one training summary, compact search/range controls, readable
  movement filters, highlights, and a continuous session list. Manual history entries now have an
  explicit simple-log fallback rather than an unrelated empty state.
- Consolidated Session Review into one completion summary and one continuous exercise breakdown,
  followed by records, trends, recovery, Maia analysis, edit/share controls, and one persistent
  Done action. Screenshot mode uses immediate local analytics instead of waiting on live AI data.
- Unified the Reports fitness-analytics summary and Maia workout-insight rows with the same metric,
  section, and quiet-surface grammar. Removed the remaining legacy card treatments in the migrated
  training views.
- Added deterministic Program Detail, Workout History, and Session Review routes. Standard and
  dark accessibility-XXXL journeys pass hierarchy, bounds, persistent-action, and text-clipping
  checks. Sixty-six focused workout analytics/model/rules/service tests pass, the full simulator
  build and strict lint pass, and all final captures were reviewed.

### Batch 15 - Wellness, Weight, Fasting, and Cycle (complete)

- Rebuilt Weight Progress, current-weight logging, goal editing, and milestone history around one
  body-trend hierarchy while preserving HealthKit writes, chart calculations, unit conversion, and
  direct logging. The chart's trend area now stays inside its intended plot bounds.
- Rebuilt the Wellness Score debrief around the score, contributing signals, and practical next
  steps. Its largest-accessibility layout replaces the fixed score ring with a readable linear
  treatment rather than compressing or colliding with the score label.
- Unified Apple Health activity and fasting surfaces with source-aware language. Fasting guidance
  now uses broad timing estimates and a clear informational disclaimer instead of unsupported
  metabolic-state claims.
- Unified cycle overview, settings, phase map, and Maia guidance. The experience now states that
  phases are calendar estimates, not measurements of fertility, ovulation, or hormone levels, and
  identifies Maia guidance as AI-generated.
- Added deterministic Weight, Wellness Score, Fasting, and Cycle routes. The standard journey and
  dark accessibility-XXXL bounds/hittability journey pass and their final captures were reviewed.
  Ten focused cycle/milestone rule tests and the app wellness-score tests pass. On iOS 26.5,
  SwiftUI's automated text-clipping audit reported false positives for visibly complete text, so
  maximum-size verification uses reviewed screenshots plus explicit bounds and action checks.
  Ten design-system tests, strict lint, and the complete simulator build also pass.

### Batch 16 - Onboarding and Account Access (complete)

- Rebuilt Welcome, Sign In, Create Account, account loading, Personal Setup, and the first-run
  feature tour around one evidence-led hierarchy with quiet grouped forms and stable actions.
- Preserved authentication, password reset, profile creation, goal calculation, and completion
  behavior while removing swipe navigation that could bypass required Personal Setup steps.
- Added a shared first-login decision rule. Missing or partially provisioned profiles now remain in
  setup until Firestore explicitly records completion, preventing a new-account timing race from
  opening the main app before required profile data exists.
- Reframed the feature tour around inspectable nutrition, cautious estimate language, training,
  wellness evidence, and editable planning rather than unsupported product claims.
- Removed screen-level accessibility identifiers that masked their child controls in SwiftUI.
  Primary actions now expose stable identifiers as actual buttons, and the largest-text feature-
  tour action retains a visible label.
- Added deterministic routes for the complete first-run family plus four focused state-rule tests.
  The standard five-screen journey and dark accessibility-XXXL four-screen journey pass with
  reviewed captures, visible and hittable actions, and explicit horizontal-bound checks. Strict
  lint and the complete simulator build pass.

### Batch 17 - Progress, Achievements, and Weekly Challenges (complete)

- Rebuilt Profile as `Your Progress`: one level/points/unlocked summary, correct threshold-relative
  level progress, one direct Weekly Challenges route, a restrained current-targets section, and a
  continuous achievement list instead of a dashboard of independent cards.
- Rebuilt Weekly Challenges around an Open/Complete/Points Left summary and one responsive list.
  In-progress, completed, and ended states now use literal status language and remain readable at
  the largest accessibility text size.
- Removed placeholder identity and gender-derived journey labels. BMI is identified as a general
  screening estimate rather than a diagnosis or complete health measure. Sharing remains an
  explicit user action and only appears for unlocked achievements.
- Added a tested level-progress contract that handles threshold spans and the maximum level, plus
  deterministic achievement and challenge repository fixtures so late subscriptions cannot replace
  screenshot state with a loading placeholder.
- Audited the older group/post prototype and kept it inaccessible. It lacks the identity,
  reporting, blocking, moderation, and privacy contracts required for a public social surface.
  Community barcode consensus also remains behind its existing default-off rollout gate.
- Four final standard/dark accessibility captures were reviewed. Focused Core rules passed 14/14,
  app fixture tests passed 6/6, both end-to-end progress-family journeys passed, strict lint passed,
  and the complete simulator target compiled with Watch, widgets, and Live Activity.

### Batch 18 - Smart Pantry, Pantry Recipes, and Receipt Review (complete)

- Rebuilt Smart Pantry around one ingredient/category summary, one direct recipe action, canonical
  category groups, quiet management rows, and a stable add/receipt bar. Existing listen, add,
  update, and delete behavior remains unchanged.
- Rebuilt pantry-generated recipe drafts as an explicitly AI-assisted review surface. Nutrition,
  quantities, and directions are labeled as estimates; generation and save failures have separate
  recovery paths; saving remains an explicit action per recipe. Unsaved AI drafts are keyed by
  their list position, preventing nil recipe IDs from collapsing multiple drafts or sharing saved
  state.
- Rebuilt receipt scanning as a review-first import. Every detected name, amount, unit, and category
  remains editable; invalid rows cannot be added; blank optional fields receive conservative
  fallbacks; camera and parsing failures use actionable user language instead of raw backend text.
- Hardened the shared sheet scaffold so its native close control receives a dedicated row at
  accessibility sizes, a stable test identifier, and an explicit viewport boundary. Long scroll
  content, titles, and subtitles can no longer compress or move the header outside the screen.
- Added deterministic Pantry, generated-recipe, and receipt fixtures plus standard and dark
  accessibility-XXXL journeys. Focused design-system and Pantry rules passed 29/29; the integrated
  app/UI result passed 10/10; final standard and delayed direct dark captures were reviewed; and
  the complete simulator target compiled with the embedded Watch app, widgets, and Live Activity.

### Batch 19 - AYCE and Restaurant Value Radar (complete)

- Rebuilt the complete Beat the Buffet family around the shared operational hierarchy: responsive
  cuisine and session setup, a live value summary with continuous menu rows, editable reviewed
  items, and a final diary summary with literal value comparisons.
- Plate scans now open review instead of adding food immediately. Every detected item can be edited
  for identity, serving, nutrition, restaurant price, and home cost; off-catalog manual items use
  the same editor; reviewed entries remain editable and removable during the session. AI and manual
  sources stay distinct, and locally entered prices are never multiplied by the selected city.
- Rebuilt Value Radar around exact printed scan prices, neutral protein-value tiers, a labeled
  fictional demo, and editable AI review before logging. Regional pricing applies only to demo
  data. A latest-request contract prevents an older scan or delayed demo from replacing newer
  results, and camera-unavailable devices fall back to photo selection.
- Hardened shared and feature math against zero, negative, NaN, and infinite values while retaining
  old saved-session compatibility. Accessibility metric strips now stack labels and values rather
  than breaking digits across columns; AYCE's pinned actions remain compact at the largest text
  sizes while preserving their VoiceOver labels.
- Focused Core coverage passed 52/52 and focused app coverage passed 13/13. The five-screen standard
  AYCE/Value Radar journey and five-screen dark accessibility-XXXL journey passed with reviewed
  captures; a dedicated dark accessibility-XXXL celebration journey and the visual-system gallery
  regression passed; strict lint and the complete simulator build also passed.

All five primary tabs, the highest-frequency nutrition entry workflows, Food Detail, Trust,
Running, My Foods, the manual food editor, and the full recipe family now share one visual grammar.
Grocery, the remaining confirmation workflows, Settings, and the complete strength-planning and
review family now join that system, along with wellness, weight, fasting, and cycle tracking. The
first-run and account-access family now joins them, as do the live progress, achievement, and
weekly-challenge surfaces. Smart Pantry, pantry recipe drafts, receipt review, AYCE, and Restaurant
Value Radar now join them. The active migration queue is the remaining reachable planning,
cooking, calculator, and long-tail report surfaces; unfinished public social surfaces remain
explicitly gated rather than being polished into accidental release scope.

## Product Direction

MyFitPlate should feel **evidence-led, training-aware, and human**.

The unifying rule is:

> Editorial when interpreting. Operational when acting. Native when configuring.

That does not mean every screen should look like Living Day. It means every screen should inherit
the same typography, color semantics, spacing, controls, navigation shell, and surface hierarchy
while choosing the composition appropriate to its job:

- **Interpretation surfaces** such as Living Day, Trust Receipt, and Week in Motion use unframed
  paths, evidence rows, and one clear observation or action.
- **Repeated workflows** such as Food Search, Fast Food Builder, workout execution, and run
  recording stay dense, predictable, and task-focused.
- **Configuration surfaces** such as Settings use quiet grouped rows and standard platform
  behavior instead of feature-style dashboards.

## Audit Scope

The pass covered the shared design system and deterministic light/dark captures of:

- Legacy Home and Living Day
- Maia
- Train
- Meal Plan
- Reports / Week in Motion
- Food Search
- Fast Food Builder
- Trust Receipt
- Running
- Settings
- Quick Log

The screenshots show three visual generations in the same app:

1. **Path and evidence:** Living Day, Trust Receipt, and Week in Motion. These are the strongest,
   most ownable surfaces.
2. **Soft glass dashboard:** legacy Home, Train, Meal Plan, Maia, and Settings. These rely on pale
   tinting, material, shadows, and nested cards.
3. **Operational utility:** Food Search, Fast Food Builder, Running, and editor/recorder screens.
   These are generally clear but do not yet share one shell or component language.

The root cause is structural rather than screen-specific. `DESIGN.md` asks for restrained neutral
surfaces, meaningful green, 16-20 point radii, and one motion curve, while the reusable defaults
still provide green-to-teal gradients, 24 point glass cards, material backgrounds, deep shadows,
and separate spring definitions.

Current source indicators:

- 120 `.glassCard()` / `.asCard()` call sites
- 68 uses of the shared primary or secondary button styles
- 42 material effects, 37 shadows, and 16 explicit linear gradients
- 39 observed raw `appFont` sizes despite six documented text roles
- 21 observed corner-radius values
- 99 navigation-title declarations plus several bespoke top-level headers
- More than 500 direct blue/cyan/orange/purple references requiring semantic review; this count
  includes legitimate data colors and is an audit queue, not a blanket replacement target

## Current Screen Assessment

| Surface | Current visual state | Direction |
|---|---|---|
| Living Day | North star, Batch 4 shell aligned | Keep the unframed path and preserve its evidence-led behavior |
| Week in Motion | North star, Batch 3 retained | Keep the rhythm/evidence structure as the Reports lead story |
| Reports detail | Batch 3 migrated | Quiet trend controls, responsive evidence, and flat report surfaces |
| Trust Receipt | Batch 6 migrated | Unframed evidence path, visible score, neutral macro summary, flat logging action |
| Running | Batch 7 migrated | Direct Start, responsive weekly/detail metrics, grouped source rows, quiet recovery and split evidence |
| Food Search | Batch 5 migrated | Search-first hierarchy, neutral repeat/result surfaces, adaptive meal selection |
| Fast Food Builder | Batch 5 migrated | Dense direct selection, persistent summary, tint reserved for brand and state |
| My Foods | Batch 8 migrated | Operational summary, compact controls, grouped duplicate review, continuous saved-food rows |
| Manual Food Editor | Batch 8 migrated | Responsive identity/nutrition/serving/details form with one pinned action |
| Recipe Library | Batch 9 migrated | One operational summary, direct search/refresh, continuous saved-recipe rows |
| Recipe Detail | Batch 9 migrated | Responsive nutrition and ingredient evidence with direct log and meal-plan actions |
| Recipe Create/Edit | Batch 9 migrated | One creation-mode control, coherent manual editor, stable Cancel and Save actions |
| Recipe Logging | Batch 9 migrated | Editable ingredient list, responsive totals, meal choice, and guarded logging action |
| Settings | Orderly but generic | Use a native grouped configuration pattern; remove the dashboard hero |
| Quick Log | Polished but over-layered | Use a neutral sheet scaffold and simpler rows |
| Maia | Batch 3 migrated | One deterministic recommendation, concise context, labeled evidence, pinned composer |
| Train | Batch 2 migrated | One progression surface, direct Start action, unframed week, flat readiness rows |
| Meal Plan | Batch 2 migrated | Unframed week, one summary band, aligned progress, quieter meal rows |
| Legacy Home | Superseded direction | Retain only as rollback until Living Day is proven, then retire it |

## Unified System

### 1. Surface hierarchy

Every screen gets at most one framed level at a time.

1. **Canvas:** `backgroundPrimary`; no decorative material or gradient.
2. **Section:** usually unframed. Use `backgroundSecondary` only when grouping materially improves
   comprehension.
3. **Interactive row:** `ControlBackground`, subtle separator or one-pixel stroke, 12-16 point
   radius when the row is not part of a grouped list.
4. **Modal:** use the native sheet/popover surface. Do not put another full-screen glass panel
   inside it.

Content cards may not contain other content cards. Metric tiles inside a hero are replaced by a
metric strip, dividers, or aligned columns.

### 2. Color

- Green remains action, success, or current state; it is never a page wash.
- Brand gradients are removed from buttons and app chrome.
- Material is limited to transient chrome: the tab bar, a compact floating control, or a system
  sheet where platform depth is useful.
- Semantic accents retain one meaning across every feature. Raw system colors are migrated as each
  screen is touched.
- Light and dark surfaces use asset-backed neutrals rather than opacity stacks that change meaning
  between appearances.

### 3. Typography

Replace raw size selection with named roles. Proposed roles:

- `display`: a true top-level feature title only
- `screenTitle`: primary tab and full-screen destinations
- `sectionTitle`: major sections
- `control`: buttons and interactive row titles
- `body`: primary explanatory content
- `secondary`: supporting values and descriptions
- `caption`: metadata and evidence labels
- `metric`: a numeric role with monospaced digits and context-specific upper bounds

The exact sizes remain Dynamic Type-aware. Screens stop choosing arbitrary values directly.

### 4. Shape and spacing

- Three content radii: 12 for controls, 16 for regular surfaces, 20 for a rare hero surface.
- Capsules are reserved for compact states, filters, and short actions. They are not generic cards.
- Standard horizontal screen inset: 20 points on phones, with a documented compact exception.
- Standard section gap: 20-24 points; internal group gap: 12-16 points.
- Shadows are removed from content. One subtle shell shadow may remain where the tab bar separates
  from scrolling content.

### 5. Motion and feedback

- One shared spring for state changes and one short ease for visibility changes.
- Haptics remain tied to meaning: navigation, committed log/save, or completion.
- No passive card entrance animations, decorative shimmer, or repeated celebration.
- Reduce Motion uses opacity/content replacement without changing information order.

### 6. Navigation shell

Build one primary-tab shell:

- Stable title position and baseline across Home, Maia, Train, Meal Plan, and Reports
- One trailing action cluster with 44 point targets and icon labels for accessibility
- Settings/profile access in a predictable location instead of a Home-only menu dependency
- Compact date navigation as content beneath the Home title, not a second oversized header card
- Native navigation bars for pushed destinations and standard cancellation/confirmation placement

The tab bar should retain five equal destinations and the centered Quick Log affordance, but lose
the oversized 128 point footprint, deep shadow, gradient stroke, and separate visual language.
Quick Log should be one compact outlined control, with the expanded menu presented as a neutral
sheet rather than a green glass panel.

## Component Migration Map

Introduce versioned components before changing legacy aliases globally. The existing shared button
styles affect 68 call sites, so a direct replacement would create an unnecessarily large review
surface.

- `AppCanvas`
- `AppScreenHeader`
- `AppSectionHeader`
- `AppSurface` with only `quiet` and `emphasized` roles
- `AppActionButton` with primary, secondary, and destructive roles
- `AppIconButton`
- `AppMetricStrip` and `AppMetricRow`
- `AppEvidenceRow`
- `AppListRow`
- `AppSegmentedControl`
- `AppEmptyState`
- `AppSheetScaffold`
- `AppTabBar`

Add a Debug component gallery that renders every primitive in light, dark, increased contrast, and
large Dynamic Type before any high-traffic screen migrates.

## Screen Migration Order

### Phase 0 - Protect the current candidate

- Finish the existing physical-device and signed-release checks.
- Create the visual-system branch only after the Living Day candidate is preserved on `main`.
- Do not combine broad visual work with release-fix commits.

### Phase 1 - Foundation and shell

- Add named typography, spacing, radius, surface, action, row, and motion primitives.
- Add the component gallery and screenshot assertions.
- Migrate the top-level header, tab bar, Quick Log sheet, and modal scaffold.
- Deprecate new uses of `glassCard`, `asCard`, and `brandGradient` without deleting legacy behavior
  yet.

### Phase 2 - Primary tabs

1. Train
2. Meal Plan
3. Maia
4. Reports detail content below Week in Motion
5. Living Day shell alignment

Train and Meal Plan come first because they have the highest combination of frequency, visual
weight, and nested-surface debt. Living Day itself changes last and only at the shell boundary.

### Phase 3 - Core repeated workflows

1. Food Search and its empty/history states (Batch 5 complete)
2. Fast Food Builder (Batch 5 complete)
3. Food Detail below Trust Receipt (Batch 6 complete)
4. Running history and run detail (Batch 7 complete)
5. My Foods and the manual Add/Edit Food path (Batch 8 complete)
6. Recipe List, Detail, Create/Edit, and Logging (Batch 9 complete)
7. Grocery and remaining logging confirmation sheets

This phase must preserve or improve time to successful food log, item selection, and workout/run
start. Editorial composition must not leak into repeated workflows.

### Phase 4 - Configuration and long tail

- Settings and account/legal surfaces (Batch 12 complete)
- Workout program/routine editors and analytics (Batches 13-14 complete)
- Wellness, weight, fasting, and cycle surfaces (Batch 15 complete)
- Onboarding/authentication (Batch 16 complete)
- Profile, achievements, and weekly challenges (Batch 17 complete)
- Dormant group/post social prototype (not release eligible; keep inaccessible until its safety
  and privacy product contracts exist)
- Smart Pantry, pantry recipe drafts, and receipt review (Batch 18 complete)
- AYCE and Restaurant Value Radar (Batch 19 complete)
- Remaining reachable planning, cooking, calculator, and long-tail report surfaces

Migrate by feature family so each batch can be reviewed and reverted independently.

### Phase 5 - Remove the old generation

- Delete the legacy Home only after Living Day rollout evidence and rollback approval.
- Remove the legacy glass aliases after their call-site count reaches zero.
- Remove brand-gradient button behavior and unused inline color paths.
- Turn the component rules into a lightweight source check so new raw sizes, radii, and forbidden
  surfaces cannot silently re-enter the app.

## Screen-Specific Changes

### Train

- Keep the next workout as the single hero.
- Replace card-in-card-in-card composition with a program header, workout summary, exercise preview
  rows separated by dividers, and one flat green `Start workout` action.
- Move Skip to a quiet text/menu action.
- Render the program week as an unframed rhythm below the hero.

### Meal Plan

- Convert the week picker into an unframed compact strip.
- Replace three metric cards plus the nested Daily Fit card with one summary band and aligned
  progress rows.
- Render planned meals as sections/rows rather than large cards with nested macro tiles.
- Keep one primary day-level action; demote generation and secondary tools to the toolbar/menu.

### Maia

- Replace the large readiness dashboard and nested metrics with a concise daily context strip.
- Show one recommended prompt/action, then quiet prompt chips.
- Keep the conversation and composer visually dominant; remove empty vertical staging space.
- Reuse Living Day evidence labels when Maia explains a recommendation.

### Food Search and Fast Food Builder

- Search remains the hero and receives the clearest focus state.
- Meal destination uses a standard segmented control.
- Secondary entry modes become a compact action row or menu rather than a row of green pills.
- Empty states use one neutral invitation, not repeated tinted cards.
- Builder selection is communicated by check, stroke, and summary state; entire rows do not need a
  green wash.
- Preserve a persistent, compact selection summary and one logging action.

### Trust and Food Detail

- Preserve the receipt path, source labels, and correction model.
- Make the food identity header neutral; trust status carries the state color.
- Replace the lower green nutrition tiles with a neutral aligned grid/list.
- Replace the green-to-teal glowing Add action with the shared flat primary action.

### Running

- Batch 7 preserves the direct hierarchy and large Start action.
- History now uses the shared quiet grouped-row treatment while retaining source and exercise
  identity.
- Run Detail uses responsive evidence and metric surfaces without changing recording behavior.
- Path/evidence language remains confined to post-run interpretation rather than the live recorder.

### My Foods and Manual Food Editor

- Batch 8 gives the library one summary, one compact control row, and grouped management lists.
- Duplicate evidence and source/review state remain visible without turning every food into a card.
- Manual Add/Edit Food uses responsive sections rather than independent macro and serving tiles.
- Nutrition fields preserve direct editing, label scan, validation, save, and log behavior while
  presenting one stable action and a complete navigation bar from every entry point.

### Recipes

- Batch 9 gives Recipe Library one compact operational summary and one continuous saved-recipe
  list, with search, refresh, edit, and deletion remaining directly available.
- Recipe Detail keeps ingredient, instruction, micronutrient, meal-plan add/replace, and logging
  behavior while presenting one responsive evidence hierarchy and two stable actions.
- Create/Edit Recipe uses one segmented creation-mode control and shared section grammar across
  Maia, pasted-text, URL, and manual workflows; manual editing retains direct ingredient changes
  and one pinned Save action.
- Recipe Logging keeps direct meal selection and ingredient editing. An empty detailed recipe now
  reports zero nutrition and cannot be logged, preventing stale original totals from returning.

### Settings

- Remove the Personal Settings hero card and its nested metric tiles.
- Use a compact Goals summary row followed by native grouped sections.
- Reserve semantic colors for the data they represent; configuration icons stay mostly neutral.
- Use the standard app tint for Done and switches rather than a separate blue configuration theme.

### Profile, Achievements, and Weekly Challenges

- Treat Profile as a progress record, not a social identity card. Lead with level, earned points,
  unlocked milestones, and the exact distance to the next threshold.
- Keep current nutrition targets secondary and label BMI cautiously as a screening estimate.
- Present achievements and challenges as continuous operational lists with literal progress,
  completion, expiry, and point states rather than nested cards or celebratory decoration.
- Keep sharing opt-in and limited to earned achievements. Do not expose the dormant public group or
  post feed without identity, reporting, blocking, moderation, and privacy review.

### Smart Pantry and Receipt Review

- Keep Pantry operational: one inventory summary, canonical category groups, direct item
  management, one recipe action, and one persistent ingredient entry bar.
- Identify pantry-generated recipes as AI-assisted drafts and keep estimate language adjacent to
  the generated nutrition, ingredients, and directions.
- Treat receipt parsing as an editable import draft. Nothing is saved until the user reviews it,
  and invalid or empty rows never enter the pantry.
- Preserve the receipt camera, PantryService writes, RecipeService saves, and existing feature flag
  while replacing raw parsing/save errors with actionable language.

## Acceptance Gates

- The twelve audited surfaces have deterministic light and dark captures on compact and standard
  phones; top-level surfaces also have large Dynamic Type captures.
- No migrated top-level screen contains nested `AppSurface` content.
- No migrated primary action uses a gradient or glow.
- Material appears only in documented transient shell locations.
- Every primary tab uses the same header and tab-bar geometry.
- Every migrated screen passes the one-hero, one-filled-action, semantic-color, number-formatting,
  VoiceOver, and Dynamic Type checks in `DESIGN.md`.
- Food logging, builder selection, workout start, and run start require no additional taps.
- Dark mode preserves hierarchy without black cards nested inside gray cards.
- The Debug component gallery and screenshot matrix pass before each feature-family merge.

## Release Strategy

This should ship as several reviewable batches on one visual-system branch, not one enormous final
diff. Foundation and shell land first; each feature-family migration follows with its own tests and
screenshots. The current Living Day candidate remains the rollback point throughout.
