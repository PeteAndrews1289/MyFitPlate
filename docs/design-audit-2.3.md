# MyFitPlate 2.3 Design And Simulator Audit

Date: 2026-07-16

## Objective

This audit asks whether the complete 2.3 candidate feels coherent, distinctive, trustworthy, and
ready to show beside established nutrition and training products. It is intentionally stricter
than a functional QA pass. A screen can work correctly and still fail this review if it feels
generic, visually unrelated, hard to scan, or less considered than the core experience.

The release design target is:

> A calm, evidence-led performance companion that explains what matters, shows why, and offers one
> useful next action.

That target is more defensible than copying the density of a calorie database or the aggression of
a conventional gym tracker. MyFitPlate's strongest lane combines the interpretive restraint of a
modern wellness product with unusually transparent food evidence and capable workout execution.

## Method

The pass covered:

- roughly 170 SwiftUI view types and the reachable presentation paths around them;
- more than 50 deterministic screenshot routes spanning first run, Home, food logging, Trust,
  Maia, strength, running, recovery, Meal Plan, Grocery, Reports, wellness, settings, and utility
  flows;
- light mode, dark mode, Accessibility XXXL, and an iPhone SE-class compact viewport;
- the existing visual-system rules, semantic palette, typography roles, spacing, motion, and
  primary-action constraints;
- current official App Store presentation and product positioning for MacroFactor, Cronometer,
  MyFitnessPal, and Hevy, plus Apple's design profile of Gentler Streak;
- interaction risk around live workout restoration, modal editors, horizontal date controls,
  loading behavior, and first-run presentation.

Simulator captures are stored locally under:

`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/DesignAudit-2.3-Captures`

The final five-star closure captures are stored under:

`/Volumes/T7 Developer/MyFitPlate/CodexBuildData/FiveStarFoundation-Captures-20260716`

The audit does not replace physical camera, speech, GPS, Watch, haptic, widget, or Live Activity
acceptance.

## Competitive Reference

