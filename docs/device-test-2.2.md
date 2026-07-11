# 2.2 full test & feedback protocol

Everything in the 2.2 build, grouped by surface. Items tagged **[outdoor]** need dry
weather + GPS; everything else works on the couch. Rough total: ~2h indoors, ~30 min
outdoors — split freely.

## How to give feedback (what gets bugs fixed in one round trip)

For anything that misbehaves, send:
1. **Where**: screen + what you tapped
2. **What happened** vs **what you expected** (screenshots help, exact copy of any error text)
3. **Device state**: were you signed in, on WiFi, watch worn/recording, app fresh-launched or resumed, dark or light mode
4. Whether it happens **again** if you retry

"AYCE summary showed $0.00 ingredients after a scan-only session, second try same,
light mode, WiFi" fixes itself. "The buffet thing looked wrong" costs us a window.

---

## 1. Install & branding (5 min)
- [ ] New MFP monogram icon: home screen, Settings, App Library
- [ ] Long-press home screen → customize → dark + tinted icon variants look right
- [ ] Watch home screen shows the monogram (old logo gone)
- [ ] App launches cleanly after update; you're still signed in; goals intact

## 2. Home (10 min)
- [ ] Rings hero renders (even before logging anything today)
- [ ] Streak flame in the date capsule (2+ logged days); grace-day copy if you skipped yesterday
- [ ] Diary sits directly under the hero; entries expand/act correctly
- [ ] Recent-food swipe rows show the mini trust badge
- [ ] "Your week" recap banner opens the recap sheet — no crash (regression)
- [ ] Recap sheet: stat grid + **Running tile with your real watch runs**
- [ ] After 3pm with ≥150 cal remaining: fill-my-macros card → suggestion arrives (WiFi); toast if it fails
- [ ] Coaching dashboard entry → daily strategy card renders with your real numbers
- [ ] Train quick action switches to the Train tab (doesn't push a duplicate screen)

## 3. Quick-log menu (5 min)
- [ ] The compact centered Quick Log action opens the menu and stays visually independent from the five evenly spaced tabs; only its outlined plus carries the green emphasis, and Search food is the single green hero row
- [ ] Three primary rows present first: Search food, Scan barcode, Describe your meal
- [ ] More options reveals: Log with camera, Log exercise, Log recipe or meal, **Beat the buffet**, **Running**
- [ ] On a compact phone, the expanded list scrolls and the final Running action remains reachable
- [ ] Each row opens the right surface and the menu dismisses; Fewer options collapses the menu cleanly

## 4. Food logging & trust (20 min)
- [ ] Type a food name without pressing Search -> FatSecret/USDA may debounce, but Open Food Facts does not query until Search is submitted; press Search and confirm global branded results join the list
- [ ] Search a common food → result has FULL micros (potassium, B vitamins) — the ingestion fix
- [ ] Saved/recent foods rank above generic results
- [ ] Quick-log a search result → logged calories MATCH the previewed calories
- [ ] Open any food detail → **trust card v2**: score, reasons, action button when warranted
- [ ] Find/AI-create a suspicious entry → "This data looks off" + Fix This Data flow; your fix persists
- [ ] Scan a common barcode → hit; note the toast if it matched My Foods or a related barcode
- [ ] Scan something obscure → miss alert: Create food / Use camera / OK all work
- [ ] Fast Food Builder → search chains, build a Chipotle/Starbucks order, Review meal opens Food Detail with a Chain Builder / Needs Review trust card, then logs normally
- [ ] Builder brand chips remain readable for both bright brands (yellow/orange) and dark brands; the catalog version/estimated-review note is visible
- [ ] Camera-log a plate → items estimated; Refine Estimate works on AI results
- [ ] Describe a meal to Maia (text log) → parsed and logged
- [ ] Log exercise, log a saved recipe — both land in the diary

## 5. Beat the buffet — full game (20 min, couch-friendly)
- [ ] Quick-log → Beat the buffet → six cuisine cards in a grid (none crushed)
- [ ] City picker: choose your metro → tile prices scale; disclaimer names the city; choice persists after closing
- [ ] Sushi menu: three sections — Nigiri & sashimi / **Rolls (29)** / Small plates & dessert
- [ ] Other five cuisines each show a real menu (KBBQ, hot pot, Chinese, dim sum, Indian)
- [ ] Tap items → ×count badges, minus undoes, ticker + BOTH progress bars move
- [ ] Cross menu break-even → ONE success haptic + "You beat the spot by $X"
- [ ] Keep tapping until kitchen spend passes the buffet price → second haptic + "they're losing money" line bolds
- [ ] Scan your plate (any real food nearby) → "From your plate" strip with ~prices
- [ ] Kill the app mid-session → reopen → session resumed with everything intact
- [ ] End session → verdict + kitchen-win trophy line (if earned) + home-cost + ingredients lines
- [ ] Add to diary → "All-you-can-eat …" meal with correct totals; scanned items show AI-estimate styling
- [ ] Start a SECOND session → **"Your record: …" line** shows wins/losses/$ beaten
- [ ] Do a losing session (end early) → honest "The spot won this round" + record updates

## 6. Running (10 min indoors + 20 min [outdoor])
Indoors today:
- [ ] Train → Running (and via quick-log): your watch runs listed, newest first, source badges
- [ ] No duplicates from parallel recordings
- [ ] Run detail: route map + replayed per-km splits + avg HR
- [ ] Records card: longest / best 5K / best 10K, "estimated" footnote
- [ ] Map icon → all-routes map: your history draws, LATEST is the bright line
- [ ] Reports → Running card: 8-week mileage chart
- [ ] Start run → permission explainer reads right → allow → recorder opens (then discard <50m)
[outdoor] when dry:
- [ ] Record a real run: live metrics tick; lock phone → Live Activity + Dynamic Island; pause freezes; resume works
- [ ] Finish → summary (+🏅 if record) → appears in history as "MyFitPlate" AND in Apple Health with route
- [ ] **Parallel-watch check**: record phone + watch simultaneously → afterwards Apple Health's active energy for that window is sane, NOT doubled (the new guard)

## 7. Train tab regression (10 min)
- [ ] With no active program, Start a Plan scrolls to Plan Library and One-off scrolls to saved routines; create a routine if empty, then confirm it can be started, edited, and deleted
- [ ] Tile row: only AI Program is green; Pre-built/Manual/Saved are neutral now
- [ ] Next-workout slider, start a workout, player: compact header, rest chip, plates, Finish
- [ ] Auto rest label doesn't letter-stack; keyboard doesn't bury the set card
- [ ] Workout history + Key Gains + Muscle recovery render sanely

## 8. Weight + Reports (10 min)
- [ ] Weight card → chart-first screen; entry field autofocuses; delta matches Home card
- [ ] Backdated weigh-in works; units respect your metric setting
- [ ] Reports: timeframe picker leads; trend hero; overview; running card (above)

## 9. Fasting + Live Activities (10 min, indoors)
- [ ] Start a fast → ring + stages screen; Live Activity on lock screen + island; End-fast button works
- [ ] Run Live Activity did NOT break fasting's (both live in one extension now)

## 10. Watch + widgets (15 min)
- [ ] Watch Today glance: live cal remaining + macro gauges (sync from phone)
- [ ] Crown-log water → Log → banner on PHONE, total updates both sides
- [ ] Watch weight glance respects units
- [ ] Home-screen widgets small/medium/large: tuned colors (calories GREEN not red), water button logs
- [ ] **Lock-screen widgets** (new): add circular + rectangular + inline → real layouts, not a squeezed medium
- [ ] Watch complications (if added): render with data

## 11. Settings & data (10 min)
- [ ] Trigger any AI feature on a clean install/account -> AI data-sharing sheet appears before any request; choose Not now and confirm the request stays blocked
- [ ] Allow AI without Apple Health -> Maia works, but steps/sleep/recovery are excluded from AI context; enable the separate Health toggle and confirm the Health context indicator appears
- [ ] Reopen Settings -> AI data sharing, change the Health toggle, then turn AI sharing off; the next AI action must ask again
- [ ] Privacy policy, Terms, and Support links open publicly without requiring a GitHub login
- [ ] Calorie goal method shows the full selected label; change it from the menu, close Settings, reopen, and confirm the choice persists
- [ ] Feedback & support opens a new email with the feedback questions plus app/build and iOS version; confirm it contains no account, food, workout, or Health data
- [ ] Share MyFitPlate opens the system share sheet and includes the live App Store listing (`id6740922831`)
- [ ] CSV export → both files share/open with sane contents (no "Optional(0)")
- [ ] Reminders: change time → survives logging food (the 20:00 overwrite fix)
- [ ] Metric toggle → weight surfaces AND watch flip units
- [ ] Notification test: log reminder arrives at the set time (check tomorrow morning)
- [ ] Value Radar real menu scan -> every ranked item has a price visibly present in the source photo; Demo Menu is plainly fictional and cannot be logged
- [ ] **Throwaway account only, after Functions deployment:** add a log/custom food/community record, delete the account, confirm the app does not report success on a forced server failure, then verify Auth + Firestore records are gone

## 12. MyFitnessPal import (10 min — needs a real MFP export)
- [ ] Get an MFP export (myfitnesspal.com → Settings → Download My Data), unzip it
- [ ] Settings → Account → "Import from MyFitnessPal" → instructions read clearly
- [ ] Choose files (try selecting diary + weight CSVs together) → preview counts look sane
- [ ] Days already logged in MyFitPlate show as "skipped (already logged here)"
- [ ] Import → progress bar advances → completion summary
- [ ] Reports/trends now include the imported history; weigh-ins appear in weight chart
- [ ] Re-import the same file → every day now counts as a conflict (idempotent, no duplicates)

## 13. System passes (10 min)
- [ ] Dark mode sweep: Home, AYCE live, run detail, trust card, coaching, MFP import — no washed-out cards
- [ ] Dynamic Type XL spot check: Home + AYCE tiles + player don't clip
- [ ] Sign out / sign in → data returns; custom calorie goal SURVIVES (the reset-bug fix)
- [ ] Five bottom tabs are visible, evenly spaced, and usable (Home, Maia, Train, Meal Plan, Reports); their label baselines stay aligned, and the centered Quick Log action does not cover labels or tappable content
- [ ] Optional review-prompt check: on a fresh local install, complete three distinct workouts over at least three days and tap Done on the third summary. The app should request a review only then; Apple may still choose not to display the system prompt

## 14. Production services (owner check before archive)
- [ ] Add a real `USDA_API_KEY` to ignored `secrets.xcconfig`; USDA results are intentionally disabled when it is absent
- [ ] Deploy `generateAIResponse`, `fatSecretProxy`, and `deleteUserData` from `functions/`, then run AI, food lookup, and throwaway-account deletion smoke tests
- [ ] Register the iOS app for Firebase App Check with App Attest; register the local debug token for development; inspect App Check metrics before enabling backend enforcement
- [ ] Confirm the updated privacy policy, Terms, and Support docs are committed and publicly reachable on `main`
- [ ] Reconcile App Store Connect privacy answers and set the public Privacy Policy URL and Support URL

## Expected oddities (not bugs)
- DebugView/analytics silent in dev builds unless launched with `-enable-debug-analytics`
- Blue location pill during screen-off runs — required by iOS
- Buffet prices say "mid-range estimates for {region}" — by design
- Best 5K/10K say "estimated from average pace" — not measured segments
- Kitchen-spend bar moves much slower than menu-value bar — that's the harder game working
