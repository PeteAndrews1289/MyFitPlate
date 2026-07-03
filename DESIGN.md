# MyFitPlate Design Rules

Enforceable rules, not taste. Agents (Claude, Codex) apply these mechanically to every
screen they touch, the same way the coverage gate applies to every commit. When a change
violates a rule, fix the violation or flag it — never ship it silently.

## 1. One hero per screen

Every screen answers exactly one question, with exactly one hero element.

| Screen | The question | The hero |
|---|---|---|
| Home | How am I doing today? | Calorie/macro ring card |
| Train | What do I do right now? | Next-workout card with Start |
| Log Food | What did I eat? | Search field + results |
| Reports | Is it working? | The headline trend |

- At most **one filled-green CTA per screen**. Everything else is outline, ghost, or text.
- Never present the same action twice on one screen (e.g. two "start next workout"
  surfaces). Pick the stronger one; delete or demote the other.
- Supporting cards answer follow-up questions, visually quieter than the hero
  (neutral background, smaller type).

## 2. Green means something

`brandPrimary` green is a signal, not a wallpaper. Allowed uses — nothing else:

- The screen's primary CTA (filled).
- Completed / success states (checkmarks, done-day dots, positive deltas).
- "Now" markers (today's ring, Next Up chip).

Everything else is neutral: card backgrounds are `backgroundSecondary` (no green
`.opacity(0.10)` washes), icon containers are neutral or match a **semantic** accent
(protein blue, warning orange), info chips are gray. Test: squint at the screen — if more
than ~3 green elements survive, the screen fails.

Semantic accents stay semantic: `accentProtein` blue = protein, orange = warnings/AI,
red = destructive, `accentPositive` = success. Never decorate with them.

## 3. Numbers are typography

- Thousands separators always: `12,650`, never `12650`. Compact above 5 digits where
  space is tight: `12.6K`.
- Units attached: `12,650 lbs`, `45 min`, `210 cal` — a bare number is a bug.
- Live/ticking values (timers, counters) use `.monospacedDigit()` so they don't jitter.
- Progress is stated in words a stranger understands: "Day 8 of 60", "Week 2",
  "5 training days" — never bare fractions like "5/7" whose meaning must be guessed.
- Never render a raw `Double` (`690752.0`, `7.700000000001`). Round + format at the
  view boundary.

## 4. Type + spacing scale (existing system — reuse, don't invent)

- `appFont` sizes and their roles: 11 caption · 12 secondary · 13 body-small ·
  15 body-strong · 17 control · 21 screen-title-adjacent. Weights: `.medium`
  for labels, `.bold` for emphasis. Don't introduce new sizes without updating this file.
- Cards: padding 14–16, corner radius 16–20 continuous, section spacing 16.
- One line of hierarchy per card: title row → optional support line → content. If a card
  needs three font sizes to explain itself, it's two cards.

## 5. Copy

- Sentence case everywhere. Buttons are verb-first, 1–3 words: "Start workout", not
  "Start Week 2 · Day 1" (the context lives in the card, not the button).
- No duplicated messaging; no exclamation marks in system copy; contractions welcome.
- Empty states invite ("Choose training days to unlock scheduling") — never apologize.

## 6. Emoji tiles are brand — keep them (decision, 2026-07-02)

Food and exercise emoji tiles (🍗 🏋️ via `FoodEmojiMapper`/`ExerciseEmojiMapper`) are a
deliberate brand choice, not clutter. They make MyFitPlate instantly recognizable next to
sterile flat-icon competitors. Rules:

- Never replace emoji tiles with SF Symbols in list rows, sliders, or diary entries.
- Emoji sit on **neutral** containers (system fills), sized 26pt in rows / 42–44pt in
  hero tiles — the container is quiet so the emoji carries the personality.
- Emoji are decorative: containers get `accessibilityHidden(true)` or are excluded from
  the combined element's label. Never rely on an emoji to convey meaning alone.
- System UI chrome (tab bar, toolbars, settings) stays SF Symbols — emoji are for
  *content* (foods, exercises), not controls.

## 7. Motion + empty states

- One spring everywhere: `.spring(response: 0.35, dampingFraction: 0.8)` for entrances and
  state changes. No bespoke curves per screen.
- Numbers that change while visible get `.contentTransition(.numericText())` — values roll,
  they don't teleport.
- Haptics map: `.light` = navigation tap · `.medium` = a log/save action · `.success`
  notification = a completed workout or a new record. Never on scroll or passive updates.
- Celebrate records once, at the moment of reveal (spring entrance + success haptic) —
  no repeat fanfare on re-visits of the same data.
- Empty states are invitations: icon + one bold line + one supporting line + optional CTA
  (patterns: `FoodSearchEmptyState`, `EmptyDailyLogView`). Never apologize, never blank.

## 8. Per-screen checklist (run before commit)

- [ ] One hero, one filled CTA, no duplicated actions
- [ ] Squint test: ≤3 green elements, all meaningful
- [ ] All numbers formatted with units; no bare fractions
- [ ] Icon-only buttons have `accessibilityLabel`; decorative images hidden
- [ ] Dark mode glance (tinted `.opacity` washes often break here)
- [ ] Dynamic Type sanity at XL (`AppFont` scales automatically; check clipping)
