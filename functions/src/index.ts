import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { createHash } from "node:crypto";
import OpenAI from "openai";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import {
  COMMUNITY_BARCODE_MODEL_VERSION,
  CommunityBarcodeAggregationResult,
  CommunityBarcodeContribution,
  buildCommunityBarcodeAggregate,
  isValidGTIN,
  normalizeBarcode,
  parseCommunityBarcodeContribution,
} from "./communityBarcode";
import {
  loadCanadianNutrientDataset,
  searchCanadianNutrientFile,
} from "./canadianNutrientFile";
import {
  lookupDietarySupplementBarcode,
  searchDietarySupplements,
} from "./dietarySupplementLabels";
import {
  AIRequestKind,
  AIVisionRouteConfiguration,
  isAIRequestRouteEnabled,
  isReasoningRoute,
  resolveAIRequestRoute,
} from "./aiRequestRouting";
import {
  aiUsageBreakdownDocumentID,
  aiUsageRequestPrefix,
  safeAIUsageCount,
} from "./aiUsageTelemetry";

initializeApp();
const db = getFirestore();

const openAIKey = defineSecret("OPENAI_API_KEY");
// The existing FatSecret proxy's base URL (e.g. http://<host>:8080). Stored as a secret so the
// IP/host stays out of source control and out of the shipped app binary.
const fatSecretProxyUrl = defineSecret("FATSECRET_PROXY_URL");

// --- Server-side guardrails ---------------------------------------------------
// The client used to be trusted to pick the model and token count, which meant a
// modified client (or a replayed auth token) could request an expensive model in a
// loop and drain the budget. The server maps a narrow request kind to a fixed model
// and separate quota; client-provided model names are never authoritative.
const MAX_OUTPUT_TOKENS = 6000; // 7-day meal plan legitimately requests ~5000; most calls ask far less.
const MAX_MESSAGES = 50;
const MAX_CONTENT_CHARS = 50000; // generous: long prompts include the daily context summary
const MAX_CONTENT_PARTS = 12; // vision messages send a few text / image_url parts
const MAX_IMAGE_DATA_URL_CHARS = 8_100_000; // just over the app's 6 MB JPEG ceiling after base64 encoding
const DAILY_CALL_LIMIT = 300; // AI calls, per user, per UTC day
const FATSECRET_DAILY_LIMIT = 600; // food lookups are cheap + frequent, but still bounded
const REFERENCE_FOOD_DAILY_LIMIT = 600;
const SUPPLEMENT_DAILY_LIMIT = 100;
const COMMUNITY_BARCODE_DAILY_LIMIT = 20;
const COMMUNITY_BARCODE_MAX_CONTRIBUTIONS = 250;
const ALLOWED_ROLES = new Set(["system", "user", "assistant"]);
const ALLOWED_FATSECRET_PARAMS = new Set(["query", "barcode", "food_id", "page", "max_results"]);
const MAX_PARAM_LENGTH = 200;
const AI_ROUTE_CONFIG_CACHE_MS = 60_000;

let cachedAIRouteConfiguration: {
  value: AIVisionRouteConfiguration;
  expiresAt: number;
} | undefined;

interface CommunityBarcodeConfig {
  acceptContributions: boolean;
  aggregationEnabled: boolean;
  killSwitch: boolean;
  minimumContributors: number;
  minimumAgreementRatio: number;
}

type CommunityBarcodeMetric =
  | "contributionsAccepted"
  | "aggregatePublished"
  | "aggregateInsufficient"
  | "aggregateConflict"
  | "aggregateQuarantined"
  | "aggregateDisabled";

/// Atomic per-user, per-day counter. Throws resource-exhausted when the limit is hit.
async function enforceDailyLimit(uid: string, collection: string, limit: number): Promise<void> {
  const day = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
  const ref = db.collection(collection).doc(`${uid}_${day}`);
  const withinLimit = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? (snap.data()?.count ?? 0) : 0;
    if (count >= limit) {
      return false;
    }
    tx.set(
      ref,
      { uid, day, count: count + 1, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    return true;
  });
  if (!withinLimit) {
    throw new HttpsError(
      "resource-exhausted",
      "Daily usage limit reached. Please try again tomorrow."
    );
  }
}

