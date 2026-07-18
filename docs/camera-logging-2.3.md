# Trust-Aware Camera Logging 2.3

## Purpose

Camera logging is a fast draft, not a measurement. Version 2.3 improves the draft with stronger
vision models, a strict response contract, food-composition grounding, and an evidence-led review
screen. It does not claim that a photo can reveal hidden oil, exact portions, branded identity, or
micronutrients that are not visible.

## Server-Owned Model Routes

The app sends a narrow request kind and Firebase selects the model. A modified client cannot select
an expensive model directly.

| Workflow | Preferred server model | Compatibility fallback | Reasoning | Why |
| --- | --- | --- | --- | --- |
| Meal photo | `gpt-5.6-terra` | `gpt-4o-mini` | Low | Food separation, identity, preparation, portion range, and uncertainty require judgment. |
| Menu photo | `gpt-5.6-terra` | `gpt-4o-mini` | Low | Menu extraction plus realistic dish-level estimation is the other judgment-heavy image path. |
| Nutrition label | `gpt-5.6-luna` | `gpt-4o-mini` | Low | Primarily structured visual extraction; missing nutrients must remain missing. |
| Grocery receipt | `gpt-5.6-luna` | `gpt-4o-mini` | None | Bounded text extraction and normalization. |
| Recipe photo | `gpt-5.6-luna` | `gpt-4o-mini` | Low | Structured ingredient/instruction extraction with limited ambiguity. |
| General Maia calls | `gpt-4o-mini` | None | N/A | Keeps routine chat and generation cost unchanged for this release. |

The server retries a vision request on `gpt-4o-mini` only when the preferred model is unavailable
to the OpenAI project (for example, a model-access denial or missing model). It does not hide quota,
authentication, schema, or provider-service errors. An unavailable preferred model is skipped on
that warm Function instance for 30 minutes, avoiding a failed preferred-model request on every
photo while retaining automatic recovery when access becomes available.

The existing Firebase `OPENAI_API_KEY` secret is sufficient for the compatibility route. The
project behind that key must have billing and explicit access to use the preferred models. The July
16 release preflight verified that the current production project exposes `gpt-4o-mini` but not the
preferred GPT-5.6 models, and a live strict-schema compatibility probe passed. No key is shipped in
the app. Current model and pricing guidance is maintained by OpenAI and must be checked before
changing the route table:
<https://developers.openai.com/api/docs/guides/latest-model>.

## Request Safeguards

- Photos are orientation-normalized, flattened onto an opaque background, resized to at most 2,048
  pixels on the longest side, and recompressed as a JPEG no larger than 6 MB.
- Functions accept only bounded JPEG data URLs for image parts and reject unknown content-part
  types, oversized prompts, arbitrary remote image URLs, and unsupported detail settings.
- All AI calls require Firebase Authentication. Vision workflows share a separate limit of 75
  requests per account per UTC day in addition to the overall AI limit.
- A stable SHA-256 value derived from the Firebase UID is sent as the privacy-preserving OpenAI
  safety identifier. Prompts and responses are not written to usage telemetry.
- Token count, latency, success, and failure totals are recorded in private daily rollups. The
  `aiUsage` document carries account/day and workflow totals; `aiUsageBreakdown` keeps a separate
  aggregate for each account/day/workflow/model combination so model comparisons cannot blend.
  Pricing is deliberately not hardcoded because provider rates can change without an app release.

## Meal Photo Contract

The meal route uses a server-owned strict JSON schema. Each visible item returns:

- generic item identity and preparation;
- best estimated grams plus a realistic low/high range when visual scale permits;
- fallback calories and macros;
- confidence, visible evidence, and possible hidden ingredients;
- whether closer confirmation is needed; and
- at most one item-level clarification question.

The overall response can ask at most two high-impact questions. An unusable or non-food image must
return no foods. Missing scale must remain `null`; it must not become a fabricated exact serving.

The other four workflows also use complete server-owned strict JSON schemas:

- nutrition labels require serving identity, calories/macros, and every supported detailed
  nutrient key, while allowing unreadable optional values to remain `null`;
- menus return bounded dish rows with name, serving, calories/macros, and an optional price;
- receipts return bounded normalized grocery rows with name, quantity, unit, and category; and
- pantry recipe photos return exactly three bounded recipe drafts with description and macros.

Every object rejects undeclared properties and every field is represented in the schema's required
set. This prevents partially shaped model responses from quietly reaching client decoders. A July
17 content-free compatibility probe confirmed that `gpt-4o-mini` accepts and returns parseable
output for all five schemas; it is protocol evidence, not camera-accuracy evidence.

## Food-Composition Grounding

