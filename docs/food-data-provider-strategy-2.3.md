# Food Data Provider Strategy for Trust

Adding databases helps only when each source fills a known evidence gap. A larger result count is
not itself a Trust improvement, and two providers repeating the same manufacturer label are not
independent confirmation.

## Decision

Do not add another broad packaged-food provider to the 2.3 critical path. USDA, FatSecret, and Open
Food Facts already provide a strong mix of government-hosted, licensed, and public coverage. Trust
3.0 now adds the two specialist sources that address measured product gaps:

1. **Health Canada CNF 2026** for generic-food micronutrient depth and explicit nutrient-source
   provenance.
2. **NIH Dietary Supplement Label Database** for supplement labels, ingredients, serving forms,
   market status, barcode identity, and historical label context.
3. **GS1 identity data** remains conditional on practical API access; use it to validate company
   and product identity, never nutrition.

Health Canada CNF and NIH DSLD are implemented for 2.3. They retain distinct search, serving, and
Trust semantics rather than behaving like a fourth and fifth interchangeable food database.

## Provider matrix

| Source | Best role | Trust lineage | Can corroborate packaged macros? | Setup / constraint | Priority |
|---|---|---|---|---|---|
| USDA Foundation / SR / Experimental | Generic-food reference and analytical nutrient values | Analytical reference | Only when matching the same generic food, not a branded barcode | Existing data.gov key; public-domain data | Existing, preserve subtype |
| USDA FNDDS | Prepared-food and survey composition | Government compilation | No branded-product claim | Existing data.gov key | Existing |
| USDA Branded | U.S. packaged labels and GTIN lookup | Manufacturer label | Yes as a second provider record, with shared-upstream caveat | Existing data.gov key | Existing |
| FatSecret | Broad commercial packaged/restaurant coverage | Licensed database | Yes as a second provider record | Existing callable and contract | Existing |
| Open Food Facts | Public international barcode recovery | Public database | Yes as a second provider record, with community provenance | No private key; source attribution/licensing must remain honored | Existing |
| Health Canada CNF 2026 | Generic-food micronutrients and Canadian reference composition | Conservatively treated as a government compilation | No branded barcode claim | Versioned 2026 relational CSV compiled into a backend-only search asset | Integrated in 2.3 |
| NIH DSLD | Current dietary-supplement labels and barcode recovery | Manufacturer label hosted by government | No food corroboration; supplement identity only | Public API, no credential, current on-market records only | Integrated in 2.3 |
| GS1 Verified by GS1 | GTIN/company/product identity | Identity evidence, not nutrition lineage | No | Public web lookup; practical API access may require GS1 member/business arrangements | Conditional |
| AFCD | Australian generic-food composition and analytical depth | Analytical reference / government compilation | No branded barcode claim | Download files; attribution and share-alike review required | Later regional source |
| UK CoFID | UK generic-food composition | Government compilation | No branded barcode claim | Download dataset and preserve release date | Later regional source |
| Edamam | Search, UPC, restaurant, and NLP coverage | Licensed database | Potentially, but upstream provenance may be opaque | Paid key, attribution, and plan-specific caching limits | Coverage fallback only |

## Integration rules

Every provider adapter must return these fields before it can influence Trust:

- provider name and provider record identifier;
- evidence lineage;
- exact barcode returned by the provider, when the request was barcode-based;
- date MyFitPlate observed the record;
- provider update/label date when the source exposes one;
- original serving description and comparable gram weight, or an explicit non-mass label serving
  for supplements;
- a field-presence mask so absent nutrients never become zero;
- source-specific data type, such as USDA Foundation versus Branded;
- license/attribution identifier and source URL where required.

A new source may participate in cross-database agreement only when:

- the exact GTIN contract passes for packaged food, or a separately designed generic-food matcher
  reaches a conservative identity threshold;
- serving normalization is possible;
- calories and all three core macros are finite and pass sanity checks;
- comparison tolerances pass;
- the provider record is not the same record as the primary source;
- the UI says `Cross-database agreement`, not `independently verified`.

The source's lineage remains visible even when agreement passes. Agreement between two
manufacturer-label databases is useful for detecting transcription and serving errors, but it is
not laboratory confirmation.

## 2.3 implementation

### Track A - Health Canada CNF 2026

The downloadable 2026 relational files are used instead of Health Canada's older public API. A
reproducible builder compiles 5,993 foods and the nutrients supported by `FoodItem` into a compact,
versioned server asset. Values remain per 100 g; absent nutrients remain absent; copper is converted
from mg to mcg; source/revision context and the 2026 release date remain attached to every result.

CNF joins debounced generic-food search and is ranked beside USDA and FatSecret. It never joins
barcode lookup, never fuzzy-enriches a branded record, and cannot earn cross-database agreement
against USDA. CNF can incorporate USDA and other compiled inputs, so counting it as independent
corroboration would overstate the evidence. The current record-level Trust lineage is deliberately
the conservative `governmentCompilation`; source summaries remain visible in metadata notes.
Search matches complete normalized tokens rather than substrings, handles common singular/plural
forms, and treats a generic `cooked` query as a request for an explicitly cooked preparation. It
does not silently substitute one specific cooking method for another.

