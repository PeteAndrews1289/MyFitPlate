# App Store Screenshots — 2.2

The listing still shows the old app. These six shots tell the new story: calm design,
trustworthy data, and nutrition + training that talk to each other. The first two matter
most — they render in search results before anyone taps.

## The six-shot narrative

| # | Screen | Headline | Subline |
|---|--------|----------|---------|
| 1 | Home (rings + streak + diary) | Your whole day, one glance | Calories, macros, and momentum — front and center |
| 2 | Food Detail with Cross-Verified badge + sanity card | Nutrition you can trust | Every food checked against real math, verified across databases |
| 3 | Log Food (search + chips + results) | Log anything in seconds | Search, scan, snap, or just describe it |
| 4 | Workout player mid-session | Training that runs itself | 27 programs, smart progression, rest timers on your lock screen |
| 5 | Fill-my-macros card + Maia suggestion sheet | Meet Maia, your AI coach | She builds dinner from your pantry and your remaining macros |
| 6 | Weekly Recap sheet | Watch your week add up | Days logged, volume moved, records set — shareable in one tap |

## Capture instructions (your device)

- Light mode, full battery icon hidden is fine (Apple doesn't require status-bar cleanup, but
  9:41 looks pro: Settings → Developer → Status Bar override, or just don't worry about it).
- Use your real account — real data reads as real. Check each screen against DESIGN.md's
  squint test before capturing.
- Shot 1: log enough food that the rings show progress; streak flame visible in the date bar.
- Shot 2: scan a barcode that cross-verifies (name-brand packaged food usually does), or
  search a food and open one with the badge.
- Shot 4: start a real workout, complete a set or two so the progress bar shows life.
- Shot 5: after 3pm with calories remaining, capture Home's card; then tap it and capture
  the suggestion sheet (pick whichever composes better).
- Shot 6: open Your Week when the recap has at least one PR if possible.
- Screenshot normally (side button + volume up). AirDrop the PNGs to the Mac.

## Pipeline

1. Drop raw captures into `tools/screenshots/raw/` named `1.png` … `6.png`
   (order matches the table above).
2. `cd tools/screenshots && python3 compose.py`
3. Framed, captioned, App Store-sized images appear in `tools/screenshots/output/`.
4. Upload to App Store Connect (6.9-inch display set; Apple scales the rest, or re-run
   with `--size 1284x2778` for the 6.5-inch set).

Captions and ordering live in `tools/screenshots/shots.json` — edit freely and re-run.
