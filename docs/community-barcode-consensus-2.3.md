# Community Barcode Consensus 2.3

This document is the implementation and rollout contract for MyFitPlate's community barcode
fallback. The private pipeline is built for internal 2.3 evaluation. Public rollout remains a
separate decision and `feature_communityBarcodeCorrections` stays off by default.

## Safety model

- A correction is private under `users/{uid}/barcodeContributions/{gtin}`. The UID exists only in
  the private document path; it is never copied into an aggregate, review, metric, or log.
- The app cannot create or update a contribution directly. It calls
  `submitCommunityBarcodeContribution`, which requires Firebase Authentication and valid App
  Check, validates a checksum-correct GTIN and bounded nutrition, and limits each account to 20
  accepted requests per UTC day.
- Owners may read or withdraw their own contribution. They cannot read another account's
  contribution or list/write the server collections.
- A server trigger groups private contributions by GTIN. It publishes only when at least three
  distinct accounts agree and at least two thirds of all eligible contributions belong to the
  winning nutrition cluster.
- Published fields contain nutrition, serving evidence, model/schema versions, aggregate counts,
  a rounded agreement ratio, revision, and timestamp. Contributor identifiers are forbidden by
  both Firestore Rules and the app parser.
- Established sources and the user's own saved correction remain ahead of community data in the
  lookup chain. A community match stays capped at the Review Trust band and is not described as
  independent database verification.

## Validation and consensus

Every submission must have:

- a GS1 checksum-valid GTIN-8, GTIN-12, GTIN-13, or GTIN-14;
- non-empty normalized name and serving text;
- calories from 0 through 5,000;
- protein, carbohydrate, fat, and optional fiber from 0 through 1,000 grams;
- serving weight from 10 through 5,000 grams;
- no unknown fields, control characters, booleans-as-numbers, or non-finite values;
- no hard nutrition-sanity finding.

Agreement uses bounded serving-weight, calorie, macro, and optional-fiber tolerances. The server
selects a deterministic winning cluster and publishes medians for numeric values and modes for
text. The resulting combined median must pass nutrition sanity again. Ties, insufficient support,
or implausible aggregate output remove any previously published document.

One account can contribute only once per barcode. A rebuild reads at most 251 documents. More
than 250 contributions withhold the aggregate with `contribution_volume_limit`, preventing an
unbounded recompute. A broader public release needs an incremental aggregation design before this
ceiling becomes a practical product limit.

## Server collections

| Path | Contents | Client access |
|---|---|---|
| `users/{uid}/barcodeContributions/{gtin}` | One private correction per user/barcode | Owner get/list/delete; no client create/update |
| `communityBarcodeAggregates/{gtin}` | Identifier-free published consensus | Signed-in known-document get only when operator config permits; no list/write |
| `communityBarcodeReviews/{gtin}` | Private status, counts, reason, and last aggregate snapshot | None |
| `communityBarcodeQuarantine/{gtin}` | Private operator block | None |
| `communityBarcodeMetrics/{yyyy-mm-dd}` | Aggregate event counters only | None |
| `communityBarcodeUsage/{uid}_{yyyy-mm-dd}` | Private per-account abuse counter | None |
| `internalConfig/communityBarcodeAggregation` | Private switches and thresholds | None |
| `barcodes/{gtin}` | Denied legacy pool pending migration/removal | None |

Account deletion recursively removes the user's private contributions and usage counters. The
Firestore delete events then rebuild or withdraw affected aggregates.

## Private operator config

Create `internalConfig/communityBarcodeAggregation` with explicit typed fields:

```text
acceptContributions: false
aggregationEnabled: true
publicReadsEnabled: false
killSwitch: false
minimumContributors: 3
minimumAgreementRatio: 0.67
```

Missing fields fail closed. Functions clamp the minimum to at least three contributors and at
least two-thirds agreement. Firestore Rules also enforce the baseline independently.

- `acceptContributions` controls the callable write path.
- `aggregationEnabled` controls server aggregation.
- `publicReadsEnabled` controls aggregate reads independently from collection.
- `killSwitch` immediately denies reads and causes all materialized aggregate documents to be
  deleted by `invalidateCommunityBarcodeAggregates`.
- Per-barcode quarantine uses `communityBarcodeQuarantine/{gtin}` with `blocked: true`. Deleting
  that quarantine document recomputes from private evidence.

## Deployment and migration

Do not combine these steps into one unobserved production change.

1. Keep `feature_communityBarcodeCorrections=false` in Remote Config.
2. Deploy Functions. This also moves the runtime from Node.js 20 to supported Node.js 22.
3. Deploy Firestore Rules and indexes. The new collection-group index is required by aggregation.
4. Create the private config above. Keep contributions and reads false.
5. Take an on-demand Firestore export using `scripts/firestore-backup.sh`.
6. From `tools/firestore-migrate`, run
   `node migrate.js --prod --dry-run --yes-i-took-a-backup` with the documented credentials,
   inspect the count, then run the guarded production migration. Migration 0002 writes each valid
   legacy correction to its owner's private path before deleting the legacy document. Invalid
   legacy records remain denied for manual review.
7. Confirm legacy `barcodes` is inaccessible, private documents contain no `createdBy`, and no
   aggregate has fewer than three contributors.
8. Enable `acceptContributions` only for the internal collection period. Keep public reads off.
9. For an app-level internal test, use a tester-targeted Remote Config condition and temporarily
   enable `publicReadsEnabled`. Verify agreement, conflict, withdrawal, quarantine, and kill-switch
   behavior with disposable accounts before any percentage rollout.

Required commands after merge:

```bash
firebase deploy --only functions --project caloriebeta-d28de
firebase deploy --only firestore:rules,firestore:indexes --project caloriebeta-d28de
```

These deployments are not performed by tests or dry runs.

## Rollback

1. Set `killSwitch=true`. Rules deny aggregate reads immediately.
2. Set `acceptContributions=false` and `publicReadsEnabled=false`.
3. Confirm `communityBarcodeAggregates` becomes empty and inspect private review/metric records.
4. Quarantine an individual GTIN when the fault is product-specific.
5. Keep the Remote Config feature false while correcting code or evidence.

Re-enabling after a global kill starts with no published aggregates by design. Fresh private
contributions rebuild the affected GTINs. A broad public rollout must add and test a bounded
administrative reaggregation job before relying on global re-enable at scale.

## Verification completed

- Functions build and 11 deterministic aggregation tests pass.
- Firestore Rules compile and 23 emulator behavior tests pass on Temurin JDK 21.
- Migration runner and migration 0002 pass 10 tests, including dry-run, preservation, and
  idempotency cases.
- Firebase Functions and Firestore Rules/indexes production dry runs pass.
- Core validates the aggregate model, exact GTIN, contributor limits, conflict math, and ratio;
  the app revalidates every aggregate and its nutrition before use.
- Full Core (999) and app (83) test suites, strict SwiftLint, and the unsigned iOS Release build
  pass after the client integration.

## Remaining public-rollout gates

- Run an internal soak with several real accounts and monitor conflicts, rejections, latency,
  trigger cost, App Check validity, and quarantine/kill-switch recovery.
- Decide whether stronger contributor independence is required. Authentication, App Check, and
  rate limits raise abuse cost but do not eliminate coordinated multi-account submissions.
- Build bounded administrative reaggregation before a broad rollout or threshold/model change.
- Set alert thresholds from observed internal traffic, then obtain Peter's explicit approval for
  any user-visible percentage rollout.