The backend asset is covered by the Open Government Licence - Canada attribution in Settings. It
adds approximately 3.2 MB to the deployed Functions package, not to the iPhone or Watch bundle.

**Peter action:** no API key or paid account is required. Deploy Functions, then verify a few
ordinary-food searches and the visible attribution before 2.3 release acceptance.

### Track B - NIH DSLD

Supplements stay in a distinct result section because supplement facts do not map cleanly onto
ordinary calories/macros. Explicit search hydrates current on-market labels from NIH DSLD; barcode
lookup uses DSLD only after the established food providers miss. The app retains DSLD identity,
barcode, entry date, product type, original label serving, and supported nutrient amounts.

Each record uses `manufacturerLabel` lineage. A serving such as `2 Capsules` is one complete label
serving in the logger, not two user-selected servings, and no gram weight is invented. Unit mapping
is intentionally narrow: ambiguous Vitamin A and Vitamin E IU values are omitted, Vitamin D IU is
converted only by its established conversion, and botanicals/proprietary blends are not converted
into nutrition totals. The first release excludes off-market labels and does not claim historical
formulation matching or laboratory verification.

**Peter action:** no API key, registration, or credential purchase is required. Deploy Functions,
then verify one supplement search and one real supplement barcode when available.

### Track C - GS1 product identity

GS1 should strengthen only the Product Identity row of the Food Passport.

1. Ask the local GS1 member organization whether production API access to Verified by GS1 is
   available for MyFitPlate's expected volume and use case.
2. If access is practical, retain GTIN, company name, product description, country, and query date.
3. Never import or infer nutrition from GS1 identity status.
4. A GS1 identity match can improve identity evidence while core nutrition remains `Source
   reported`, `Cross-database agreement`, or `Needs correction` on its own merits.

**Peter action:** contact GS1 only after usage data shows product-identity mismatch is a meaningful
failure mode. There is no reason to buy enterprise access speculatively.

## Commercial provider gate

Evaluate a new paid broad provider only if production data shows one of these conditions:

- raw packaged-food barcode miss rate remains materially high after saved corrections and the
  existing three-provider cascade;
- restaurant coverage prevents users from completing logs;
- a target country has poor existing coverage;
- provider latency or reliability creates a measurable logging failure.

Before signing, require written answers for:

- whether MyFitPlate may persist full nutrition in an individual user's account;
- whether saved foods may be reused indefinitely;
- whether data may be used for search after caching;
- whether cross-provider comparison is permitted;
- attribution requirements;
- deletion requirements when the contract ends;
- rate limits, uptime, regions, barcode count, formulation dates, and per-request cost;
- whether the provider discloses source/upstream lineage.

Edamam is not the default recommendation for the current architecture. Its published plans permit
only plan-specific caching, often limited to the identifier, label, image, calories, protein, fat,
and net carbs; its terms explicitly do not permit building a reusable search copy without the
appropriate permission. MyFitPlate's saved-food and correction model needs broader, durable
per-user persistence, so written contractual approval would be required first.

## Rollout and measurement

The two specialist providers ship default-on with independent Remote Config kill switches:

- `feature_healthCanadaFoodSearch`
- `feature_nihSupplementLabels`

Existing selection, logging, barcode-outcome, and Trust-calibration events retain privacy-safe
provider categories without sending food identity, barcode, or nutrient values. The relevant
evaluation outcomes are:

- result selected and ultimately logged;
- serving evidence present;
- detailed nutrient field count;
- later correction rate by provider, lineage, and Trust model;
- exact supplement barcode hits and misses.

Promote a provider only if it reduces misses or materially improves field coverage without a worse
correction rate, slower logging, confusing duplicate results, or unsustainable cost.

## Official references

- [USDA FoodData Central API guide](https://fdc.nal.usda.gov/api-guide/)
- [USDA data type documentation](https://fdc.nal.usda.gov/data-documentation/)
- [Health Canada CNF 2026](https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/nutrient-data/canadian-nutrient-file-about-us.html)
- [Health Canada CNF open dataset](https://open.canada.ca/data/en/dataset/1b6139bd-ed7e-4043-bc28-ff00e10f3109)
- [Open Government Licence - Canada](https://open.canada.ca/en/open-government-licence-canada)
- [Health Canada CNF API guide](https://produits-sante.canada.ca/api/documentation/cnf-documentation-en.html)
- [NIH Dietary Supplement Label Database](https://ods.od.nih.gov/Research/Dietary_Supplement_Label_Database.aspx)
- [NIH DSLD API v9](https://api.ods.od.nih.gov/dsld/v9/)
- [GS1 Verified by GS1](https://www.gs1.org/services/verified-by-gs1)
- [Australian Food Composition Database](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd)
- [UK CoFID](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid)
- [Edamam Food Database API and caching summary](https://developer.edamam.com/food-database-api)