interface AIUsageResult {
  model: string;
  requestKind?: AIRequestKind;
  durationMs: number;
  succeeded: boolean;
  inputTokens?: number;
  outputTokens?: number;
  totalTokens?: number;
}

async function ensureAIRequestRouteEnabled(kind: AIRequestKind): Promise<void> {
  if (kind === "general") {
    return;
  }

  const now = Date.now();
  if (!cachedAIRouteConfiguration || cachedAIRouteConfiguration.expiresAt <= now) {
    try {
      const snapshot = await db.collection("internalConfig").doc("aiRoutes").get();
      const data = snapshot.data() ?? {};
      const value: AIVisionRouteConfiguration = {};
      for (const routeKind of [
        "meal_photo",
        "nutrition_label",
        "menu_photo",
        "receipt_photo",
        "recipe_photo",
      ] as const) {
        if (typeof data[routeKind] === "boolean") {
          value[routeKind] = data[routeKind];
        }
      }
      cachedAIRouteConfiguration = {
        value,
        expiresAt: now + AI_ROUTE_CONFIG_CACHE_MS,
      };
    } catch (error) {
      logger.warn("Could not refresh AI route configuration", {
        errorType: error instanceof Error ? error.name : "unknown",
      });
      cachedAIRouteConfiguration = {
        value: cachedAIRouteConfiguration?.value ?? {},
        expiresAt: now + AI_ROUTE_CONFIG_CACHE_MS,
      };
    }
  }

  if (!isAIRequestRouteEnabled(kind, cachedAIRouteConfiguration.value)) {
    throw new HttpsError(
      "failed-precondition",
      "This camera analysis route is temporarily unavailable."
    );
  }
}

/// Stores aggregate billing inputs without prompts, responses, or analytics identifiers.
/// Pricing is deliberately not hardcoded because provider rates can change independently
/// of an app release; the dashboard applies the current invoice rate to these token totals.
async function recordAIUsageResult(uid: string, result: AIUsageResult): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const ref = db.collection("aiUsage").doc(`${uid}_${day}`);
  const requestKind = result.requestKind ?? "general";
  const requestPrefix = aiUsageRequestPrefix(requestKind);
  const inputTokens = safeAIUsageCount(result.inputTokens);
  const outputTokens = safeAIUsageCount(result.outputTokens);
  const totalTokens = safeAIUsageCount(result.totalTokens);
  const latencyMs = safeAIUsageCount(result.durationMs);
  const data: Record<string, unknown> = {
    uid,
    day,
    usageSchema: 3,
    successfulCount: FieldValue.increment(result.succeeded ? 1 : 0),
    failedCount: FieldValue.increment(result.succeeded ? 0 : 1),
    inputTokens: FieldValue.increment(inputTokens),
    outputTokens: FieldValue.increment(outputTokens),
    totalTokens: FieldValue.increment(totalTokens),
    totalLatencyMs: FieldValue.increment(latencyMs),
    [`${requestPrefix}SuccessfulCount`]: FieldValue.increment(result.succeeded ? 1 : 0),
    [`${requestPrefix}FailedCount`]: FieldValue.increment(result.succeeded ? 0 : 1),
    [`${requestPrefix}InputTokens`]: FieldValue.increment(inputTokens),
    [`${requestPrefix}OutputTokens`]: FieldValue.increment(outputTokens),
    [`${requestPrefix}TotalTokens`]: FieldValue.increment(totalTokens),
    [`${requestPrefix}TotalLatencyMs`]: FieldValue.increment(latencyMs),
    lastLatencyMs: latencyMs,
    lastModel: result.model,
    lastRequestKind: requestKind,
    lastOutcome: result.succeeded ? "success" : "failure",
    updatedAt: FieldValue.serverTimestamp(),
  };
  const breakdownID = aiUsageBreakdownDocumentID(uid, day, requestKind, result.model);
  const breakdownRef = db.collection("aiUsageBreakdown").doc(breakdownID);
  const breakdownData: Record<string, unknown> = {
    uid,
    day,
    usageSchema: 1,
    requestKind,
    model: result.model,
    successfulCount: FieldValue.increment(result.succeeded ? 1 : 0),
    failedCount: FieldValue.increment(result.succeeded ? 0 : 1),
    inputTokens: FieldValue.increment(inputTokens),
    outputTokens: FieldValue.increment(outputTokens),
    totalTokens: FieldValue.increment(totalTokens),
    totalLatencyMs: FieldValue.increment(latencyMs),
    lastLatencyMs: latencyMs,
    lastOutcome: result.succeeded ? "success" : "failure",
    updatedAt: FieldValue.serverTimestamp(),
  };

  try {
    const batch = db.batch();
    batch.set(ref, data, { merge: true });
    batch.set(breakdownRef, breakdownData, { merge: true });
    await batch.commit();
  } catch (error) {
    // Telemetry must never turn a successful model response into a user-visible failure.
    logger.warn("Could not persist aggregate AI usage telemetry", {
      errorType: error instanceof Error ? error.name : "unknown",
    });
  }
}

