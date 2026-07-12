# Micronutrient Data Contract - Version 2.3

The title and filename retain the internal milestone label; this contract ships in replacement
public version 2.2.

## Product rule

MyFitPlate must never present an unavailable micronutrient as measured zero.

- A non-`nil` value means a source explicitly reported the nutrient. Zero is valid reported data.
- `nil` means the source did not report the nutrient. It is unknown, not deficient intake.
- Scaling, recipes, saved foods, recent foods, diary persistence, and reports must preserve this
  distinction.
- Estimated meals may omit micronutrients. The app must not fabricate a complete panel to make a
  screen look fuller.

## Canonical units

`FoodItem` stores fiber in g. It stores calcium, iron, potassium, sodium, vitamin C, magnesium,
phosphorus, zinc, manganese, vitamins B1/B2/B3/B5/B6, and vitamin E in mg. It stores vitamin A as
mcg RAE and vitamins D/B12/K, folate, copper, and selenium in mcg.

Provider adapters own conversion into these units. Views and goal calculations must not reinterpret
raw provider values.

## Provider behavior

### USDA FoodData Central

- Text search includes Foundation, SR Legacy, and Survey (FNDDS). Foundation/SR records retain the
  higher verified confidence; FNDDS remains a conservative database match.
- Barcode search remains exact-GTIN Branded lookup.
- USDA values are scaled from 100 g to the declared gram serving.
- Vitamin A uses nutrient 320 (mcg RAE). Nutrient 318 is IU and must not be relabeled as mcg.
- Copper nutrient 312 is converted from mg to mcg.
- An explicitly reported zero remains non-`nil`.

Reference: https://fdc.nal.usda.gov/api-guide.html

### FatSecret

- Search rows are macro previews and carry no invented optional values.
- Numeric FatSecret results must be hydrated from the detail endpoint before normal or quick log.
- Detail decoding preserves reported zero and leaves absent/`N/A` fields nil.
- FatSecret's supported detail panel is narrower than USDA's. Missing B vitamins and trace minerals
  are expected unless the server response genuinely supplies them.

Reference: https://platform.fatsecret.com/docs/v4/food.get

### Open Food Facts

- Per-serving values win when present; otherwise per-100 g values scale to the resolved serving.
- Canonical Open Food Facts nutrient amounts are converted from g into the app's mg/mcg units.
- Supported aliases include `vitamin-pp` for B3, `pantothenic-acid` for B5, and `vitamin-b9` or
  `folates` for folate.
- The adapter maps all 22 vitamins/minerals represented by `FoodItem`.

Reference: https://openfoodfacts.github.io/openfoodfacts-server/dev/explain-nutrition-data/

## Exact-product enrichment

Barcode lookup may fill a primary record's missing detail nutrients from USDA or Open Food Facts
only when all of these are true:

1. Both records came from the same checksum-valid exact or accepted zero-padded-equivalent GTIN.
2. The existing `FoodSourceAgreement` calorie/macro normalization and tolerance checks pass.
3. Both records pass nutrition sanity checks and have comparable serving weights.
4. The candidate value is finite and nonnegative.

The candidate value is scaled to the primary serving. Enrichment never changes identity, calories,
macros, serving text, source metadata, Trust evidence, or any existing primary value. Candidate
order is deterministic; later records cannot overwrite a value filled by an earlier agreeing one.

Text search does not perform fuzzy nutrient merging. An exact normalized-name collision may select
the source record that reports more nutrients, but values from different text results are not
combined.

## Recipes and estimates

- Recipe totals sum only reported optional values. If no ingredient reports a nutrient, the recipe
  value remains nil.
- Ingredient quantity edits scale macros, serving weight, fat detail, fiber, and the full vitamin/
  mineral panel together.
- Recipes without detailed ingredient records retain their saved aggregate nutrition.
- Maia text logging requests `null` for unknown nutrients. Photo/menu/meal-plan estimates may remain
  macro-only and must retain estimated source metadata.

## Presentation and reports

- Daily progress uses N/A when no logged food reports a nutrient and shows reported-food coverage.
- The displayed total is the sum of reported values only; partial coverage is labeled.
- Historical micronutrient averages divide by days with at least one reported value for that
  nutrient, not every logged day. Each average shows reported days over nutrition days.
- Food and Recipe detail disclose how many of the 22 vitamins/minerals are reported. A reported
  zero remains visible.
- Maia coaching context says `not reported` for absent fiber or sodium rather than sending zero.

## Migration boundary

Existing diary and saved-food records are immutable nutrition snapshots. Version 2.3 does not
silently rewrite historical USDA Vitamin A/copper values or invent values for old records. Reopening
or relogging a current provider result receives the corrected adapter behavior. A future migration
would require explicit provider/version evidence and must never infer which legacy values were raw
IU, mg, or unavailable.

## Regression gates

- Parser fixtures cover unit conversion, per-serving precedence, aliases, and explicit zero.
- Coverage tests distinguish nil, zero, partial, and complete reporting.
- Exact-product tests cover serving scaling, primary-value preservation, and disagreement refusal.
- Recipe tests cover full-panel aggregation, scaling, and conversion back to `FoodItem`.
- The complete MyFitPlateCore suite must pass before release.
