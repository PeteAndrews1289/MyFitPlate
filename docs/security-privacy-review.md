# Security and Privacy Review

Updated for the 2.2 App Store release candidate on July 9, 2026.

## Data Flow Summary

- Account, nutrition, weight, workout, meal-plan, pantry, recipe, and preference data is stored under the authenticated user's Firebase records, with local caches for app and widget behavior.
- HealthKit data is read or written only after Apple permission and is used for visible app functionality. Precise location is used for an active outdoor run.
- AI requests go through authenticated Firebase callable Functions to OpenAI. The client never contains the OpenAI secret.
- FatSecret requests go through an authenticated Firebase callable proxy. USDA and Open Food Facts are direct HTTPS lookup sources; USDA is disabled without a dedicated configured key.
- Firebase Analytics and Crashlytics receive app/reliability context without the Firebase Auth UID. Health, nutrition, body, and workout values are removed from analytics event parameters.

## Controls Implemented

### AI processing

- A versioned, per-account consent record is required before every production AI request.
- The consent sheet names OpenAI and Firebase and describes submitted text/images plus nutrition, journal, cycle, pantry, meal, and workout context.
- Apple Health context has a separate toggle. Maia chat, weekly insight prompts, and smart-notification prompts exclude HealthKit-derived values unless it is enabled.
- Revoking consent blocks future AI calls. AI estimates retain visible review/estimate labeling.

### Account deletion

- Password reauthentication happens before deletion.
- The callable Function is the source of truth and recursively deletes the user's Firestore tree, owned posts/groups, memberships, contributed barcodes, usage counters, and Firebase Authentication record.
- The login record is deleted last. A server failure is shown to the user and cannot be reported as success.
- After server success, the app clears its full local defaults domain and shared widget data.

### Data integrity and abuse resistance

- Firebase Functions require authentication, validate payload shape and allowlisted parameters, clamp AI model/token settings, and enforce per-user daily limits.
- App Check client support uses the Debug provider for development and App Attest for release. Backend enforcement remains an owner-controlled rollout after production metrics confirm client readiness.
- Diary mutations are serialized per user/day to prevent overlapping writes from losing food, water, exercise, or deletion changes.
- Malformed remote daily logs now surface an error instead of becoming an empty writable replacement.
- Open Food Facts requires an identifying User-Agent and only joins text results after explicit Search submission.

## Release Owner Actions

1. Commit and push the current privacy policy, terms, and support pages so the in-app URLs resolve to the reviewed versions.
2. Deploy the updated Firebase Functions and test account deletion with a throwaway account.
3. Register App Attest and development debug tokens in Firebase App Check; review metrics before enabling callable enforcement.
4. Add the USDA FoodData Central key to ignored `secrets.xcconfig` for the archive.
5. Reconcile App Store Connect privacy answers with `PrivacyInfo.xcprivacy` and the public policy.
6. Have qualified counsel review the policy and terms before relying on them as final legal advice.

## Residual Risks

- Nutrition databases, AI estimates, menu scans, GPS, wearables, and calorie formulas remain inherently fallible; review labeling and device testing are required.
- App Check does not protect production callables until server enforcement is enabled.
- Firebase Functions changes do not affect production until deployed.
- Real-device HealthKit, route recording, background execution, Watch sync, signed archive, and deletion behavior cannot be fully proven by simulator tests.
