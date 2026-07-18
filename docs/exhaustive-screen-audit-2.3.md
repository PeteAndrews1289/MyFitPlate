# MyFitPlate 2.3 Exhaustive Surface Audit

Date: 2026-07-16

Status: Implemented and re-graded. The detailed inventory preserves the original census as a
baseline; the closure register below supersedes baseline scores for every surface changed during
the five-star implementation pass.

## Purpose

This is the complete user-facing surface census for the 2.3 candidate. The goal is not merely to
confirm that the major tabs look good. It is to identify every screen, sheet, full-screen flow,
dialog, meaningful empty/loading/error state, Watch surface, widget family, and Live Activity that
a user can encounter, then judge:

- what job the surface performs;
- whether its color and hierarchy match the current MyFitPlate identity;
- how modern and deliberate it feels;
- where clarity, trust, accessibility, or workflow gaps remain;
- whether the surface is current, legacy, dormant, debug-only, or physically testable only.

The design target used throughout this audit is:

> A calm, evidence-led performance companion that explains what matters, shows why, and offers one
> useful next action.

## Scope And Method

The census was built from:

- 478 Swift source files;
- 508 SwiftUI view declarations;
- 249 explicit sheets, full-screen covers, alerts, confirmation dialogs, menus, and navigation
  destinations;
- the app's deterministic screenshot routes and seeded demo data;
- 151 exported UI-test attachments covering standard, dark, compact, and Accessibility XXXL
  layouts;
- focused current captures for Trust Hub, Meal Plan, Feature Tour, Add Shoe, and Recovery Field;
- source inspection for screens that require camera, GPS, HealthKit, speech, Watch transport,
  widgets, Live Activities, account state, or destructive actions;
- a reachability pass that found 23 unreferenced view declarations.

Broad phone captures are stored at:

`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/ExhaustiveScreenAudit-2.3-UIAttachments-20260716`

Focused current captures are stored at:

`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/ExhaustiveScreenAudit-2.3-Focused-20260716`

The paired Watch Home capture is stored at:

`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/ExhaustiveScreenAudit-2.3-Watch-20260716`

### Coverage Labels

| Label | Meaning |
| --- | --- |
| `VC` | Visually inspected in a focused current capture |
| `VB` | Visually inspected in the broad 2.3 capture set |
| `SI` | Source-inspected; simulator image was not practical or would be misleading |
| `PD` | Requires final physical-device acceptance |
| `DR` | Dormant, debug-only, legacy, or currently unreachable |

### Modernity Score

| Score | Meaning |
| ---: | --- |
| 5 | Showpiece quality; distinctive and presentation-ready |
| 4 | Modern, coherent, and professional |
| 3 | Functional and acceptable, but generic or less authored |
| 2 | Noticeably legacy, prototype-like, or visually disconnected |
| 1 | Dead, placeholder, misleading, or not suitable for release exposure |

Scores describe presentation quality, not feature importance or correctness.

## Review Map

