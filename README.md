<div align="center">
  <img src="CalorieBeta/Assets.xcassets/AppIcon.appiconset/icon-light-1024.png" width="120" alt="MyFitPlate app icon">
  <h1>MyFitPlate</h1>
  <p><strong>The food log you can trust, built for people who train.</strong></p>
  <p>Nutrition, training, recovery, and an evidence-aware AI coach in one native Apple experience.</p>
  <p>
    <a href="https://apps.apple.com/us/app/myfitplate/id6740922831"><img src="https://img.shields.io/badge/App_Store-MyFitPlate-0D96F6?logo=apple&amp;logoColor=white" alt="MyFitPlate on the App Store"></a>
    <img src="https://img.shields.io/badge/iOS-17%2B-111111?logo=apple" alt="Requires iOS 17 or newer">
    <a href="https://github.com/PeteAndrews1289/MyFitPlate/actions/workflows/ci.yml"><img src="https://github.com/PeteAndrews1289/MyFitPlate/actions/workflows/ci.yml/badge.svg?branch=main" alt="Continuous integration status"></a>
  </p>
</div>

## What MyFitPlate Is

MyFitPlate is a native iPhone and Apple Watch app that connects food logging with the training and
recovery decisions people make every day. Logging is designed to be fast, but not opaque: when a
food record, estimate, or coaching suggestion affects the user's totals, the app should explain
where it came from and how much confidence to place in it.

This checkout targets **2.4 (build 2)**. It combines a full nutrition diary with barcode and camera
logging, the Maia AI coach, strength and running tools, Apple Health integration, meal planning,
grocery and restaurant workflows, reports, widgets, Live Activities, and an Apple Watch companion.

