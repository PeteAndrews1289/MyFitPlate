# My Foods Library 2.3 Contract

## Purpose

My Foods is the user's reusable food-data workspace. It closes the Trust correction loop without
turning Food Search into a management screen or allowing library cleanup to rewrite the diary.

## Storage boundary

- Library reads and mutations use only `users/{uid}/customFoods/{foodID}`.
- Dated diary entries are independent snapshots. Edit, barcode removal, delete, and duplicate
  merge do not query, patch, relink, or delete historical logs.
- Recent-food data is read only to display `Last used`; a match requires the saved food's exact ID,
  `sourceID`, or `matchedFoodID`. A same-name food is not treated as the same item.
- No migration or Cloud Functions deployment is required. Existing owner-scoped Firestore rules
  already cover these documents.

## User operations

- Search by food name or serving text.
- Filter all foods, personal barcode corrections, manual foods, recipes, recently used foods, or
  foods that need review.
- Sort by stable name, most recent use, or Trust.
- Edit the complete saved item in place while preserving its document ID and creation timestamp.
- Remove only the personal barcode association while retaining the saved food.
- Delete only the reusable saved copy.
- Review and merge exact duplicate copies in one atomic Firestore batch.

Every destructive confirmation states that diary history will not change. The visible model updates
only after persistence succeeds; a failed or offline write leaves the original item actionable.

## True-duplicate rule

Two saved foods are merge candidates only when all of the following match:

1. normalized name, serving description, and serving unit;
2. normalized barcode state;
3. original source category, including recipe provenance;
4. calories, macros, fat subtypes, fiber, serving weight, and quantity;
5. every stored micronutrient value, including the distinction between unknown and zero.

This deliberately prefers false negatives over destructive false positives. Similar names,
different serving bases, different barcode associations, different micronutrients, or different
source categories never merge. The keeper is the most recently used copy when identity-backed
history exists, then the higher-Trust copy, then a stable ID tie-breaker. At most 499 duplicates are
removed in one batch.

## Provenance and compatibility

Saving a non-manual item as custom records its prior source category in optional
`originSourceType`. This keeps saved recipes filterable after `sourceType` becomes `custom`.
The field is optional, so existing Firestore documents and cached JSON decode without migration.

Custom-food edits are full-document replacements. This is intentional: a merge write would retain
old optional fields that a user cleared, such as saturated fat, serving weight, or provenance.
Personal barcode removal uses a targeted nested-field deletion instead.

## Privacy and analytics

Analytics may include only aggregate library counts, filter enums, action enums, success, and item
count. Food names, search text, serving text, barcodes, nutrition values, document IDs, and account
identifiers are prohibited. Public community-barcode records are a separate system; removing a
personal association does not claim to remove a provider or public database match.

## Verification gate

- Core tests pin identity-backed last use, every filter, stable sorting, provenance compatibility,
  duplicate exclusions, keeper selection, and barcode detachment.
- App tests pin success-after-persistence behavior and failure-closed edit/delete/merge paths.
- Standard and accessibility-extra-extra-extra-large renders must remain legible and nonoverlapping.
- Full Core and app suites, SwiftLint, Debug simulator build, and unsigned generic-device Release
  build must pass before the slice is published.
