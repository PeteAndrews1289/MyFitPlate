# App Store Metadata - 2.2

This is the paste-ready default product-page story for 2.2. It leads with the
specific reason to switch: trustworthy nutrition logging built for people who train.

## Default product page

**Name:** MyFitPlate

**Subtitle (28/30 characters):**

```text
Nutrition Built for Training
```

**Promotional text:**

```text
Log food you can trust, build real restaurant orders, and connect nutrition to your workouts, recovery, meal plans, and progress with Maia.
```

**Keywords (85/100 characters):**

```text
macro tracker,calorie counter,food log,protein,meal planner,workout,running,nutrition
```

Do not add competitor names, `app`, category names, or duplicate plurals to the
keyword field.

## Description

```text
MyFitPlate is the food log you can trust, built for people who train. Log meals quickly, see where nutrition data came from, and connect every day of eating to workouts, recovery, and measurable progress.

LOG FASTER
- Search multiple nutrition databases at once
- Scan barcodes and nutrition labels
- Log by voice, photo, text, recent foods, or yesterday's meals
- Import compatible diary and weight history without overwriting days already logged

KNOW WHAT YOU CAN TRUST
- See the source and review status for each food
- Review cross-checks and nutrition-math sanity checks
- Correct questionable entries and reuse your saved version
- Keep AI estimates visibly labeled and editable

NUTRITION BUILT FOR TRAINING
- Follow structured strength programs or build your own routines
- Track working sets, warmups, supersets, RPE, RIR, rest, and progression
- Record runs with splits, routes, heart-rate context, and recovery guidance
- Connect Apple Health on your terms

EAT IN THE REAL WORLD
- Build custom orders across 25 popular restaurant chains
- Review portions, calories, macros, and available sodium before logging
- Scan restaurant menus for reviewable meal estimates
- Turn pantry ingredients and remaining macros into a practical meal

MEET MAIA
- Start with useful nutrition and recovery actions instead of a blank chat
- Turn remaining calories and macros into structured meal suggestions
- Review and edit AI-generated actions before logging
- Control AI data sharing and optional Apple Health context separately

SEE WHETHER IT IS WORKING
- Follow smoothed weight trends instead of reacting to daily noise
- Review nutrition consistency, training frequency, and weekly progress
- Plan seven days of meals against your calorie and macro targets
- Share weekly recaps, workout summaries, achievements, and run stories

MyFitPlate provides fitness and nutrition tools, not medical advice. Nutrition and AI estimates should be reviewed before use.
```

## Screenshot order

Use the final eight-shot sequence in `docs/app-store-screenshots.md`. The first
three screenshots must remain Home, Trust, and Food Search because they are the
complete positioning and activation story visible from search results.

## Custom product pages

Create these after the default 2.2 page is approved. They reuse the existing assets,
so they do not require another binary.

### Lifters

- **Order:** Home, Train, Maia, Reports, Trust, Food Search, Builder, Meal Plan.
- **Promotional text:** Track macros you can trust, run your next workout, and turn
  training into one practical nutrition decision at a time.
- **Link destination:** Train tab when App Store Connect deep-link configuration is
  available for the intended OS versions.

### Real-world dining

- **Order:** Builder, Trust, Food Search, Home, Maia, Reports, Meal Plan, Train.
- **Promotional text:** Build the meal you actually ordered, adjust every portion,
  and review its nutrition before it enters your day.
- **Link destination:** Fast Food Builder.

### Runners

- Prepare after 2.2 using the recorder, route detail, recovery handoff, Reports, and
  Trust screens. Do not publish a runner page using generic lifting screenshots.

### Switchers

- Prepare after 2.2 using the import preview, no-overwrite explanation, first-session
  choice, Food Search, Trust, and Home screens.
- Competitor trademarks may be used only where App Store policy and the actual import
  behavior permit them; never place competitor names in the keyword field.

## Custom product page deep-link boundary

Version 2.3 adds exact queued routes for the following destinations:

| Destination | URL |
|-------------|-----|
| Food Search | `myfitplate://food-search` |
| Trust Hub | `myfitplate://trust` |
| Fast Food Builder | `myfitplate://builder` |
| Running | `myfitplate://runs` |
| Meal Plan | `myfitplate://meal-plan` |

Do not attach these exact routes to a live custom product page while 2.2 is the current
binary. The 2.2 app recognizes only the older broad tab routes and would fall back to Home
for several of these URLs. Custom pages may publish with screenshots, promotional text,
and approved keyword assignments now; add the exact deep links only after 2.3 is approved.

The 2.3 coordinator queues the latest requested route while login, onboarding, or a first-
session sheet is active, then opens it from the stable app shell. Every route must still be
tested from Notes while signed in and signed out before it is added in App Store Connect.

## Launch-week routine

1. Record the release timestamp and existing rating/review count.
2. Check crash rate, product-page conversion, first-time downloads, D1 retention, and
   D7 retention in App Store Connect against peer-group percentiles.
3. In Firebase Analytics, watch `onboarding_completed`, `first_food_logged`,
   `first_workout_completed`, and `nutrition_training_loop_completed`. Compare the
   `elapsed_seconds` distribution for the first-value events.
4. Review `first_session_choice_selected`, `mfp_import_started`,
   `mfp_import_completed`, barcode recovery, and quick-log source events for the
   activation path that succeeds most often.
5. Read and respond to every substantive review. Route technical reports into the
   release-health checklist instead of debating them in public.
6. Treat fewer than 20 serious new users as qualitative evidence, not a statistically
   meaningful conversion experiment. Interview and support them directly.
7. Do not buy ads until the first-log funnel is reliable and D7 retention is at least
   competitive with the App Store peer median.
