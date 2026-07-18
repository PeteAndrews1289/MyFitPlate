# Version 2.3 Physical Acceptance

This is the retained hands-on release record for version 2.3 build 1. Candidate `39e3d1a2` passed
the broad device matrix but is superseded by the accepted Food Detail addition. Record any later
failure in `docs/feedback-triage-2.3.md` before changing code.

Peter physically validated the ordinary device journeys in sections 1 through 9 on July 17, 2026,
then accepted the final-source upgrade and cross-tab smoke in section 10 on July 18.
Peter also accepted all six nutrition-first Food Detail checks in
`docs/food-detail-nutrient-profile-2.3.md` on July 18, including correction persistence, physical
keyboard dismissal, dark mode, and large text.
The comparative 25-image camera scorecard was not retained, so it remains a post-release
calibration task rather than evidence for a 2.3 accuracy claim. The online Maia Natural service
check and final App Store-processed candidate smoke also remain open because they require
unavailable API access or final-candidate evidence rather than another ordinary device journey.

Stop the release for a crash, data loss, wrong diary day, duplicate write, account-deletion failure,
private data in a share or diagnostic, unusable primary action, hidden AI write, or materially
misleading nutrition/training result.

## Setup

- [x] Install 2.3 (1) on the primary iPhone and update the companion Watch app.
- [x] Record baseline app commit `39e3d1a2` and Functions commit `0aa44de9`. The backend remains
  unchanged; record the replacement app commit after the Food Detail merge and package refresh.
- [x] Run the OpenAI model-access preflight against the Firebase secret. Record whether the run is
  testing GPT-5.6 or the `gpt-4o-mini` compatibility route. As of the July 17 physical pass,
  `gpt-5.6-terra` returns `model_not_found` and meal photos successfully use the compatibility
  route; do not expect online Maia Natural until the API project can access its speech model.
- [x] Confirm the phone has enough representative meals, a current meal plan, one completed
  strength workout, and at least one imported or recorded run.
- [x] Keep one disposable account available for camera and deletion testing.
- [x] Test once on the smallest supported physical iPhone available.
- [x] Keep the T7 attached before opening Xcode or Organizer.

## 1. Launch, Home, And Reports

- [x] Cold-launch the app. Confirm the current dark-green/mint mark appears, the loading copy is
  readable, and Home opens without a blank or old-logo flash.
- [x] In a five-second glance, identify what happened today, what is planned, and the one next
  action. Confirm calories and all macros show consumed and goal values, not only what remains.
- [x] Add 8 oz of water from Home. Confirm the total updates once, survives leaving Home, and uses
  the intended diary day.
- [x] Open the Daily Log. Confirm meal rows, totals, semantic colors, and Trust states remain clear
  in the flatter 2.3 design.
- [x] Tap Quick Log once. Confirm it opens immediately and does not cover or crowd the five tab
  labels.
- [x] Switch Home -> Reports -> Home three times. Living Day must return every time.
- [x] Open Reports immediately after launch, leave, and return. Week in Motion may show its reserved
  loading state once, but content below it must not jump when data arrives.
- [x] Switch Living Day between compact and detailed density, change day, relaunch, and confirm the
  intended Home and density persist.

## 2. Trust, Food Sources, And Corrections

- [x] Search `chicken breast` and open a Health Canada result. Confirm a 100 g serving, broad
  micronutrients, Health Canada attribution, the 2026 release context, and composition wording that
  does not claim branded identity or laboratory verification.
- [x] Search a multivitamin explicitly. Confirm Supplements is separate from ordinary food,
  manufacturer-label language is visible, the original tablet/capsule serving is retained, and
  missing or ambiguous nutrients are not shown as zero.
- [x] Scan one real supplement barcode. NIH should be used only after ordinary food barcode sources
  miss, and the result must retain label-serving language.
- [x] Open Settings > Nutrition Data Sources in light mode, dark mode, and large text. Confirm the
  Health Canada licence and NIH explanation are fully reachable.
- [x] Open one USDA generic food, one packaged barcode with a second-source match, one photo
  estimate, one corrected My Food, one sparse food, and one old or unknown-date record. Confirm the
  Food Passport clearly distinguishes supported, estimated, missing, corrected, and stale evidence.
- [x] On a mixed diary day, open Trust Hub. Confirm supported-calorie and supported-protein
  percentages are understandable and the highest-impact corrections appear first.