/// Validates the chat payload shape without rejecting legitimate vision messages, whose
/// `content` is an array of text / image_url parts rather than a plain string.
function validateMessages(messages: unknown): void {
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new HttpsError("invalid-argument", "Request must include a non-empty 'messages' array.");
  }
  if (messages.length > MAX_MESSAGES) {
    throw new HttpsError("invalid-argument", "Too many messages in a single request.");
  }
  for (const message of messages as any[]) {
    if (typeof message !== "object" || message === null) {
      throw new HttpsError("invalid-argument", "Each message must be an object.");
    }
    if (!ALLOWED_ROLES.has(message.role)) {
      throw new HttpsError("invalid-argument", "Unsupported message role.");
    }
    if (typeof message.content === "string") {
      if (message.content.length > MAX_CONTENT_CHARS) {
        throw new HttpsError("invalid-argument", "Message content is too long.");
      }
    } else if (Array.isArray(message.content)) {
      if (message.content.length > MAX_CONTENT_PARTS) {
        throw new HttpsError("invalid-argument", "Too many content parts in a message.");
      }
      for (const part of message.content) {
        if (typeof part !== "object" || part === null || typeof part.type !== "string") {
          throw new HttpsError("invalid-argument", "Invalid message content part.");
        }
        if (part.type === "text") {
          if (typeof part.text !== "string" || part.text.length > MAX_CONTENT_CHARS) {
            throw new HttpsError("invalid-argument", "Invalid text content part.");
          }
          continue;
        }
        if (part.type === "image_url") {
          const image = part.image_url;
          const url = typeof image === "object" && image !== null ? image.url : undefined;
          const detail = typeof image === "object" && image !== null ? image.detail : undefined;
          if (typeof url !== "string"
            || !url.startsWith("data:image/jpeg;base64,")
            || url.length > MAX_IMAGE_DATA_URL_CHARS) {
            throw new HttpsError("invalid-argument", "Image must be a bounded JPEG data URL.");
          }
          if (detail !== undefined
            && !["auto", "low", "high", "original"].includes(detail)) {
            throw new HttpsError("invalid-argument", "Unsupported image detail setting.");
          }
          continue;
        }
        throw new HttpsError("invalid-argument", "Unsupported message content part type.");
      }
    } else {
      throw new HttpsError("invalid-argument", "Message content must be text or content parts.");
    }
  }
}

