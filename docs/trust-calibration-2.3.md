# Trust Calibration Report Contract 2.3

This is the reproducible analysis plan for Trust model calibration. Instrumentation is ready in
analytics schema `2.3.2`; the report itself remains open until enough real 2.3 behavior exists.
The goal is to learn whether lower Trust bands predict later corrections, not to make scores look
higher.

## Questions

1. Do Review/Low entries produce more material corrections than Strong/Excellent entries?
2. Within a Trust band, is one provider corrected more often than another?
3. Does independent cross-verification predict fewer corrections than a single database?
4. Which coarse field groups are corrected: identity, serving, core nutrition, or detail
   nutrition?
5. Does the correction flow resolve warnings, fail to save, or get abandoned?
6. Do users who save corrections later recover barcode scans from My Foods?

## Privacy boundary

Calibration events contain only:

- source class, Trust score/band/model, and whether correction is required;
- evidence class, validated cross-verification count, review state, and serving-evidence class;
- sanity finding IDs and coarse changed-field groups;
- stable action/result labels.

They never contain account IDs, food IDs/names, raw barcodes, nutrition values, free-form text,
prompts, queries, Health data, or location. Firebase's `user_pseudo_id` may be used for aggregate
app-instance cohorts in BigQuery; the app does not set Firebase Auth UID as Analytics identity.
The central sanitizer explicitly removes common identity/content keys even if a future call site
adds one accidentally.

## Event contract

| Event | Meaning |
|---|---|
| `food_trust_card_viewed` | One Food Detail exposure, deduplicated for that view instance |
| `food_trust_action` | User chose the Trust Card's structured correction action |
| `food_correction_action` | Correction funnel action with the original Trust context |
| `barcode_lookup_outcome` | Barcode hit/miss; `source=custom_barcode` is saved-correction reuse |
| `barcode_label_correction_saved` | Barcode-miss correction actually persisted to My Foods |
| `barcode_label_correction_save_failed` | My Foods persistence failed after the food log action |

`food_correction_action.action` values:

- `trust_fix_opened`, `fix_opened`, `sanity_fix_opened`, or `refine_opened`;
- `correction_abandoned` when the sheet closes without submission;
- `correction_submitted` when Save passes local validation;
- `correction_saved` only after the custom-food store confirms persistence;
- `correction_save_failed` when persistence fails;
- `remember` for the separate unchanged-food remember action.

Every Trust/correction event carries `source`, `trust_score`, `trust_level`,
`trust_model_version`, `requires_correction`, `cross_verified`, `cross_verified_count`,
`review_status`, `evidence_class`, `serving_evidence`, `sanity_profile`, and
`sanity_finding_count`. Profiles are warning-first and length-bounded for stable ingestion; counts
preserve the full number of findings.

Submitted/saved events also carry `correction_scope`. Its ordered values are any combination of
`identity`, `serving`, `core_nutrition`, and `detail_nutrition`, or `no_material_change`. Successful
saves add `resulting_sanity`, `resulting_sanity_profile`, and `resulting_review_status`.

## Required Firebase setup

1. Enable Firebase Analytics export to BigQuery before collecting the calibration window.
2. Register `evidence_class`, `serving_evidence`, `sanity_profile`, `correction_scope`,
   `resulting_sanity`, and `resulting_review_status` as custom dimensions for console exploration.
3. Register `cross_verified_count`, `sanity_finding_count`, and
   `resulting_sanity_finding_count` as numeric metrics. `trust_score` is already part of the 2.3
   dashboard contract.
4. Filter every report to `analytics_schema=2.3.2` and one `trust_model_version`. Never merge
   score semantics across model versions.

## Primary correction-rate query

Replace the table path and date suffixes. A material correction excludes
`no_material_change`, which is a confirmation rather than evidence that the source was wrong.

```sql
WITH trust_events AS (
  SELECT
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'trust_level') AS trust_level,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'trust_model_version') AS model_version,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'evidence_class') AS evidence_class,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action') AS action,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'correction_scope') AS correction_scope
  FROM `PROJECT.analytics_DATASET.events_*`
  WHERE _TABLE_SUFFIX BETWEEN 'YYYYMMDD' AND 'YYYYMMDD'
    AND event_name IN ('food_trust_card_viewed', 'food_correction_action')
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'analytics_schema') = '2.3.2'
)
SELECT
  model_version,
  source,
  trust_level,
  evidence_class,
  COUNTIF(event_name = 'food_trust_card_viewed') AS card_views,
  COUNTIF(action = 'correction_saved') AS persisted_saves,
  COUNTIF(action = 'correction_saved' AND correction_scope != 'no_material_change') AS material_corrections,
  SAFE_DIVIDE(
    COUNTIF(action = 'correction_saved' AND correction_scope != 'no_material_change'),
    COUNTIF(event_name = 'food_trust_card_viewed')
  ) AS material_correction_rate
FROM trust_events
GROUP BY model_version, source, trust_level, evidence_class
HAVING card_views >= 100
ORDER BY material_correction_rate DESC;
```

