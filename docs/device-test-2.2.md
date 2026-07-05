# 2.2 device-test checklist

Everything shipped since the last on-device build, ordered as one walkthrough.
Report failures with what you saw + device state (per the debugging protocol).

## 1. Install & branding (2 min)
- [ ] New MFP monogram icon on the home screen; check dark mode + tinted variants
- [ ] Watch shows the same monogram (old logo gone)
- [ ] Onboarding/app opens normally after update (no migration weirdness)

## 2. Watch app (5 min)
- [ ] Watch "Today" glance shows live calories remaining + macro gauges (synced from phone)
- [ ] Crown-log water on watch → Log button → banner appears on PHONE and total updates
- [ ] Watch weight glance shows current/goal in your units
- [ ] Fasting Live Activity still works (regression check — run widget joined the same bundle)

## 3. Running (15 min — the walk-around-the-block test)
- [ ] Train → Running: your real Apple Watch runs appear (source badges, distances sane)
- [ ] No duplicate runs from parallel recordings (watch + anything else)
- [ ] Tap a watch run → route map draws + per-km splits appear (replayed from GPS)
- [ ] Records card shows longest / best 5K / best 10K (marked estimated)
- [ ] Map icon → all-routes map: routes draw, LATEST run is the bright green one
- [ ] Start run → permission explainer → allow → live timer/distance/pace tick
- [ ] Lock the phone mid-run → Live Activity on lock screen + Dynamic Island; timer ticks
- [ ] Pause → Live Activity shows paused + frozen clock; resume works
- [ ] Finish → summary (splits; 🏅 line if it set a record) → run appears in history AND Apple Health (with route)
- [ ] Recorded run shows as "MyFitPlate" source in history (round-trip)
- [ ] Reports tab → Running card: 8-week mileage chart renders
- [ ] Weekly Recap → Running tile shows this week's runs + distance

## 4. Beat the buffet (10 min — fake session at home is fine)
- [ ] Tab-bar + → "Beat the buffet" → six cuisine cards in a grid
- [ ] City picker: pick your metro; note tile prices scale; choice persists next session
- [ ] Sushi menu shows sections: Nigiri & sashimi / Rolls (29 of them) / Small plates & dessert
- [ ] Tap items → ×count badges, minus undoes; status ticker + BOTH bars move (menu value + kitchen spend)
- [ ] Cross break-even → one-time success haptic + "You beat the spot by $X"
- [ ] Scan your plate → camera → items appear in "From your plate" strip with ~prices
- [ ] Kill the app mid-session → reopen → session resumed
- [ ] End session → verdict + "Cooking this at home" + "Their ingredients" lines
- [ ] Add to today's diary → meal "All-you-can-eat Sushi" in the diary with correct calories
- [ ] Scanned items show AI-estimate trust styling in the diary; catalog items don't

## 5. Barcode + trust (5 min)
- [ ] Scan a common packaged product → hit; note toast if matched from My Foods / related barcode
- [ ] Scan something obscure → miss alert offers Create food / Use camera / OK
- [ ] Open any food's detail → new trust card (score, reasons, action button when warranted)
- [ ] Recent-food rows show the mini trust badge

## 6. Coaching + earlier fixes (5 min)
- [ ] Coaching dashboard opens; daily strategy card renders with your data
- [ ] Weekly Recap opens (no crash — regression check)
- [ ] After 3pm with ≥150 cal remaining: fill-my-macros card on Home → suggestion arrives
- [ ] Streak flame in the date bar (if you've logged 2+ days)

## 7. Expected oddities (not bugs)
- Firebase DebugView is silent in dev builds unless launched with `-enable-debug-analytics`
- Background-location blue pill appears during runs with screen off — correct behavior
- Buffet prices are labeled mid-range estimates for your chosen region — by design