- [Executive assessment](#executive-assessment)
- [Color and visual system](#color-and-visual-system)
- [Launch, authentication, and first run](#1-launch-authentication-and-first-run)
- [Global shell and cross-app surfaces](#2-global-shell-and-cross-app-surfaces)
- [Home, Living Day, and daily logging](#3-home-living-day-and-daily-logging)
- [Food search, entry, detail, and Trust](#4-food-search-entry-detail-and-trust)
- [Recipes, Pantry, and Grocery](#5-recipes-pantry-and-grocery)
- [Meal Plan and meal preparation](#6-meal-plan-and-meal-preparation)
- [Maia, AI review, and voice](#7-maia-ai-review-and-voice)
- [Strength training, programs, and recovery](#8-strength-training-programs-and-recovery)
- [Running](#9-running)
- [Reports, trends, and wellness](#10-reports-trends-and-wellness)
- [Settings, account, privacy, and support](#11-settings-account-privacy-and-support)
- [Restaurant and distinctive nutrition tools](#12-restaurant-and-distinctive-nutrition-tools)
- [Profile, Challenges, and removed Community prototypes](#13-profile-challenges-and-removed-community-prototypes)
- [Debug and visual-QA surfaces](#14-debug-and-visual-qa-surfaces)
- [Widgets](#15-widgets)
- [Live Activities and Dynamic Island](#16-live-activities-and-dynamic-island)
- [Apple Watch](#17-apple-watch)
- [System-owned, external, and physical-only surfaces](#18-system-owned-external-and-physical-only-surfaces)
- [Removed dormant and duplicate views](#removed-dormant-and-duplicate-view-closure)
- [Cross-surface closure](#cross-surface-closure)
- [Physical acceptance matrix](#physical-acceptance-matrix)
- [Final product judgment](#final-product-judgment)

## Executive Assessment

The standard-size 2.3 experience is substantially unified. It now has a recognizable structure:
editorial page headings, quiet white or black canvases, cool-gray controls, pale mint emphasis,
brand-green current actions, and labeled semantic color for nutrition, training, recovery, and
caution.

The strongest surfaces are:

1. Living Day.
2. Trust Hub and Food Trust Receipt.
3. Train, live workout, and session review.
4. Run detail and recovery context.
5. Meal Plan after the current revision.
6. AYCE and Value Radar as original product ideas.
7. Feature Tour after replacing abstract explanation with real product previews.

The broadest remaining weaknesses are evidence and scale gaps rather than unfinished screen
design:

1. **Physical ecosystem confidence remains lower than simulator confidence.** Camera, speech,
   GPS, HealthKit authorization, Watch transport, widgets, haptics, and Live Activities still
   require real-hardware acceptance.
2. **Database breadth remains an incumbent advantage.** The interface now explains missing,
   partial, and converging evidence honestly, but Health Canada, NIH, USDA, FatSecret, and
   community coverage still need production observation.
3. **System-owned surfaces cannot become MyFitPlate showpieces.** Permission prompts, keyboards,
   activity sheets, external browsers, and OS voice selection should be clear and recoverable,
   but native predictability is the correct target.
4. **A signed release build remains the final truth.** App Check, production speech, Watch
   companion behavior, privacy manifests, Store processing, and exact-candidate packaging cannot
   be closed by a simulator pass.

No simulator-visible release-blocking crash, privacy dead end, or unreachable primary action was
found during this visual census.

### Baseline Inventory Snapshot

The final audit contains 411 uniquely identified surface/state rows:

| Modernity score | Rows | Interpretation |
| ---: | ---: | --- |
| 5 | 23 | Showpiece or highly distinctive |
| 4 | 271 | Modern and coherent |
| 3 | 105 | Functional but generic, system-like, or awaiting physical proof |
| 2 | 11 | Dormant, legacy, or visibly disconnected |
| 1 | 1 | Placeholder that should not ship as a product surface |

This count is intentionally unweighted and records the pre-closure census. A destructive account
alert and the Home tab each receive one row even though their product importance is very
different. The closure pass removed every score-1 placeholder and score-2 dormant product surface
from the shipping project, then rebuilt the source-addressable score-3 outliers listed below.

## Five-Star Implementation Closure

The follow-up pass implemented every source-addressable recommendation that was appropriate for
2.3. It did not force every utility or system-owned screen to score 5: in this rubric, 5 means a
distinctive showpiece, while a quiet, predictable editor is usually better product design at 4.
Camera quality, voice naturalness, GPS, HealthKit permission behavior, Watch transport, widgets,
Live Activities, external legal hosting, and signed-build behavior remain evidence-gated because
simulator code cannot prove them.

### Shared Improvements

- Added a shared authored editor shell with stable headers, quiet sections, inline validation,
  keyboard-safe pinned actions, dismissal policy, and compact accessibility behavior.
- Added a shared accessibility breakpoint so primary actions and operational content stay ahead
  of supporting copy at large text sizes.
- Reserved mint for interpreted or recommended content and moved ordinary editable containers
  toward neutral surfaces.
- Extended Trust's evidence grammar to wellness, Health data, Recovery Field, Watch, widgets, and
  Live Activities through source, freshness, missing-data, uncertainty, and action language.
- Replaced indefinite image work with named stages, cancellation, retry, preserved input, and
  review-before-write behavior.
- Added explicit distinctions among zero, unavailable, not supplied, not synced, insufficient
  evidence, and intentionally withheld.

### Re-Graded Surfaces

| IDs | Current score | Closure |
| --- | ---: | --- |
| FR-01 | 4 | Added an intentional dark-green launch background that matches the first SwiftUI frame. |
| FR-14, FR-18 | 4 | Rebuilt first-session choice and compacted the Feature Tour at accessibility sizes. |
| GL-04, GL-09 | 4 | Quick Log now compacts descriptions at large text; image work is staged and cancellable. |
| HM-06, HM-34, HM-38, HM-39 | 4 | Living Day and nested daily editors now use compact authored layouts. |
| FD-05, FD-19, FD-21 | 4 | Search preserves partial provider results; photo/menu review has authored recovery and review states. |
| RP-15 | 4 | Receipt capture now supports shared source choice, staged review, date context, retake, and inline failure. |
| MA-03, MA-04, MA-14, MA-16, MA-17, MA-18 | 4 | Maia preserves prompts, separates offline/service failure, and uses authored consent, voice, and workout-generation surfaces. |
| ST-04, ST-15, ST-16, ST-21, ST-26, ST-27, ST-30, ST-40 | 4 | Training compacts at large text; picker, set, generator, target, swap, and add-exercise flows are now authored and intent-aware. |
| ST-36, ST-37 | 5 | Recovery Field now has selectable front/back anatomy, stable one-row legend, evidence, freshness, uncertainty, and an accessibility list alternative. |
| RN-04 and run/template editors | 4 | Running utility editors use the shared shell and explicit metric intent. |
| RW-21, RW-22, RW-24, RW-34 | 4 | Weight deletion has undo; calculator, wellness, and Health activity expose assumptions and freshness. |
| SE-03, SE-09, SE-16, SE-22, SE-25, SE-27, SE-28, SE-29 | 4 | Settings now has authored calculator/consent states, freshness, mail fallback, and clearer account boundaries. |
| WG-01 through WG-11 | 4 | Widgets distinguish stale, empty, warning, and current data while preserving concise actions. |
| WA-01 through WA-15 | 4 | Watch now exposes freshness, stale/disconnected recovery, queued versus saved actions, and phone handoff. |

### Removed Rather Than Polished

The following unreachable or misleading stacks were removed from source and the Xcode project:

- dormant Community Hub, post, comments, group creation, group selection, and join confirmation;
- dormant AI Journal;
- duplicate dormant Sleep Report stack;
- retired calorie/food logs, meal score/suggestion cards, smart suggestions, and continue-program
  card;
- retired settings legal component, avatar, audio visualizer, circular weight display, generic
  mileage/chart variants, and placeholder Live Activity control;
- unused training metric, completion, empty-state, food-row, suggestion-button, and mileage helpers.

After pruning, no score-1 placeholder or score-2 dormant product surface remains in the shipping
project. Debug galleries and deterministic screenshot routes remain intentionally available only
as QA infrastructure.

## Color And Visual System

### Current Semantic Palette

| Role | Approximate color | Current use | Assessment |
| --- | --- | --- | --- |
| Brand | Green `#43AD6F` | Current tab, primary actions, success, selected states | Strong and recognizable |
| Primary canvas | White / black | Page background | Clean and contemporary |
| Emphasis surface | Pale mint | Important cards, summaries, selected domains | Attractive, currently overused |
| Quiet control | Cool light gray / charcoal | Inputs, inactive tiles, utility controls | Consistent and useful |
| Protein / effort | Blue | Protein, workout effort, report evidence | Clear when labeled |
| Carbohydrate / achievement | Gold | Carbs, achievements, selected training signals | Warm and effective |
| Fat | Purple | Fat progress and nutrition charts | Familiar and legible |
| Hydration / recovery | Teal | Water, recovery, run context | Appropriate and calm |
| Attention | Orange | Trust warning, fuel timing, caution | High-signal; use sparingly |
| Critical | Red | Invalid data, destructive warning, failed checks | Clear and conventional |

### Color Decisions

- Keep green for action, current state, and positive confirmation. Avoid using it as generic
  decoration.
- Keep semantic colors labeled. Color should reinforce the noun beside it, not be the only way to
  decode meaning.
- Reduce mint on screens where the card is merely a container. Use white/gray framing for ordinary
  utility and reserve mint for interpreted or recommended content.
- Permit each major domain one secondary signature:
  - Food and Trust: green plus orange evidence signals.
  - Strength: green plus blue effort.
  - Running and recovery: green plus teal.
  - Planning: green plus gold.
  - Maia: green plus a restrained neutral or teal, not an entire mint conversation.
- New screens should normally use neutrals, brand green, and no more than two labeled semantic
  accents.

## Complete Surface Inventory

## 1. Launch, Authentication, And First Run

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| FR-01 | Generated iOS launch frame | SI, PD | 3 | Bridges icon tap to SwiftUI. The project asks iOS to generate this surface, so the user may see a plain system canvas. | Add an intentional, static launch treatment that matches the first frame of account loading without implying progress. |
| FR-02 | Account loading: normal | SI | 4 | Branded monogram, "Preparing your day," and restrained progress message now match the product. | Verify there is no visible flash from the generated launch frame on older devices. |
| FR-03 | Account loading: recoverable error and retry | SI | 4 | Gives a clear recovery path instead of an indefinite spinner. | Add offline-specific wording if the error can be classified confidently. |
| FR-04 | Welcome | VB | 4 | Calm first impression with direct sign-in and account creation choices. | Maintain a visible hint of product identity beyond the wordmark at smaller sizes. |
| FR-05 | Welcome: dark Accessibility XXXL | VB | 3 | Controls remain reachable, but the composition becomes text-heavy and loses some visual identity. | Use a compact large-text title treatment rather than simply scaling the standard editorial hierarchy. |
| FR-06 | Sign in | VB | 4 | Familiar, uncluttered authentication hierarchy. | Make keyboard progression and password-manager behavior part of physical acceptance. |
| FR-07 | Sign in: validation/network error | SI, PD | 3 | Uses conventional error presentation and preserves the form. | Distinguish invalid credentials from connectivity failure in user language. |
| FR-08 | Password reset confirmation | SI | 3 | Standard alert is sufficient for a brief confirmation. | Avoid exposing whether an address exists in the system. |
| FR-09 | Create account | VB | 4 | Clean form and clear primary action. | "Create your workspace" language feels more like SaaS than a personal health companion. |
| FR-10 | Create account: validation/error | SI, PD | 3 | Conventional and understandable. | Keep errors adjacent to the relevant field where possible, not only in a general alert. |
| FR-11 | Personal setup: baseline | VB | 4 | Establishes goals without overwhelming the user. | Explain why each sensitive answer improves the experience when context is not obvious. |
| FR-12 | Personal setup: lifestyle | VB | 4 | Choice-based interaction is fast and visually coherent. | Confirm all option labels remain unambiguous at large text sizes. |
| FR-13 | Personal setup: units, body data, activity, goals, and menu steps | SI | 4 | Uses one repeated onboarding language, which lowers cognitive load. | Keep step count and progress visible; avoid turning later steps into a long survey. |
| FR-14 | First Session Choice | SI | 3 | Offers immediate logging or import after onboarding. It still uses an older animated-background/card style. | Bring it fully into the current editorial shell and make one option clearly recommended without making import feel secondary or risky. |
| FR-15 | MFP import: entry and instructions | VB | 4 | Honest handoff for users arriving from an incumbent. | Include a privacy note before file selection and a concise supported-format note. |
| FR-16 | MFP import: parsing/progress/success/failure | SI, PD | 3 | Functional state coverage exists. | Show counts, skipped records, and a downloadable/import review summary when partial success occurs. |
| FR-17 | Feature Tour: five product pages | VC | 5 | Now previews Maia, camera review, training, wellness, and planning using the real app language. | Keep screenshots/previews synchronized as flagship screens evolve. |
| FR-18 | Feature Tour: dark Accessibility XXXL | VC | 3 | Action remains reachable but previews and explanatory balance degrade. | Create a deliberate large-text layout with smaller fixed preview height and shorter supporting copy. |
| FR-19 | HealthKit authorization prompt and post-permission return | SI, PD | 3 | System-owned permission UI is expected. | Pre-permission copy must name the user benefit and avoid asking for broad access without context. |
| FR-20 | Notification authorization prompt | SI, PD | 3 | System-owned. | Ask only after a user selects a useful reminder, not as an unexplained first-run interruption. |

## 2. Global Shell And Cross-App Surfaces

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| GL-01 | Main tab bar: Home, Maia, Train, Meal Plan, Reports | VB | 4 | Five equal destinations are stable and easy to learn. The centered Quick Log floats above them. | Check all labels in every supported localization; five tabs leave little width margin. |
| GL-02 | Quick Log: collapsed | VB | 4 | Distinctive outlined plus treatment solves the earlier oversized filled-button problem. | Continue keeping the label and bottom tab labels optically level. |
| GL-03 | Quick Log: expanded action sheet | VB | 4 | Consolidates food, photo, barcode, text, exercise, run, recipes, grocery, and restaurant entry. | Ensure the most common actions stay above the fold and order can respond to actual usage data. |
| GL-04 | Quick Log: dark Accessibility XXXL | VB | 3 | Functional, but the sheet becomes visually dense and slower to scan. | Use shorter action subtitles or hide nonessential descriptions at accessibility sizes. |
| GL-05 | Settings sheet shell | VB | 4 | Consistent close behavior and target-first hierarchy. | Avoid additional top-level settings cards; the surface is approaching its scanning limit. |
| GL-06 | Spotlight tour overlay | SI | 4 | Provides contextual discovery without adding persistent instructional text. | Verify VoiceOver focus is trapped correctly and the highlighted control remains actionable. |
| GL-07 | Spotlight text/action menu | SI | 4 | Lightweight secondary explanation. | Add a persistent replay path only where users commonly miss the feature. |
| GL-08 | In-app notification banner/toast | SI, PD | 4 | Quiet transient feedback matches the product. | Verify banners never cover navigation controls, Dynamic Island safe areas, or the Quick Log button. |
| GL-09 | Loading overlays and image-processing state | SI, PD | 3 | Communicates expensive AI/image work. | Prefer stage language and cancellation over an indefinite generic spinner. |
| GL-10 | Generic confirmation dialogs | SI | 3 | Appropriate for destructive or mutually exclusive choices. | Keep titles action-specific and avoid long explanations inside system dialogs. |
| GL-11 | Generic alerts | SI | 3 | Suitable for short errors and confirmations. | Route recoverable failures back to the relevant inline state instead of relying on alerts alone. |
| GL-12 | Share sheet, mail composer, photo picker, camera picker | SI, PD | 3 | System-owned surfaces are familiar and trustworthy. | Verify presentation/dismissal from every parent sheet so stacked modals do not dead-end. |
| GL-13 | PDF export progress, share, and export error | VB, SI | 4 | Evidence reports can leave the app without losing context. | Include generation date and data boundaries in exported documents. |
| GL-14 | Compact-screen shell | VB | 4 | Primary controls remain reachable on an SE-class viewport. | Recheck any new fixed-width week strip, board, or metric grid before release. |
| GL-15 | Dark mode shell | VB | 5 | One of the strongest presentation states; hierarchy survives without neon styling. | Protect secondary-text contrast as more muted colors are introduced. |

## 3. Home, Living Day, And Daily Logging

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| HM-01 | Living Day Home | VB | 5 | The best expression of the product: a chronological, interpreted day rather than a generic dashboard. | Treat this as the design reference for future surfaces. |
| HM-02 | Living Day: launch transition and return-to-tab restoration | SI, PD | 4 | Preserves the authored entrance and current-day context. | Confirm it reliably reappears after tab navigation without replaying excessive animation. |
| HM-03 | Living Day: prior day | SI | 4 | Supports review without implying future recommendations. | Visually distinguish historical evidence from actions that can still be completed. |
| HM-04 | Living Day: future day | SI | 4 | Supports planning. | Do not show certainty-oriented language for projected events. |
| HM-05 | Living Day: sparse/empty day | SI | 4 | Should orient the user toward one first action. | Avoid filling empty space with multiple equally strong prompts. |
| HM-06 | Living Day: accessibility XXXL | VB | 3 | Still usable, but the editorial opening consumes most of the viewport. | Create a compact accessibility-specific summary that preserves chronology sooner. |
| HM-07 | Living Day share options | VB | 4 | Makes privacy and content selection explicit before sharing. | Keep health-sensitive fields opt-in, not merely removable after preview. |
| HM-08 | Living Day share card | SI, PD | 4 | Extends the identity outside the app. | Verify light/dark exported contrast and long-name handling. |
| HM-09 | Legacy Home rollback path | SI, DR | 3 | Retains the older dashboard in case feature rollout is disabled. | Keep it visually functional while the flag exists, then retire it rather than maintaining two permanent Home systems. |
| HM-10 | Date navigation and streak header | VB | 4 | Clear temporal anchor. | Streak should remain motivational context, not compete with the day's actual state. |
| HM-11 | Calories and macro progress page | VB | 4 | Familiar nutrition read with clear semantic colors. | Show both consumed and goal, not only remaining, in every compact state. |
| HM-12 | Water progress and quick adjustment | SI, PD | 4 | Restores a crucial daily action to Home. | Confirm haptic feedback, unit conversion, undo, and accidental double-tap behavior. |
| HM-13 | Micronutrient progress page | SI | 4 | Important differentiator when data exists. | Make missing data visually distinct from zero intake and expose coverage quality. |
| HM-14 | Nutrition inconsistency notice | SI | 4 | Protects the user from totals built on suspect food data. | Link directly to the exact entries and fields responsible. |
| HM-15 | Daily food diary: grouped meals | SI | 4 | Familiar operational log beneath the interpreted summary. | Maintain a clear distinction between planned, estimated, and confirmed food. |
| HM-16 | Daily food diary: empty | SI | 4 | Provides an obvious first log action. | Avoid duplicating Quick Log with several equally prominent empty-state buttons. |
| HM-17 | Food row: detail navigation and swipe actions | SI, PD | 4 | Efficient editing while preserving detail access. | Verify destructive swipes have undo and remain discoverable without relying on gestures. |
| HM-18 | Exercise row: detail, edit, and deletion | SI, PD | 4 | Keeps activity integrated with food. | Differentiate imported Health activity from manually logged exercise. |
| HM-19 | Quick Actions section | VB | 4 | Puts remaining-day tasks near the first viewport. | Limit to genuinely high-value actions; it is the most likely area to accumulate clutter. |
| HM-20 | Review Food Trust entry point | VB | 5 | Makes the differentiator visible in daily life rather than hiding it inside food detail. | Preserve one concise status and avoid turning Home into a Trust dashboard. |
| HM-21 | Trust Hub: evidence map | VC | 5 | Distinguishes product identity, serving, core nutrition, and detailed nutrition at a glance. | Add compact definitions for documented versus independently corroborated evidence. |
| HM-22 | Trust Hub: review-needed list | VC | 5 | Converts uncertainty into a concrete correction queue. | Keep highest-impact fields first and show how corrections affect daily totals. |
| HM-23 | Trust Hub: no-review state | SI | 4 | Rewards completion without claiming perfect truth. | Say "No items need review" rather than implying every field is verified. |
| HM-24 | Coaching Dashboard | SI | 4 | Consolidates interpreted daily guidance. | Ensure it does not duplicate Living Day or Maia with different wording. |
| HM-25 | Detailed Insights: populated | VB | 4 | Evidence-led report with clear export path. | Keep the opening interpretation brief and move methodology into expandable evidence. |
| HM-26 | Detailed Insights: loading, empty, and export error | SI | 3 | Complete operational coverage. | Use skeletons that preserve final layout and a useful empty-state action. |
| HM-27 | Weekly Recap: populated | SI | 4 | Summarizes adherence, training, and Trust. | Avoid over-crediting incomplete logging; state the evidence window. |
| HM-28 | Weekly Recap: loading, empty, and share options | SI | 4 | Complete lifecycle. | Keep share preview private by default. |
| HM-29 | Week In Motion | VB | 5 | Distinctive weekly visual that joins training and food coverage. | Add a legend or tap explanation for every icon and state. |
| HM-30 | Week In Motion day-detail sheet | SI | 4 | Turns the compact timeline into an understandable day receipt. | Include imported/manual source distinctions and clear no-data language. |
| HM-31 | Weekly Check-in full-screen flow | SI, PD | 4 | Captures subjective context and progress. | Keep completion short and avoid medical interpretation. |
| HM-32 | Trend Dashboard | SI | 4 | Provides longitudinal context after the check-in. | Use uncertainty ranges where sparse data would otherwise look precise. |
| HM-33 | Suggestion detail | SI | 4 | Gives one recommendation enough context to be actionable. | State why it appeared and what data was used. |
| HM-34 | Suggestion preferences Form | SI | 3 | Functional control over guidance. | Rebuild with the authored settings surface if this becomes frequently used. |
| HM-35 | Training Fuel planner sheet | SI | 4 | Connects upcoming work to practical food targets. | Keep assumptions visible and offer easy target adjustment. |
| HM-36 | Training Fuel confirmation dialog and destination routing | SI | 3 | Chooses between search, builder, and other follow-up paths. | Use direct labeled actions and avoid nested modal confusion. |
| HM-37 | Meal Suggestion detail | VB | 4 | Fits remaining targets and gives an immediate food action. | Show confidence/estimate status and alternatives for unavailable ingredients. |
| HM-38 | Add Exercise sheet | SI | 3 | Simple manual activity entry. | Current system Form is serviceable but less visually integrated than Home. |
| HM-39 | Edit exercise sheet | SI | 3 | Corrects logged activity. | Clarify whether edits change HealthKit, local data, or both. |
| HM-40 | Weight entry sheet | SI, PD | 4 | Fast numeric update. | Confirm units, decimal keyboard, saved confirmation, and HealthKit write behavior. |
| HM-41 | Fasting sheet | VB | 4 | Cohesive wellness utility. | Avoid implying universal health benefit; surface disclaimer access. |
| HM-42 | MFP import from Home | VB | 4 | Provides an ongoing migration path. | Avoid showing after a successful completed import unless explicitly requested. |
| HM-43 | Past Workout detail from Home | SI | 4 | Maintains continuity between the day and training history. | Match the same evidence labels used in Session Review. |

## 4. Food Search, Entry, Detail, And Trust

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| FD-01 | Food Search: recent/history state | VB | 4 | Familiar starting point with direct logging actions. | Keep recents grouped by user-confirmed versus estimated entries. |
| FD-02 | Food Search: query results | VB | 4 | Grouping and source/trust cues make broad database results manageable. | Explain ranking when a less familiar source outranks a recognizable brand. |
| FD-03 | Food Search: loading | SI | 4 | Preserves search structure while sources resolve. | Show which sources are still being checked only when that helps, not as technical noise. |
| FD-04 | Food Search: no results | SI | 4 | Provides manual, barcode, photo, and text recovery paths. | Recommend the best next method based on the query instead of presenting every option equally. |
| FD-05 | Food Search: network/provider failure | SI, PD | 3 | Search can fail partially across providers. | Preserve successful local/provider results and identify partial coverage without exposing backend jargon. |
| FD-06 | Food Search: compact meal picker | SI | 4 | Keeps quick logging in context. | Maintain stable selection when sheets open and close. |
| FD-07 | Food Search action grid | SI | 4 | Surfaces barcode, photo, text, manual, builder, My Foods, and value tools. | Limit first-row actions to the most common methods; advanced restaurant tools can live under More. |
| FD-08 | Yesterday log actions | SI | 4 | Speeds repeated meals. | Make date and serving reuse explicit before commit. |
| FD-09 | Barcode Scanner: active | SI, PD | 4 | Focused full-camera task with clear framing. | Verify torch, one-handed reach, duplicate scan suppression, and VoiceOver alternative. |
| FD-10 | Barcode Scanner: permission denied/unavailable | SI, PD | 3 | Must recover to Settings or manual entry. | Use a direct Settings action and preserve the scanned/logging context. |
| FD-11 | Barcode Miss Recovery | SI | 4 | Converts a miss into manual correction, contribution, or alternate search. | Explain how a community contribution will be reviewed and reused. |
| FD-12 | Scan error alert | SI | 3 | Short recovery message. | Differentiate unreadable code, network failure, and unknown product. |
| FD-13 | Manual Food: blank | VB | 4 | Current editor is responsive and considerably more polished than a default Form. | Keep required fields obvious without making optional micronutrients look unimportant. |
| FD-14 | Manual Food: barcode-seeded correction | SI | 4 | Preserves product identity while inviting correction. | Show whether saving updates only My Foods or also submits a community correction. |
| FD-15 | Manual Food: label-photo loading/error/result | SI, PD | 4 | Useful AI-assisted entry with review before save. | Highlight low-confidence or missing fields and never silently retain stale nutrient values. |
| FD-16 | Manual Food: preview and save | VB | 4 | Gives a final sanity check. | Include serving conversion and source/provenance before commit. |
| FD-17 | Quick Add Macros | VB | 4 | Fast fallback when only totals are known. | Label the entry as macro-only so micronutrient reports do not treat missing values as zero. |
| FD-18 | Menu Scanner | SI, PD | 4 | Camera path for restaurant menus. | Allow crop/retake and clearly separate detected text from generated nutrition estimates. |
| FD-19 | Photo estimate processing | SI, PD | 3 | Expensive operation is visible. | Add cancel, retry, and a clear statement that portions require user review. |
| FD-20 | AI photo summary/review | SI | 4 | Review-first design is responsible and editable. | Show uncertainty per item and preserve the original image while editing. |
| FD-21 | AI menu item selection | SI | 3 | Lets users select from detected menu items. | A standard List works, but a more authored scan-review layout would feel more premium. |
| FD-22 | AI Text Log: prompt | VB | 4 | Low-friction natural language entry. | Add examples without making the screen instructional or cluttered. |
| FD-23 | AI Text Results: editable estimate | VB | 4 | Strong review-before-log behavior. | Surface per-item confidence and detect internally inconsistent totals. |
| FD-24 | AI Text Results: item edit and removal | VB | 4 | User retains control over the estimate. | Keep removed items recoverable until final log. |
| FD-25 | Food Detail: loading | SI | 4 | Uses a dedicated card rather than layout collapse. | Ensure the final page does not jump dramatically after loading. |
| FD-26 | Food Detail: identity and serving hero | VB | 4 | Product, source, and serving establish context immediately. | Always show the normalization basis when database serving and user serving differ. |
| FD-27 | Food Detail: macro and micronutrient detail | VB | 4 | Clear nutrition hierarchy. | Explicitly distinguish absent, not provided, estimated, and zero micronutrients. |
| FD-28 | Food Detail: Trust Receipt | VB | 5 | The clearest category-level differentiator in the app. | Add a compact fingerprint at the top while keeping full evidence below. |
| FD-29 | Food Detail: source convergence details | SI | 5 | Can show agreement across USDA, FatSecret, Health Canada, NIH, and user evidence. | Make convergence inspectable by source and field without converting it into false certainty. |
| FD-30 | Food Detail: correction sheet | SI | 4 | Gives the user a direct route from warning to correction. | Include every field that can trigger a warning, especially total fat and saturated fat together. |
| FD-31 | Food Detail: label scan action | SI, PD | 4 | Lets packaging evidence improve a weak record. | Make stale versus replaced values explicit before save. |
| FD-32 | Food Detail: barcode memory/contribution action | SI | 4 | Builds future database coverage. | Show contribution status and whether independent moderation has occurred. |
| FD-33 | Food Detail: scan error and notice cards | SI | 3 | Keeps failures in context. | Use inline recovery where possible instead of separate alerts. |
| FD-34 | Food Detail: add-to-log action bar | VB | 4 | Stable bottom action supports long Trust receipts. | Verify keyboard, sheet, and Dynamic Type clearance. |
| FD-35 | My Foods: populated library | VB | 4 | Operational and grouped, with clear edit/log affordances. | Too many badges can slow scanning; reserve badges for actionable distinctions. |
| FD-36 | My Foods: filter/search/empty | SI | 4 | Complete library lifecycle. | Explain why an item appears under a filter when source categories overlap. |
| FD-37 | My Foods: edit and destructive confirmations | SI | 4 | Corrects personal database records. | Clarify downstream impact on previous logs versus future uses. |
| FD-38 | Fast Food Builder: chain list | VB | 4 | Direct and understandable entry into chain menus. | Database breadth is the main weakness; visually mark incomplete or region-specific menus. |
| FD-39 | Fast Food Builder: menu and customization | SI | 4 | Supports item selection and order composition. | Add category search, modifier provenance, and last-updated date. |
| FD-40 | Fast Food Builder: order review and log | SI | 4 | Converts a restaurant order into a transparent set of items. | Display per-item source and whether modifiers are exact or estimated. |
| FD-41 | Nutrition progress: calories/macros/water/micros | SI | 4 | Shared progress components remain familiar and legible. | Use one consistent consumed/goal/remaining grammar across Home, widgets, and reports. |
| FD-42 | Nutrition consistency warning | SI | 4 | Prevents suspect food data from disappearing into totals. | Let the user inspect exact math and affected reports. |

## 5. Recipes, Pantry, And Grocery

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| RP-01 | Recipe Library: populated | VB | 4 | Strong summary, rows, and direct creation path. | Keep user recipes, generated recipes, and imported recipes visually distinguishable. |
| RP-02 | Recipe Library: empty | SI | 4 | Clear creation action. | Offer manual and photo creation as two explicit methods, not a vague plus. |
| RP-03 | Recipe Library: delete confirmation | SI | 3 | Conventional destructive flow. | Explain whether planned meals or past logs keep a snapshot. |
| RP-04 | Create Recipe: manual | VB | 4 | Clear identity, ingredients, instructions, and nutrition workflow. | Add autosave or draft recovery for long recipes. |
| RP-05 | Create Recipe: photo/import processing and failure | SI, PD | 4 | Useful acceleration with visible processing. | Preserve source image and clearly mark generated fields for review. |
| RP-06 | Ingredient Food Search sheet | SI | 4 | Reuses familiar search inside recipe creation. | Make return context and quantity editing obvious. |
| RP-07 | Recipe Detail | VB | 4 | Strong hierarchy across identity, nutrition, ingredients, and instructions. | Add source/trust summary for ingredients that affect nutrition quality. |
| RP-08 | Edit Recipe | SI | 4 | Uses the same creation language. | Warn when serving changes recalculate existing plan portions. |
| RP-09 | Recipe Logging | VB | 4 | Editable portion and meal selection are clear. | Show estimated versus confirmed nutrition coverage. |
| RP-10 | Add Recipe To Meal Plan | SI | 4 | Supports one day or repeated placement. | Preview collisions with existing planned meals before save. |
| RP-11 | Add Recipe failure | SI | 3 | Alert preserves context. | Provide an inline retry and avoid losing selected day/meal. |
| RP-12 | Pantry: populated | VB | 4 | Cohesive inventory surface with useful generation action. | Add quantity confidence and expiration only if it can remain easy to maintain. |
| RP-13 | Pantry: empty | SI | 4 | Direct first-item or receipt-scan actions. | Explain the value in one sentence, then get out of the way. |
| RP-14 | Pantry item menu/edit/delete | SI | 3 | Functional row utilities. | Consider a dedicated compact editor if quantity and unit complexity grows. |
| RP-15 | Receipt Scanner: camera and permission states | SI, PD | 3 | Useful acquisition path but dependent on physical camera quality. | Add crop/retake, store-date context, and review before pantry mutation. |
| RP-16 | Receipt Review | VB | 4 | Strong review-first hierarchy. | Group probable duplicates and show confidence. |
| RP-17 | Pantry recipe generation: loading/results | VB | 4 | Useful bridge from inventory to action. | Keep the generated status prominent and explain what pantry facts were used. |
| RP-18 | Pantry recipe generation: save error | SI | 3 | Failure is surfaced. | Preserve generated result and allow copy/retry rather than discarding work. |
| RP-19 | Grocery List: shopping run summary | VB | 4 | One of the strongest operational screens; clear counts and progress. | Avoid letting the summary card dominate once the user is actively shopping. |
| RP-20 | Grocery List: populated categories | VB | 4 | Scannable rows and category grouping. | Merge obvious singular/plural duplicates such as Banana/Bananas and Bell Pepper/Bell Peppers. |
| RP-21 | Grocery List: checked items hidden/shown | VB | 4 | Useful shopping control with clear state. | Preserve location in the list when toggled. |
| RP-22 | Grocery List: all complete | SI | 4 | Gives closure without deleting the list automatically. | Offer archive/clear as a secondary action, not an immediate destructive prompt. |
| RP-23 | Grocery List: loading and empty | SI | 4 | Complete lifecycle. | Empty state should distinguish no plan from a completed/cleared run. |
| RP-24 | Manual Grocery Item: add | VB | 4 | Direct editor matches the new system. | Add duplicate detection before save. |
| RP-25 | Manual Grocery Item: edit | SI | 4 | Keeps source and category context. | Make quantity/unit normalization predictable. |
| RP-26 | Grocery barcode scan and fetch error | SI, PD | 3 | Fast packaged-item entry. | Unknown barcode should hand off to manual entry with the code preserved. |
| RP-27 | Grocery row menu | SI | 3 | Provides edit/delete without cluttering the row. | Add undo after deletion. |
| RP-28 | Clear grocery confirmation | SI | 3 | Appropriate use of confirmation dialog. | Offer clear checked items separately from clearing everything. |

## 6. Meal Plan And Meal Preparation

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| MP-01 | Meal Plan: populated weekly view | VC | 4 | The revised hierarchy now feels like a current 2.3 screen and makes the week legible. | Continue reducing repeated card chrome; the page is information-dense. |
| MP-02 | Meal Plan: compact seven-day strip | VC | 4 | Current sizing fits the full week on compact phones. | Lock this with regression screenshots. |
| MP-03 | Meal Plan: accessibility week cards | VC | 3 | Wider cards prevent clipping, but the page becomes long quickly. | Use a compact day selector at accessibility sizes and move detail below. |
| MP-04 | Meal Plan: loading | SI | 4 | Dedicated skeleton/state preserves structure. | Avoid a one-second blank or late pop-in after tab selection. |
| MP-05 | Meal Plan: empty | SI | 4 | Clear routes to generation or manual addition. | Recommend one starting method based on whether the user has recipes/pantry data. |
| MP-06 | Meal Plan: day and meal card actions | SI, PD | 4 | Supports edit, log, replace, and preparation. | Keep the action menu consistent across generated and manually added meals. |
| MP-07 | Meal Plan: grocery handoff | VB | 4 | Strong connection between planning and execution. | Ask whether to replace, merge, or archive an existing grocery run. |
| MP-08 | Add Meal To Plan: results | SI | 4 | Lets users place saved recipes and relevant foods. | Make source type and nutrition coverage visible. |
| MP-09 | Add Meal To Plan: loading/empty/no matches | SI | 4 | Complete states. | Empty state should route directly to recipe creation without losing day/meal context. |
| MP-10 | Add Meal To Plan: add failure | SI | 3 | Error is surfaced. | Keep the selection and provide inline retry. |
| MP-11 | Meal Plan Survey: step 1 proteins | VB | 4 | Clear selection language and progress. | The fixed option set should not imply it is exhaustive; custom entry needs reliable affordance. |
| MP-12 | Meal Plan Survey: carbohydrates, vegetables, extras, cuisine | SI | 4 | Repeated interaction reduces effort. | Normalize singular/plural ingredient naming before grocery creation. |
| MP-13 | Meal Plan Survey: cooking style | VB | 4 | Stronger than the prior design and easy to compare. | Make time/effort implications concrete. |
| MP-14 | Meal Plan Survey: generation loading | SI, PD | 3 | Communicates work in progress. | Show cancellable stages and preserve selections if generation fails. |
| MP-15 | Meal Plan Survey: success/failure alert | SI | 3 | Functional conclusion. | Success should transition directly to the saved plan; failure should remain in context, not rely only on an alert. |
| MP-16 | Vision recipe/image result | SI, PD | 4 | Turns a meal image into plan candidates. | Review confidence and ingredients before insertion. |
| MP-17 | Image analysis error | SI | 3 | Recoverable. | Include retake, alternate method, and preserved day context. |
| MP-18 | Meal Prep: ingredient mode | VB | 4 | Practical pre-cooking checklist. | Allow pantry and grocery status to be distinguished from preparation completion. |
| MP-19 | Meal Prep: step mode | VB | 4 | Clear sequential cooking workflow. | Keep timer and current step visible without covering instructions. |
| MP-20 | Meal Prep: empty state | SI | 4 | Handles incomplete recipes honestly. | Offer recipe edit rather than presenting a dead end. |
| MP-21 | Timer setup sheet | SI, PD | 3 | Standard utility is adequate. | Match the app's number controls and support multiple named timers if meal prep expands. |
| MP-22 | Meal Suggestion | VB | 4 | Practical recommendation grounded in remaining targets. | State whether values are exact recipe data or an estimate. |
| MP-23 | Meal Suggestion: accessibility XXXL | VB | 3 | Reachable but vertically heavy. | Collapse nonessential macro explanation into one compact row. |

## 7. Maia, AI Review, And Voice

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| MA-01 | Maia tab: initial recommendation | VB | 4 | Clear editorial heading, one practical next step, and restrained composer. | The page can feel sparse when there is little context; use purposeful evidence, not decorative cards. |
| MA-02 | Maia tab: conversation history | SI, PD | 4 | Keeps action cards and chat in one continuous record. | Distinguish user questions, Maia interpretation, and executable actions more strongly. |
| MA-03 | Maia: typing/loading | SI, PD | 3 | Standard conversational feedback. | Use a subtle stage indicator for tool-backed work without exposing technical implementation. |
| MA-04 | Maia: error | SI, PD | 3 | Alert/state exists. | Preserve the user's prompt and offer retry; identify offline versus service failure. |
| MA-05 | Maia: clear-chat confirmation | SI | 3 | Appropriate destructive confirmation. | Explain whether saved actions/logged items remain. |
| MA-06 | Maia suggestion buttons | SI | 4 | Accelerate common prompts. | Avoid a permanent horizontal row if suggestions are not contextually relevant. |
| MA-07 | Maia suggestion detail | SI | 4 | Provides evidence and next action. | Use the same "why this" grammar as Trust and wellness. |
| MA-08 | Maia Action Board | SI | 4 | Lets structured actions coexist with conversational text. | Keep at most one primary filled action per card. |
| MA-09 | Maia meal action card | VB | 4 | Converts advice into a reviewable food log. | Nutrition estimate must show source and review status. |
| MA-10 | Maia workout action card | SI | 4 | Makes a plan actionable. | Preview duration, equipment, and training target before commit. |
| MA-11 | Maia water, fast, weight, and fallback cards | SI | 4 | Structured actions reduce ambiguity. | Ensure each action explains where the data will be written. |
| MA-12 | Maia Action Card Gallery: debug | VB, DR | 4 | Useful visual QA harness, not a user surface. | Keep excluded from release navigation. |
| MA-13 | AI data boundary / Health context | SI | 4 | Important transparency around what Maia can use. | Make current permission status and freshness visible. |
| MA-14 | AI Data Consent | VB | 3 | Functionally clear but visually closer to a default Form than the rest of 2.3. | Rebuild as an authored privacy sheet with concise categories and expandable details. |
| MA-15 | Read Aloud control | VB, PD | 3 | Discoverable and aligned with accessibility. | Current system speech still sounds robotic; quality is a product gap rather than a layout defect. |
| MA-16 | Voice selection and preview | VB, PD | 3 | Gives choice and immediate preview. | Group voices by quality/language and identify downloaded/offline availability. |
| MA-17 | Voice unavailable/offline/fallback | SI, PD | 3 | Prevents a dead action. | Explain why a selected voice changed and preserve the user's preference. |
| MA-18 | AI Workout Generator Form | SI | 3 | Capable, but nested system Form/List styling is less distinctive. | Rebuild around equipment, time, goal, and preview as four authored sections. |
| MA-19 | Generated Program Preview | SI | 4 | Review before save is correct. | Show weekly load and exercise substitutions before creation. |
| MA-20 | AI photo/text/menu review flows | VB, SI | 4 | Consistently review-first and appropriately skeptical. | Unify confidence language across every AI ingestion method. |

## 8. Strength Training, Programs, And Recovery

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| ST-01 | Train dashboard: current program | VB | 4 | Professional operational hierarchy with direct continuation. | Protect the first viewport from accumulating analytics cards. |
| ST-02 | Train dashboard: no program | SI | 4 | Provides prebuilt, AI, and manual paths. | Recommend one path based on user experience without hiding alternatives. |
| ST-03 | Train dashboard: completed program/week transition | SI | 4 | Provides closure and next step. | Separate completion celebration from pressure to immediately start another plan. |
| ST-04 | Train dashboard: dark Accessibility XXXL | VB | 3 | Usable but large headings and cards slow scanning. | Use compact accessibility summaries and retain primary workout action near the top. |
| ST-05 | Workout History: populated | VB | 4 | Strong evidence hierarchy and clear route to session detail. | Add source distinctions for manual, Watch, and imported workouts. |
| ST-06 | Workout History: loading, empty, filtered no matches | SI | 4 | Complete states. | Empty-state action should reflect whether no workouts exist or a filter removed them. |
| ST-07 | Session Review / Workout Complete | VB | 5 | One of the strongest screens; performance, effort, recovery, and Trust read as one system. | Keep celebration subordinate to useful evidence. |
| ST-08 | Session Review: PRs, insights, and recovery meal | SI | 4 | Gives accomplishment and practical follow-through. | Explain PR comparison window and estimate assumptions. |
| ST-09 | Session Review: nutrition audit and workout editor | SI | 4 | Allows correction without leaving the context. | Preserve original imported values in an audit trail. |
| ST-10 | Past Workout Detail | SI | 4 | Supports historical review and editing. | Use the same labels and ordering as Session Review. |
| ST-11 | Program List: populated | VB | 4 | Clear saved-program hierarchy. | Make active, archived, and template status visually distinct. |
| ST-12 | Program List: empty/menu/delete | SI | 4 | Complete management states. | Add undo for deletion and avoid burying duplication under a menu. |
| ST-13 | Program Builder | VB | 4 | Coherent authored form for program identity and routines. | Autosave long edits and show unsaved state. |
| ST-14 | Routine Builder | VB | 4 | Strong hierarchy for exercises and sets. | Keep drag/reorder accessible without gesture-only operation. |
| ST-15 | Exercise Picker | SI | 3 | Functional selection/search surface. | A standard sheet/list feels less premium; add muscle/equipment filters with clear chips. |
| ST-16 | Exercise Set Editor | SI | 3 | Complete detail editing. | Reduce field density and use steppers/segmented controls where values are constrained. |
| ST-17 | Program Detail | VB | 4 | Good weekly evidence, schedule, and routine access. | Keep calendar and routine actions visually distinct. |
| ST-18 | Program Calendar | SI | 4 | Provides scheduling context. | Explicitly show completed, planned, skipped, and rescheduled states. |
| ST-19 | Prebuilt Program Catalog | SI | 4 | Familiar browse/filter model. | Add transparent level/equipment/time comparisons. |
| ST-20 | Prebuilt Program: empty/error/detail/start-date | SI | 4 | Complete lifecycle. | Avoid a generic error page when cached programs remain usable. |
| ST-21 | AI Workout Generator and preview | SI | 3 | Useful alternate program path. | Same authorship gap as Maia's generator Form. |
| ST-22 | Live Workout Player: strength | VB | 5 | Credible beside dedicated workout trackers; dense but operational. | Preserve speed above decorative interpretation during an active set. |
| ST-23 | Live Workout Player: cardio/flexibility | SI, PD | 4 | Adapts the same shell to other exercise types. | Verify controls do not assume reps/weight when duration or distance is primary. |
| ST-24 | Live Workout: rest state and timer | SI, PD | 4 | Clear temporal state with skip control. | Verify background/Live Activity synchronization and stale-state recovery. |
| ST-25 | Live Workout: restored state | SI, PD | 4 | Resumes recent sessions and now discards impossible stale/future timers. | Physically test app termination, reboot, and cross-midnight restoration. |
| ST-26 | Live Workout: target-reps alert | SI | 3 | Quick numeric edit. | Inline editing may be faster and more visually integrated. |
| ST-27 | Swap Exercise sheet | SI | 3 | Functional List-based substitution. | Show why alternatives match equipment/muscle intent. |
| ST-28 | Exercise Note sheet | SI | 3 | Useful lightweight context. | Surface the note on the next occurrence without interrupting flow. |
| ST-29 | Exercise History sheet | SI | 3 | Gives prior performance. | Use the same chart language as the dedicated trend screen. |
| ST-30 | Add Exercise during workout | SI | 3 | Preserves flexibility. | Keep the active session visible enough that users trust it was not lost. |
| ST-31 | Plate Calculator | VB | 4 | Useful, visually integrated strength utility. | Keep loading convention and unit assumptions explicit. |
| ST-32 | Plate Math detail | VB | 4 | Explains how a loading result was produced. | Show bar weight and available plates at the top. |
| ST-33 | Finish/discard workout dialogs | SI | 3 | Appropriate confirmation points. | Make "finish" and "discard" visually and linguistically impossible to confuse. |
| ST-34 | Exercise History full screen | SI | 4 | Dedicated longitudinal evidence. | Include set quality and unit changes in chart interpretation. |
| ST-35 | Exercise Trend chart | SI | 4 | Useful progress visualization. | Avoid implying trend when sample count is too low. |
| ST-36 | Recovery Field: front/back body | VC | 4 | The slimmer current silhouette is clearer than the old bulky body and supports direct region selection. | Continue refining anatomy, overlap, and pose so it feels premium rather than schematic. |
| ST-37 | Recovery Field: selected-muscle evidence panel | VC | 5 | Interaction is strong: selection changes the explanatory card and exposes evidence. | Add freshness and uncertainty in a compact line. |
| ST-38 | Recovery Field: no evidence/fully recovered/high load | SI | 4 | Semantic states exist. | Ensure gray means unknown rather than recovered, and never rely on color alone. |
| ST-39 | Recovery Field: dark/compact | VC | 4 | Maintains clarity across appearance and viewport. | Verify smallest tap targets on actual devices. |
| ST-40 | Recovery Field: Accessibility XXXL | VC | 3 | Heading and explanatory copy push the interactive body below the first viewport. | Start with the selected-region summary or compact heading at accessibility sizes. |
| ST-41 | Shoe Manager: populated | SI | 4 | Useful running/gear utility with mileage context. | Add clear active/default shoe status. |
| ST-42 | Shoe Manager: empty | SI | 4 | Direct first-shoe action. | Explain why tracking matters in one sentence. |
| ST-43 | Add Shoe | VC | 4 | Current custom editor now matches the app and corrects the old generic Form outlier. | Physically verify decimal keyboard and metric conversion. |
| ST-44 | Shoe row menu/edit/delete | SI | 3 | Functional management. | Add retirement/archive so old mileage history is not lost. |

## 9. Running

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| RN-01 | Run History: populated | VB | 4 | Clean history with strong summary and map access. | Distinguish outdoor, treadmill, imported, and guided runs. |
| RN-02 | Run History: empty | SI | 4 | Direct start action. | Offer an honest walking option and avoid assuming every user is a runner. |
| RN-03 | Run start/workout picker sheet | SI, PD | 3 | Chooses free run or a saved guided workout. | Rebuild the standard sheet into a compact, high-confidence start surface. |
| RN-04 | Treadmill entry sheet | SI, PD | 3 | Manual indoor logging. | Current Form is functional but visually less authored; clarify active versus total calories. |
| RN-05 | Run template editor | SI | 3 | Builds guided sessions. | Segment warm-up, work, recovery, and cooldown visually. |
| RN-06 | Run step template editor | SI | 3 | Detailed interval configuration. | Constrained values should use controls rather than free text wherever possible. |
| RN-07 | Run Recorder: ready/start | SI, PD | 4 | Focused pre-run state. | Confirm GPS quality, HealthKit status, and selected workout before start. |
| RN-08 | Run Recorder: active | SI, PD | 4 | Essential metrics remain prominent. | Keep controls operable in sunlight, rain, and one-handed use. |
| RN-09 | Run Recorder: paused/resume/end | SI, PD | 4 | Clear state transition is safety-critical. | Use strong color and haptics without making accidental End too easy. |
| RN-10 | Guided-run card and current interval | SI, PD | 4 | Adds coaching context without replacing core metrics. | Voice/haptic cue quality requires physical acceptance. |
| RN-11 | Run result card | SI, PD | 4 | Confirms distance, duration, and save path. | Explain any GPS trimming or HealthKit reconciliation. |
| RN-12 | Nothing-to-save/discard alert | SI | 3 | Prevents empty records. | Preserve route/workout selection after dismissal. |
| RN-13 | Run Detail: summary | VB | 5 | Professional and comparable to established fitness products. | Add source/freshness for imported metrics. |
| RN-14 | Run Detail: standard map | VB | 4 | Familiar route context. | Provide privacy-aware route cropping for sharing. |
| RN-15 | Run Detail: pace heatmap | VB | 4 | Useful visual comparison. | Include a legend and avoid over-reading GPS pauses as pace changes. |
| RN-16 | Run Detail: heart-rate zones | VB | 4 | Clear semantic distribution. | Explain zone model and missing-HR behavior. |
| RN-17 | Run Detail: glycogen/fuel impact | VB | 4 | Distinctive link between training and nutrition. | Keep estimate assumptions and uncertainty visible. |
| RN-18 | Run Detail: splits and negative-split insight | VB | 4 | Strong familiar running analysis. | Use one unit consistently and explain partial split handling. |
| RN-19 | Run Detail: no route/no HR/no zones | SI | 4 | Must remain honest when sensors are absent. | Replace blank charts with a concise reason and useful alternative, not inferred data. |
| RN-20 | Run recovery Food Search | SI | 4 | Directly connects analysis to action. | Carry the exact target and time window into search. |
| RN-21 | Run Story Poster | SI, PD | 4 | Shareable visual extension. | Default to privacy-safe maps and allow metric selection. |
| RN-22 | Run Map: all routes | SI | 4 | Provides geographic history. | Add date/filter controls and clear map privacy behavior. |
| RN-23 | Running: dark Accessibility XXXL | VB | 3 | Summary remains legible, but card scale slows navigation. | Compact large-text summary and preserve start action. |

## 10. Reports, Trends, And Wellness

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| RW-01 | Reports tab: populated | VB | 4 | Unified weekly interpretation with clear supporting sections. | Keep the opening statement grounded in logging coverage. |
| RW-02 | Reports: loading | SI | 4 | Dedicated state prevents a blank delayed pop-in. | Match skeleton geometry to final content. |
| RW-03 | Reports: empty/message | SI | 4 | Explains what data is needed. | Route to the one most useful action rather than listing every missing input. |
| RW-04 | Week In Motion weekly strip | VB | 5 | Memorable and compact visual summary. | Every icon needs an accessible label and tap explanation. |
| RW-05 | Week In Motion day sheet | SI | 4 | Expands icons into evidence. | Include data source and logging coverage. |
| RW-06 | Training rhythm | VB | 4 | Clear activity cadence. | Avoid double-counting strength and runs when a day contains both. |
| RW-07 | Fuel coverage | VB | 4 | Makes food logging relevant to training. | State whether "logged" means any food or sufficient coverage. |
| RW-08 | Recovery timing/follow-through | VB | 4 | Original connection between run/workout and post-training food. | Avoid judgment when a target was not generated or data was unavailable. |
| RW-09 | Trust coverage | VB | 5 | Extends data quality into longitudinal reporting. | Separate reviewed items from independently corroborated items. |
| RW-10 | Detailed Insights report | VB | 4 | Strong evidence-led utility. | Keep sections collapsible and export methodology. |
| RW-11 | Weekly Recap report/share | SI | 4 | Practical high-level review. | Do not overstate trends from a single week. |
| RW-12 | Nutrition Trends / Calorie Tracking | VB | 4 | Modern chart and legend treatment. | Charts are color-dense; labels and pattern/shape cues must remain primary. |
| RW-13 | Nutrition Trends: empty and sparse data | SI | 4 | Dedicated chart empty state exists. | Require minimum sample count before showing a trend line. |
| RW-14 | Nutrition Trends: micronutrients | SI | 4 | Valuable completeness view. | Show data coverage beside intake so missing provider data is not mistaken for deficiency. |
| RW-15 | Adaptive Metabolism: valid estimate | SI | 4 | Differentiating analytical model with clear progress rows. | Show sample window and uncertainty range. |
| RW-16 | Adaptive Metabolism: withheld implausible estimate | VB | 5 | Excellent trust-preserving guardrail. | Keep explicit actions for repairing logging coverage. |
| RW-17 | Adaptive Metabolism: loading/error/insufficient data | SI | 4 | Complete honest lifecycle. | Never show a placeholder estimate while data is being evaluated. |
| RW-18 | Workout Analytics | SI | 4 | Summarizes volume, frequency, muscle groups, and trends. | Use the same training semantic colors and definitions as session review. |
| RW-19 | Weight Progress | VB | 4 | Clear current, goal, and chart hierarchy. | Avoid celebrating rapid change without health context. |
| RW-20 | Weight entry and target sheets | SI, PD | 4 | Direct editing and goal management. | Explain whether goal changes affect calorie targets immediately. |
| RW-21 | Weight delete confirmation | SI | 3 | Appropriate destructive alert. | Add undo when feasible. |
| RW-22 | Caloric Calculator | SI | 3 | Useful standard calculation. | Current Form is visually less authored and should foreground assumptions, not just result. |
| RW-23 | Wellness card | VB | 4 | Consolidates sleep, activity, nutrition, and subjective evidence. | Keep score caveats visible and avoid medical framing. |
| RW-24 | Wellness Debrief / detail | VB | 4 | Strong evidence hierarchy and actionable interpretation. | Show freshness and missing inputs near the score. |
| RW-25 | Wellness signal rows | SI | 4 | Allows inspection of each contributor. | Let users distinguish unavailable from unfavorable. |
| RW-26 | Nutrition evidence section | SI | 4 | Connects Trust and logging coverage to wellness. | Avoid circular scoring where one weak entry affects several signals invisibly. |
| RW-27 | Sleep evidence and stage distribution | SI | 4 | Useful HealthKit context. | Label consumer sensor limitations and missing-stage behavior. |
| RW-29 | Cycle Phase | VB | 4 | Clear ring and phase explanation. | Keep all predictions explicitly estimated and private. |
| RW-30 | Cycle Settings | SI, PD | 3 | Functional configuration. | Use an authored editor and explain impact of each input. |
| RW-31 | Cycle menu/actions | SI | 3 | Compact utilities. | Avoid hiding important privacy or reset actions in an unlabeled menu. |
| RW-32 | Fasting | VB | 4 | Cohesive and visually calm. | Keep disclaimer and stop action easy to reach. |
| RW-33 | Fasting menu/preset states | SI, PD | 3 | Functional state selection. | Avoid gamifying longer fasts. |
| RW-34 | Health Activity card | SI, PD | 4 | Brings steps/activity into the wellness story. | Show HealthKit freshness and source device. |
| RW-35 | Health Disclaimer | VB | 4 | Clear, readable boundary-setting. | Link from every analytical surface that could be interpreted medically. |
| RW-36 | Plate Calculator | VB | 4 | Useful macro composition tool with clear hierarchy. | Clarify whether targets are grams, percentages, or meal-specific allocations. |
| RW-37 | Plate Math / Set Plate Loading | VB | 4 | Explains the recommendation instead of hiding the math. | Keep assumptions visible at the top. |
| RW-38 | Reports: dark Accessibility XXXL | VB | 3 | Important sections remain reachable but weekly headline dominates. | Use a concise accessibility-specific summary and move detailed prose below. |

## 11. Settings, Account, Privacy, And Support

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| SE-01 | Settings main | VB | 4 | Target-first organization and authored section cards feel coherent. | It is near the practical density limit; keep rarely used tools under clearly named subpages. |
| SE-02 | Goals/calorie targets | VB | 4 | Clear current targets and edit route. | Show whether targets are manual, calculated, or adaptively adjusted. |
| SE-03 | Caloric Calculator from Settings | SI | 3 | Functional calculation path. | Same authorship and assumptions gap as Reports. |
| SE-04 | Height editor | VB | 4 | Custom surface is clean and direct. | Verify unit switching never changes stored value unexpectedly. |
| SE-05 | Water goal editor | VB | 4 | Cohesive, visual, and easy to understand. | Avoid presenting a universal ideal; frame as a user target. |
| SE-06 | Appearance controls | SI, PD | 4 | Standard light/dark/system choice. | Preview should update immediately and persist reliably. |
| SE-07 | Units controls | SI, PD | 4 | Familiar segmented/menu behavior. | Confirm every dependent screen updates and values are converted, not reinterpreted. |
| SE-08 | HealthKit integration: unauthorized | SI, PD | 4 | Gives a direct permission path. | Explain read versus write benefits separately. |
| SE-09 | HealthKit integration: authorized/sync status | SI, PD | 4 | Confirms connection. | Add last successful sync and source freshness. |
| SE-10 | Notification preferences | SI, PD | 4 | Groups daily, hydration, weigh-in, and training-fuel reminders. | Show system authorization status and prevent toggles from appearing active when blocked at OS level. |
| SE-11 | Quiet hours | SI, PD | 3 | Functional time controls. | Validate overnight ranges and timezone changes. |
| SE-12 | Training effort picker | SI | 4 | Lets users shape program guidance. | Explain the behavioral impact of each choice. |
| SE-13 | Maia tone | SI | 4 | Personalizes written style. | Keep examples short and ensure tone never changes safety boundaries. |
| SE-14 | Maia voice and preview | VB, PD | 3 | Choice is present, but voice realism remains below premium assistants. | Improve provider/voice quality or position read-aloud as accessibility rather than human conversation. |
| SE-15 | Nutrition Data Sources | SI | 4 | Important transparency around USDA, FatSecret, Health Canada, NIH, and community evidence. | Show current availability, scope, and last successful provider contact without exposing implementation noise. |
| SE-16 | AI Data Consent | VB | 3 | Complete privacy controls but visually generic. | Rebuild as an authored consent receipt with concise categories and expandable policy detail. |
| SE-17 | Health Disclaimer | VB | 4 | Clear legal/health boundary. | Keep language readable and specific to actual features. |
| SE-18 | Export data and system share | SI, PD | 4 | Gives user control over their information. | Show export scope, format, progress, and failure recovery. |
| SE-19 | MFP Import | VB | 4 | Useful account migration path. | Preserve detailed import receipt. |
| SE-20 | Privacy Policy external page | SI, PD | 3 | Public GitHub-hosted policy is reachable. | A dedicated stable web domain would feel more professional and avoid repository chrome. |
| SE-21 | Terms external page | SI, PD | 3 | Reachable legal document. | Same hosting concern as Privacy Policy. |
| SE-22 | Feedback mail composer | SI, PD | 3 | Direct support path. | Provide an in-app fallback if Mail is not configured. |
| SE-23 | Share app activity sheet | SI, PD | 3 | Familiar system behavior. | Use current App Store URL and concise share copy. |
| SE-24 | Replay Feature Tour confirmation | SI | 3 | Clear reversible preference. | Start the tour immediately after confirmation and preserve return context. |
| SE-25 | Sign out confirmation | SI, PD | 3 | Appropriate destructive boundary. | Explain which local data remains or is cleared. |
| SE-26 | Delete account confirmation | SI, PD | 4 | High-friction by design and clearly destructive. | Keep timeline, scope, and irreversible effects explicit. |
| SE-27 | Delete account reauthentication | SI, PD | 3 | Required security step. | Support current auth provider rather than assuming password-only reauthentication. |
| SE-28 | Delete account progress/error | SI, PD | 3 | Communicates a long destructive operation. | Never leave the user in an ambiguous half-deleted state; provide support reference on failure. |
| SE-29 | Settings: dark Accessibility XXXL | VB | 3 | Reachable but section headers and rows become slow to scan. | Collapse explanatory copy and keep control labels concise. |

## 12. Restaurant And Distinctive Nutrition Tools

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| RT-01 | AYCE Start | VB | 5 | Original, memorable framing for a difficult logging context. | Keep purpose and estimate limitations clear. |
| RT-02 | AYCE Start: restored draft | SI, PD | 4 | Prevents accidental loss of an active session. | Clearly identify age and state of restored data. |
| RT-03 | AYCE Live Session | VB | 5 | Strong active-session hierarchy with progress and catalog. | Keep interaction fast and one-handed. |
| RT-04 | AYCE scanner | SI, PD | 4 | Adds plates through camera capture. | Review duplicate plate detection and low-light behavior. |
| RT-05 | AYCE Plate Review | VB | 4 | Review-first design protects against overconfident estimates. | Make portion uncertainty and editable items prominent. |
| RT-06 | AYCE Plate Draft Editor | SI | 4 | Supports correction before commit. | Keep field count manageable and preserve image context. |
| RT-07 | AYCE Summary | VB | 5 | Distinctive recap without pretending restaurant estimates are exact. | Avoid moralizing language around intake. |
| RT-08 | AYCE Celebration overlay | VB | 5 | Expressive and memorable while still connected to the product. | Reserve for meaningful completion so it stays special. |
| RT-09 | AYCE dark Accessibility XXXL family | VB | 3 | Usable, but editorial titles push active controls below the fold. | Use compact mode-specific headers for active tasks. |
| RT-10 | Restaurant Value Radar | VB | 5 | Another original concept with a strong decision-oriented hierarchy. | Keep the comparison basis and uncertainty visible. |
| RT-11 | Value Radar image picker and item review | SI, PD | 4 | Supports camera-assisted restaurant comparison. | Separate menu facts from estimated nutrition. |
| RT-12 | Value Radar demo | VB, DR | 4 | Clearly labeled demo data is useful for QA and presentation. | Keep unreachable in production navigation unless explicitly framed as a sample. |
| RT-13 | Value Radar dark Accessibility XXXL | VB | 3 | Functional but extremely tall. | Prioritize the winning comparison and defer detailed explanation. |
| RT-14 | Celebration demo | VB, DR | 4 | QA harness. | Keep debug-only. |

## 13. Profile, Challenges, And Removed Community Prototypes

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| CM-01 | User Profile | VB | 4 | Clear progress identity and route to challenges. | Decide whether this is a private progress profile or future social identity; the current app suggests both. |
| CM-02 | Challenges | VB | 4 | Cohesive progress surface. | Explain challenge source, rules, and privacy before social expansion. |
| CM-03 | Profile/Challenges dark Accessibility XXXL | VB | 3 | Usable but oversized. | Apply the same compact large-text strategy as Reports and Home. |

The unshipped Community Hub, posting, comments, group creation, group selection, and join
confirmation prototypes were removed during closure. They are no longer part of the source or
Xcode target and do not represent deferred 2.3 UI debt.

## 14. Debug And Visual-QA Surfaces

These views are intentionally reachable only through debug screenshot routing. They are valuable
for design review and regression capture, but they are not production product destinations.

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| QA-01 | App Visual System Gallery | VB, DR | 5 | Central reference for typography, palette, controls, surfaces, and component behavior. | Keep updated whenever a token or reusable component changes. |
| QA-02 | Living Day Prototype Gallery | SI, DR | 4 | Preserves rail, timeline, clock, budget, action, and evidence experiments. | Archive rejected concepts clearly so old prototypes do not re-enter production accidentally. |
| QA-03 | Maia Action Card Gallery | VB, DR | 4 | Compares every structured Maia action state in one place. | Add failure, disabled, and long-localized-copy variants. |
| QA-04 | AYCE Plate Review Demo | VB, DR | 4 | Deterministic review state for restaurant QA. | Keep seeded data visibly fictional and aligned with the current editor. |
| QA-05 | Restaurant Value Radar Demo | VB, DR | 4 | Deterministic restaurant comparison for screenshots. | Keep the demo banner unmistakable. |
| QA-06 | Celebration Overlay Demo | VB, DR | 4 | Exercises motion and completion styling without a full workflow. | Include Reduce Motion and high-contrast variants. |
| QA-07 | Direct screenshot routes for Trust, recovery, planning, reports, and settings | VB, DR | 5 | Make hard-to-seed states repeatable and were essential to this audit. | Continue treating screenshot routes as test infrastructure with no production entry point. |

## 15. Widgets

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| WG-01 | Small widget: populated legacy summary | SI, PD | 4 | Compact calories/protein glance. | Align consumed/goal/remaining language with Home. |
| WG-02 | Small widget: Living Day next action | SI, PD | 4 | Extends the daily interpretation to the Home Screen. | Test truncation for every action kind and large accessibility settings. |
| WG-03 | Medium widget: macros, water, path, and action | SI, PD | 4 | Good balance of glance and utility. | Avoid crowding when both path and action are present. |
| WG-04 | Large widget: full day path | SI, PD | 4 | Most complete extension of Living Day. | Keep event count limited and privacy-safe. |
| WG-05 | Accessory circular | SI, PD | 4 | Appropriate calorie progress glance. | Verify zero-goal and over-goal rendering. |
| WG-06 | Accessory rectangular | SI, PD | 4 | Useful Lock Screen context. | Keep text concise across action kinds. |
| WG-07 | Accessory inline | SI, PD | 3 | Minimal status string. | Test localization and stale-data wording. |
| WG-08 | Empty invite state | SI, PD | 4 | Directs the user to open the app. | Distinguish signed-out, no-today-data, and stale shared storage when possible. |
| WG-09 | Macro inconsistency warning | SI, PD | 4 | Extends Trust protection outside the app. | Do not let warning text crowd out the primary glance. |
| WG-10 | Water App Intent action | SI, PD | 4 | High-value one-tap action. | Test repeated taps, optimistic updates, failure reconciliation, and units. |
| WG-11 | No-next-action state | SI, PD | 4 | Falls back to progress without inventing advice. | Ensure the layout does not leave awkward empty space. |

## 16. Live Activities And Dynamic Island

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| LA-01 | Workout Lock Screen: active set | SI, PD | 4 | Keeps exercise, progress, and elapsed context visible. | Test long exercise names and stale activity cleanup. |
| LA-02 | Workout Lock Screen: resting | SI, PD | 4 | Highlights rest countdown and Skip Rest. | Verify action responsiveness while the app is suspended. |
| LA-03 | Workout Dynamic Island: expanded | SI, PD | 4 | Uses leading/trailing/center/bottom regions appropriately. | Check every exercise/rest state on all Island sizes. |
| LA-04 | Workout Dynamic Island: compact/minimal | SI, PD | 4 | Preserves timer/state at a glance. | Use unmistakable active/rest visual distinction without color alone. |
| LA-05 | Fasting Lock Screen: active | SI, PD | 4 | Shows elapsed/progress and End Fast. | Avoid celebratory pressure around longer durations. |
| LA-06 | Fasting Dynamic Island: expanded | SI, PD | 4 | Clear progress and target. | Confirm End Fast requires an intentional action. |
| LA-07 | Fasting Dynamic Island: compact/minimal | SI, PD | 4 | Concise and appropriate. | Test countdown/elapsed formatting over 24 hours. |
| LA-08 | Run Lock Screen: active | SI, PD | 4 | Essential metrics remain visible. | Confirm GPS and elapsed updates under lock. |
| LA-09 | Run Lock Screen: paused | SI, PD | 4 | Must be visually unmistakable. | Use haptic and text state, not only color. |
| LA-10 | Run Lock Screen: guided step/target | SI, PD | 4 | Extends current interval guidance. | Test long labels and unit switching. |
| LA-11 | Run Dynamic Island: expanded | SI, PD | 4 | Useful glance for an active outdoor task. | Verify readability in sunlight and accidental action prevention. |
| LA-12 | Run Dynamic Island: compact/minimal | SI, PD | 4 | Keeps pace/time state present. | Test paused state and no-GPS state. |
| LA-13 | AYCE Lock Screen: active session | SI, PD | 4 | Original use of Live Activity for plate/session progress. | Protect potentially sensitive intake information on the Lock Screen. |
| LA-14 | AYCE before/after "beat" state | SI, PD | 4 | Gives session progression meaning. | Keep language nonjudgmental. |
| LA-15 | AYCE Dynamic Island: expanded/compact/minimal | SI, PD | 4 | Strong extension of a distinctive workflow. | Test privacy, truncation, and stale session cleanup. |

## 17. Apple Watch

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| WA-01 | Watch Home: populated | VC, PD | 4 | The paired seeded capture is clean and immediately answers "how am I doing today?" with calories and labeled macro gauges. | Show last sync age when data may be stale. |
| WA-02 | Watch Home: no data | SI, PD | 4 | Distinguishes no account data, not-yet-synced data, and stale transport with a phone handoff. | Verify retry and troubleshooting on hardware. |
| WA-03 | Watch next action: pre-workout fuel | SI, PD | 4 | Shows target detail and protein/carbohydrate metrics. | Add freshness and time window. |
| WA-04 | Watch next action: recovery meal | SI, PD | 4 | Practical post-workout guidance. | Keep estimate boundaries concise. |
| WA-05 | Watch next action: protein catch-up | SI, PD | 4 | Clear single-metric action. | Avoid urgency when the day is incomplete or logs are sparse. |
| WA-06 | Watch next action: Trust review | SI, PD | 4 | Extends the differentiator appropriately. | Deep-link to the exact phone queue when possible. |
| WA-07 | Watch next action: steady day | SI, PD | 4 | Honest no-urgent-action state. | Avoid making it look like a completed goal when data is incomplete. |
| WA-08 | Repeat Meal: normal | SI, PD | 4 | High-value repeat action with calorie/item summary. | Show meal age/date and require review if source Trust has changed. |
| WA-09 | Repeat Meal: queued/success/error | SI, PD | 4 | Queued-for-phone, saved, and failed states are explicitly distinct. | Verify offline replay and duplicate prevention on hardware. |
| WA-10 | Water: crown at zero | SI, PD | 4 | Custom bottle is clear and tactile. | Verify crown focus is immediate and VoiceOver has an equivalent adjustment path. |
| WA-11 | Water: pending amount and commit | SI, PD | 4 | Lighter pending band is a thoughtful interaction. | Test optimistic queue reconciliation and duplicate commits. |
| WA-12 | Weight: populated | SI, PD | 4 | Honest current, goal, and gap without a misleading chart. | Show last measurement date. |
| WA-13 | Weight: no data/at goal/gap | SI, PD | 4 | Complete and appropriately restrained. | Deep-link or explain that weigh-ins happen on phone. |
| WA-14 | Watch navigation/back/system title behavior | SI, PD | 4 | Native Watch hierarchy is appropriate. | Verify all rows and buttons fit 41 mm and 45/46 mm devices. |
| WA-15 | Watch transport stale/disconnected state | SI, PD | 4 | Dedicated freshness, stale, disconnected, retry, and phone-handoff states are present. | Verify thresholds and reconnect behavior on hardware. |

## 18. System-Owned, External, And Physical-Only Surfaces

| ID | Surface and meaningful states | Evidence | Score | Purpose and design notes | Improvement or gap |
| --- | --- | --- | ---: | --- | --- |
| PX-01 | Camera authorization | SI, PD | 3 | System-owned. | Pre-permission context must match the exact camera task. |
| PX-02 | Photo library authorization and picker | SI, PD | 3 | System-owned. | Limited-library state needs a useful recovery path. |
| PX-03 | Health share/update authorization | SI, PD | 3 | System-owned. | Phone and Watch purpose strings must remain clear and complete. |
| PX-04 | Notification authorization | SI, PD | 3 | System-owned. | Ask in response to a chosen reminder. |
| PX-05 | Location authorization for running | SI, PD | 3 | System-owned. | Explain precise/background need and provide reduced-function fallback. |
| PX-06 | Speech/audio behavior | SI, PD | 3 | System voice engine is outside visual control. | Test interruptions, silent mode, Bluetooth routing, and unavailable voice fallback. |
| PX-07 | App Store/share activity | SI, PD | 3 | System-owned. | Verify current URL and metadata. |
| PX-08 | Mail composer unavailable | SI, PD | 4 | Feedback falls back to a copyable support address when Mail is unavailable. | Verify the signed-device fallback and current support address. |
| PX-09 | External privacy/terms browser | SI, PD | 3 | Opens public documents. | Stable first-party hosting would improve trust and presentation. |
| PX-10 | Keyboard states across editors | SI, PD | 3 | System-owned but affects layout materially. | Verify bottom actions, tab bar, and fields remain visible in compact and large text. |
| PX-11 | Haptics across logging/workout/run/watch | SI, PD | 3 | Important feedback layer unavailable to screenshots. | Create a deliberate haptic vocabulary and test for overuse. |
| PX-12 | Offline/poor-network provider degradation | SI, PD | 3 | Affects search, Maia, scan, Trust, and planning. | Preserve local work, expose partial results, and never strand the user behind a spinner. |

## Removed Dormant And Duplicate View Closure

The original reachability audit found dormant social, journal, retired nutrition, duplicate
wellness, unused chart, retired avatar, and placeholder extension implementations. Every listed
shipping-risk item was either removed from source and the Xcode project or reduced to an active
component with a verified caller. Debug galleries and deterministic screenshot routes remain
intentionally because they are test infrastructure, not production destinations.

No dormant Community, AI Journal, duplicate Sleep Report, retired log, placeholder Control
Widget, or unused presentation component remains as a score-1 or score-2 shipping surface.

## Cross-Surface Closure

The six broad recommendations from the baseline census are implemented:

1. A shared compact accessibility composition preserves operational content and pinned actions at
   large text sizes.
2. Mint is reserved for interpreted or recommended content; ordinary editable data uses neutral
   surfaces.
3. Nested editors use the authored editor shell with validation, dismissal policy, and
   keyboard-safe actions.
4. Trust's source, support, freshness, missing-evidence, uncertainty, and action grammar now
   appears across food, wellness, recovery, reports, Watch, widgets, and Live Activities where
   the data supports it.
5. Extension surfaces expose freshness, stale or disconnected state, and a recovery path.
6. Zero, unavailable, not supplied, denied, stale, insufficient, and withheld states use distinct
   language instead of sharing one empty visual.

Peter accepted the ordinary hardware register on July 17: camera and Photos recovery, GPS/run
recording, HealthKit, Watch transport, haptics, widgets, Live Activities, VoiceOver order, keyboard
clearance, policy links, sharing, account deletion, and signed-device launch behavior. The retained
25-image camera benchmark and preferred online Maia speech remain post-release evidence tasks, and
the App Store-processed build still needs its short TestFlight smoke. Provider misses and camera
corrections must be measured before making database-coverage or model-quality claims.

## Physical Acceptance Matrix

These are the surfaces that cannot be considered visually or behaviorally complete from static
simulator captures alone.

| Area | Required physical checks |
| --- | --- |
| Camera logging | Permission, capture, retake, crop, low light, portion review, error recovery |
| Barcode | Focus speed, torch, duplicate suppression, unknown code, offline recovery |
| Receipt/menu scanning | Long receipt, glare, crop, duplicate items, generated-field review |
| Maia voice | Voice quality, routing, interruptions, silent mode, downloaded voice, fallback |
| Strength workout | Keyboard, timer, rest haptics, backgrounding, termination/restoration, Live Activity |
| Running | GPS accuracy, pause/resume, route privacy, HealthKit reconciliation, guided cues, smoke-safe later test |
| HealthKit | Read/write prompts, denied state, partial permission, freshness, duplicate prevention |
| Watch | Initial sync, stale sync, offline queue, repeat meal, water crown, weight freshness |
| Widgets | Every family, light/dark, empty, stale, warning, action, localization |
| Live Activities | Lock Screen and every Dynamic Island size/state for workout, run, fast, and AYCE |
| Accessibility | VoiceOver order, Switch Control, Reduce Motion, Increase Contrast, largest practical text |
| Account | Sign out, provider reauth, deletion, export, import partial failure |

## Final Product Judgment

The current 2.3 candidate is not a collection of unrelated feature prototypes anymore. Its best
surfaces share a real product idea: evidence should be visible, uncertainty should be named, and
the user should receive one practical next action.

Living Day, Trust, Session Review, Run Detail, Meal Plan, and the restaurant tools are credible
demonstration surfaces, and the release sweep carried their language through secondary editors,
missing-data states, and device extensions. After the processed-build smoke, the next quality jump
should be measured from production behavior: provider misses, correction burden, activation,
retention, and the proposed Recovery Continuum rather than another pre-release visual motif.