- [x] Complete one correction loop:
  1. Open a barcode or photo result and note its current Trust evidence.
  2. Edit identity, serving, total fat, saturated fat, and one detailed nutrient where applicable.
  3. Confirm the before/after preview contains every changed field.
  4. Save and verify Trust refreshes.
  5. Reopen or rescan the same food and verify the corrected record is reused once, with no stale
     nutrients or duplicate legacy food.

## 3. Camera Acceptance And Fixed Benchmark

- [x] Prove one authenticated camera request succeeds after the current Function deployment before
  scoring any fixed-set image.
- [ ] Prepare the exact 25-image set in `docs/camera-benchmark-2.3.md`: 13 meals, four labels, three
  menus, two receipts, and three recipes.
- [ ] Run the set from a dedicated disposable account with no unrelated Maia requests.
- [x] Confirm no image writes to the diary before final confirmation.
- [x] Confirm the non-food image invents no food.
- [x] Confirm missing label values and ambiguous recipe quantities stay missing or uncertain.
- [ ] For every meal result, record useful identity, item separation, whether the true portion is
  inside the range, hidden-ingredient warnings/questions, inappropriate reference matches,
  correction size, malformed responses, failures, and latency.
- [x] On a mixed plate, edit one item and remove another before logging. Reopen the saved result and
  confirm photo-estimate lineage and user review remain visible.
- [x] Try one large portrait photo and one unusable image. The large photo must upload without
  corruption; the unusable image must fail cleanly and remain recoverable.
- [x] Choose one benchmark image from the photo library. Deny Photos access once if iOS presents
  the permission, confirm MyFitPlate explains how to recover, then grant Limited or Full access in
  Settings and select the image without relaunching or losing the pending workflow.
- [x] Smoke-test nutrition label, menu, receipt, and recipe-photo extraction after the meal set.
- [ ] Record the matching `aiUsageBreakdown` workflow/model totals and billed cost, then delete the
  temporary account.

## 4. Meal Plan, Grocery, And Fast Food

- [x] Generate a full six-step meal plan. Confirm every step, loading state, empty state, summaries,
  pantry access, and generated meal row matches the 2.3 operational design.
- [x] Add one manual grocery item. Regenerate or refresh the meal plan and confirm old generated
  items are replaced while the manual item remains.
- [x] Confirm singular/plural duplicates such as `Banana` and `Bananas` collapse into one sensible
  row.
- [x] Check a grocery item, hide checked items, restore them, leave, and return. Checked and hidden
  state must remain coherent without a double tap.
- [x] Open and log one saved recipe. Confirm its serving and nutrition totals remain stable.
- [x] In Fast Food Builder, search by menu item and test representative burger, chicken, coffee,
  pizza, Mexican, sandwich, and dessert chains.
- [x] For each representative chain, confirm the menu feels populated, the official source link
  opens, add/remove and portion controls update totals immediately, and the reviewed order logs once.

## 5. Maia Voice And Reviewable Actions

- [x] Ask the same practical nutrition question in Balanced, Coach, and Analyst modes. Confirm each
  answers directly, sounds distinct but natural, and avoids canned praise or dashboard recitation.
- [x] Open one structured food or workout action. Confirm values are disclosed or editable and no
  write occurs before confirmation.
- [x] Preview the default voice and at least one French or French-Canadian system voice. Confirm the
  displayed selection matches the sound, Stop Preview works, and other audio resumes.
- [ ] After the API project receives access to the configured speech model, select Maia Natural.
  Confirm it is labeled online and AI-generated, sounds materially more natural, and does not
  silently claim to be a Siri voice. Redeploy only if the bound Firebase secret changes.
- [x] Disable AI data sharing and attempt Maia Natural, then repeat offline. Both cases must use the
  local full-response fallback without sending speech text, exposing a raw error, or truncating the
  spoken answer.
- [x] If only Standard voices exist, download an Enhanced or Premium French voice in iOS Spoken
  Content settings, reopen MyFitPlate, and confirm it becomes selectable.
- [x] Read aloud a response containing an action card. Confirm only visible prose is spoken,
  nutrition units sound natural, hidden JSON is never spoken, and the control changes to Stop Reading.

## 6. Strength And Recovery

- [x] Complete a real strength session with normal, warmup, drop, and failure sets; RPE or RIR;
  changed load/reps; rest timer; and adjacent supersets.
