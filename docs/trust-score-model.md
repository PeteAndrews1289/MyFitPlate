# Trust Score Model v2

Trust Score is MyFitPlate's explanation of how much support exists for a food entry's
calories and core macros. It is designed to answer three separate questions:

1. Where did this nutrition come from?
2. Did an independent database report comparable calories, protein, carbs, and fat?
3. Did automated checks or the user's own review find anything that deserves attention?

The score is an evidence ranking, not a statistical probability. A score of 86 does not
mean "86% accurate," and no score guarantees label accuracy, food safety, allergen safety,
or medical suitability.

## Product invariants

- `Excellent` requires current, recognized cross-database agreement. User confirmation,
  editing, source reputation, or a community submission cannot earn it alone.
- `Cross-Verified` means calories and the three core macros agreed. It does not claim that
  vitamins, minerals, ingredients, allergens, or serving text matched.
- Estimates and community submissions cannot rise above the Review tier.
- A user review is shown separately from database evidence. Review improves confidence but
  never becomes independent verification.
- Red means a concrete nutrition value needs correction. Limited evidence and ordinary
  estimates use orange, not red.
- Non-finite, negative, physically impossible, or unsupported values never receive trusted
  agreement and cannot crash score formatting.
- The model version is included with Trust analytics. Current version: `2`.

## Score bands

| Score | Level | Meaning |
|---|---|---|
| 90-99 | Excellent | A recognized independent database agreed on calories and macros; comparable serving weight and nutrition checks are clean |
| 75-89 | Strong | Good source or user evidence, but no current independent agreement |
| 55-74 | Review | Usable with a visible limitation, estimate, community source, or informational nutrition finding |
| 0-54 | Low | Evidence is sparse or a concrete value needs correction |

Reviewed estimates and personal entries use resolved labels such as `Reviewed estimate`
and `Reviewed entry`. They remain in the appropriate evidence tier without repeatedly
asking the user to complete a review they already performed.

## Base scores

| Source | Base |
|---|---:|
| USDA | 86 |
| FatSecret packaged-food match | 74 |
| Open Food Facts | 68 |
| Private saved barcode match | 82 |
| Manual or non-barcode custom entry | 68 |
| Recipe, meal plan, or recent-history entry | 82 |
| Community barcode submission | 68 |
| Fast Food Builder catalog | 66 |
| Maia / AI estimate | 58 |
| Unknown or legacy source | 55 |

USDA Foundation and SR Legacy records retain the stronger `High Trust` provenance label.
USDA Branded records are labeled `Database Match` because they originate from manufacturer
label submissions hosted by USDA rather than an independent laboratory confirmation. Both
still require a second database match to reach Excellent.

## Modifiers and caps

Modifiers are applied in this order:

| Evidence or limitation | Effect |
|---|---:|
| Valid independent database agreement | Add 12 and set a floor of 92 |
| Nutrition edited by the user | +10 |
| Serving selected by the user | +6 |
| Unreviewed estimate | -16 |
| Reviewed estimate | -4 |
| No comparable serving weight | -7 |
| Informational nutrition finding | -8 |
| Hard nutrition warning | Cap at 34 |
| No independent agreement | Cap at 89 |
| Estimate or community submission | Cap at 74 |
| Missing comparable weight or any sanity finding | Cap at 89 |
| Final range | Clamp to 0-99 |

These values are deterministic product heuristics. They should be recalibrated from real
correction rates and provider-specific outcomes, never interpreted as measured accuracy.

## Cross-verification contract

Cross-verification is earned only when all of the following hold:

- The scanned identifier is a checksum-valid GTIN-8, GTIN-12, GTIN-13, or GTIN-14.
- Barcode variants differ only by GS1 zero padding. A non-zero GTIN-14 packaging indicator
  is not collapsed into a retail-unit UPC/EAN.
- The provider returned that GTIN or a zero-padded equivalent. USDA's text-search response
  is searched for the matching `gtinUpc`; the first result is never accepted blindly.
- Both entries have finite, nonnegative calories/macros and a known serving weight of at
  least 10 g.
- Neither entry has a hard nutrition-sanity warning.
- Values are normalized per 100 g. Calories agree within `max(20 kcal, 12%)`; each of
  protein, carbs, and fat agrees within `max(2.5 g, 20%)`.
- The corroborating source is exactly one of USDA, FatSecret, or Open Food Facts, is not the
  primary source, and is counted only once.

Persisted agreement is cleared when an entry becomes a custom food or its nutrient density
is edited. A strict rounding-only comparison preserves evidence when the user merely scales
the serving; the broader database-agreement tolerance is not reused for edit persistence.

Barcode providers run concurrently for each exact or zero-padding-equivalent candidate.
Direct USDA and Open Food Facts cross-checks use six-second request timeouts, while the
FatSecret callable has an eight-second step timeout. A timeout or miss returns the primary
database result without a badge instead of blocking food logging.

## Nutrition sanity checks