For each model-identified food, MyFitPlate searches USDA FoodData Central and Health Canada CNF.
A reference is used only when identity and preparation are sufficiently close and a usable gram
estimate exists. Reference nutrition and micronutrients are then scaled to the photo-estimated
portion.

This is composition grounding, not independent verification. The saved source remains
`Maia Vision`; the reference source is retained as secondary evidence. Identity and portion remain
photo estimates, and Trust must never call this cross-database agreement. Low-confidence identity,
missing grams, or a preparation conflict leaves nutrition as a model estimate and forces review.

## Review Experience

Nothing enters the diary until the user confirms the review screen. The screen exposes:

- overall and per-item photo confidence;
- portion ranges rather than false precision;
- whether nutrition came from a composition reference or remains model-estimated;
- possible hidden oil, sauce, dressing, filling, and topping risks;
- clarification questions; and
- direct item editing and removal before the final write.

After confirmation, the item records user review while retaining its photo-estimate lineage and
original estimate for Trust history.

## Emergency Controls

Every camera workflow has two independent controls:

- The current app checks Firebase Remote Config before sending the request. The keys are
  `feature_mealPhotoLogging`, `feature_nutritionLabelScanner`, `feature_menuScanner`,
  `feature_receiptScanner`, and `feature_recipePhotoScanner`.
- The callable checks the server-owned Firestore document `internalConfig/aiRoutes`. Boolean fields
  named `meal_photo`, `nutrition_label`, `menu_photo`, `receipt_photo`, and `recipe_photo` can each
  be set to `false`. Missing fields default to enabled, general Maia is never affected, and a server
  change takes effect on warm instances within 60 seconds.

The Firestore document is covered by the default-deny Rules and can be changed only through an
operator/admin path. Use the server control for a cost, provider, or output-quality incident and
the matching Remote Config control to remove the unavailable workflow from the current app.

## Deployment And Acceptance

As of July 17, the current `generateAIResponse` fallback and complete strict schemas are deployed.
A real authenticated meal-photo request attempted `gpt-5.6-terra`, received `model_not_found`,
then succeeded through `gpt-4o-mini`. The observed successful route used 26,025 input tokens, 179
output tokens, and 3,323 ms. This proves deployment and fallback behavior only; it is not a fixed-
set camera accuracy result or evidence of GPT-5.6 quality.

No additional deployment is required for backend commit `0aa44de9` or binary candidate commit
`39e3d1a2`; no Functions source changed after the deployed backend freeze. Redeploy this callable
only if Functions source changes after that commit:

```bash
firebase deploy --only functions:generateAIResponse
```

Before changing the route table or running a future model comparison, check the models exposed to
the exact Firebase secret without printing it:

```bash
cd functions
npm run preflight:openai-models -- --firebase-project caloriebeta-d28de
```

The compatibility model is release-required. Missing preferred models are a visible warning and
mean the benchmark is measuring the compatibility route, not the intended GPT-5.6 candidate.

No new Firebase secret, Firestore Rules, index, or migration is required. The optional
`internalConfig/aiRoutes` document is needed only when an operator wants to disable a route. Before
release, use at least 20-30 real photos across simple single foods, mixed plates, bowls/soups, restaurant meals,
visible and hidden sauces/oils, beverages, poor lighting, and missing scale. Record:

- correct item separation and useful generic identity;
- whether the true portion is inside the displayed range;
- high-impact hidden ingredients or questions surfaced;
- inappropriate database matches;
- correction scope before logging;
- end-to-end latency, malformed responses, and failures; and
- tokens by request kind and model in `aiUsageBreakdown`.

Use a dedicated temporary account for each fixed-set comparison and do not make unrelated AI calls
with that account during the run. In Firestore, filter `aiUsageBreakdown` by its `uid` and `day`,
then confirm the `requestKind`, `model`, success/failure counts, token totals, and total latency. A
preferred-model availability failure followed by a fallback success will produce one row for each
model; this is intentional and makes the compatibility path visible rather than silently blending
it into the preferred route.
Divide `totalLatencyMs` by successful plus failed calls for the mean server round-trip. Delete the
temporary account after recording aggregate results; account deletion removes both usage stores.

Compare the same fixed photo set against the previous route before claiming an accuracy gain. A
better-sounding answer is not evidence of better nutrition logging.

Use [Camera Benchmark 2.3](camera-benchmark-2.3.md) as the fixed manifest and result record.

## Scale Controls

If production usage grows, first reduce cost with measured routing changes rather than lowering
trust visibility: evaluate Luna for more menu cases, reduce image dimensions when accuracy holds,
cache repeated composition searches, or tighten the vision quota. Keep the client unable to select
models and preserve the review contract even when a cheaper model is used.
