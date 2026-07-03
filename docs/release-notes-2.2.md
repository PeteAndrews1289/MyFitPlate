# MyFitPlate 2.2 — Release Notes

## App Store "What's New" (paste-ready)

```
Our biggest update yet: a fresh look, your week at a glance, and food data you can actually trust.

A FRESH LOOK
• New app icon and one calm, consistent color palette (dark-mode icon included).
• Redesigned Home, workout player, weight tracking, reports, and meal planner — every screen now leads with the one thing that matters.

YOUR WEEK, UNDERSTOOD
• Weekly Recap — workouts, new records, calorie averages, and weight trend in one card you can share.
• Logging streak with a built-in grace day, right in the date bar.
• Fill my macros — from mid-afternoon on, Maia can suggest a dinner that fits exactly what you have left today (and can build it from your pantry).

FOOD DATA YOU CAN TRUST
• Every food is checked against nutrition math. Bad database entries get flagged with a clear "This data looks off" card, and one tap opens an editor to fix them — your fix is remembered.
• Cross-Verified badge when two independent databases agree on a barcode.
• Search now blends USDA data, so more foods come with complete vitamins and minerals — and quick-logging captures full nutrition, not a preview.
• AI photo and menu estimates get a one-tap "Refine Estimate" to dial in portions.

AND MORE
• Fasting Live Activity on your lock screen and in the Dynamic Island.
• Export your food diary and workouts as CSV any time, from Settings.
• Accessibility improvements and reliability fixes throughout.
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
| Design system | DESIGN.md written (one hero, green-means-something, type/copy rules) + Train screen; app-wide sweep incl. calorie-goal reset fix | 31515892, 3d04b7ca |
| Design: structure | Home hero restructure + emoji-tiles decision; Food Search chip row; quick-log menu; weight tracking rebuild; Reports (trend = hero); Meal Plan + Maia passes | c8b05aec, 08900aa7, 28b751a2, febaa786, 183631a4 |
| Workout player | Compact header + one-row control bar (~200pt returned to set cards); Auto-rest label clamp | cfd27cb7, 592522bc |
| Weekly Recap | Core builder (PR/weight/volume math) + Your Week sheet, shareable card, Home entry | 62522604, b4814cae, 682e26ce |
| Fill my macros | Home card ≥3pm → Maia dinner from remaining macros + pantry; decoder fix (was rejecting every AI response) | 7751ba27, 14ec9154, d4d6b8d7 |
| Streak | Grace-day streak math (Core) + flame in Home's date bar | 6e49409d |
| Motion | DESIGN.md §7: one spring, number roll-ups, haptics map, PR celebration | e4f64f7d |
| Food data | Micronutrient ingestion fixed: quick-log hydrates full nutrition, USDA merged into search, OFF potassium unit slip | 805114ea |
| Data export | Food diary + workout CSVs from Settings (RFC 4180) | a2bfd78b |
| Fasting | Live Activity polish (lock screen + Dynamic Island; verified on hardware) | a2bfd78b |
| Stability | Weekly Recap crash (WorkoutService injection) + fill-my-macros silent failure, from device reports | 09d3eb15, d4d6b8d7 |
| Brand | New app icon (deep-green MFP monogram, iOS 18 dark/tinted) + tuned one-family palette (DESIGN.md §2a); Watch icon matched | c49a9b25, b32c9a9e |
| Marketing | App Store screenshot pipeline: narrative, captions, compositor | 54105645 |
| Infra | firestore.indexes.json live snapshot (unblocks rules deploys) | b850a43f |
| Release | Version 2.2 (build 3) across app + extensions; accessibility pass on main flows | ac243e5a, c4da8f6c |

## Before archive
1. **Revoke the watch Gemini API key** in Google AI Studio. The old watch Recipe Bot bundled `Secrets.plist` into the watch app (synced folder groups auto-include it), so the key shipped inside every build that contained the watch app — treat it as public. The bot and the plist are removed from the build; revoking the key closes it out.
2. Recapture the six App Store shots on-device (current composites show the pre-tune accent colors), rerun `tools/screenshots/compose.py`, upload.
3. Device sanity: Weekly Recap opens, fill-my-macros suggests after 3pm, streak flame shows, new icon on home screen + watch; watch check: Today glance shows live numbers, crown-log water lands on the phone.
4. Confirm version/build across app + extensions still aligned.

## Post-release checklist
1. Flip `feature_communityBarcodeCorrections` → `true` in Firebase Console → Remote Config (instant kill switch: set back to `false`).
2. Watch Firebase → Analytics → Events: `food_data_suspicious`, `food_correction_action`, funnel events, `weekly_recap_viewed`.
3. Watch Crashlytics non-fatals for `operation`-tagged failures (data layer + `decode_meal_suggestion`).
