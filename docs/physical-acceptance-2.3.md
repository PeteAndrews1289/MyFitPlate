# Version 2.3 Physical Acceptance

This is the remaining hands-on release checklist. Run it against version 2.3 build 1 from the
current candidate source. Record any failure in `docs/feedback-triage-2.3.md` before changing code.

Stop the release for a crash, data loss, wrong diary day, duplicate write, account-deletion failure,
private data in a share or diagnostic, unusable primary action, hidden AI write, or materially
misleading nutrition/training result.

## Setup

- [ ] Install 2.3 (1) on the primary iPhone and update the companion Watch app.
- [ ] Confirm the phone has enough representative meals, a current meal plan, one completed
  strength workout, and at least one imported or recorded run.
- [ ] Keep one disposable account available for camera and deletion testing.
- [ ] Test once on the smallest supported physical iPhone available.
- [ ] Keep the T7 attached before opening Xcode or Organizer.

## 1. Launch, Home, And Reports

- [ ] Cold-launch the app. Confirm the current dark-green/mint mark appears, the loading copy is
  readable, and Home opens without a blank or old-logo flash.
- [ ] In a five-second glance, identify what happened today, what is planned, and the one next
  action. Confirm calories and all macros show consumed and goal values, not only what remains.
- [ ] Add 8 oz of water from Home. Confirm the total updates once, survives leaving Home, and uses
  the intended diary day.
- [ ] Open the Daily Log. Confirm meal rows, totals, semantic colors, and Trust states remain clear
  in the flatter 2.3 design.
- [ ] Tap Quick Log once. Confirm it opens immediately and does not cover or crowd the five tab
  labels.
- [ ] Switch Home -> Reports -> Home three times. Living Day must return every time.
- [ ] Open Reports immediately after launch, leave, and return. Week in Motion may show its reserved
  loading state once, but content below it must not jump when data arrives.
- [ ] Switch Living Day between compact and detailed density, change day, relaunch, and confirm the
  intended Home and density persist.

## 2. Trust, Food Sources, And Corrections

- [ ] Search `chicken breast` and open a Health Canada result. Confirm a 100 g serving, broad
  micronutrients, Health Canada attribution, the 2026 release context, and composition wording that
  does not claim branded identity or laboratory verification.
- [ ] Search a multivitamin explicitly. Confirm Supplements is separate from ordinary food,
  manufacturer-label language is visible, the original tablet/capsule serving is retained, and
  missing or ambiguous nutrients are not shown as zero.
- [ ] Scan one real supplement barcode. NIH should be used only after ordinary food barcode sources
  miss, and the result must retain label-serving language.
- [ ] Open Settings > Nutrition Data Sources in light mode, dark mode, and large text. Confirm the
  Health Canada licence and NIH explanation are fully reachable.
- [ ] Open one USDA generic food, one packaged barcode with a second-source match, one photo
  estimate, one corrected My Food, one sparse food, and one old or unknown-date record. Confirm the
  Food Passport clearly distinguishes supported, estimated, missing, corrected, and stale evidence.
- [ ] On a mixed diary day, open Trust Hub. Confirm supported-calorie and supported-protein
  percentages are understandable and the highest-impact corrections appear first.
- [ ] Complete one correction loop:
  1. Open a barcode or photo result and note its current Trust evidence.
  2. Edit identity, serving, total fat, saturated fat, and one detailed nutrient where applicable.
  3. Confirm the before/after preview contains every changed field.
  4. Save and verify Trust refreshes.
  5. Reopen or rescan the same food and verify the corrected record is reused once, with no stale
     nutrients or duplicate legacy food.

## 3. Fixed Camera Benchmark

- [ ] Prepare the exact 25-image set in `docs/camera-benchmark-2.3.md`: 13 meals, four labels, three
  menus, two receipts, and three recipes.
- [ ] Run the set from a dedicated disposable account with no unrelated Maia requests.
- [ ] Confirm no image writes to the diary before final confirmation.
- [ ] Confirm the non-food image invents no food.
- [ ] Confirm missing label values and ambiguous recipe quantities stay missing or uncertain.
- [ ] For every meal result, record useful identity, item separation, whether the true portion is
  inside the range, hidden-ingredient warnings/questions, inappropriate reference matches,
  correction size, malformed responses, failures, and latency.
- [ ] On a mixed plate, edit one item and remove another before logging. Reopen the saved result and
  confirm photo-estimate lineage and user review remain visible.
- [ ] Try one large portrait photo and one unusable image. The large photo must upload without
  corruption; the unusable image must fail cleanly and remain recoverable.
- [ ] Smoke-test nutrition label, menu, receipt, and recipe-photo extraction after the meal set.
- [ ] Record the matching `aiUsageBreakdown` workflow/model totals and billed cost, then delete the
  temporary account.

## 4. Meal Plan, Grocery, And Fast Food

- [ ] Generate a full six-step meal plan. Confirm every step, loading state, empty state, summaries,
  pantry access, and generated meal row matches the 2.3 operational design.
- [ ] Add one manual grocery item. Regenerate or refresh the meal plan and confirm old generated
  items are replaced while the manual item remains.
- [ ] Confirm singular/plural duplicates such as `Banana` and `Bananas` collapse into one sensible
  row.
- [ ] Check a grocery item, hide checked items, restore them, leave, and return. Checked and hidden
  state must remain coherent without a double tap.
