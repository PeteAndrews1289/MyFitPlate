# MyFitPlate 2.3 Design Direction

## Position

MyFitPlate should feel like the training-aware nutrition app that explains its reasoning.
The ownable interaction pattern is:

> Signal, evidence, action.

- **Signal:** one fast interpretation of the current state.
- **Evidence:** the source, amount, trend, or limitation behind it.
- **Action:** one direct next step when an action is useful.

This is more distinctive than another card dashboard and more trustworthy than a score without an
explanation. Editorial surfaces interpret; operational surfaces help the user act; settings remain
native and predictable.

## Competitor Review

Official App Store screenshots and product pages were reviewed on 2026-07-14:

| Product | What it does well | What MyFitPlate should take | What MyFitPlate should avoid |
|---|---|---|---|
| [Strong](https://apps.apple.com/us/app/strong-workout-tracker-gym-log/id464254577) | Dense, legible set logging with very little ceremony | Fast entry, stable rows, obvious current set | A purely utilitarian identity with little explanation |
| [Hevy](https://apps.apple.com/us/app/hevy-workout-tracker-gym-log/id1458862350) | Clear exercise hierarchy, history, and approachable progress views | Familiar gym vocabulary and readable history | Letting social mechanics compete with the active workout |
| [Fitbod](https://apps.apple.com/us/app/fitbod-gym-fitness-planner/id1041517543) | Muscle-aware recommendations and fatigue visualization | Connect readiness to the next training decision | Presenting a fatigue model as more certain than its inputs allow |
| [WHOOP](https://apps.apple.com/us/app/whoop/id933944389) | One dominant recovery or strain interpretation per view | Strong state hierarchy and consistent signal language | Dense proprietary scores that obscure source evidence |

MyFitPlate should not imitate any one visual style. It combines Strong's operational speed,
Hevy's clarity, Fitbod's muscle context, and WHOOP's interpretation hierarchy, then differentiates
through visible evidence and the nutrition-to-training loop.

## Visual Contract

### Surfaces

1. Canvas is the stage.
2. One emphasized surface answers the screen's primary question.
3. Quiet surfaces group real controls or evidence; they do not decorate empty space.
4. Continuous lists use dividers rather than a card for every row.
5. No card sits inside another card.
6. Shadows, material, and gradients remain limited to the documented shell, transient, chart, and
   exported-art exceptions.

### Type

- Display and screen titles are reserved for top-level identity.
- Section titles name a real content group, not a decorative block.
- Metrics use literal units and monospaced digits when they change live.
- Status badges are compact labels, never miniature headlines.
- Accessibility text may change layout, but controls and badges do not grow into competing heroes.

### Color

The closed color contract lives in `DESIGN.md` and `AppVisualSystem.swift`.

- Brand green means current, selected, ready, or the one primary action.
- Signal roles describe state: positive, effort, recovery, caution, critical, achievement, neutral.
- Domain roles describe data: energy, protein, carbohydrate, fat, hydration.
- The same hue is called through the role that explains its meaning.
- No state relies on color alone. Text, icons, progress, and shape remain legible in grayscale.

## Screen Family Matrix

| Family | Primary question | Required hierarchy |
|---|---|---|
| Home | What matters today? | Day signal, evidence timeline, next action |
| Food search/logging | What did I eat? | Search or item identity, source/trust, log action |
| Food detail/trust | Can I rely on this? | Trust state, source evidence, editable correction |
| Meal planning/grocery | What will I prepare? | Current plan/run, grouped items, one plan or shopping action |
| Maia | What should I do next? | Concise answer, grounded evidence, reviewable action |
| Train | What do I do now? | Next session, readiness context, start action |
| Live workout | What set is next? | Session identity, current exercise/set, stable controls |
| Workout history | What did I accomplish? | Result signal, measured evidence, detail or repeat action |
| Recovery Field | What appears ready? | Body signal, selected-region evidence, planning limitation |
| Reports/wellness | Is it working? | Headline trend, source-aware evidence, cautious interpretation |
| Settings/onboarding | What must I configure? | Native sections, explicit choices, one save/continue action |

Reachable screens use this matrix. Dormant group/post prototypes remain gated until identity,
reporting, blocking, moderation, and privacy contracts exist; visual polish must not accidentally
make them release eligible.

## Training Identity

Training is MyFitPlate's sharpest opportunity to look distinct without becoming theatrical.

- Use a quiet, high-contrast stage with blue effort, teal recovery, gold achievement, orange
  caution, and brand green only for current/ready/action states.
- Keep live workout density closer to Strong and Hevy than to an editorial Home screen.
- Use the shared progress track across live work, plans, and recovery so movement through training
  feels related.
- Keep the current exercise and current set visually dominant. Timers use monospaced digits.
- Put secondary tools in compact icon controls with labels for assistive technology.
- Preserve content imagery and exercise identity, but keep interface chrome professional and
  symbol-based.
- Completed-workout analytics should explain the session with measured facts before any coaching.

## Recovery Field

Recovery Field is a planning instrument, not a medical assessment and not a precise biological
measurement.

### Inputs

- Latest session time by broad muscle group.
- Working-set count when available.
- A conservative proxy when legacy daily activity lacks set detail.
- Recent sleep score when available.

### Output

- Six broad regions: shoulders, chest, arms, core, legs, back.
- Five named states: fatigued, recovering, nearly ready, ready, and no recent signal.
- Front and back interactive body field.
- Selected-region evidence: last trained, recent volume, estimated recovery window, and sleep
  adjustment.
- An explicit limitation beside the visualization.

### Rules

- Estimates are deterministic and testable.
- Missing evidence fails to `no recent signal`, not false readiness.
- Color always appears with a status label and percentage or evidence statement.
- The field can inform session planning, but it cannot diagnose soreness, injury, or readiness to
  train through pain.
- Future improvements should add user-reported soreness and per-muscle exercise mapping only when
  their provenance and correction paths are equally visible.

## Acceptance Gates

- Standard light, standard dark, and accessibility-XXXL captures for live workout and Recovery
  Field are visually reviewed.
- No important control overlaps, clips, or becomes unreachable at accessibility sizes.
- Workout controls remain stable while timer and set values change.
- Recovery Field exposes its body field, muscle controls, and evidence groups to VoiceOver.
- Release-reachable feature UI passes `scripts/check_visual_system.sh`.
- Direct spectrum colors remain limited to measured/categorical data, physical plate standards,
  celebration/export artwork, cycle phases, and explicitly gated prototypes.
- Core signal and recovery rules have deterministic tests.
- No Firebase or data migration is required for this visual pass.
