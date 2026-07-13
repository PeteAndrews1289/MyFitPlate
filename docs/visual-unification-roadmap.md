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

The next primary-tab batch aligns only the Living Day shell boundary. Its evidence-led timeline,
feature decision, and rollback behavior remain unchanged. Core repeated workflows follow after all
five primary tabs share the same chrome.

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
| Living Day | North star | Keep the unframed path; align shell, copy case, and action treatment |
| Week in Motion | North star, Batch 3 retained | Keep the rhythm/evidence structure as the Reports lead story |
| Reports detail | Batch 3 migrated | Quiet trend controls, responsive evidence, and flat report surfaces |
| Trust Receipt | Strong but split | Keep receipt; flatten the nutrition grid and replace the gradient footer CTA |
| Running | Strong utility | Keep density; adopt shared header, rows, and surfaces |
| Food Search | Clear but over-tinted | Make search the hero; neutralize selectors and empty states |
| Fast Food Builder | Useful and distinct | Increase density; reserve tint for selection and evidence only |
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

1. Food Search and its empty/history states
2. Fast Food Builder
3. Food Detail below Trust Receipt
4. Running history and run detail
5. My Foods, recipes, grocery, and logging confirmation sheets

This phase must preserve or improve time to successful food log, item selection, and workout/run
start. Editorial composition must not leak into repeated workflows.

### Phase 4 - Configuration and long tail

- Settings and account/legal surfaces
- Workout program/routine editors and analytics
- Wellness and weight surfaces
- Onboarding/authentication
- Community surfaces
- Remaining recipe, pantry, and specialty nutrition tools

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

- Preserve its direct hierarchy and large Start action.
- Adopt the shared screen header and quiet list-row treatment.
- Keep source labels and exercise identity; remove unnecessary card shadows.
- Reuse the path/evidence language only in run detail and post-run interpretation, not recording.

### Settings

- Remove the Personal Settings hero card and its nested metric tiles.
- Use a compact Goals summary row followed by native grouped sections.
- Reserve semantic colors for the data they represent; configuration icons stay mostly neutral.
- Use the standard app tint for Done and switches rather than a separate blue configuration theme.

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
