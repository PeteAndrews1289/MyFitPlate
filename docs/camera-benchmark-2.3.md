# Camera Benchmark 2.3

## Status

Not yet run. This document defines the fixed set and scoring record; it is not evidence of an
accuracy improvement by itself.

Keep benchmark photos outside Git unless they are deliberately sanitized and approved for source
control. Use the same files, in the same order, for every baseline and candidate run.

## Fixed 25-Image Set

Before the first run, record a local filename and the known facts that a useful result should
preserve. Do not change the set after seeing candidate output; add a separately versioned set when
new failure modes need coverage.

| ID | Workflow | Required scenario | Local photo reference | Known facts / review target |
| --- | --- | --- | --- | --- |
| M01 | Meal | Single plated food with known weight |  |  |
| M02 | Meal | Single food without scale |  |  |
| M03 | Meal | Two clearly separated foods |  |  |
| M04 | Meal | Mixed plate with three or more items |  |  |
| M05 | Meal | Bowl, stew, or mixed grain dish |  |  |
| M06 | Meal | Soup with partly hidden ingredients |  |  |
| M07 | Meal | Restaurant entree and sides |  |  |
| M08 | Meal | Visible sauce or dressing |  |  |
| M09 | Meal | Likely hidden oil, butter, or filling |  |  |
| M10 | Meal | Caloric beverage |  |  |
| M11 | Meal | Poor lighting or awkward angle |  |  |
| M12 | Meal | Missing visual scale and ambiguous portion |  |  |
| M13 | Meal | Unusable or non-food image |  | Must return no invented food. |
| L01 | Label | Clear single-serving nutrition label |  |  |
| L02 | Label | Multi-serving package label |  |  |
| L03 | Label | Label with missing optional micronutrients |  | Missing must remain missing. |
| L04 | Label | Glare, crop, or low-confidence label |  | Must fail or request review honestly. |
| U01 | Menu | Clear menu with prices and descriptions |  |  |
| U02 | Menu | Dense multi-column menu |  |  |
| U03 | Menu | Menu item with ambiguous preparation |  |  |
| C01 | Receipt | Short grocery receipt |  |  |
| C02 | Receipt | Long receipt with discounts or repeats |  |  |
| R01 | Recipe | Printed recipe page |  |  |
| R02 | Recipe | Handwritten or visually noisy recipe |  |  |
| R03 | Recipe | Recipe missing quantities or yield |  | Must preserve ambiguity. |

## Run Record

Run with a dedicated temporary Firebase account and no unrelated AI calls. Record one row per
baseline and candidate.

| Field | Baseline | Candidate |
| --- | --- | --- |
| Run date and UTC day |  |  |
| App commit/build |  |  |
| Functions commit/deployment |  |  |
| Device, OS, and network |  |  |
| Firebase test UID |  |  |
| Route/model table |  |  |
| Fixed-set revision | `camera-25-v1` | `camera-25-v1` |

## Per-Image Results

Copy this row for all 25 images and both runs.

| Run | ID | Usable result | Identity 0-2 | Expected / returned items | Portion in range | Risk or question surfaced | Bad reference match | Correction scope | Malformed / failure | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |  |

Scoring contract:

- Identity `0`: wrong or unsafe; `1`: useful generic identity; `2`: correct useful identity and
  preparation.
- Portion in range is `yes`, `no`, or `n/a` when no defensible known portion exists.
- Correction scope is `none`, `minor` (one low-impact field), `major` (identity, item separation,
  portion, or multiple fields), or `reject` (faster/safer to discard).
- A reference match is bad when identity or preparation does not support the composition used.
- A risk/question counts only when it addresses a material hidden ingredient or ambiguity.

## Private Usage Summary

In Firestore, filter `aiUsageBreakdown` by the test UID and UTC day. Copy one row per workflow/model
document. The document is aggregate-only and must contain no image, prompt, response, or food name.

| Run | Workflow | Model | Success | Failure | Input tokens | Output tokens | Total tokens | Total latency ms | Mean latency ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |  |

Mean latency is `totalLatencyMs / (successfulCount + failedCount)`. Use the OpenAI invoice as the
cost source of truth; token totals explain the route contribution but do not replace billed cost.

## Release Decision

The candidate is acceptable only when all safety invariants hold:

- no image writes food to the diary before confirmation;
- M13 returns no invented food;
- missing label or recipe values remain missing or explicitly uncertain;
- malformed responses never become editable nutrition silently;
- composition references are not presented as independent photo verification; and
- every failed request leaves a recoverable UI state.

For quality, compare baseline and candidate on identity, item separation, portion-range coverage,
material risk/question coverage, bad reference matches, and major/reject correction rate. Record
latency, failures, and billed cost alongside quality. Do not approve an accuracy claim from prose
quality alone, and do not accept a candidate that improves average results by hiding uncertainty.

After recording the aggregate results, delete the temporary account and confirm account deletion
removes its `aiUsage` and `aiUsageBreakdown` documents.
