# Cross-Device Next Action 2.3 Contract

This document defines the compact action shared by the app, widgets, Watch, and local
notifications. These surfaces may make an existing plan easier to act on; they must not invent
food, training completion, recovery, or a new calorie target.

## Priority and routes

Core selects exactly one `DailyNextAction` in this order:

1. An actionable pre-workout target from a confirmed upcoming Training Fuel plan.
2. An actionable recovery target after an explicit completed-session outcome.
3. A food entry whose Trust review is still unresolved.
4. A protein gap of at least 20 g while at least 150 calories remain.
5. A neutral steady-day state.

The action contains a short title/detail, optional protein/carb targets, and one route. Training
uses `myfitplate://training-fuel`, Trust uses `myfitplate://trust`, protein catch-up uses
`myfitplate://food-search`, and steady day uses `myfitplate://home`. It contains no account ID,
email, food name, workout/session name, route/GPS data, or HealthKit sample.

## Widget

- `WidgetData.nextAction` is optional so 2.2 app-group payloads continue to decode.
- Small, medium, large, rectangular, and inline families show the action at an appropriate
  density. Circular remains a calorie glance and routes Home.
- The widget's body route is the action's exact deep link. Interactive water logging is unchanged.
- Only a log dated today may replace app-group widget data. Looking at yesterday cannot make the
  widget or Watch report yesterday as today.
- The old `LogPlannedMealIntent` was removed because it claimed to log but only refreshed a
  timeline.

## Watch

- Phone context includes today's totals, the compact next action, one complete recent meal when
  eligible, and a random local account scope. Firebase UID and email never cross WatchConnectivity.
- Watch can review training/recovery targets and repeat the recent meal through a confirmation
  screen. It does not perform database food search.
- `transferUserInfo` queues water and meal replay while the phone is unreachable. Meal requests
  contain a unique action ID and are persisted/deduplicated on the phone.
- The phone validates the random account scope, rejects another account's request, gives every
  repeated food a new ID and the Watch request timestamp, and acknowledges the request only after
  the diary write succeeds. This keeps an offline request on the day it was actually made,
  including across midnight. Invalid, empty, or more-than-24-item meals are not offered or
  partially logged.
- Logout clears Watch context and pending actions. A delayed Watch session activation sends the
  latest signed-in context or the pending account clear.

## Notifications

All three types default off and are independently controlled in Settings:

- **Before training:** only a live pre-session target; timing follows its confirmed allocation.
- **Recovery target:** only after an explicit completed outcome; never from elapsed clock time.
- **Evening protein catch-up:** only the same meaningful protein-gap rule used by next action.

Quiet hours default to 10:00 PM-7:00 AM. Quiet candidates are suppressed rather than moved into a
different context. At most two candidates are produced per day. Stable system identifiers and a
local fingerprint ledger replace changed pending content but do not recreate a reminder after its
intended time. A preference edit first cancels the old pending set and ledger, then valid today
data may schedule the new set; stale content cannot survive a type or time change. The retired
generic AI background nudge is canceled. A latest-sync generation also rejects delayed
authorization callbacks from an older preference state.

Notification content may show the opted-in target. Analytics receives only `notification_type`
for scheduled/opened events. A tap queues the exact route through login/onboarding just like a
widget or external link.

## Physical-device closure

1. Add every widget size, confirm today's action and water button, then tap Training Fuel, Trust,
   Food Search, and Home examples after each is naturally available.
2. With a paired Watch, verify today's calories/macros, next-action review, recent-meal summary,
   water, and weight. Queue water and one meal with the phone unreachable; reconnect and confirm
   each writes exactly once. Sign out and confirm old account data disappears from Watch.
3. Enable one reminder type at a time, verify quiet-hour suppression, receive a real pre-session
   or recovery reminder, tap it from the Lock Screen, and confirm the exact destination opens.
4. Repeat the checks with larger text and dark mode. No reminder or Watch action should expose a
   user ID, session name, food names on the main Watch glance, or raw health/location data.
