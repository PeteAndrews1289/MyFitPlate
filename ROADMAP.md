# MyFitPlate Roadmap

A living roadmap, maintained alongside the code and re-ranked as real usage data
comes in. Tags: 🟢 quick win (low effort) · 🔵 larger effort.

## Guiding principle: let analytics drive priorities

2.0 ships with full analytics enabled — use it. Before committing to the features
below, give 2.0 ~1–2 weeks of real usage and let adoption data do the ranking.
Watch:

- **Feature adoption** — % of users touching Maia chat, photo logging, the menu
  scanner, meal plans, fasting. Low adoption = a discovery problem or a candidate to deprioritize.
- **Logging-method split** — photo vs. search vs. Maia chat. Shows where to invest the core loop.
- **Funnel** — onboarding completion, D1 / D7 retention.
- **Cost** — chat / photo / meal-plan call frequency vs. the ~$90/mo at-scale estimate.

---

## Now — during / just after review
- [ ] Stand up monitoring: Crashlytics (first real crashes), Analytics dashboards, App Store reviews
- [ ] Write integration / UI tests (the CI scaffold is ready to host them)
- [ ] Plan App Check enforcement — flip only once 2.0 is the dominant installed version

## 2.1 — core-loop polish (the retention lever)
Logging speed is the #1 retention driver for nutrition apps.
- [ ] 🟢 Quick-add: favorites, recent foods, "repeat yesterday," meal templates
- [ ] 🟢 Photo-library logging — currently camera-only; add "choose from library"
- [ ] 🟢 Log reminders / notifications — meal times, water, weigh-in
- [ ] 🔵 Metric units — ft/in + lbs only today; unlocks international users
- [ ] 🟢 Loose ends: weight backdating, multiple pantry-recipe ideas, Key Gains date handling

## 2.2–2.3 — stickiness
- [ ] 🔵 Streaks / habit tracking / daily goals
- [ ] 🔵 Apple Watch app build-out (the `watchkitapp` target already exists)
- [ ] 🟢 Widget expansion (`CalorieWidget` exists) — calorie ring + quick-log
- [ ] 🔵 Progress photos + body measurements
- [ ] 🟢 Data export (CSV / PDF)
- [ ] 🔵 Deeper Health sync — steps / active energy auto-adjusting targets

## 3.0 — bigger bets
- [ ] 🔵 Revive community (dormant Firestore code exists) — only if data shows demand
- [ ] 🔵 Monetization tuning — paywall placement, trial, premium AI tier
- [ ] 🔵 Localization (pairs with metric units)
- [ ] 🔵 Advanced AI — smarter weekly reviews, predictive insights, voice logging
- [ ] 🟢 Sign in with Apple — reduce signup friction

## Always-on — technical / ops
- [ ] Cost monitoring vs. the at-scale estimate
- [ ] Expand CI to integration tests
- [ ] App Check enforcement once 2.0 is dominant
- [ ] Crashlytics triage

---

_Living document — re-rank as analytics arrive. Last updated: 2026-06-25._
