# Week in Motion 2.3 Contract

## Purpose

Week in Motion is the weekly expression of the Living Day system. It opens Reports with one
readable seven-day story before the existing timeframe controls, trend charts, report cards, and
exports. It does not replace those details or introduce a readiness, wellness, or food score.

## Source of truth

- `WeeklyRecapBuilder` remains authoritative for nutrition denominators, training history,
  timestamped run-recovery rules, Trust review status, records, and comparable-history changes.
- `WeeklyRecap` adds exactly seven chronological `WeeklyRecapDay` values. Each day contains only
  food presence, strength-session count, run count, and the existing demanding-strength flag.
- `WeekInMotionBuilder` is a pure editorial projection over one recap. SwiftUI performs no
  repository fetches or health calculations.
- Reports and the detailed sheet share one `WeeklyRecapLoader` result. Opening details does not
  create a second competing report; a direct detail deep link still loads independently.

No backend schema, Cloud Function, Firestore rule, or deployment is required.

## Visual hierarchy

1. literal `Week in Motion` label, rolling date range, and factual headline;
2. seven stable day positions with different shapes/icons for strength, running, mixed, rest,
   demanding strength, and food presence;
3. an unframed evidence trace for training rhythm, fuel coverage, recovery timing, and Trust;
4. exactly one bounded observation with its calculation basis;
5. a handoff to the existing detailed Training & Fuel report.

At accessibility Dynamic Type, the seven-column rhythm becomes a chronological semantic list.
Color never carries a state alone. Progress bars appear only when the adjacent sentence names the
same assessable denominator.

## Observation boundary

The builder selects at most one observation in this order:

1. no recorded activity;
2. missing food coverage on a recorded training day;
3. incomplete assessed run-recovery targets;
4. incomplete assessable hard-strength-day fuel;
5. unresolved review-required Trust entries;
6. a result that beat comparable prior history;
7. complete training-day diary coverage;
8. neutral diary coverage.

Pending recovery windows remain explicitly unscored. First attempts establish a baseline and are
not called records. Coverage confirms presence only; it does not claim nutrition quality or timing.
The observation never contains food, meal, exercise, routine, shoe, account, or route names and
never issues medical or autonomous goal advice.

## Sharing and privacy

The fixed Week in Motion image contains only the rolling date range, aggregate headline, seven
coarse day states, aggregate training/fuel/recovery/Trust values, and the bounded observation. It
excludes account IDs, document IDs, names, routes, coordinates, raw heart-rate samples, body values,
and nutrition values. The existing aggregate CSV remains unchanged and independently privacy
reviewed.

Analytics may emit aggregate counts plus coarse observation kind and tone enums. It must not send
day-level states, observation prose, names, search text, routes, nutrition/body values, or raw
Health data.

## Failure and performance behavior

- Week in Motion loads independently from the older Reports cards, so a failure does not hide
  weight, sleep, nutrition, or workout reports already available below it.
- A failed forced refresh keeps the previous recap rather than replacing it with zeros.
- Invalid or unavailable values keep a zero denominator and render as unavailable, not failure.
- Health route and heart-rate enrichment remain in the shared recap loader; individual visual
  rows never query HealthKit.

## Verification gate

- Core tests pin seven-day ordering, shape states, observation priority, pending recovery, explicit
  denominators, quiet weeks, and private-name exclusion.
- Standard, dark, accessibility-extra-extra-extra-large, and fixed-share renders must be legible,
  nonoverlapping, and unclipped.
- The real Reports screenshot must keep Week in Motion in the first viewport with detailed content
  visibly continuing below it.
- Existing populated, scrollable, and accessibility weekly-report UI tests must remain green.
- Full Core/app tests, SwiftLint, Debug simulator build, and unsigned generic-device Release build
  must pass before publication.