Hard warnings drive `Needs correction` and red presentation:

- invalid, infinite, NaN, negative, or unsupported numeric values;
- protein and fat alone materially exceeding stated calories;
- macros that cannot fit inside a known serving weight;
- energy density above pure fat;
- saturated fat above total fat;
- likely sodium or potassium unit slips at the stated serving concentration.

Informational findings use orange and do not claim the label is wrong:

- standard macro math differs because fiber, sugar alcohols, allulose, alcohol, organic
  acids, or label rounding can use different energy factors;
- fiber exceeds reported total carbohydrate;
- a serving or whole-recipe mineral total is unusually large but physically possible.

This distinction follows FDA labeling guidance, which permits energy factors other than
4/4/9 for soluble and insoluble fiber, sugar alcohols, and allulose.

## Community barcode status

`feature_communityBarcodeCorrections` remains `false` by default. The internal 2.3 pipeline,
shipping dormant in replacement 2.2, stores
one private contribution per user/barcode through an authenticated App Check callable. A
server-owned aggregate publishes only after at least three distinct contributors and at least
two-thirds agreement. Published records contain no contributor identifiers; strict Rules permit
known-document reads only when private operator config allows them, while listing and every
client write remain denied.

The server validates checksum-correct GTINs, exact fields, finite ranges, serving evidence, and
nutrition sanity before accepting a submission. It resolves consensus deterministically, uses
median nutrition, checks the combined median again, withholds conflict/over-volume results,
records aggregate-only health metrics, and supports per-barcode quarantine plus a global kill
switch that invalidates materialized results. The app independently revalidates the model,
barcode, counts, ratio, schema, fields, timestamp, and nutrition before use.

Community consensus is labeled `Community Consensus`, remains capped at Review, and is treated as
final-fallback recovery rather than independent database verification. Public rollout is still
blocked on internal soak, observed abuse/cost behavior, a bounded administrative reaggregation
job, and explicit owner approval. The full contract and rollout order are in
`docs/community-barcode-consensus-2.3.md`.

## UI and accessibility contract

- The card exposes four distinct facts: Source, Verification, Your Review, Nutrition Check.
- The header describes provenance once; fact rows carry the score explanation without
  repeating the same evidence in decorative bullets.
- Cautions and corrections remain visible beneath the facts. Pure evidence bullets are
  omitted because they duplicate the fact rows.
- The score is announced as `N out of 99` in VoiceOver.
- The correction/review action remains a separate accessible button; the whole card is not
  combined into one inaccessible element.
- Long source/confidence combinations and fact rows stack at accessibility text sizes.

## Verification coverage

Automated coverage includes:

- source spoofing, self-reference, duplicate evidence, and custom-entry forgery;
- checksum-valid and invalid GTINs, zero-padding equivalence, and packaging indicators;
- exact USDA barcode identity and unknown serving-weight behavior;
- finite/negative/extreme numeric values and safe formatting;
- calorie-factor edge cases, recipe totals, unit slips, and physical impossibilities;
- score-band gates, reviewed-state completion, estimate/community caps, and reason priority;
- cross-verification invalidation after edits and preservation after serving rescaling;
- concurrent barcode callers, search ranking, meal-plan provenance, and Firestore rule shape;
- compact and accessibility-size Trust UI rendering.

## Known limitations and next calibration work

- Agreement currently covers calories, protein, carbs, and fat only.
- The score does not include label recency, formulation changes, provider uptime, or a
  cryptographic snapshot of the corroborating record.
- Source weights are expert-set heuristics until enough correction-outcome data exists.
- A clean sanity result means "no modeled warning found," not "nutrition is correct."
- Alcohol, organic acids, and specialized carbohydrate labeling can still create legitimate
  informational findings.

Post-release calibration should compare score/source/model version against correction opens,
saved edits, barcode recovery, and repeated-use outcomes. Raise or lower weights only from a
documented cohort analysis, and increment `FoodTrustEvaluation.modelVersion` whenever score
semantics change. Analytics schema 2.3.2 now distinguishes correction abandonment, submission,
persistence success/failure, coarse changed fields, resulting sanity, and cohort-level saved
barcode reuse. The privacy boundary, BigQuery templates, sample thresholds, and decision rules
are in `docs/trust-calibration-2.3.md`.

## Primary references

- [USDA FoodData Central data documentation](https://fdc.nal.usda.gov/data-documentation/)
- [USDA Global Branded Food Products Database documentation](https://fdc.nal.usda.gov/GBFPD_Documentation/)
- [FDA nutrition-labeling guidance](https://www.fda.gov/media/134505/download)
- [Open Food Facts API and data documentation](https://openfoodfacts.github.io/openfoodfacts-server/api/)
- [GS1 check digit calculator and explanation](https://www.gs1.org/services/check-digit-calculator)
- [GS1 GTIN zero-padding guidance](https://support.gs1.org/support/solutions/articles/43000734528-what-type-of-gtin-can-be-encoded-in-itf-14-)