This is an exposure-rate proxy, not a food-level causal join. One view can generate multiple
correction actions; only persisted `correction_saved` outcomes belong in the numerator.

## Correction funnel query

```sql
WITH actions AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'trust_level') AS trust_level,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'evidence_class') AS evidence_class,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action') AS action
  FROM `PROJECT.analytics_DATASET.events_*`
  WHERE _TABLE_SUFFIX BETWEEN 'YYYYMMDD' AND 'YYYYMMDD'
    AND event_name = 'food_correction_action'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'analytics_schema') = '2.3.2'
)
SELECT
  source,
  trust_level,
  evidence_class,
  COUNTIF(action IN ('trust_fix_opened', 'fix_opened', 'sanity_fix_opened', 'refine_opened')) AS opens,
  COUNTIF(action = 'correction_abandoned') AS abandoned,
  COUNTIF(action = 'correction_submitted') AS submitted,
  COUNTIF(action = 'correction_saved') AS saved,
  COUNTIF(action = 'correction_save_failed') AS save_failed,
  SAFE_DIVIDE(
    COUNTIF(action = 'correction_abandoned'),
    COUNTIF(action IN ('trust_fix_opened', 'fix_opened', 'sanity_fix_opened', 'refine_opened'))
  ) AS abandonment_rate
FROM actions
GROUP BY source, trust_level, evidence_class
ORDER BY opens DESC;
```

## Saved-correction reuse cohort

This measures whether an app instance that saved any correction later receives any
`custom_barcode` hit. It deliberately cannot prove reuse of the same food because no barcode or
food identifier is sent.

```sql
WITH saves AS (
  SELECT user_pseudo_id, MIN(event_timestamp) AS first_save_at
  FROM `PROJECT.analytics_DATASET.events_*`
  WHERE _TABLE_SUFFIX BETWEEN 'YYYYMMDD' AND 'YYYYMMDD'
    AND event_name = 'food_correction_action'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action') = 'correction_saved'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'analytics_schema') = '2.3.2'
  GROUP BY user_pseudo_id
), reuse AS (
  SELECT DISTINCT event.user_pseudo_id AS reuse_user_pseudo_id
  FROM `PROJECT.analytics_DATASET.events_*` AS event
  JOIN saves ON event.user_pseudo_id = saves.user_pseudo_id
  WHERE event._TABLE_SUFFIX BETWEEN 'YYYYMMDD' AND 'YYYYMMDD'
    AND event.event_name = 'barcode_lookup_outcome'
    AND event.event_timestamp > saves.first_save_at
    AND (SELECT value.string_value FROM UNNEST(event.event_params) WHERE key = 'source') = 'custom_barcode'
)
SELECT
  COUNT(*) AS app_instances_with_a_saved_correction,
  COUNTIF(reuse.reuse_user_pseudo_id IS NOT NULL) AS app_instances_with_later_custom_barcode_hit,
  SAFE_DIVIDE(COUNTIF(reuse.reuse_user_pseudo_id IS NOT NULL), COUNT(*)) AS later_reuse_rate
FROM saves
LEFT JOIN reuse ON saves.user_pseudo_id = reuse.reuse_user_pseudo_id;
```

## Decision rules

- Wait for at least 14 clean days and 100 Trust Card views in a reported source/band cell. Use
  95% confidence intervals; do not act on rank order from tiny cells.
- A healthy directional model has monotonically higher material-correction rates from Excellent
  to Strong to Review/Low. If not, inspect source and evidence mix before changing weights.
- Do not interpret abandonment as source inaccuracy. High abandonment points first to editor
  friction, unclear warnings, or low perceived value.
- Do not count `correction_submitted` as success, and do not count `no_material_change` as a
  material correction.
- Compare independent cross-verification with single-database evidence inside the same provider
  and Trust band where possible.
- Change a weight only when a repeated, adequately sized cohort shows the same direction. Record
  the evidence and increment `FoodTrustEvaluation.modelVersion` in the same release.

## Report output

For each model version, publish one internal table with source, band, evidence class, exposures,
material correction rate and interval, abandonment, save failure, dominant correction scope,
warning resolution, and later custom-barcode reuse cohort. End with one of three decisions:

- `hold`: data is sparse or directional behavior is acceptable;
- `investigate`: a provider/flow is anomalous but causality is unclear;
- `reweight`: a replicated cohort justifies a documented model-version change.
