# App Store Metadata - 2.3

This is the paste-ready product-page and review package for version 2.3. It follows the
current 2.3 positioning: **the food log you can trust, built for people who train**.

Apple's current limits were rechecked on 2026-07-17: 30 characters for the subtitle,
170 for promotional text, 4,000 for the description, and 100 bytes for keywords.
References: [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/),
[app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/),
and [custom product pages](https://developer.apple.com/app-store/custom-product-pages/).

## Default product page

**Name:** Keep the current `MyFitPlate: Macro Tracker` name.

**Subtitle (25/30 characters):**

```text
Food Trust Meets Training
```

**Promotional text (159/170 characters):**

```text
See food and training as one living day. Review every source, correct estimates before logging, and let Maia turn today's context into one practical next step.
```

**Keywords (100/100 bytes):**

```text
calorie,counter,protein,nutrition,meal,planner,workout,weight,loss,barcode,scanner,water,running,gym
```

Do not add competitor names, `app`, the developer name, or repetitions of `MyFitPlate`,
`macro`, or `tracker`. Keep the primary category as Health & Fitness and use Food & Drink as
the secondary category if those remain the current selections.

## Description

```text
MyFitPlate is the food log that shows its work, built for people who train. Bring meals, workouts, hydration, and recovery into one living day. See where food data came from, correct estimates before they affect your totals, and get one practical next step from Maia.

SEE YOUR WHOLE DAY
- Living Day combines logged meals, planned meals, workouts, recovery, and hydration in one timeline
- See consumed and planned calories, protein, carbs, and fat against your goals
- Log water from the first screen and keep Quick Log within reach
- Review your Week in Motion without turning every signal into a single score

KNOW WHAT YOU CAN TRUST
- See calories and macros first, then explore reported vitamins and minerals with general label % Daily Value
- Open a Trust Receipt for source lineage, nutrition checks, evidence coverage, and review status
- Search food data from USDA FoodData Central, Health Canada, FatSecret, Open Food Facts, and NIH supplement labels
- See what was source-reported, cross-checked, estimated, missing, or corrected
- Fix questionable fields and reuse your reviewed food without stale values returning

LOG FAST WITHOUT LOSING CONTROL
- Search, scan barcodes and labels, describe a meal, or start from recent and saved foods
- Review meal photos, menus, receipts, recipes, and text estimates before anything enters your diary
- Edit or remove every estimated item and keep uncertainty visible
- Build the order you ate across 25 restaurant chains with responsive portions and macro totals
- Import compatible diary and weight CSV history without overwriting days already logged

TRAIN WITH CONTEXT
- Follow structured strength programs or build your own routines
- Log load, reps, warmups, drop sets, supersets, RPE, RIR, rest, and progression in one workout flow
- Record or import runs with routes, splits, heart-rate context, and recovery-fueling guidance
- Select regions in Recovery Field to inspect the recent training evidence behind each estimate
- Use Apple Watch, widgets, notifications, and Live Activities for useful context beyond the phone

TURN CONTEXT INTO ACTION
- Maia turns today's food and training state into one practical next step
- Review structured actions before they change your log or plan
- Choose coaching tone and a supported system voice for Read Aloud
- Generate measured meal plans, keep a synchronized grocery list, and use pantry-aware suggestions
- Review weight, nutrition, running, strength, and data-quality trends without hiding the underlying evidence

YOUR DATA, YOUR CHOICE
- Apple Health and AI context are optional and controlled separately
- AI estimates stay labeled and editable
- Account deletion is available in the app
- MyFitPlate does not use advertising tracking

MyFitPlate provides fitness and nutrition tools, not medical advice. Food data, recovery estimates, and AI-generated suggestions should be reviewed before use.
```

## What's New

```text
Version 2.3 brings food, training, hydration, and recovery into one clearer daily story.

- Living Day shows what happened, what is planned, and what matters next.
- Food Detail now puts calories and macros first, keeps Trust compact, and opens the complete Evidence receipt one tap away.
- Nutrient Profile expands reported vitamins and minerals with label % Daily Value and keeps missing fields distinct from zero.
- Maia now starts from today's real context and offers one practical, reviewable next step.
- Meal, label, menu, receipt, and recipe estimates stay editable and do not enter your diary before confirmation.
- Food search adds Health Canada nutrient data and NIH supplement labels with honest source language.
- Fast Food Builder now covers 25 chains with searchable menus, portion controls, source links, and live totals.
- Strength logging, running details, Reports, Meal Plan, Grocery, Watch, widgets, and Live Activities share one refined design.
- Recovery Field lets you select a muscle region and inspect the training evidence behind its estimate.
- Adaptive TDEE now withholds implausible results and explains when the diary does not contain enough reliable evidence.

This update also includes accessibility, reliability, privacy, and data-integrity improvements throughout.
```

## Screenshot order

Use the eight-shot default sequence in `docs/app-store-screenshots.md`:

1. Living Day
2. Nutrition-first Food Detail and Evidence
3. Maia next action
4. Review-before-log meal estimate
5. Fast Food Builder
6. Live strength workout
7. Recovery Field
8. Reports

Do not replace these deterministic fixtures with screenshots from a personal account. The approved
upload set is in `/Volumes/T7 Developer/MyFitPlate/ReleaseArtifacts/2.3-6a5e535e/Screenshots/`.

## App Review information

### Credentials

Enter a dedicated review account directly in App Store Connect. Do not put its password in Git.

```text
Username: [APP REVIEW ACCOUNT EMAIL]
Password: [APP REVIEW ACCOUNT PASSWORD]
```

Seed the account with one week of deterministic-looking meals, at least one completed strength
workout, one planned day, and no personal health or route data. Confirm the credentials immediately
before submission.

### Review notes

```text
MyFitPlate 2.3 is a nutrition and training app. A review account is provided above because the primary experience is account-scoped.

Suggested review path:
1. Sign in and open Home. Living Day combines logged and planned nutrition, hydration, training, and one next action.
2. Open any food from the timeline or use Quick Log > Search Food. Calories and macros lead Food Detail, reported vitamins and minerals remain visible, and the compact Food Trust passport opens the complete Evidence receipt. Missing nutrient fields are not treated as zero.
3. Use Quick Log > Describe a Meal. The estimate opens in Confirm Meal and nothing is written until Log Items is tapped. Every item can be edited or removed first.
4. Open Quick Log > Fast Food Builder. Select a chain, change a portion, and confirm the totals update before review.
5. Open Train to review programs and the workout player. Muscle Recovery opens the selectable Recovery Field and its supporting evidence.
6. Open Maia to see the current-day context and reviewable next action. AI consent is requested before remote AI processing.
7. Open Reports for weight, nutrition, training, running, and data-quality evidence.
8. Open Settings > Nutrition Data Sources for USDA, Health Canada, NIH, FatSecret, and Open Food Facts attribution.

Apple Health is optional. If authorized, MyFitPlate reads user-selected nutrition, activity, workout, heart-rate, sleep, and body data and writes only user-requested supported records. Location is requested only for a user-started outdoor run and may continue in the background while that run is active. The embedded Watch app uses the required HealthKit purpose strings and syncs account-scoped daily context; it can queue water and recent-meal actions while temporarily offline.

Camera and text estimates are review-first. Images and prompts for enabled AI workflows are sent through authenticated Firebase Functions to the disclosed AI provider; no provider API key is embedded in the app. The app remains usable without AI consent or Apple Health access.

There are no medical diagnoses or treatment recommendations. Recovery, nutrition, and AI outputs are estimates with visible limitations.

Deep links for focused review:
- myfitplate://trust
- myfitplate://builder
- myfitplate://train
- myfitplate://runs
- myfitplate://meal-plan
- myfitplate://reports
```

### Reviewer readiness

- Verify every production Function and provider flag against the exact candidate before submission.
- Keep community barcode aggregate reads disabled unless their separate release gate is complete.
- Confirm the supplied account is below all AI and search quotas.
- Attach a short demo video only if App Review cannot reproduce Watch, Live Activity, outdoor-run,
  or camera behavior without hardware or movement. Apple explicitly recommends supplemental context
  for features that are difficult to reproduce.

## Custom product pages

Apple currently permits custom screenshots, promotional text, app previews, keyword assignments,
and an iOS 18+ deep link. Each assigned keyword combination should be unique to one page and match
that page's intent. Submit these independently after 2.3 is live if the final screenshots differ
from the 2.2 product.

### Trusted food data

- **Lead:** Nutrition-first Food Detail, Nutrient Profile, Trust Receipt, review-before-log, Living Day, Fast Food Builder, Reports, Maia.
- **Promotional text:** See where food data came from, inspect field-level evidence, correct questionable values, and keep every estimate reviewable before it changes your day.
- **Deep link:** `myfitplate://trust`
- **Keyword intent:** food database, barcode scanner, nutrition label, food diary accuracy.

### Strength and recovery

- **Lead:** Live workout, Recovery Field, Living Day, Maia, Reports, Trust Receipt.
- **Promotional text:** Log every set without losing the flow, connect training to nutrition, and inspect the recent evidence behind each muscle-recovery estimate.
- **Deep link:** `myfitplate://train`
- **Keyword intent:** workout log, strength training, lifting tracker, muscle recovery.

### Real-world dining

- **Lead:** Fast Food Builder, review-before-log, Trust Receipt, Living Day, Maia, Reports.
- **Promotional text:** Build the order you actually ate, change every portion, follow official source links, and review the full estimate before it reaches your diary.
- **Deep link:** `myfitplate://builder`
- **Keyword intent:** restaurant calories, fast food nutrition, menu scanner, dining tracker.

### Running and fuel

- **Lead:** Running summary, Training & Fuel report, Living Day, Maia, Reports, Trust Receipt.
- **Promotional text:** Record or import runs, review routes, splits, and heart-rate context, then connect the effort to practical recovery-fueling targets.
- **Deep link:** `myfitplate://runs`
- **Keyword intent:** running log, route tracker, run recovery, heart rate zones.

### Meal planning

- **Lead:** Meal Plan, Grocery, Living Day, Maia, Trust Receipt, Reports.
- **Promotional text:** Plan a measured week, keep grocery items synchronized, use pantry-aware suggestions, and see planned nutrition alongside what you actually log.
- **Deep link:** `myfitplate://meal-plan`
- **Keyword intent:** meal planner, grocery list, macro meal plan, pantry recipes.

Prepare dedicated deterministic alternate composites before publishing a custom page. Reordering a
default image is acceptable only when that image genuinely shows the page's promised feature.

## Featuring nomination

Apple recommends at least two weeks of lead time and wider consideration up to three months ahead.
Its CSV template currently allows a 60-character nomination name, 1,000-character description,
and 500-character Helpful Details field. References:
[getting featured](https://developer.apple.com/app-store/getting-featured/) and
[nomination template](https://developer.apple.com/help/app-store-connect/reference/nominations/nominations-template/).

**Nomination name:**

```text
MyFitPlate 2.3: Food Trust Meets Training
```

**Nomination type:** `App Enhancements`

**Platforms:** `iOS (iPhone), watchOS`

**Publish date:** `[SET THE REAL 2.3 RELEASE DATE OR WINDOW]`

**Nomination description:**

```text
MyFitPlate 2.3 gives a familiar food-tracking category a more transparent foundation. Its new Trust Receipt shows source lineage, cross-checks, missing evidence, review status, and user corrections field by field instead of hiding them behind one confidence number. Living Day then connects logged and planned food, hydration, workouts, and recovery in a readable timeline, while Maia turns that context into one practical action that remains reviewable before it changes the diary. The update also adds purpose-routed camera review, Health Canada nutrient data, NIH supplement labels, a 25-chain meal builder, a refined strength player, running and recovery-fuel context, and an interactive Recovery Field. The experience is built in SwiftUI with HealthKit, WatchConnectivity, WidgetKit, ActivityKit, and strong VoiceOver and Dynamic Type support. It is a substantial redesign and data-integrity update from an independent developer, not a cosmetic reskin.
```

**Helpful Details:**

```text
Most food logs optimize for a fast number. MyFitPlate's differentiator is showing the evidence behind that number and preserving the user's correction. Version 2.3 carries the same signal-evidence-action idea from food data into the daily timeline, coaching, training, recovery, and reports. AI estimates never write before review, specialist databases keep honest source language, and optional Apple Health context is controlled separately from AI sharing.
```

**Initial markets:** Use `No` unless there is a real staged-market plan.

**In-App Event:** `No` unless a separate event is created and ready for review.

**Supplemental materials:** Use the public App Store page, privacy policy, support page, and an
optional unlisted demo video. The marketing website is intentionally omitted while unavailable.

## Public URLs

- Privacy Policy: `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/privacy_policy.md`
- Support: `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/support.md`
- Terms: `https://github.com/PeteAndrews1289/MyFitPlate/blob/main/docs/terms_of_service.md`
- Marketing URL: leave blank until a maintained public site exists.

## Final pre-paste checks

1. Recount all localized fields after any edit; App Store Connect counts keyword bytes, not words.
2. Confirm screenshots still match the accepted candidate and contain no personal account data.
3. Recheck privacy answers against `docs/data-safety.md` and the built privacy manifests.
4. Confirm Support and Privacy URLs load while signed out.
5. Enter review credentials only in App Store Connect and test them on a fresh install.
6. Select the exact signed build that passed the release gate before adding the version for review.
7. Do not label camera accuracy as improved until the fixed benchmark in
   `docs/camera-benchmark-2.3.md` is complete.
