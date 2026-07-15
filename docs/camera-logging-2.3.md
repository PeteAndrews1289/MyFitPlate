# Trust-Aware Camera Logging 2.3

## Purpose

Camera logging is a fast draft, not a measurement. Version 2.3 improves the draft with stronger
vision models, a strict response contract, food-composition grounding, and an evidence-led review
screen. It does not claim that a photo can reveal hidden oil, exact portions, branded identity, or
micronutrients that are not visible.

## Server-Owned Model Routes

The app sends a narrow request kind and Firebase selects the model. A modified client cannot select
an expensive model directly.

| Workflow | Server model | Reasoning | Why |
| --- | --- | --- | --- |
| Meal photo | `gpt-5.6-terra` | Low | Food separation, identity, preparation, portion range, and uncertainty require judgment. |
| Menu photo | `gpt-5.6-terra` | Low | Menu extraction plus realistic dish-level estimation is the other judgment-heavy image path. |
| Nutrition label | `gpt-5.6-luna` | Low | Primarily structured visual extraction; missing nutrients must remain missing. |
| Grocery receipt | `gpt-5.6-luna` | None | Bounded text extraction and normalization. |
| Recipe photo | `gpt-5.6-luna` | Low | Structured ingredient/instruction extraction with limited ambiguity. |
| General Maia calls | `gpt-4o-mini` | N/A | Keeps routine chat and generation cost unchanged for this release. |

The existing Firebase `OPENAI_API_KEY` secret is sufficient. Do not create or ship a second key.
The project behind that key must have billing and access to the selected models. Current model and
pricing guidance is maintained by OpenAI and must be checked before changing the route table:
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
- Token count, latency, success, and failure totals are recorded by workflow and model. Pricing is
  deliberately not hardcoded because provider rates can change without an app release.

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

## Deployment And Acceptance

Deploy the changed callable before testing:

```bash
firebase deploy --only functions
```

No new Firebase secret, Firestore Rules, index, or migration is required. Before release, use at
least 20-30 real photos across simple single foods, mixed plates, bowls/soups, restaurant meals,
visible and hidden sauces/oils, beverages, poor lighting, and missing scale. Record:

- correct item separation and useful generic identity;
- whether the true portion is inside the displayed range;
- high-impact hidden ingredients or questions surfaced;
- inappropriate database matches;
- correction scope before logging;
- end-to-end latency, malformed responses, and failures; and
- tokens by request kind in `aiUsage`.

Compare the same fixed photo set against the previous route before claiming an accuracy gain. A
better-sounding answer is not evidence of better nutrition logging.

## Scale Controls

If production usage grows, first reduce cost with measured routing changes rather than lowering
trust visibility: evaluate Luna for more menu cases, reduce image dimensions when accuracy holds,
cache repeated composition searches, tighten the vision quota, or place the route table behind a
server feature flag. Keep the client unable to select models and preserve the review contract even
when a cheaper model is used.