- [x] Confirm progression prompts, exercise navigation, rest behavior, completion, and the recovery
  handoff remain fast and stable.
- [x] Reopen workout history. Confirm set types and effort persist, while warmups remain excluded
  from volume and personal-record totals.
- [x] Open Recovery Field. Confirm the body proportions look acceptable, front/back selection is
  clear, tapping each tested region updates the matching muscle card, and the supporting training
  evidence is understandable and cautious.
- [x] Repeat Recovery Field in dark mode, large text, Increased Contrast, and VoiceOver. Every
  selectable region and evidence action must remain reachable.

## 7. Running

- [x] Complete one real guided outdoor interval. Confirm step transitions, spoken and haptic cues,
  pause/resume, target text, GPS distance, final review, Live Activity, and Apple Health save.
- [x] Open one Watch-imported run with heart-rate samples. Confirm real time-in-zone appears and
  distance/calories are not duplicated.
- [x] Open or record one phone-only run without heart rate. HR cards must remain unavailable rather
  than showing zero.
- [x] Reopen a route containing a long stop or weak-GPS interval. Split times must reconcile with
  total workout duration and a misleading Negative Split badge must remain hidden.

## 8. Watch, Widgets, Live Activity, And Links

- [x] Change today's phone data, open the Watch app, and confirm calories, macros, water, units,
  next action, and last-sync state refresh without an `Open the phone app` loop.
- [x] Put the phone out of reach, queue water and one recent-meal repeat on Watch, reconnect, and
  confirm exactly one write for each action on the intended day.
- [x] Sign out on iPhone and confirm account-scoped Watch context clears.
- [x] Add and tap every supported widget family. Confirm current data appears and each opens its
  exact destination.
- [x] Start a supported workout/run and confirm the Live Activity starts, updates, deep-links
  correctly, and ends.
- [x] Receive one Training Fuel notification from the Lock Screen and confirm it opens Training Fuel.
- [x] Test `myfitplate://trust`, `builder`, `train`, `runs`, `meal-plan`, and `reports`.

## 9. Sharing, Accessibility, Resilience, And Deletion

- [x] Share one Living Day and one Week in Motion image through a real destination after changing
  the visible-section toggles. The delivered image must match the preview and contain no account ID,
  food/workout name, route, coordinate, item nutrition, or raw Health sample.
- [x] Repeat a short Home, Maia, Train, Meal Plan, and Reports sweep in dark mode and the largest
  practical text size. Confirm there is no clipped text, unreachable action, nested-card regression,
  or visually unrelated legacy page.
- [x] With VoiceOver, traverse Home, Quick Log, Trust, Maia, the workout player, Recovery Field,
  Meal Plan, and Reports. Spoken order must be useful and decorative content must stay silent.
- [x] Repeat Home and workout interactions with Reduce Motion and Increased Contrast enabled.
  Saved writes and navigation must not wait for animation.
- [x] Disable connectivity during Food Search. Saved/recent foods must remain usable and remote
  failure must offer Try Again and Create Food without a raw error. Restore connectivity and recover
  without relaunching.
- [x] Deny Apple Health, AI sharing, camera, Photos, microphone/speech, notifications, and location
  one at a time. Each affected feature must explain the limitation without crashing or blocking
  unrelated use; re-enable each permission in Settings and confirm the feature recovers without an
  account reset or duplicate write.
- [x] With a disposable account, add one diary item and make one AI request, then delete the account
  in-app. Confirm sign-in no longer works and phone, Watch, widget, and shared local state clear.

## 10. Final Candidate Smoke

- [x] Install the final 2.3 source over the prior public version on the primary iPhone. Confirm
  existing account data remains intact.
- [x] Open all five tabs, add one disposable Quick Log item, remove it, and confirm Watch context
  refreshes.
- [x] Record the July 18 physical result: final-source phone build passed without a reported blocker.
- [ ] After App Store processing, install the exact TestFlight candidate and confirm the processed
  binary still preserves the same upgrade and cross-tab behavior.
- [ ] Check Firebase App Check metrics from that processed signed build. Keep enforcement off unless
  valid requests are consistently clean and unexplained invalid/unknown traffic is understood.

The two remaining checks validate Apple's processed package and production App Attest path, which a
local Xcode installation cannot establish. If app source changes, regenerate the archive and any
affected screenshots before upload.
