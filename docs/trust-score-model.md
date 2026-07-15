# Trust Model v3

MyFitPlate Trust explains what evidence supports each part of a food entry. It answers five
separate questions instead of asking one score to stand in for all of them:

1. What kind of source produced this entry?
2. Is the product identity tied to a provider record or checksum-valid barcode?
3. Are the serving, calories, and core macros supported by one source, another database, or a
   saved user correction?
4. Which detailed nutrients are present, and which areas have not been checked?
5. How current is the underlying provider record?

Trust is an evidence ranking, not a statistical probability. A numeric evidence index of 86 does
not mean "86% accurate." No state guarantees label accuracy, ingredients, allergen safety, food
safety, or medical suitability.

## Product invariants

- The Food Passport is the primary user-facing contract. The numeric evidence index is secondary
  diagnostic detail behind `Why this rating`.
- Evidence is field-specific. Agreement on calories and core macros does not imply agreement on
  micronutrients, ingredients, allergens, or serving text.
- Source lineage is explicit. Analytical reference data, manufacturer labels, licensed databases,
  public databases, personal review, community consensus, model estimates, derived entries, and
  restaurant catalogs are not presented as interchangeable evidence.
- `Cross-database agreement` means two recognized provider records matched within the documented
  nutrition tolerances. It does not claim independent laboratories or independent upstream data.
- A saved user correction is visible as personal review. It can support the fields actually
  changed, but it never becomes database corroboration.
- Estimates and community submissions cannot rise above the Review tier.
- Red means a concrete nutrition value needs correction. Limited evidence, missing fields,
  uncertain freshness, and ordinary estimates use caution or neutral states.
- Non-finite, negative, physically impossible, or unsupported values never receive trusted
  agreement and cannot crash score formatting.
- Provider retrieval time is not silently presented as a formulation update date.
- Trust analytics include the scoring-model version. Current scoring model: `3`. Current Food
  Passport model: `1`.

## Food Passport

Every `FoodItem` can be evaluated into five scopes:

| Scope | What it can say | What it does not imply |
|---|---|---|
| Product identity | Valid barcode, provider record, or cross-database barcode match | Nutrition accuracy |
| Serving | Comparable gram weight, a manufacturer-reported supplement serving, or a serving confirmed by the user | Core nutrition accuracy |
| Core nutrition | Source reported, cross-database agreement, saved core correction, estimate, or correction required | Detailed nutrients or ingredients |
| Detailed nutrition | Number of optional fats, fiber, vitamins, and minerals present; saved detail correction; estimate; or correction required | Completeness of every nutrient |
| Ingredients & allergens | Currently `Not checked` | Any allergen or ingredient assurance |

The passport also reports source lineage and freshness:

- `Current`: provider update date is at most 18 months old.
- `Aging`: provider update date is more than 18 and at most 36 months old.
- `Stale`: provider update date is more than 36 months old.
- `Retrieved`: only the date MyFitPlate observed the record is known.
- `Unknown`: neither date is available.

A retrieval date means only that MyFitPlate fetched or saved the record on that date. It is not a
claim about when a manufacturer changed its formulation.

## Source lineage

| Lineage | Typical MyFitPlate source |
|---|---|
| Analytical reference | USDA Foundation, SR Legacy, or Experimental records |
| Government compilation | USDA FNDDS / survey foods and Health Canada CNF |
| Manufacturer label | USDA Branded records, official label snapshots, and NIH DSLD supplements |
| Licensed database | FatSecret and future contract providers |
| Public database | Open Food Facts |
| Personal review | Saved user-created or corrected food |
| Community consensus | Server-qualified aggregate correction |
| Model estimate | Maia, image, menu, or receipt estimate |
| Derived entry | Recipe, meal-plan, or recent-history derivative |
| Restaurant catalog | Fast Food Builder catalog |
| Unknown | Legacy entry without durable provenance |

USDA is intentionally split by data type. USDA documents Foundation data as analytically derived,
FNDDS as compiled, and Branded data as manufacturer label information. A government host does not
turn every hosted record into laboratory evidence.

Health Canada CNF is conservatively compilation lineage because one record can combine Canadian
analysis, calculations, manufacturer values, and upstream composition data. NIH DSLD is
manufacturer-label lineage: NIH hosting does not establish that the product was laboratory tested.

## Evidence index bands

| Index | Level | Meaning |
|---|---|---|
| 90-99 | Excellent | Recognized cross-database agreement on calories and core macros, comparable serving evidence, no modeled contradiction, and no explicit stale-provider flag |
| 75-89 | Strong | Good source or personal evidence, but no current cross-database agreement |
| 55-74 | Review | Usable with a visible limitation, estimate, community source, or informational nutrition finding |
| 0-54 | Low | Evidence is sparse or a concrete value needs correction |