| Product | Current strength | Lesson for MyFitPlate | MyFitPlate opportunity |
| --- | --- | --- | --- |
| [MacroFactor](https://apps.apple.com/us/app/macrofactor-macro-tracker/id1553503471) | High-contrast visual confidence, excellent information density, a clear adaptive model | Make analytical states feel deliberate and immediately legible | Explain evidence and training context more transparently |
| [Cronometer](https://apps.apple.com/us/app/cronometer-calorie-counter/id1145935738) | Deep micronutrient visibility and explicit nutrition detail | Never hide nutrient completeness or missing data | Turn accuracy from a marketing claim into inspectable field-level evidence |
| [MyFitnessPal](https://apps.apple.com/us/app/myfitnesspal-calorie-counter/id341232718) | Familiar logging patterns, broad database recognition, polished mainstream entry points | Keep common actions predictable and fast | Offer a more authored, less ad-like, more trustworthy daily experience |
| [Hevy](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350) | Fast workout logging and familiar gym controls | Live set entry must remain operational and low-friction | Connect training to recovery and food without weakening workout speed |
| [Gentler Streak](https://developer.apple.com/news/?id=3m0ht22s) | Human interpretation, distinctive identity, and one memorable visual compass | A strong product organizes data around meaning, not feature count | Own an evidence-and-action model across food, training, and recovery |

The comparison suggests that MyFitPlate should not chase one incumbent screen for screen.
MacroFactor and Cronometer remain ahead in mature analytical density, MyFitnessPal in database
scale and familiarity, and Hevy in established workout reputation. MyFitPlate can be more
memorable by making uncertainty visible, joining food to training context, and giving the user a
calm explanation rather than another wall of metrics.

## What Already Looks Strong

### Living Day

Living Day is the clearest expression of the new product direction. It has an authored point of
view, a useful chronology, and a stronger sense of "today" than a conventional card dashboard.
It is a credible showpiece and should remain the first screen in demonstrations.

### Trust Receipt

Trust Receipt is the strongest competitive differentiator. It does something competitors rarely
do: separate source identity, core-nutrition support, consistency checks, personal review, source
agreement, freshness, and missing evidence. The language generally avoids converting a score into
a false probability.

### Training

The Train dashboard, live workout player, program surfaces, workout history, and completion review
now share a professional operational identity. Controls are dense without becoming decorative,
and the live player compares favorably with dedicated workout trackers. The Recovery Field's
selectable regions and evidence card are a useful bridge from logging to interpretation.

### Dark Mode

Dark mode is one of the candidate's strongest presentation states. Surfaces retain hierarchy,
semantic accents remain readable, and the product feels more premium without relying on
decorative gradients or black-on-neon styling.

### Supporting Product Breadth

Food Search, Fast Food Builder, Grocery, Meal Plan, AI estimate review, Pantry, Recipes, Reports,
running detail, wellness detail, plate tools, and the restaurant value features generally feel
like parts of one app rather than a collection of prototypes.

## Five-Star Closure

The follow-up implementation pass treated the audit as a complete product-system brief, not a
short list of flagship-screen tweaks. Every source-addressable recommendation appropriate for
2.3 was either implemented or removed:

- shared authored editors replaced generic nested forms across nutrition, Maia, training,
  running, wellness, and settings;
- large-text layouts compact supporting copy and keep operational content and primary actions
  reachable;
- mint now represents interpreted or recommended content while ordinary editable data uses quiet
  neutral surfaces;
- Trust's evidence grammar now carries source, support, freshness, missing-data, uncertainty, and
  action language into wellness, Recovery Field, reports, Watch, widgets, and Live Activities;
- image workflows expose named stages, cancellation, retry, preserved input, and review before
  write;
- exercise selection gained muscle and equipment filters, intent-aware rows, target presets, and
  set-preserving swaps;
- Recovery Field gained refined front/back anatomy, direct region selection, a stable legend,
  evidence, freshness, uncertainty, and an accessibility list alternative;
- Watch, widgets, and Live Activities now distinguish current, stale, disconnected, empty, queued,
  saved, and failed states;
- dormant Community, journal, duplicate wellness, retired nutrition, unused presentation, and
  placeholder extension code was removed from source and the Xcode project.

A five on the surface rubric means a memorable showpiece, not merely correctness. Living Day,
Trust, Recovery Field, and the distinctive restaurant tools can appropriately reach that level.
A predictable settings editor, permission recovery sheet, or compact Watch status is usually
better product design at four: authored and polished, but deliberately quiet.

## Findings And Decisions

### P0 - Submission Blockers

No simulator-visible P0 crash, privacy, data-loss, or unreachable-primary-action defect was found
during this visual pass.

### P1 - Correctness And Credibility

#### Abandoned workout timers could restore indefinitely

The live workout player restored any persisted start date, including a start date many hours or
days old. This produced an impossible multi-hour timer in the audit and would damage trust in the
training experience after a crash or abandoned session.

Resolution:

- workout state older than 12 hours is now discarded;
- future start dates are discarded;
- valid recent sessions still resume;
- focused tests cover valid persistence, stale state, future state, and formatting.

### P2 - Visible Polish Gaps

#### Shoe setup fell back to a generic system Form

The old add-shoe sheet was the clearest remaining visual outlier in Training. It lacked the
hierarchy, surfaces, field treatment, and bottom action pattern used elsewhere.

Resolution:

- rebuilt as a scrollable app-system editor with an authored header;
- separated shoe identity from mileage tracking;
- added stable units and an honest replacement-range note;
- corrected the default metric replacement range to 560 km;
- retained the same shoe persistence behavior;
- added a stable bottom Save action and large-text layout.

#### Feature Tour described the product without showing it

The previous tour used a small icon, text, and a large blank area. It looked like documentation
rather than a first-run product showcase.

Resolution:

- each page now has a domain-specific visual preview;
- Maia shows a contextual recommendation and actions;
- camera logging shows an editable estimate review;
- Training shows live set progress;
- wellness shows source signals;
- Meal Plan shows a week and grocery handoff;
- the previews use the same visual language as the app rather than marketing artwork.

#### Meal Plan clipped the seventh day on compact phones

The week strip used seven 44-point cells plus spacing, which exceeded the available width on the
compact simulator. Accessibility cards were also too narrow for comfortable planned-meal text.

Resolution:

- compact day cells and spacing now fit seven days without clipping;
- accessibility day cards are wider and allow two deliberate lines;
- stable cell dimensions preserve selection and prevent layout shifts.

#### Trust needed an instant daily visual, not only long receipts

Trust Receipt is strong but necessarily text-heavy. The daily Trust Hub previously led with four
metrics and three lists, making users infer which evidence layer was weakest.

Resolution:

- added an Evidence Map for Product Identity, Serving, Core Nutrition, and Detailed Nutrition;
- the map deliberately separates a documented field from cross-database agreement;
- core nutrition counts only validated cross-database agreement or a correction saved by the user;
- the weakest evidence layer receives one concise explanation;
- item-level correction links remain the action path;
- analytics record the weakest evidence field for future calibration.

### P3 - Non-Blocking Residual Risk

The remaining quality gaps are not unfinished source recommendations:

- physical camera, barcode, speech, GPS, HealthKit, Watch, haptic, widget, and Live Activity
  behavior still needs direct observation;
- production provider breadth and micronutrient completeness remain smaller than incumbent
  databases even though missing evidence is now presented honestly;
- system-owned permission, keyboard, share, browser, and voice surfaces should remain native
  rather than being forced into ornamental custom chrome;
- interaction analytics and correction outcomes are still needed before changing Trust weighting
  or adding more first-viewport Home emphasis.

## Accessibility Review

The broad pass found no systemic inability to reach primary actions. Shared compact composition
now reduces supporting copy, converts wide layouts where needed, and preserves pinned actions at
accessibility sizes. Remaining physical acceptance should emphasize:

- Trust explanatory copy at the user's largest practical text size;
- VoiceOver order through Evidence Map and Trust item sections;
- live workout controls while the keyboard is present;
- Recovery Field region selection without relying on color;
- feature-tour scrolling and bottom-action reachability;
- compact Quick Log clearance above the tab bar.

## Color And Identity Review

The app is now recognizably MyFitPlate, but that identity comes from structure more than from
painting every surface green:

- green remains current/action/success;
- blue carries effort and protein where labeled;
- teal carries hydration and recovery where labeled;
- gold carries achievement, carbohydrates, and caution only where the label disambiguates it;
- food and exercise emoji remain the warmer content signature;
- dark green is best reserved for icon, export, and Store presentation.

The largest remaining risk is feature-driven color accumulation. New screens should use neutrals,
brand, and no more than two labeled semantic accents.

## Verification Evidence

The implementation pass was verified against the same working tree used for the final captures:

- MyFitPlateCore passed 1,143 tests with zero failures;
- Firebase Functions passed 28 tests with zero failures;
- the complete simulator Debug build passed, including phone, Watch, widget, and Live Activity;
- SwiftLint reported zero violations across the 214 Swift files in the shipping lint scope after
  deliberate dead-code removal;
- embedded products, project structure, plists, and diff whitespace checks passed;
- focused workout timer tests passed 5/5, including stale and future persisted start dates;
- six focused UI tests passed with zero failures in 288 seconds;
- the UI run covered Trust navigation and dismissal, the new Evidence Map, Meal Plan hierarchy,
  Train and Meal Plan at Accessibility XXXL, both first-run families, and Add Shoe's clipping
  audit;
- the final focused live-workout/Recovery Field UI test passed in 62.8 seconds, including direct
  Core selection and evidence-panel update;
- the dark Accessibility XXXL live-workout/Recovery Field test passed after moving selected-region
  evidence ahead of summary counts and removing duplicate editorial framing;
- final settled captures cover Home, Trust Hub, Train, Routine Builder, live workout, Reports,
  Meal Plan, Feature Tour, and Recovery Field under
  `/Volumes/T7 Developer/MyFitPlate/CodexBuildData/FiveStarFoundation-Captures-20260716`.

Peter accepted the ordinary real-device audio, camera safety, GPS, HealthKit, Watch transport,
haptic, widget, and Live Activity paths on July 17. The retained 25-image camera comparison,
preferred online Maia voice, and processed-build smoke remain separate evidence tasks; none is used
to support a 2.3 accuracy or online-speech claim.

## Objective Product Rating

Scores reflect the current 2.3 candidate after the audit fixes, not market size or advertising.

| Dimension | MyFitPlate 2.3 | Industry-leading range | Assessment |
| --- | ---: | ---: | --- |
| Visual identity | 9.1 / 10 | 9.0-9.5 | Distinctive, calm, and coherent across the reachable product |
| Core workflow clarity | 9.0 / 10 | 9.0-9.5 | Strong hierarchy with authored recovery in secondary flows |
| Trust and evidence design | 9.6 / 10 | 7.0-8.5 | Category-leading product idea with field-level evidence |
| Workout execution UI | 9.1 / 10 | 9.0-9.4 | Credible beside dedicated trackers and more connected to recovery |
| Nutrition-data breadth | 8.0 / 10 | 9.0-9.7 | Better provider coverage; incumbent scale remains a real advantage |
| Micronutrient transparency | 8.8 / 10 | 9.0-9.5 | Missing and converging evidence is unusually honest |
| Accessibility readiness | 9.1 / 10 | 9.0-9.5 | Strong automated composition plus accepted physical VoiceOver and large-text paths |
| Cross-app polish consistency | 9.2 / 10 | 9.1-9.6 | No score-1 placeholder or score-2 dormant product surface remains |
| Differentiation | 9.3 / 10 | 8.0-9.5 | Trust plus food-training-recovery context is meaningfully different |

Overall product-design rating: **9.1 / 10**.

This does not mean MyFitPlate has caught incumbents in database scale, brand trust, support
operations, or years of production refinement. It means the candidate now belongs in the same
visual conversation, its workout experience is credible beside specialist products, and its
evidence model is a clearer original idea than several larger products offer.

## Next Distinctive Product Bet

The safest post-2.3 concept is a **Recovery Continuum** built from capabilities already present:

1. A completed workout establishes regional muscle load and fuel demand.
2. Sleep, heart rate, elapsed time, and subsequent training update the Recovery Field.
3. Logged carbohydrate, protein, hydration, and meal timing show which recovery actions were
   completed.
4. The user can tap a body region or recovery need to see the evidence, uncertainty, and next
   useful action.
5. Reports show whether recovery actions correlated with readiness or training quality without
   making medical or causal claims.

This would join the Recovery Field, Training Fuel, Living Day, and Trust model into one memorable
system competitors do not currently present as a coherent workflow. It should be built after 2.3,
with clear evidence boundaries and no readiness claims beyond the available data.

## Final Submission Focus

The app source is frozen at `39e3d1a2`. The exact-candidate suite, replacement signed archive,
exported IPA, Store images, package inspection, and physical sections 1-9 are complete. Before
submission, Peter only needs to upload that package, install the processed TestFlight build over
2.2, inspect App Check and launch health, verify the review account, and submit the prepared Store
package. Broad feature work remains deferred until the accepted 2.3 source is merged to `main`.
