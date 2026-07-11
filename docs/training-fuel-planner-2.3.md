# Training Fuel Planner 2.3 Core Contract

This document defines the deterministic Core engine that will power the 2.3 Training Fuel
Planner UI. The engine divides part of the user's existing daily calorie, protein, and carb
targets around one planned strength session or run. It never changes those targets.

The allocations are transparent product heuristics for general fitness coaching. They are
not medical advice, a diagnosis, or an individualized sports-nutrition prescription.

## Inputs

`TrainingFuelSession` carries:

- session kind: strength or run;
- planned start time;
- expected duration;
- easy, moderate, or hard intensity;
- optional strength focus: upper, lower, full body, mixed, or unknown.

`TrainingFuelPreference` independently records whether the user wants food before training,
after training, both, or neither. `TodayFuelPlanGoals` supplies the user's existing daily
targets, and the current-day `DailyLog` supplies intake already logged.

The engine returns its normalized duration, intensity, time until training, remaining daily
budget, allocations, status, and every assumption or limiting factor. The UI must display
defaults and uncertainty instead of presenting them as observed facts.

## Demand heuristic

Intensity factors are fixed at `0.75` for easy, `1.0` for moderate, and `1.25` for hard.
Duration factors are bounded before use.

### Strength

- Carb demand starts at `35 g * bounded duration hours * intensity factor`.
- Duration is bounded to a factor from `0.5` to `2.0`.
- Moderate lower/full-body work adds 8 g; hard lower/full-body work adds 15 g.
- The result is bounded to 20-110 g.
- Protein demand is 20 g easy, 25 g moderate, or 30 g hard.

### Running

- Carb demand starts at `45 g * bounded duration hours * intensity factor`.
- Duration is bounded to a factor from `0.5` to `3.0`.
- The result is bounded to 20-160 g.
- Protein demand is 20 g, or 25 g for sessions lasting at least 75 minutes.

These are maximum planning demands before the user's actual remaining targets are applied.
They are not additions to the daily targets.

## Allocation rules

1. When both phases are selected, 55% of carbs begin before training and 45% after. Protein
   is primarily reserved for after training; up to 10 g can sit before when at least one hour
   remains.
2. Within 30 minutes of training, pre-session carbs are capped at 25 g. From 31-60 minutes,
   they are capped at 35 g. Overflow can move after training only when that phase is selected.
3. Protein and carbs are independently scaled to remaining macro targets.
4. The combined allocation is then scaled to remaining calories at four calories per gram.
5. Rounding always goes down. A macro below 10 g and an allocation below 60 calories are
   removed instead of showing a misleading token target.
6. The final plan must satisfy all three invariants:
   `allocated calories <= remaining calories`,
   `allocated protein <= remaining protein`, and
   `allocated carbs <= remaining carbs`.

Fat is not prescribed by this engine. Logged fat still affects remaining calories, and the
eventual food choice may contain fat as long as the complete logged food remains inside the
user's daily target.

Version 1 does not prescribe food during training. Longer endurance sessions can require an
individualized during-session carbohydrate and hydration strategy that depends on body size,
environment, tolerance, and event goals; that is outside this daily-budget allocator. The
post-session phase also does not imply a narrow anabolic window. Meeting the day's overall
energy and protein needs remains more important than minute-level timing.

## Neutral and uncertainty states

- `invalid_calorie_target`: no valid positive daily calorie target exists.
- `over_target_review`: the day is at or over target; no compensatory fuel is created.
- `needs_session_time`: no time was supplied, so the engine does not invent one.
- `stale_session`: the planned start is more than 15 minutes in the past.
- `outside_today`: the session is not today, or a post-only choice would occur after midnight.
- `insufficient_budget`: the remaining calorie/macro budget cannot form an actionable target.
- `invalid_diary_data`: today's diary contains an unusable nutrition value, so its remaining
  budget cannot be verified and no allocation is made.
- `no_fuel_requested`: the user disabled both phases.
- `ready`: at least one bounded allocation is available.

Missing duration defaults to 45 minutes and missing intensity defaults to moderate, with
explicit notes. Duration is clamped to 15-240 minutes and disclosed. Non-finite, negative, or
unsupported current-day diary magnitudes stop planning rather than overstating the remaining
budget. The planner accepts at most 1,000,000 calories and 100,000 g per macro as corruption
guards, not plausible recommendations; an out-of-range calorie target also stops planning. A
`DailyLog` from another calendar day is ignored so browsing history cannot alter today's plan.

## Scientific boundary

The shape of these conservative product heuristics is informed by the 2016 Academy of
Nutrition and Dietetics, Dietitians of Canada, and ACSM joint position statement on
[Nutrition and Athletic Performance](https://pubmed.ncbi.nlm.nih.gov/26891166/), plus the ISSN
position stands on [nutrient timing](https://pubmed.ncbi.nlm.nih.gov/28919842/) and
[protein and exercise](https://pubmed.ncbi.nlm.nih.gov/28642676/). Those sources emphasize
individual context and total daily intake; they do not validate this app's exact formulas.
Personalized performance or clinical nutrition belongs with a qualified sports dietitian.

If a session ends after midnight, its post-session allocation is not charged against today's
budget. The future reconciliation layer must use the next day's real log instead.

## Integration boundary

The Core engine is intentionally independent of SwiftUI, AI, network providers, and workout
storage. The next implementation layer must:

1. derive the next strength session from the active program or accept a selected run plan;
2. let the user review/change time, duration, intensity, focus, and pre/post preferences;
3. map deterministic allocations to Food Search, saved/recent meals, Fill Macros, Meal Plan,
   and Fast Food Builder without sending the budget to AI as authority;
4. reconcile against food actually logged and confirmed session completion;
5. expire or recompute plans when the diary, goals, session, date, or preferences change.

Regression coverage lives in
`MyFitPlateCore/Tests/MyFitPlateCoreTests/TrainingFuelPlannerRulesTests.swift`. Its 22 focused
tests include a deterministic 1,344-combination matrix spanning session kind, duration,
intensity, diary budget, and every pre/post preference while enforcing all output invariants.
