# Food Detail And Nutrient Profile 2.3

Status: source complete, simulator accepted, and physically accepted by Peter on July 18, 2026.

## Product Intent

Food Detail should answer three questions in this order:

1. What am I about to log?
2. What nutrition does this serving contain?
3. Why should I trust the data, and what can I correct?

The former screen gave the complete Trust Receipt most of the first viewport. That made strong
evidence visible, but pushed the food's calories and macros below it. Micronutrients lived in a
small disclosure group and were easy to miss even when useful data existed.

## Shipping Hierarchy

The final 2.3 candidate uses this hierarchy:

1. Food identity and serving.
2. Calories, protein, carbohydrates, and total fat.
3. Any meaningful calorie-versus-macro consistency warning.
4. Compact Food Trust passport with rating, core-evidence state, source agreement, and detailed
   nutrient coverage.
5. Serving controls.
6. Always-visible Micronutrient profile.
7. Secondary fat-breakdown and fiber detail.
8. Label-scan recovery and the persistent log action.

The complete Trust Receipt remains unchanged in substance and opens in a dedicated Evidence sheet.
Trust is therefore prominent without competing with the nutrition the user came to inspect.

## Micronutrient Profile

- The summary shows up to six reported vitamins or minerals, ordered by percent Daily Value.
- Each row shows the source amount, unit, general U.S. label percent Daily Value, and a restrained
  progress bar.
- `Explore nutrient profile` opens an All/Vitamins/Minerals workspace with every reported field and
  a separate list of fields the source did not report.
- A missing value remains unknown. It is never displayed or totaled as zero.
- An explicit reported zero remains a reported value.
- Percent Daily Value is labeled as a general food-label reference, not a personalized target.
- Foods with no detailed nutrients get an honest empty state and a direct Nutrition Label scan
  action instead of an empty disclosure.

The reference values follow the current U.S. Nutrition Facts label values for adults and children
age four and older. MyFitPlate does not infer or generate missing micronutrients.

## Correction Workspace

`Fix food` is now a full-screen workspace so the keyboard and nested presentation stack do not
fight for space. It supports:

- food identity, serving description, and serving weight;
- calories, protein, carbohydrates, total fat, saturated fat, and fiber;
- all 12 vitamin fields and all 10 mineral fields used by MyFitPlate;
- blank-as-unknown and explicit-zero semantics;
- saturated-fat-versus-total-fat validation;
- a before/after change summary before Save;
- a persistent keyboard-dismiss control beside Save while a field is focused.

The saved correction continues through the existing Trust correction path, including calibration
and saved-food reuse behavior.

## Analytics And Privacy

Analytics schema `2.3.3` adds `food_nutrient_profile_action` for these coarse actions:

- `profile_opened`
- `label_scan_from_summary`
- `label_scan_from_detail`
- `label_scan_from_profile`

The event records only the action, a coarse reported-field bucket, and provider type. Food names,
food identifiers, nutrient names, nutrient amounts, macro values, and health values are excluded.
The central sanitizer also rejects nutrition, nutrient, vitamin, mineral, and individual mineral
parameter keys.

## Verification Evidence

- Strict SwiftLint: 0 violations.
- MyFitPlateCore: 1,223 passed, 0 failed.
- App tests: 116 passed, 0 failed.
- Focused UI matrix: 6 passed, 0 failed across nutrition-first hierarchy, full Trust Receipt,
  nutrient explorer, no-micronutrient recovery, correction semantics, and dark Accessibility XXXL.
- Full nightly UI matrix: 83 of 85 passed in the broad run. The two outliers then passed in focused
  closure: the Health Canada/NIH journey after fixing its ambiguous row accessibility target, and
  the unchanged workout dashboard after an iOS 26.5 simulator signal termination.
- UI harness closure: Home and Quick Log to food search passed 2/2 after removing the redundant
  pre-test app launch and adding verified text-entry fallback behavior.
- Cold optimized Release simulator build: passed for the phone app, Watch app, widget, and Live
  Activity extension.
- UI result: `/Volumes/T7 Developer/MyFitPlate/TestResults/Food-Detail-UI-Matrix-20260718.xcresult`.
- Nightly closure results:
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Food-Specialist-Closure-20260718.xcresult`,
  `/Volumes/T7 Developer/MyFitPlate/TestResults/Workout-Dashboard-Closure-20260718.xcresult`, and
  `/Volumes/T7 Developer/MyFitPlate/TestResults/UI-Explicit-Launch-Closure-20260718.xcresult`.
- Settled captures: `/Volumes/T7 Developer/MyFitPlate/TestResults/Food-Detail-Captures-20260718`.
- Release log: `/Volumes/T7 Developer/MyFitPlate/TestResults/Food-Detail-Release-Build-20260718.log`.

## Physical Acceptance

Peter confirmed all six checks on physical hardware on July 18, 2026:

- [x] A richly sourced food shows identity and macros before the compact Food Trust passport; the
  Evidence sheet exposes the complete receipt.
- [x] A food with micronutrients shows useful summary rows, while All, Vitamins, and Minerals
  expose reported and missing fields correctly.
- [x] A macro-only food explains that detailed nutrients were not reported, offers Nutrition Label
  scanning, and does not treat missing fields as zero.
- [x] A saved or barcode food preserves an explicit fiber zero; macro, vitamin, and mineral edits
  persist after saving and reopening, with Trust and nutrient values updated.
- [x] The top-bar keyboard control hides the physical numeric keyboard without dismissing the
  correction workspace, and Save completes normally.
- [x] The first viewport and correction workspace remain readable in dark mode and large text, with
  wrapping intact and the bottom log action reachable.

The branch no longer has a physical-acceptance blocker.