[View MyFitPlate on the App Store](https://apps.apple.com/us/app/myfitplate/id6740922831)

## The Difference: Food Trust

Nutrition databases often disagree, omit nutrients, use incompatible serving sizes, or repeat the
same manufacturer label through several providers. MyFitPlate treats that as a product problem
rather than hiding it behind a single green checkmark.

The Food Passport and Trust Score surface:

- the provider and evidence lineage behind a food;
- barcode identity and serving-size evidence;
- cross-database agreement when records are actually comparable;
- nutrition sanity checks and values that need correction;
- a direct correction path for saved and scanned foods;
- clear separation between source-reported data, agreement, and stronger analytical evidence.

The goal is not to claim certainty that the data cannot support. The goal is to help users log
quickly, see limitations, and repair questionable entries before those entries shape their day.

## Product Areas

### Food and nutrition

- Manual entry, recent and saved foods, meal reuse, and recipe logging
- Search-first food logging with a compact meal destination, five repeat foods, and secondary capture tools under More
- Multi-food meal drafts with portion review, interruption recovery, safe retry, and one undo
- Planned meals and AI suggestions confirm accepted saves and retain failed actions for retry
- Text, barcode, multi-barcode, nutrition-label, receipt, menu, pantry, and meal-photo workflows
- Calories, macros, fiber, sodium, and detailed micronutrients
- Food search across USDA FoodData Central, FatSecret, and Open Food Facts
- Food Trust review, source evidence, corrections, and personal food history

### Training and recovery

- Strength programs, routines, supersets, RPE/RIR, set types, rest timers, and progression guidance
- Reviewable per-set progression from recent working sets, editable equipment increments, lighter-session targets, and conditional Undo
- Recoverable program/routine edits, compact set entry, and retained workout libraries during partial reads
- One-action workout starts, confirmed skips, and retryable previous-workout loading without blocking set entry
- Outdoor running with route, pace, splits, heart-rate zones, training fuel, and shoe mileage
- Apple Watch workout capture and phone-to-watch synchronization
- Apple Health context for workouts, heart rate, sleep, HRV, weight, and nutrition
- Workout history, muscle-group analytics, wellness signals, and recovery guidance

### Planning and coaching

- Maia, an AI coach for questions, meal ideas, and reviewable logging actions
- Confirmed weight saving and import progress that reflects accepted records
- Seven-day meal plans, recipes, pantry tools, and generated grocery lists
- Restaurant menu analysis, fast-food building, and buffet planning
- Adaptive calorie and macro goals, hydration, fasting, body trends, and weekly reports
- Widgets and Live Activities for useful information outside the main app

## Current Source

The source in this repository is organized around one product language:
**signal, evidence, action**.

- A unified visual system across nutrition, training, planning, Maia, reports, and settings
- Living Day, a source-aware timeline that connects food, training, hydration, and recovery
- Recovery Field, an interactive muscle view with explicit inputs and limitations
- Trust 3.0, with deeper nutrient provenance, calibration, and correction feedback
- Specialist Health Canada food composition and NIH supplement-label coverage
- Purpose-routed camera logging with database grounding and an explicit estimate review step
- Broader accessibility, visual-regression, device, Watch, and release acceptance coverage

The [2.4 release notes](docs/release-notes-2.4.md) describe the changes to food logging, training, and cooking.

The first version of **Rescue my week**, **One useful question**, and **What works for me?** is also implemented. These connect reversible workout/meal adjustments, focused photo review, and familiar-meal comparisons to the existing app.

## Release And Branch Policy

The historical 2.2 source is tagged `v2.2`. Use a short-lived `codex/` branch for new work and
merge into `main` after the release checks pass. Branch names in older release notes describe
the work at that time, not the current checkout.

## Architecture

```mermaid
flowchart TB
    App["iPhone app\nSwiftUI"] --> Core["MyFitPlateCore\nmodels, Trust, nutrition, training"]
    App <--> Watch["Apple Watch\nworkouts and quick logging"]
    App --> Extensions["Widgets and Live Activities"]
    Extensions --> Shared["MyFitPlateShared\nwidget and Live Activity data"]
    Core --> Shared
    App <--> Health["Apple Health and HealthKit"]
    App --> Firebase["Firebase Auth, Firestore, Analytics, App Check"]
    Core --> Food["Food provider adapters"]
    Food --> USDA["USDA FoodData Central"]
    Food --> OFF["Open Food Facts"]
    App --> Functions["Firebase Cloud Functions"]
    Functions --> FatSecret["FatSecret"]
    Functions --> Reference["Health Canada CNF and NIH DSLD"]
    Functions --> OpenAI["OpenAI models"]
```

The iOS app owns presentation and device integrations. Reusable models, validation, ranking,
Trust, and deterministic planning logic live in `MyFitPlateCore`. The widget and Live Activity
extensions link only `MyFitPlateShared`, the few types they exchange with the app, so they stay
small; Core re-exports it. Cloud Functions protect AI and
provider credentials, enforce quotas, validate structured responses, and handle privileged data
operations. Firestore rules, App Check, and server-owned deletion protect the shared data layer.

## Repository Map

| Path | Purpose |
| --- | --- |
| `CalorieBeta/` | Main iOS app, feature screens, infrastructure, resources, and design system |
| `MyFitPlateCore/` | Reusable Swift package (`MyFitPlateCore` and the extension-sized `MyFitPlateShared`) and deterministic unit-test suite |
| `MyFitPlateWatch Watch App/` | watchOS companion and workout experience |
| `CalorieWidget/` | Home and Lock Screen widgets |
| `LiveActivity/` | Workout and timer Live Activities |
| `functions/` | TypeScript Firebase Cloud Functions and backend tests |
| `MyFitPlateTests/` | App-level unit and rendering tests |
| `MyFitPlateUITests/` | End-to-end UI smoke and reachability tests |
| `docs/` | Product contracts, release acceptance, privacy, Trust, and operations notes |
| `scripts/` and `tools/` | CI checks, data builders, migrations, and release tooling |

## Local Development

### Requirements

- macOS with a current stable Xcode release
- An iOS 17 or newer simulator or physical device
- Node.js 22 for Firebase Functions (`nvm use` reads the repository pin)
- Java 21 when running Firestore emulator tests
- SwiftLint for the same lint checks used by CI

### App setup

```bash
git clone https://github.com/PeteAndrews1289/MyFitPlate.git
cd MyFitPlate
cp secrets.example.xcconfig secrets.xcconfig
open MyFitPlate.xcodeproj
```

Fill `secrets.xcconfig` only with values for an environment you control. The file is ignored by
Git. A complete signed build also needs an Apple development team, matching entitlements, a
Firebase project configuration, and deployed backend functions. OpenAI credentials belong in
Cloud Functions secret storage, not in the app bundle.

Select the `MyFitPlate` scheme and let Xcode resolve Swift Package Manager dependencies. A fork
should use its own Firebase project and must not treat the production backend as development
infrastructure.

### Core and backend checks

```bash
swift test --package-path MyFitPlateCore

cd functions
npm ci
npm test
```

The GitHub Actions pipeline also runs strict SwiftLint, visual-system enforcement, app unit tests,
UI smoke tests, release compilation, Firestore rule tests, coverage floors, dependency audit, and
migration-runner tests.

## Product And Safety Contracts

- [Design system](DESIGN.md)
- [Roadmap](ROADMAP.md)
- [Trust Score model](docs/trust-score-model.md)
- [Security and privacy review](docs/security-privacy-review.md)
- [Privacy Policy](docs/privacy_policy.md)
- [Terms of Service](docs/terms_of_service.md)
- [Support](docs/support.md)

MyFitPlate is a wellness and fitness product, not a medical device. Its estimates and coaching do
not diagnose conditions or replace advice from a qualified healthcare professional.

## Feedback

Product feedback and reproducible bug reports are welcome through
[GitHub Issues](https://github.com/PeteAndrews1289/MyFitPlate/issues). Account, privacy, billing, or
data requests should use the contact path in [Support](docs/support.md).

## License

This repository is published for product transparency and portfolio review. No open-source license
is granted. All source code, visual assets, product copy, and trademarks are copyright MyFitPlate;
all rights reserved. Third-party data and services remain subject to their respective terms and
licenses.