Reviewed estimates and personal entries use resolved labels such as `Reviewed estimate` and
`Reviewed entry`. They remain in their evidence tier without repeatedly requesting the same review.

## Base scores

| Source | Base |
|---|---:|
| USDA | 86 |
| Health Canada CNF | 86 |
| NIH DSLD current supplement label | 76 |
| FatSecret packaged-food match | 74 |
| Open Food Facts | 68 |
| Private saved barcode match | 82 |
| Manual or non-barcode custom entry | 68 |
| Recipe, meal plan, or recent-history entry | 82 |
| Community barcode submission | 68 |
| Fast Food Builder catalog | 66 |
| Maia / AI estimate | 58 |
| Unknown or legacy source | 55 |

## Modifiers and caps

Modifiers are applied in this order:

| Evidence or limitation | Effect |
|---|---:|
| Valid cross-database agreement | Add 12 and set a floor of 92 |
| Nutrition edited by the user | +10 |
| Serving selected by the user | +6 |
| Unreviewed estimate | -16 |
| Reviewed estimate | -4 |
| No comparable serving weight | -7 |
| Explicit provider update older than 36 months | -12 |
| Informational nutrition finding | -8 |
| Hard nutrition warning | Cap at 34 |
| No cross-database agreement | Cap at 89 |
| Estimate or community submission | Cap at 74 |
| Missing comparable weight, any sanity finding, or explicit stale record | Cap at 89 |
| Final range | Clamp to 0-99 |

These values are deterministic product heuristics. They must be recalibrated from real correction
rates and provider-specific outcomes, never interpreted as measured accuracy.

## Cross-database agreement contract

Agreement is earned only when all of the following hold:

- The scanned identifier is a checksum-valid GTIN-8, GTIN-12, GTIN-13, or GTIN-14.
- Barcode variants differ only by GS1 zero padding. A non-zero GTIN-14 packaging indicator is not
  collapsed into a retail-unit UPC/EAN.
- The provider returned that GTIN or a zero-padded equivalent. USDA text search is inspected for a
  matching `gtinUpc`; the first result is never accepted blindly.
- Both entries have finite, nonnegative calories/macros and a known serving weight of at least 10 g.
- Neither entry has a hard nutrition-sanity warning.
- Values are normalized per 100 g. Calories agree within `max(20 kcal, 12%)`; protein, carbs, and
  fat each agree within `max(2.5 g, 20%)`.
- The corroborating source is USDA, FatSecret, or Open Food Facts, is not the primary source, and is
  counted only once.
- Structured evidence preserves source type, source lineage, provider identifier, observation
  time, and provider update time when available.

This proves provider agreement only. Providers can share upstream manufacturer label data, so the
UI never calls the result independent verification.

Health Canada CNF does not participate in this agreement contract. CNF may use USDA composition as
an upstream source, and a generic-food name is not an exact branded-product identity. NIH DSLD is a
separate supplement-label lane and likewise does not corroborate ordinary food macros.

Persisted agreement is cleared when an entry becomes a custom food or its nutrient density is
edited. A strict rounding-only comparison preserves evidence when the user merely scales the
serving; the broader provider-agreement tolerance is not reused for edit persistence.

Barcode providers run concurrently for each exact or zero-padding-equivalent candidate. Direct
USDA and Open Food Facts checks use six-second request timeouts, while the FatSecret callable uses
an eight-second step timeout. A timeout or miss returns the primary result without an agreement
state instead of blocking food logging.

After those food providers miss, NIH DSLD may recover a current supplement label by equivalent
UPC/GTIN. Its non-mass label serving is valid serving evidence for that supplement, but it does not
become gram-comparable food evidence.

## Nutrition sanity checks

Hard warnings drive `Needs correction` and red presentation:

- invalid, infinite, NaN, negative, or unsupported numeric values;
- protein and fat alone materially exceeding stated calories;
- macros that cannot fit inside a known serving weight;
- energy density above pure fat;
- saturated fat above total fat;
- likely sodium or potassium unit slips at the stated serving concentration.

Informational findings use caution and do not claim the label is wrong:

- standard macro math differs because fiber, sugar alcohols, allulose, alcohol, organic acids, or
  label rounding can use different energy factors;
- fiber exceeds reported total carbohydrate;
- a serving or whole-recipe mineral total is unusually large but physically possible.

## Trust coverage

Trust Hub measures supported intake, not the average of food scores:

- `Calories supported` is the share of logged calories from foods whose core nutrition has either
  cross-database agreement or a saved core-nutrition correction.
- `Protein supported` is the equivalent protein-weighted share.
- A source record alone, a serving confirmation, a detail-only correction, or an estimate does not
  count as supported core nutrition.

This makes the product goal actionable: improve the evidence behind the foods that contribute the
most to a user's day, rather than maximizing decorative badges on tiny entries.

