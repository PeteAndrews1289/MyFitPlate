import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import OpenAI from "openai";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

const openAIKey = defineSecret("OPENAI_API_KEY");
// The existing FatSecret proxy's base URL (e.g. http://<host>:8080). Stored as a secret so the
// IP/host stays out of source control and out of the shipped app binary.
const fatSecretProxyUrl = defineSecret("FATSECRET_PROXY_URL");

// --- Server-side guardrails ---------------------------------------------------
// The client used to be trusted to pick the model and token count, which meant a
// modified client (or a replayed auth token) could request an expensive model in a
// loop and drain the budget. These limits are enforced here so the client can never
// escalate cost or send abusive payloads regardless of what it sends.
const ALLOWED_MODELS = new Set(["gpt-4o-mini"]);
const DEFAULT_MODEL = "gpt-4o-mini";
const MAX_OUTPUT_TOKENS = 6000; // 7-day meal plan legitimately requests ~5000; most calls ask far less.
const MAX_MESSAGES = 50;
const MAX_CONTENT_CHARS = 50000; // generous: long prompts include the daily context summary
const MAX_CONTENT_PARTS = 12; // vision messages send a few text / image_url parts
const DAILY_CALL_LIMIT = 300; // AI calls, per user, per UTC day
const FATSECRET_DAILY_LIMIT = 600; // food lookups are cheap + frequent, but still bounded
const ALLOWED_ROLES = new Set(["system", "user", "assistant"]);
const ALLOWED_FATSECRET_PARAMS = new Set(["query", "barcode", "food_id", "page", "max_results"]);
const MAX_PARAM_LENGTH = 200;

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
      }
    } else {
      throw new HttpsError("invalid-argument", "Message content must be text or content parts.");
    }
  }
}

export const generateAIResponse = onCall(
  {
    secrets: [openAIKey],
    // NOTE: App Check enforcement is intentionally left OFF. 2.0 ships the App Check
    // SDK and the debug token is registered, BUT the live 1.x build has NO App Check —
    // enforcing now would 403 every existing user. Flip this to `true` only once 2.0 is
    // the dominant installed version (watch the App Check "APIs" metrics drop to mostly
    // verified), and enforce Firestore/Auth in the console at the same time.
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
    const data = request.data;
    const { messages, model, maxTokens, temperature, responseFormat } = data;
    validateMessages(messages);

    // 3. Per-user daily rate limit (atomic counter via Admin SDK), only for valid requests.
    await enforceDailyLimit(uid, "aiUsage", DAILY_CALL_LIMIT);

    // 4. Clamp model / tokens / temperature to safe server-side values
    const safeModel =
      typeof model === "string" && ALLOWED_MODELS.has(model)
        ? model
        : DEFAULT_MODEL;
    const safeMaxTokens = Math.min(
      typeof maxTokens === "number" && maxTokens > 0
        ? maxTokens
        : MAX_OUTPUT_TOKENS,
      MAX_OUTPUT_TOKENS
    );
    const safeTemperature =
      typeof temperature === "number" && temperature >= 0 && temperature <= 2
        ? temperature
        : 0.7;

    // 5. Only allow the JSON-object response format (or none) — never pass an arbitrary one through.
    const safeResponseFormat =
      responseFormat && responseFormat.type === "json_object"
        ? { type: "json_object" as const }
        : undefined;

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      const params: any = {
        model: safeModel,
        messages: messages,
        temperature: safeTemperature,
        max_tokens: safeMaxTokens,
      };
      if (safeResponseFormat) {
        params.response_format = safeResponseFormat;
      }

      const completion = await openai.chat.completions.create(params);

      return {
        content: completion.choices[0]?.message?.content || "",
      };
    } catch (error: any) {
      logger.error("Error calling OpenAI:", error);
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
    // enforceAppCheck: true, // flip together with generateAIResponse once 2.0 is dominant
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

// Server-owned account deletion. Uses the Admin SDK to remove everything tied to the user —
// including backend-only metadata (the aiUsage / fatSecretUsage counters) the client can't reach
// under the security rules — so deletion matches the privacy policy's "all associated data."
export const deleteUserData = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const uid = request.auth.uid;

  // Recursively delete the user's document and every subcollection (logs, weight history,
  // recent/custom foods, recipes, pantry, etc.).
  await db.recursiveDelete(db.collection("users").doc(uid));

  // Delete the per-user usage counters stored in top-level collections.
  for (const collection of ["aiUsage", "fatSecretUsage"]) {
    const snapshot = await db.collection(collection).where("uid", "==", uid).get();
    if (snapshot.empty) {
      continue;
    }
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  return { deleted: true };
});