- [ ] Open and log one saved recipe. Confirm its serving and nutrition totals remain stable.
- [ ] In Fast Food Builder, search by menu item and test representative burger, chicken, coffee,
  pizza, Mexican, sandwich, and dessert chains.
- [ ] For each representative chain, confirm the menu feels populated, the official source link
  opens, add/remove and portion controls update totals immediately, and the reviewed order logs once.

## 5. Maia Voice And Reviewable Actions

- [ ] Ask the same practical nutrition question in Balanced, Coach, and Analyst modes. Confirm each
  answers directly, sounds distinct but natural, and avoids canned praise or dashboard recitation.
- [ ] Open one structured food or workout action. Confirm values are disclosed or editable and no
  write occurs before confirmation.
- [ ] Preview the default voice and at least one French or French-Canadian system voice. Confirm the
  displayed selection matches the sound, Stop Preview works, and other audio resumes.
- [ ] If only Standard voices exist, download an Enhanced or Premium French voice in iOS Spoken
  Content settings, reopen MyFitPlate, and confirm it becomes selectable.
- [ ] Read aloud a response containing an action card. Confirm only visible prose is spoken,
  nutrition units sound natural, hidden JSON is never spoken, and the control changes to Stop Reading.

## 6. Strength And Recovery

- [ ] Complete a real strength session with normal, warmup, drop, and failure sets; RPE or RIR;
  changed load/reps; rest timer; and adjacent supersets.
- [ ] Confirm progression prompts, exercise navigation, rest behavior, completion, and the recovery
  handoff remain fast and stable.
- [ ] Reopen workout history. Confirm set types and effort persist, while warmups remain excluded
  from volume and personal-record totals.
- [ ] Open Recovery Field. Confirm the body proportions look acceptable, front/back selection is
  clear, tapping each tested region updates the matching muscle card, and the supporting training
  evidence is understandable and cautious.
- [ ] Repeat Recovery Field in dark mode, large text, Increased Contrast, and VoiceOver. Every
  selectable region and evidence action must remain reachable.

## 7. Running

- [ ] Complete one real guided outdoor interval. Confirm step transitions, spoken and haptic cues,
  pause/resume, target text, GPS distance, final review, Live Activity, and Apple Health save.
- [ ] Open one Watch-imported run with heart-rate samples. Confirm real time-in-zone appears and
  distance/calories are not duplicated.
- [ ] Open or record one phone-only run without heart rate. HR cards must remain unavailable rather
  than showing zero.
- [ ] Reopen a route containing a long stop or weak-GPS interval. Split times must reconcile with
  total workout duration and a misleading Negative Split badge must remain hidden.

## 8. Watch, Widgets, Live Activity, And Links

- [ ] Change today's phone data, open the Watch app, and confirm calories, macros, water, units,
  next action, and last-sync state refresh without an `Open the phone app` loop.
- [ ] Put the phone out of reach, queue water and one recent-meal repeat on Watch, reconnect, and
  confirm exactly one write for each action on the intended day.
- [ ] Sign out on iPhone and confirm account-scoped Watch context clears.
- [ ] Add and tap every supported widget family. Confirm current data appears and each opens its
  exact destination.
- [ ] Start a supported workout/run and confirm the Live Activity starts, updates, deep-links
  correctly, and ends.
- [ ] Receive one Training Fuel notification from the Lock Screen and confirm it opens Training Fuel.
- [ ] Test `myfitplate://trust`, `builder`, `train`, `runs`, `meal-plan`, and `reports`.

## 9. Sharing, Accessibility, Resilience, And Deletion

- [ ] Share one Living Day and one Week in Motion image through a real destination after changing
  the visible-section toggles. The delivered image must match the preview and contain no account ID,
  food/workout name, route, coordinate, item nutrition, or raw Health sample.
- [ ] Repeat a short Home, Maia, Train, Meal Plan, and Reports sweep in dark mode and the largest
  practical text size. Confirm there is no clipped text, unreachable action, nested-card regression,
  or visually unrelated legacy page.
- [ ] With VoiceOver, traverse Home, Quick Log, Trust, Maia, the workout player, Recovery Field,
  Meal Plan, and Reports. Spoken order must be useful and decorative content must stay silent.
- [ ] Repeat Home and workout interactions with Reduce Motion and Increased Contrast enabled.
  Saved writes and navigation must not wait for animation.
- [ ] Disable connectivity during Food Search. Saved/recent foods must remain usable and remote
  failure must offer Try Again and Create Food without a raw error. Restore connectivity and recover
  without relaunching.
- [ ] Deny Apple Health, AI sharing, camera, microphone/speech, notifications, and location one at a
  time. Each affected feature must explain the limitation without crashing or blocking unrelated use.
- [ ] With a disposable account, add one diary item and make one AI request, then delete the account
  in-app. Confirm sign-in no longer works and phone, Watch, widget, and shared local state clear.

## 10. Final Candidate Smoke

- [ ] Install the TestFlight or App Store-processed candidate over the prior public version. Confirm
  existing account data remains intact.
- [ ] Open all five tabs, add one disposable Quick Log item, remove it, and confirm Watch context
  refreshes.
- [ ] Check Firebase App Check metrics from this signed build. Keep enforcement off unless valid
  requests are consistently clean and unexplained invalid/unknown traffic is understood.
- [ ] Record pass/fail, device, OS, build, and any blocker. If app source changes, regenerate the
  archive and any affected screenshots before upload.
