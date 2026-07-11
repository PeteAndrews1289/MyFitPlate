# App Store Screenshots - 2.2

The 2.2 gallery leads with MyFitPlate's clearest advantage: trustworthy nutrition
logging built for people who train. The sequence moves from the daily loop through
trust, logging, dining, training, coaching, planning, and measurable progress.

## Final eight-shot narrative

| # | Screen | Headline | Subline |
|---|--------|----------|---------|
| 1 | Home | Nutrition built for training | Calories, macros, hydration, and today's next move |
| 2 | Trust detail | Know what you can trust | Sources, cross-checks, review status, and nutrition sanity |
| 3 | Food Search | Log meals in seconds | Repeat yesterday or search three trusted databases |
| 4 | Fast Food Builder | Build the meal you ordered | Choose portions across 25 chains, then review every macro |
| 5 | Train | Your next workout, ready | Programs, progression, sets, and one clear next step |
| 6 | Maia | Meet Maia, your action coach | Turn remaining macros and training into practical actions |
| 7 | Meal Plan | Plan a week that fits | Every meal measured against your calorie and macro targets |
| 8 | Reports | See whether it's working | Smoothed weight, nutrition scores, and training consistency |

The first three images carry the main conversion story and should remain first. The
Quick Log menu is captured as `alternate-quick-log.png` for review or later listing
experiments, but it is not stronger than Food Search in the primary sequence.

## Current deliverables

- `tools/screenshots/output/appstore-01-1320x2868.png` through
  `appstore-08-1320x2868.png`: 6.9-inch iPhone set.
- `tools/screenshots/output/appstore-01-1284x2778.png` through
  `appstore-08-1284x2778.png`: 6.5-inch iPhone set.
- `tools/screenshots/raw/`: unframed simulator captures used by the compositor.

All current images use deterministic local demo data. They contain no personal
account data and do not call production nutrition, HealthKit, or AI services.
The current gallery was recaptured after the final compact, outlined Quick Log
refinement, so no output contains the older right-edge placement or filled teal action.
The Trust source (`raw/2.png`) was recaptured again after Trust Score model v2 hardening;
both final output sizes now show the separate Source, Verification, Your Review, and
Nutrition Check facts with the higher-contrast score treatment.

## Deterministic recapture

The screenshot fixture exists only in Debug builds. Build and install MyFitPlate on a
booted iPhone simulator, then launch one screen at a time:

```sh
xcrun simctl launch --terminate-running-process booted MyFitPlate.CalorieBeta \
  -ui-testing -screenshot-mode -screenshot-screen home
sleep 20
xcrun simctl io booted screenshot tools/screenshots/raw/1.png
```

Use the following screen and file pairs:

| Screen argument | Raw file |
|-----------------|----------|
| `home` | `1.png` |
| `trust` | `2.png` |
| `food-search` | `3.png` |
| `builder` | `4.png` |
| `train` | `5.png` |
| `maia` | `6.png` |
| `meal-plan` | `7.png` |
| `reports` | `8.png` |
| `quick-log` | `alternate-quick-log.png` |
| `settings` | UI-verification target only; not in the primary gallery |
| `runs` | 2.3 deterministic Running history fixture |

Custom-product-page aliases resolve to the same deterministic destinations:

| CPP argument | Destination |
|--------------|-------------|
| `cpp-trust` | Trust detail |
| `cpp-logging` | Food Search |
| `cpp-dining` | Fast Food Builder |
| `cpp-strength` | Train |
| `cpp-running` | Running history with fixture runs |
| `cpp-weight` | Reports |
| `cpp-meal-plan` | Meal Plan |

The Running fixture bypasses HealthKit only in Debug screenshot mode. It supplies four
deterministic runs with splits, route availability, heart-rate summaries, and mixed source
badges so a custom Running page never captures a permission prompt, loading spinner, empty
state, or personal workout history.

Wait at least 20 seconds for each destination to settle before capturing. This also
lets translucent tab-bar layers become fully opaque in the simulator screenshot's
alpha channel before composition. Do not replace these fixtures with a personal
account: deterministic data makes the gallery reproducible and avoids accidentally
publishing private health or nutrition history.

For dark-mode visual QA, add `-screenshot-dark-mode` to the same Debug launch command.
This switch is for inspection only; the App Store gallery remains the approved light set.

Screenshot mode pins Food Search and Fast Food Builder to Dinner so their story does
not change with the capture time. This override is Debug-only; ordinary app launches
still choose the default meal from the current time.

## Composition pipeline

The compositor requires Python and Pillow. The Codex bundled Python runtime includes
Pillow; a normal Python installation can also be used after installing it.

```sh
cd tools/screenshots
python3 compose.py
python3 compose.py --size 1284x2778
```

Captions and ordering live in `tools/screenshots/shots.json`. The compositor uses SF
Rounded, flattens simulator transparency onto white, adds the brand-green field, and
writes RGB PNG files to `tools/screenshots/output/`.

Before uploading, visually inspect all 16 outputs at full size and confirm the exact
pixel dimensions. Upload the 6.9-inch set first; keep the 6.5-inch set available where
App Store Connect requests it.

Custom product pages can reorder the approved default images immediately. New Running
screens still need dedicated captions and composition before publication; the raw
`cpp-running` fixture is a repeatable source, not a finished App Store asset by itself.
