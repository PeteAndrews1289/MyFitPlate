# MyFitPlate 2.1 Release Health Runbook

This is the production-readiness checklist for the 2.1 ship window. It focuses on the pieces we are doing now: Crashlytics/release health, branch protection, and production dashboards/alerts.

Not done in this sprint: TestFlight automation and App Check enforcement. Keep both as suggested next steps after 2.1 is stable.

## 1. Crashlytics / Release Health

The app now stamps every launch with a release-health context:

- `app_version`
- `build_number`
- `bundle_identifier`
- `build_environment`
- `os_version`
- `is_ui_testing`
- `is_logged_in`
- `release_health_schema`

The launch event is `app_session_started`. Non-fatal production issues should be recorded through `ReleaseHealth.recordNonFatal(...)`, which also emits `nonfatal_error_recorded`.

Startup performance is tracked with `app_startup_completed`, including:

- `duration_ms`
- `duration_bucket`

Before shipping 2.1:

- Build the same configuration you plan to put on your phone.
- Launch once, sign in, sign out, and sign in again.
- Confirm Crashlytics receives the latest version/build keys.
- Confirm Analytics shows `app_session_started`.
- Confirm Analytics shows `app_startup_completed`.
- Confirm no new issue is marked as a fatal crash for the 2.1 build.

## 2. Real-Device 2.1 Smoke Test

Run this on Peter's phone using the same build style intended for release:

- Fresh launch: app opens without hanging, latest version/build appears in Crashlytics keys, `app_startup_completed` appears in Analytics.
- Auth: sign in, background the app, foreground it, sign out, then sign back in.
- Home: dashboard loads, water/food/workout cards do not overlap, spotlight/tour state does not block use.
- Food logging: search and log one food, quick-add/recents still behave, delete or adjust the item.
- Water: log water and verify widget/shared state still updates if widget is installed.
- Workout: start a lightweight workout, complete it, and confirm the completion analytics/review screen opens.
- AI: run one low-cost Maia/logging action and confirm success or graceful error messaging.
- HealthKit: open any HealthKit-backed screen after granting permissions; deny/revoke path should not crash.
- Offline/poor network: briefly disable network, open Home/Food/Workouts, and confirm no crash or permanent loading state.
- Relaunch: kill and reopen the app; confirm prior logged state/data reloads.

During the first 24 hours after release:

- Watch crash-free users and crash-free sessions for the latest version only.
- Watch new fatal issues first, then high-volume non-fatal issues.
- Check whether `nonfatal_error_recorded` clusters around `authentication`, `database`, `healthkit`, or `ai`.
- Check whether `app_startup_completed` clusters above `2s_to_4s` or `over_4s`.
- If a new issue appears only in 2.1, treat it as release-blocking until understood.

## 3. Branch Protection

Branch protection is a GitHub repository setting, not something this repo can fully enforce through code alone. The recommended setup for `main` is:

- Require pull requests before merging.
- Require status checks to pass before merging.
- Require branches to be up to date before merging.
- Required checks:
  - `Unit tests`
  - `Firebase rules`
- Block force pushes.
- Block branch deletion.
- Require conversation resolution before merge.
- Allow admins to bypass only for emergency release recovery.

For a solo-tester workflow, keep this lightweight: agents can work on branches and only merge once CI is green. You can still build directly to your phone from local branches.

Source-controlled support files:

- `.github/pull_request_template.md` gives each agent a short release-health checklist.
- `.github/rulesets/main-branch-protection.json` captures the intended GitHub ruleset for `main`.

## 4. Production Dashboards / Alerts

Create these Firebase Console views for 2.1:

- Crashlytics latest-release view filtered to version `2.1`.
- Analytics event view for `app_session_started`.
- Analytics event view for `app_startup_completed`, grouped by `duration_bucket`.
- Analytics event view for `nonfatal_error_recorded`, grouped by `area` and `operation`.
- Feature health view for AI and logging events:
  - `food_logged`
  - `food_logged_bulk`
  - `water_logged`
  - `workout_logged_ai`
  - `meal_plan_generated`
  - `ai_recipe_generated`
  - `ai_feature_used`

Recommended alert thresholds:

- Any new fatal crash in latest release: investigate immediately.
- Crash-free users below 99% for latest release: pause rollout/release promotion.
- Sudden spike in `nonfatal_error_recorded`: inspect by `area` and `operation`.
- Startup durations clustering above `2s_to_4s`: profile launch before adding more startup work.
- AI feature error spike: verify API/proxy health before assuming an app bug.
- Firestore or Functions error spike: check Firebase status, rules changes, and recent deploys.

## Suggested Next Steps After 2.1

- TestFlight/Fastlane automation: not done. Lower priority while Peter is the only tester and installs directly to device.
- App Check enforcement: not done. Keep prepared, but enforce only after 2.1 is dominant and verified requests look clean.
- Continue Core coverage from 70% toward 80% by extracting rules from framework wrappers before testing glue.