## Correction contract

- Trust Hub ranks review work by severity and nutrition impact instead of score alone.
- The correction sheet shows a `Changes to Save` comparison for identity, serving, core nutrition,
  saturated fat, and fiber before persistence.
- A submitted correction leaves the existing receipt authoritative while persistence is pending.
- Provenance, findings, review state, haptic confirmation, and VoiceOver resolution update only
  after the saved-food write succeeds.
- A failed write keeps the prior evidence and action visible.
- Saving a materially edited custom entry clears inherited cross-database evidence.

## Community barcode status

`feature_communityBarcodeCorrections` remains `false` by default. The private pipeline stores one
contribution per user/barcode through an authenticated App Check callable. A server-owned aggregate
publishes only after at least three distinct contributors and at least two-thirds agreement.
Published records contain no contributor identifiers.

Community consensus is labeled `Community Consensus`, receives community lineage, remains capped at
Review, and is a final-fallback recovery path rather than database corroboration. Public rollout is
still blocked on internal soak, observed abuse/cost behavior, bounded reaggregation, and explicit
owner approval. The full contract is `docs/community-barcode-consensus-2.3.md`.

## UI and accessibility contract

- Food Detail leads with one unframed Trust Receipt and an evidence-state verdict, not a large
  numeric score.
- Source, core nutrition, Product Identity, Serving, Detailed Nutrition, Ingredients & Allergens,
  and freshness are visible in evidence order.
- The evidence index remains available behind `Why this rating` and is announced accessibly as
  `N out of 99`; it is explicitly described as evidence, not probability.
- Shape, icon, label, and text carry meaning without relying on color.
- Nutrition findings sit beside the affected values and lead to one correction action.
- Long source/lineage combinations and every evidence row stack at accessibility text sizes.

## Automated coverage

Automated coverage includes:

- source spoofing, self-reference, duplicate evidence, and custom-entry forgery;
- checksum-valid and invalid GTINs, zero-padding equivalence, and packaging indicators;
- exact USDA barcode identity and unknown serving-weight behavior;
- finite/negative/extreme numeric values and safe formatting;
- score-band gates, stale-provider caps, estimate/community caps, and reason priority;
- lineage/date decoding for USDA, Open Food Facts, Health Canada CNF, and NIH DSLD;
- CNF nil-versus-zero and canonical-unit preservation across broad micronutrient panels;
- supplement label-serving semantics and conservative refusal of ambiguous IU conversions;
- field-level passport separation, including core versus detail-only user corrections;
- calorie- and protein-weighted Trust coverage;
- agreement invalidation after edits and preservation after serving rescaling;
- compact and accessibility-size Trust UI rendering.

## Known limitations and next work

- Cross-database agreement currently covers calories, protein, carbs, and fat only.
- Product identity and formulation identity are not the same. A valid barcode can outlive a recipe
  change, which is why update freshness remains separate.
- Open Food Facts and commercial providers may ultimately repeat manufacturer label data also
  present in USDA Branded. Agreement is useful error detection, not proof of independent origin.
- CNF improves generic-food micronutrient availability but is not product-specific branded
  evidence. DSLD reflects current label claims and is not assay data or formulation verification.
- Ingredients and allergens are deliberately `Not checked` until MyFitPlate preserves source-level
  evidence for those fields. The UI must never infer allergen safety from nutrition evidence.
- Source weights remain expert-set heuristics until correction-outcome cohorts are large enough.
- A clean sanity result means "no modeled warning found," not "nutrition is correct."

Post-release calibration compares source, lineage, score band, passport states, and model version
against correction opens, saved edits, barcode recovery, and repeated-use outcomes. Reweight only
from a documented cohort analysis and increment `FoodTrustEvaluation.modelVersion` whenever score
semantics change. The privacy boundary and decision rules are in
`docs/trust-calibration-2.3.md`.

## Primary references

- [USDA FoodData Central data documentation](https://fdc.nal.usda.gov/data-documentation/)
- [USDA FoodData Central API guide](https://fdc.nal.usda.gov/api-guide/)
- [FDA nutrition-labeling guidance](https://www.fda.gov/media/134505/download)
- [Open Food Facts API and data documentation](https://openfoodfacts.github.io/openfoodfacts-server/api/)
- [Health Canada Canadian Nutrient File 2026](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html)
- [NIH Dietary Supplement Label Database](https://ods.od.nih.gov/Research/Dietary_Supplement_Label_Database.aspx)
- [GS1 check digit calculator and explanation](https://www.gs1.org/services/check-digit-calculator)
- [GS1 GTIN zero-padding guidance](https://support.gs1.org/support/solutions/articles/43000734528-what-type-of-gtin-can-be-encoded-in-itf-14-)
