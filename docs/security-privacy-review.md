# Security and Privacy Review

Updated for the replacement 2.2 release candidate on July 12, 2026. Internal 2.3 contract
filenames and analytics schema remain unchanged for traceability.

## Data Flow Summary

- Account, nutrition, weight, workout, meal-plan, pantry, recipe, and preference data is stored under the authenticated user's Firebase records, with local caches for app and widget behavior.
- HealthKit data is read or written only after Apple permission and is used for visible app functionality. Precise location is used for an active outdoor run.
- AI requests go through authenticated Firebase callable Functions to OpenAI. The client never contains the OpenAI secret.
- FatSecret requests go through an authenticated Firebase callable proxy. USDA and Open Food Facts are direct HTTPS lookup sources; USDA is disabled without a dedicated configured key.
- Firebase Analytics receives an app-instance/device identifier, approximate location, and
  app/reliability context without the Firebase Auth UID. Crashlytics receives unlinked crash and
  diagnostic context and is explicitly cleared of any user ID. Health, nutrition, body, and
  workout values are removed from analytics event parameters.
- Trust calibration uses only source/band/evidence categories, coarse changed-field groups, and
  stable outcomes. The central sanitizer also rejects raw identity and free-form content keys
  such as barcode, food/account ID, email, prompt, query, and message.

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
- Community barcode submissions require authentication, App Check, a checksum-valid GTIN,
  exact bounded fields, serving evidence, and clean nutrition sanity checks. They are stored under
  private per-user paths without UID fields and are rate limited to 20 accepted requests per
  account/day. Clients cannot create or update those documents directly.
- Only a server-owned 3+ contributor, at least two-thirds consensus can be published. Published
  records omit contributor identifiers, deny collection listing and client writes, pass strict
  Rules and app-side validation, and remain capped at Review behind
  `feature_communityBarcodeCorrections=false`. Private quarantine, aggregate health counters, a
  250-document rebuild ceiling, and a kill switch provide fail-closed rollback.

## Release Owner Actions

1. Commit and push the current privacy policy, terms, and support pages so the in-app URLs resolve to the reviewed versions.
2. For the dormant community pipeline, deploy Functions first and then Firestore Rules/indexes. Keep
   community barcode Remote Config disabled and follow the backup-first rollout in
   `docs/community-barcode-consensus-2.3.md`.
3. Test account deletion and private-contribution withdrawal with throwaway accounts.
4. Register App Attest and development debug tokens in Firebase App Check; review metrics before enabling callable enforcement.
5. Add the USDA FoodData Central key to ignored `secrets.xcconfig` for the archive.
6. Reconcile App Store Connect privacy answers with `PrivacyInfo.xcprivacy` and the public policy.
7. Have qualified counsel review the policy and terms before relying on them as final legal advice.

## Residual Risks

- Nutrition databases, AI estimates, menu scans, GPS, wearables, and calorie formulas remain inherently fallible; review labeling and device testing are required.
- App Check does not protect production callables until server enforcement is enabled.
- Firebase Functions changes do not affect production until deployed.
- Authentication, App Check, and rate limits do not eliminate coordinated multi-account abuse.
  Community results therefore remain a conservative Review-band fallback pending internal soak;
  public rollout and broad reaggregation remain open gates rather than replacement 2.2 release requirements.
- The Functions runtime is moved to Node.js 22. Future runtime lifecycle notices must be handled
  before deprecation rather than during an emergency release.
- Real-device HealthKit, route recording, background execution, Watch sync, signed archive, and deletion behavior cannot be fully proven by simulator tests.
