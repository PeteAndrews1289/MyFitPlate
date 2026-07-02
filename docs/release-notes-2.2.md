# MyFitPlate 2.2 — Release Notes

## App Store "What's New" (paste-ready)

```
Food data you can actually trust.

• Nutrition sanity check — every food is checked against nutrition math. Bad database entries (impossible calories, unit mistakes) get flagged with a clear "This data looks off" card.
• Fix This Data — one tap opens an editor to correct any flagged entry. Your fix is remembered for future scans and searches.
• Cross-Verified badge — when two independent databases agree on a barcode, we tell you. When they don't, you'll know to double-check.
• AI estimates, refined — every AI photo or menu estimate now has a one-tap "Refine Estimate" so you can dial in portions in seconds.
• Smarter search — foods you've saved, fixed, or logged before now rank above generic database results.
• Accessibility improvements and general reliability fixes.
```

## Internal changelog (2.1 archive → 2.2)

| Area | Change | Commits |
|---|---|---|
| Reliability | Silent data-layer failures now report Crashlytics non-fatals + user toasts | fb1e448b |
| Food trust | FoodDataSanity checker (Atwater, unit slips, physical impossibility) + detail card + row badges + `food_data_suspicious` telemetry | f47fe949 |
| Analytics | Activation funnel: onboarding_completed / first_food_logged / first_workout_completed (once per install) | f47fe949 |
| Food trust | Cross-source agreement: per-100g comparison, `crossVerifiedBy` metadata, "Cross-Verified" descriptor | 6334f5cb |
| Food trust | Community barcode-correction pool — **dark**, flag `communityBarcodeCorrections` (Remote Config `feature_communityBarcodeCorrections`); rules deployed, flip after 2.2 is live | 29fddecd |
| Food trust | AI-estimate refine card + `food_correction_action` telemetry (per-source fix/remember rates) | fd505665 |
| Infra | firestore.indexes.json live snapshot (unblocks rules deploys) | b850a43f |
| Release | Version 2.2 (build 3) across app + extensions; accessibility pass on main flows | this batch |

## Post-release checklist
1. Flip `feature_communityBarcodeCorrections` → `true` in Firebase Console → Remote Config (instant kill switch: set back to `false`).
2. Watch Firebase → Analytics → Events: `food_data_suspicious`, `food_correction_action`, funnel events.
3. Watch Crashlytics non-fatals for `operation`-tagged data-layer failures.
