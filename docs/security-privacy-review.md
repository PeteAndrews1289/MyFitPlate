# Security and Privacy Review

Updated for the 2.3 release candidate on July 15, 2026. Version 2.2 is the current public release;
internal contract filenames and analytics schema remain unchanged for traceability.

## Data Flow Summary

- Account, nutrition, weight, workout, meal-plan, pantry, recipe, and preference data is stored under the authenticated user's Firebase records, with local caches for app and widget behavior.
- HealthKit data is read or written only after Apple permission and is used for visible app functionality. Precise location is used for an active outdoor run.
- AI requests go through authenticated Firebase callable Functions to OpenAI. The client never contains the OpenAI secret.
- FatSecret requests go through an authenticated Firebase callable proxy. USDA and Open Food Facts
  are direct HTTPS lookup sources; USDA is disabled without a dedicated configured key. Health
  Canada CNF is searched from a versioned backend asset. Explicit supplement searches and food-
  provider barcode misses can send a bounded search term or barcode through an authenticated
  callable to NIH DSLD; those values are not written to the rate-limit document.
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
- The client supplies a narrow purpose such as meal photo or nutrition label; Functions owns the
  model route, reasoning level, token ceiling, and response contract. Stronger vision models are
  reserved for image workflows while ordinary Maia traffic retains the lower-cost route.
- Meal photos use an evidence-led review contract. Database composition can be scaled to a
  photo-estimated identity and portion, but the source remains an AI estimate and is never promoted
  to independent verification.

### Account deletion

- Password reauthentication happens before deletion.
- The callable Function is the source of truth and recursively deletes the user's Firestore tree,
  owned posts/groups, memberships, contributed barcodes, AI/FatSecret/reference-food/supplement/
  community usage counters, and Firebase Authentication record.
- The login record is deleted last. A server failure is shown to the user and cannot be reported as success.
- After server success, the app clears its full local defaults domain and shared widget data.

### Data integrity and abuse resistance

- Firebase Functions require authentication, validate payload shape and allowlisted parameters,
  clamp AI model/token settings, and enforce per-user daily limits. Image parts must be bounded JPEG
  data URLs; arbitrary remote URLs and unknown content-part types are rejected. The app also
  normalizes and recompresses images before upload.
- Vision calls have a separate 75-request daily account limit. Aggregate success, failure, token,
  and latency totals are retained by purpose and model without prompts or responses. A SHA-256
  derivative of the account UID is used only as OpenAI's stable safety identifier.
- Meal, label, menu, receipt, and recipe camera routes each have an app Remote Config switch and a
  server-owned `internalConfig/aiRoutes` boolean. The server document is default-denied to clients,
  does not affect general Maia, and is cached for no more than 60 seconds.
- App Check client support uses the Debug provider for development and App Attest for release. Backend enforcement remains an owner-controlled rollout after production metrics confirm client readiness.
- Diary mutations are serialized per user/day to prevent overlapping writes from losing food, water, exercise, or deletion changes.
- Malformed remote daily logs now surface an error instead of becoming an empty writable replacement.
- Open Food Facts requires an identifying User-Agent and only joins text results after explicit Search submission.
- Health Canada and NIH lookups require authentication, validate bounded input, and use separate
  per-user daily limits. Health Canada data stays inside Functions; NIH receives only the explicit
  supplement term or barcode needed for the selected lookup path.
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
2. Deploy Functions for Health Canada CNF, NIH DSLD, and the purpose-routed camera models before
   testing them. The existing `OPENAI_API_KEY` remains sufficient; confirm its OpenAI project has
   billing and access to the selected models. No new Firestore Rules or indexes are required.
3. For the dormant community pipeline, deploy Functions first and then Firestore Rules/indexes. Keep
   community barcode Remote Config disabled and follow the backup-first rollout in
   `docs/community-barcode-consensus-2.3.md`.
4. Test account deletion and private-contribution withdrawal with throwaway accounts.
5. Register App Attest and development debug tokens in Firebase App Check; review metrics before enabling callable enforcement.
6. Add the USDA FoodData Central key to ignored `secrets.xcconfig` for the archive.
7. Reconcile App Store Connect privacy answers with `PrivacyInfo.xcprivacy` and the public policy.
8. Have qualified counsel review the policy and terms before relying on them as final legal advice.

## Residual Risks

- Nutrition databases, AI estimates, menu scans, GPS, wearables, and calorie formulas remain
  inherently fallible; review labeling and device testing are required. A stronger model does not
  make hidden ingredients or exact portions observable, so release claims require a fixed-photo
  benchmark rather than subjective fluency.
- CNF is generic composition rather than exact branded-product evidence. DSLD contains manufacturer
  label claims, not assay results, and NIH availability can affect supplement lookup.
- App Check does not protect production callables until server enforcement is enabled.
- Firebase Functions changes do not affect production until deployed.
- Authentication, App Check, and rate limits do not eliminate coordinated multi-account abuse.
  Community results therefore remain a conservative Review-band fallback pending internal soak;
  public rollout and broad reaggregation remain open gates rather than replacement 2.2 release requirements.
- The Functions runtime is moved to Node.js 22. Future runtime lifecycle notices must be handled
  before deprecation rather than during an emergency release.
- Real-device HealthKit, route recording, background execution, Watch sync, signed archive, and deletion behavior cannot be fully proven by simulator tests.