async function loadCommunityBarcodeConfig(): Promise<CommunityBarcodeConfig> {
  const snapshot = await db.collection("internalConfig").doc("communityBarcodeAggregation").get();
  const data = snapshot.data() ?? {};
  const configuredMinimum = finiteNumber(data.minimumContributors) ?? 3;
  const configuredRatio = finiteNumber(data.minimumAgreementRatio) ?? (2 / 3);
  return {
    acceptContributions: data.acceptContributions === true,
    aggregationEnabled: data.aggregationEnabled === true,
    killSwitch: data.killSwitch === true,
    minimumContributors: Math.min(Math.max(Math.floor(configuredMinimum), 3), 20),
    minimumAgreementRatio: Math.min(Math.max(configuredRatio, 2 / 3), 1),
  };
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function validatedLookupText(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `A ${field} is required.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < 2 || trimmed.length > 120) {
    throw new HttpsError(
      "invalid-argument",
      `${field[0].toUpperCase()}${field.slice(1)} must be between 2 and 120 characters.`
    );
  }
  return trimmed;
}

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.min(Math.max(Math.floor(value), minimum), maximum);
}

async function recordCommunityBarcodeMetric(metric: CommunityBarcodeMetric): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  try {
    await db.collection("communityBarcodeMetrics").doc(day).set({
      schemaVersion: 1,
      [metric]: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    logger.warn("Could not persist community barcode metric", {
      metric,
      errorType: error instanceof Error ? error.name : "unknown",
    });
  }
}

function contributionPayload(data: FirebaseFirestore.DocumentData): Record<string, unknown> {
  return {
    barcode: data.barcode,
    name: data.name,
    calories: data.calories,
    protein: data.protein,
    carbs: data.carbs,
    fats: data.fats,
    ...(data.fiber === undefined ? {} : { fiber: data.fiber }),
    servingSize: data.servingSize,
    servingWeight: data.servingWeight,
  };
}

async function rebuildCommunityBarcodeAggregate(
  rawBarcode: string,
  eventDate: Date
): Promise<void> {
  const barcode = normalizeBarcode(rawBarcode);
  if (!isValidGTIN(barcode)) {
    return;
  }

  const [config, quarantineSnapshot] = await Promise.all([
    loadCommunityBarcodeConfig(),
    db.collection("communityBarcodeQuarantine").doc(barcode).get(),
  ]);
  const isQuarantined = quarantineSnapshot.data()?.blocked === true;
  let evaluation: CommunityBarcodeAggregationResult | undefined;
  let forcedStatus: "disabled" | "quarantined" | undefined;

  if (config.killSwitch || !config.aggregationEnabled) {
    forcedStatus = "disabled";
  } else if (isQuarantined) {
    forcedStatus = "quarantined";
  } else {
    const snapshot = await db.collectionGroup("barcodeContributions")
      .where("barcode", "==", barcode)
      .limit(COMMUNITY_BARCODE_MAX_CONTRIBUTIONS + 1)
      .get();
    if (snapshot.size > COMMUNITY_BARCODE_MAX_CONTRIBUTIONS) {
      evaluation = {
        status: "conflict",
        contributorCount: snapshot.size,
        agreementCount: 0,
        rejectedCount: 0,
        reason: "contribution_volume_limit",
      };
    }
    const contributions: CommunityBarcodeContribution[] = [];
    let rejectedDocumentCount = 0;
    for (const document of evaluation === undefined ? snapshot.docs : []) {
      const contributorKey = document.ref.parent.parent?.id ?? "";
      const parsed = parseCommunityBarcodeContribution(
        contributionPayload(document.data()),
        contributorKey
      );
      if (parsed.ok) {
        contributions.push(parsed.contribution);
      } else {
        rejectedDocumentCount += 1;
      }
    }
    if (evaluation === undefined) {
      evaluation = buildCommunityBarcodeAggregate(
        contributions,
        config.minimumContributors,
        config.minimumAgreementRatio
      );
    }
    if (rejectedDocumentCount > 0) {
      evaluation = {
        ...evaluation,
        rejectedCount: evaluation.rejectedCount + rejectedDocumentCount,
      };
    }
  }

  const aggregateRef = db.collection("communityBarcodeAggregates").doc(barcode);
  const reviewRef = db.collection("communityBarcodeReviews").doc(barcode);
  const eventTimestamp = Timestamp.fromDate(eventDate);
  const applied = await db.runTransaction(async (transaction) => {
    const reviewSnapshot = await transaction.get(reviewRef);
    const lastEventAt = reviewSnapshot.data()?.lastEventAt;
    if (lastEventAt instanceof Timestamp && lastEventAt.toMillis() > eventTimestamp.toMillis()) {
      return false;
    }
    const aggregateSnapshot = await transaction.get(aggregateRef);
    const revision = (finiteNumber(aggregateSnapshot.data()?.revision) ?? 0) + 1;

    if (forcedStatus !== undefined) {
      transaction.delete(aggregateRef);
      transaction.set(reviewRef, {
        schemaVersion: 1,
        modelVersion: COMMUNITY_BARCODE_MODEL_VERSION,
        barcode,
        status: forcedStatus,
        contributorCount: 0,
        agreementCount: 0,
        rejectedCount: 0,
        lastEventAt: eventTimestamp,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    }

    if (evaluation?.status === "published") {
      transaction.set(aggregateRef, {
        ...evaluation.aggregate,
        revision,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(reviewRef, {
        schemaVersion: 1,
        modelVersion: COMMUNITY_BARCODE_MODEL_VERSION,
        barcode,
        status: "published",
        contributorCount: evaluation.aggregate.contributorCount,
        agreementCount: evaluation.aggregate.agreementCount,
        conflictCount: evaluation.aggregate.conflictCount,
        rejectedCount: evaluation.rejectedCount,
        lastAggregate: evaluation.aggregate,
        lastEventAt: eventTimestamp,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    }

    transaction.delete(aggregateRef);
    transaction.set(reviewRef, {
      schemaVersion: 1,
      modelVersion: COMMUNITY_BARCODE_MODEL_VERSION,
      barcode,
      status: evaluation?.status ?? "insufficient",
      contributorCount: evaluation?.contributorCount ?? 0,
      agreementCount: evaluation?.agreementCount ?? 0,
      rejectedCount: evaluation?.rejectedCount ?? 0,
      reason: evaluation?.reason ?? "no_eligible_contributions",
      lastEventAt: eventTimestamp,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (!applied) {
    return;
  }
  if (forcedStatus === "quarantined") {
    await recordCommunityBarcodeMetric("aggregateQuarantined");
  } else if (forcedStatus === "disabled") {
    await recordCommunityBarcodeMetric("aggregateDisabled");
  } else if (evaluation?.status === "published") {
    await recordCommunityBarcodeMetric("aggregatePublished");
  } else if (evaluation?.status === "conflict") {
    await recordCommunityBarcodeMetric("aggregateConflict");
  } else {
    await recordCommunityBarcodeMetric("aggregateInsufficient");
  }
}

export const generateAIResponse = onCall(
  {
    secrets: [openAIKey],
    // Client App Check is enabled in 2.2. Keep enforcement off only until Firebase metrics
    // confirm older non-App-Check builds no longer represent meaningful active traffic.
    // enforceAppCheck: true,
  },
  async (request) => {
    // 1. Require authentication
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "The function must be called while authenticated."
      );
    }
    const uid = request.auth.uid;

    // 2. Validate the payload BEFORE counting usage, so a malformed request can't burn quota.
    const data = request.data ?? {};
    const { messages, maxTokens, temperature, responseFormat, requestKind } = data;
    validateMessages(messages);
    const route = resolveAIRequestRoute(requestKind);
    await ensureAIRequestRouteEnabled(route.kind);

    // 3. Per-user daily rate limit (atomic counter via Admin SDK), only for valid requests.
    await enforceDailyLimit(uid, "aiUsage", DAILY_CALL_LIMIT);
    if (route.usageCollection && route.dailyLimit) {
      await enforceDailyLimit(uid, route.usageCollection, route.dailyLimit);
    }

    // 4. Clamp model / tokens / temperature to safe server-side values. The request kind,
    // not a model string supplied by the app, determines any higher-cost route.
    const safeModel = route.model;
    const safeMaxTokens = Math.min(
      typeof maxTokens === "number" && maxTokens > 0
        ? maxTokens
        : route.maxOutputTokens,
      route.maxOutputTokens,
      MAX_OUTPUT_TOKENS
    );
    const safeTemperature =
      typeof temperature === "number" && temperature >= 0 && temperature <= 2
        ? temperature
        : 0.7;

    // 5. Higher-trust camera routes use a server-owned schema. General calls may request only
    // the legacy JSON-object mode; arbitrary client schemas are never passed through.
    const safeResponseFormat = route.forcedResponseFormat ?? (
      responseFormat && responseFormat.type === "json_object"
        ? { type: "json_object" as const }
        : undefined
    );

    const requestStartedAt = Date.now();
    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      const params: any = {
        model: safeModel,
        messages: messages,
        safety_identifier: createHash("sha256").update(uid).digest("hex"),
      };
      if (isReasoningRoute(route)) {
        params.max_completion_tokens = safeMaxTokens;
        params.reasoning_effort = route.reasoningEffort ?? "none";
      } else {
        params.temperature = safeTemperature;
        params.max_tokens = safeMaxTokens;
      }
      if (safeResponseFormat) {
        params.response_format = safeResponseFormat;
      }

      const completion = await openai.chat.completions.create(params);

      await recordAIUsageResult(uid, {
        model: safeModel,
        requestKind: route.kind,
        durationMs: Date.now() - requestStartedAt,
        succeeded: true,
        inputTokens: completion.usage?.prompt_tokens,
        outputTokens: completion.usage?.completion_tokens,
        totalTokens: completion.usage?.total_tokens,
      });

      return {
        content: completion.choices[0]?.message?.content || "",
      };
    } catch (error: any) {
      const durationMs = Date.now() - requestStartedAt;
      await recordAIUsageResult(uid, {
        model: safeModel,
        requestKind: route.kind,
        durationMs,
        succeeded: false,
      });
      logger.error("OpenAI request failed", {
        model: safeModel,
        requestKind: route.kind,
        durationMs,
        errorType: error instanceof Error ? error.name : "unknown",
        status: typeof error?.status === "number" ? error.status : undefined,
      });
      throw new HttpsError(
        "internal",
        "An error occurred while generating the AI response."
      );
    }
  }
);

// HTTPS wrapper around the existing FatSecret proxy so the iOS app never speaks plaintext HTTP.
// App -> (HTTPS) this function -> (server-side) existing proxy -> FatSecret. The proxy is untouched.
export const fatSecretProxy = onCall(
  {
    secrets: [fatSecretProxyUrl],
    // enforceAppCheck: true, // flip together with generateAIResponse after the metrics check
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;

    const { path, params } = request.data || {};
    const allowedPaths = new Set(["search", "barcode", "food"]);
    if (typeof path !== "string" || !allowedPaths.has(path)) {
      throw new HttpsError("invalid-argument", "Unsupported lookup path.");
    }

    // Validate params against an allowlist with length caps before building the URL.
    const base = fatSecretProxyUrl.value().replace(/\/+$/, "");
    const url = new URL(`${base}/${path}`);
    if (params && typeof params === "object") {
      for (const [key, value] of Object.entries(params)) {
        if (!ALLOWED_FATSECRET_PARAMS.has(key)) {
          throw new HttpsError("invalid-argument", "Unsupported lookup parameter.");
        }
        const stringValue = String(value);
        if (stringValue.length > MAX_PARAM_LENGTH) {
          throw new HttpsError("invalid-argument", "Lookup parameter is too long.");
        }
        url.searchParams.set(key, stringValue);
      }
    }

    // Per-user daily rate limit for food lookups (after validation).
    await enforceDailyLimit(uid, "fatSecretUsage", FATSECRET_DAILY_LIMIT);

    try {
      const response = await fetch(url.toString());
      if (!response.ok) {
        throw new HttpsError("internal", `Food provider returned ${response.status}.`);
      }
      return await response.json();
    } catch (error: any) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("fatSecretProxy error:", error);
      throw new HttpsError("internal", "Food lookup failed.");
    }
  }
);

// Health Canada's current CNF release is distributed as relational CSV files rather than a
// production search API. MyFitPlate compiles the supported nutrients into a compact immutable
// asset and searches it here so neither the iPhone nor Watch bundle carries the full dataset.
export const healthCanadaFoodSearch = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const query = validatedLookupText(request.data?.query, "query");
  const limit = boundedInteger(request.data?.limit, 12, 1, 20);
  await enforceDailyLimit(
    request.auth.uid,
    "referenceFoodUsage",
    REFERENCE_FOOD_DAILY_LIMIT
  );

  try {
    return searchCanadianNutrientFile(loadCanadianNutrientDataset(), query, limit);
  } catch (error) {
    logger.error("healthCanadaFoodSearch error", {
      errorType: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("internal", "Canadian food reference search failed.");
  }
});

// NIH DSLD is a supplement-label repository, not an analytical food-composition database.
// Keep it behind a separate callable and response model so the client can present supplements
// as label evidence instead of silently mixing them into ordinary food matches.
export const nihSupplementSearch = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const query = validatedLookupText(request.data?.query, "query");
  const limit = boundedInteger(request.data?.limit, 6, 1, 8);
  await enforceDailyLimit(
    request.auth.uid,
    "supplementLookupUsage",
    SUPPLEMENT_DAILY_LIMIT
  );

  try {
    return await searchDietarySupplements(query, limit);
  } catch (error) {
    logger.warn("nihSupplementSearch error", {
      errorType: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("unavailable", "Supplement label search is temporarily unavailable.");
  }
});

export const nihSupplementBarcodeLookup = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const barcode = validatedLookupText(request.data?.barcode, "barcode");
  if (!/^\d{8,14}$/.test(barcode)) {
    throw new HttpsError("invalid-argument", "A valid numeric barcode is required.");
  }
  await enforceDailyLimit(
    request.auth.uid,
    "supplementLookupUsage",
    SUPPLEMENT_DAILY_LIMIT
  );

  try {
    return await lookupDietarySupplementBarcode(barcode) ?? null;
  } catch (error) {
    logger.warn("nihSupplementBarcodeLookup error", {
      errorType: error instanceof Error ? error.name : "unknown",
    });
    throw new HttpsError("unavailable", "Supplement label lookup is temporarily unavailable.");
  }
});

// Community submissions are private server-owned documents. The callable is dormant unless the
// private Firestore config explicitly accepts contributions, and App Check is mandatory because
// no published client before replacement 2.2 build 2 needs this endpoint.
export const submitCommunityBarcodeContribution = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const config = await loadCommunityBarcodeConfig();
    if (config.killSwitch || !config.acceptContributions) {
      throw new HttpsError("failed-precondition", "Community corrections are not accepting submissions.");
    }

    const parsed = parseCommunityBarcodeContribution(request.data, request.auth.uid);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", `Contribution rejected: ${parsed.reason}.`);
    }

    await enforceDailyLimit(
      request.auth.uid,
      "communityBarcodeUsage",
      COMMUNITY_BARCODE_DAILY_LIMIT
    );
    const contribution = parsed.contribution;
    const privateRef = db.collection("users")
      .doc(request.auth.uid)
      .collection("barcodeContributions")
      .doc(contribution.barcode);
    await privateRef.set({
      schemaVersion: 1,
      barcode: contribution.barcode,
      name: contribution.name,
      calories: contribution.calories,
      protein: contribution.protein,
      carbs: contribution.carbs,
      fats: contribution.fats,
      ...(contribution.fiber === undefined ? {} : { fiber: contribution.fiber }),
      servingSize: contribution.servingSize,
      servingWeight: contribution.servingWeight,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await recordCommunityBarcodeMetric("contributionsAccepted");
    return { accepted: true };
  }
);

// Every private contribution update/delete rebuilds the one aggregate for that barcode. Event
// timestamps make an older delayed trigger unable to overwrite a newer result.
export const aggregateCommunityBarcodeContribution = onDocumentWritten(
  "users/{userId}/barcodeContributions/{barcode}",
  async (event) => {
    await rebuildCommunityBarcodeAggregate(
      event.params.barcode,
      safeEventDate(event.time)
    );
  }
);

// An operator can quarantine or release a barcode from the Firebase console. A blocked document
// immediately deletes the published aggregate; removing the block recomputes from private data.
export const moderateCommunityBarcodeAggregate = onDocumentWritten(
  "communityBarcodeQuarantine/{barcode}",
  async (event) => {
    await rebuildCommunityBarcodeAggregate(
      event.params.barcode,
      safeEventDate(event.time)
    );
  }
);

// Rules deny reads as soon as the operator disables aggregation or raises the kill switch.
// Removing the materialized documents as well prevents stale consensus from reappearing if the
// feature is later re-enabled. Rebuilding is deliberately explicit through fresh contributions
// or the migration/runbook rather than automatic after an emergency rollback.
export const invalidateCommunityBarcodeAggregates = onDocumentWritten(
  "internalConfig/communityBarcodeAggregation",
  async (event) => {
    const config = event.data?.after.data();
    const shouldInvalidate = config === undefined ||
      config.killSwitch === true ||
      config.aggregationEnabled !== true;
    if (!shouldInvalidate) {
      return;
    }

    await db.recursiveDelete(db.collection("communityBarcodeAggregates"));
    await recordCommunityBarcodeMetric("aggregateDisabled");
    logger.warn("Community barcode aggregates invalidated by private operator config", {
      reason: config === undefined
        ? "config_deleted"
        : config.killSwitch === true
          ? "kill_switch"
          : "aggregation_disabled",
    });
  }
);

function safeEventDate(value: string | undefined): Date {
  const date = value === undefined ? new Date() : new Date(value);
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

// Server-owned account deletion. Uses the Admin SDK to remove everything tied to the user —
// including backend-only usage counters the client can't reach under the security rules — so
// deletion matches the privacy policy's "all associated data."
export const deleteUserData = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const uid = request.auth.uid;

  const deleteQueryResults = async (query: FirebaseFirestore.Query): Promise<void> => {
    const snapshot = await query.get();
    for (const document of snapshot.docs) {
      await db.recursiveDelete(document.ref);
    }
  };

  // Remove top-level social/community records tied to the account. For groups the user owns,
  // also remove memberships that would otherwise point at a deleted group.
  const ownedGroups = await db.collection("groups").where("creatorID", "==", uid).get();
  const ownedGroupsLegacy = await db.collection("groups").where("creatorId", "==", uid).get();
  const groupIDs = new Set([...ownedGroups.docs, ...ownedGroupsLegacy.docs].map((doc) => doc.id));
  for (const groupID of groupIDs) {
    await deleteQueryResults(db.collection("groupMemberships").where("groupID", "==", groupID));
    await deleteQueryResults(db.collection("groupMemberships").where("groupId", "==", groupID));
    await db.recursiveDelete(db.collection("groups").doc(groupID));
  }

  const ownedQueries = [
    db.collection("posts").where("authorID", "==", uid),
    db.collection("posts").where("authorId", "==", uid),
    db.collection("groupMemberships").where("userID", "==", uid),
    db.collection("groupMemberships").where("userId", "==", uid),
    db.collection("barcodes").where("createdBy", "==", uid),
  ];
  for (const query of ownedQueries) {
    await deleteQueryResults(query);
  }

  // Recursively delete the user's document and every subcollection (logs, weight history,
  // recent/custom foods, recipes, pantry, meal plans, workouts, etc.).
  await db.recursiveDelete(db.collection("users").doc(uid));

  // Delete the per-user usage counters stored in top-level collections.
  const usageCollections = [
    "aiUsage",
    "aiUsageBreakdown",
    "aiVisionUsage",
    "fatSecretUsage",
    "referenceFoodUsage",
    "supplementLookupUsage",
    "communityBarcodeUsage",
  ];
  for (const collection of usageCollections) {
    const snapshot = await db.collection(collection).where("uid", "==", uid).get();
    if (snapshot.empty) {
      continue;
    }
    // Long-lived accounts can exceed Firestore's 500-operation batch ceiling, especially when
    // one workflow/model aggregate is retained per day. Keep deletion bounded and retryable.
    for (let index = 0; index < snapshot.docs.length; index += 450) {
      const batch = db.batch();
      snapshot.docs.slice(index, index + 450).forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
  }

  // Delete the login record last. If any prior deletion fails, the account remains available
  // so the user can retry instead of receiving a false-success state with orphaned data.
  await getAuth().deleteUser(uid);

  return { deleted: true };
});
