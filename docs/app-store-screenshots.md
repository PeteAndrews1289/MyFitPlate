# App Store Screenshots - 2.3

The 2.3 gallery expresses MyFitPlate's product model in order: signal, evidence, action.
It leads with the food-and-training loop, proves the Trust Receipt, shows Maia's practical
next step, and then demonstrates reviewable logging, dining, live strength, muscle recovery,
and measurable progress.

## Final eight-shot narrative

| # | Screen | Headline | Subline |
|---|--------|----------|---------|
| 1 | Living Day | See your whole day in motion | Food, training, hydration, and one clear next step |
| 2 | Trust Receipt | Know what you can trust | Field-level sources, checks, and corrections you control |
| 3 | Maia | Act on what matters next | Food and training context, turned into a practical next step |
| 4 | Meal estimate review | Review before you log | Edit every estimate before anything enters your diary |
| 5 | Fast Food Builder | Build the order you ate | Choose portions across 25 chains and watch macros update |
| 6 | Live strength workout | Run every set with context | Log load, reps, effort, rest, and progression in one flow |
| 7 | Recovery Field | See recovery by region | Select a region and inspect the training evidence behind it |
| 8 | Reports | See whether it's working | Weight, nutrition, training, and data quality in one view |

The first three images carry the 2.3 promise and should remain first. Meal Plan, Running,
Food Search, and Quick Log remain viable custom-product-page or product-page-optimization
alternates; the default gallery favors the features that are both most differentiated and
most visually legible without personal data.

## Current deliverables

- `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-39e3d1a2/Screenshots/iPhone/output/`
  contains eight 1320x2868 and eight 1284x2778 RGB iPhone images.
- The sibling `raw/` directory contains the eight unframed simulator captures used by the
  compositor.
- `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-39e3d1a2/Screenshots/Watch/output/`
  contains the 416x496 RGB Watch capture.

All current images use deterministic local demo data. They contain no personal account data and do
not call production nutrition, HealthKit, or AI services. They were freshly captured and visually
approved on July 17 from the final 2.3 UI. Candidate `39e3d1a2` changes only release-key packaging
after that UI commit, so the captures remain an exact visual representation of the submitted app.

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
| `maia` | `3.png` |
| `ai-text-results` | `4.png` |
| `builder` | `5.png` |
| `workout-player` | `6.png` |
| `muscle-recovery` | `7.png` |
| `reports` | `8.png` |
| `quick-log` | `alternate-quick-log.png` |
| `food-search` | Default-page or logging-page alternate |
| `meal-plan` | Default-page or planning-page alternate |
| `runs` | Deterministic Running custom-product-page fixture |
| `settings` | UI-verification target only; not in the primary gallery |

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

The release-draft raw files can also be exported directly from the definitive UI result's
attachments. This is equivalent to launching each deterministic route and avoids recapturing
transient animation states. Keep the source result and its attachment manifest with local release
evidence; neither belongs in Git.

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

All 16 iPhone outputs were inspected at full size and verified as RGB PNGs without alpha. Upload the
6.9-inch set first; keep the 6.5-inch set available where App Store Connect requests it. The Watch
output is also RGB without alpha at 416x496.

Default product-page copy, App Review notes, custom product page plans, and the featuring
nomination are in `docs/app-store-metadata-2.3.md`.

Custom product pages can reorder approved default images immediately. Running, planning, and
logging pages should use their deterministic alternates and dedicated captions rather than imply
that a default-gallery image shows a feature it does not.
