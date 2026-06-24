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
// modified client (or a replayed auth token) could request an expensive model in
// a loop and drain the OpenAI budget. These limits are now enforced here so the
// client can never escalate cost regardless of what it sends.
const ALLOWED_MODELS = new Set(["gpt-4o-mini"]);
const DEFAULT_MODEL = "gpt-4o-mini";
const MAX_OUTPUT_TOKENS = 6000; // 7-day meal plan legitimately requests ~5000; most calls ask far less. The per-user daily call limit still bounds total cost.
const MAX_MESSAGES = 50;
const DAILY_CALL_LIMIT = 300; // per user, per UTC day

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

    // 2. Per-user daily rate limit (atomic counter in Firestore via Admin SDK)
    const day = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
    const counterRef = db.collection("aiUsage").doc(`${uid}_${day}`);
    const withinLimit = await db.runTransaction(async (tx) => {
      const snap = await tx.get(counterRef);
      const count = snap.exists ? (snap.data()?.count ?? 0) : 0;
      if (count >= DAILY_CALL_LIMIT) {
        return false;
      }
      tx.set(
        counterRef,
        { uid, day, count: count + 1, updatedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      return true;
    });
    if (!withinLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Daily AI usage limit reached. Please try again tomorrow."
      );
    }

    // 3. Validate input
    const data = request.data;
    const { messages, model, maxTokens, temperature, responseFormat } = data;

    if (!messages || !Array.isArray(messages)) {
      throw new HttpsError(
        "invalid-argument",
        "The function must be called with an array of 'messages'."
      );
    }
    if (messages.length > MAX_MESSAGES) {
      throw new HttpsError(
        "invalid-argument",
        "Too many messages in a single request."
      );
    }

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

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      const params: any = {
        model: safeModel,
        messages: messages,
        temperature: safeTemperature,
        max_tokens: safeMaxTokens,
      };
      if (responseFormat) {
        params.response_format = responseFormat;
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

    const { path, params } = request.data || {};
    const allowedPaths = new Set(["search", "barcode", "food"]);
    if (typeof path !== "string" || !allowedPaths.has(path)) {
      throw new HttpsError("invalid-argument", "Unsupported lookup path.");
    }

    const base = fatSecretProxyUrl.value().replace(/\/+$/, "");
    const url = new URL(`${base}/${path}`);
    if (params && typeof params === "object") {
      for (const [key, value] of Object.entries(params)) {
        url.searchParams.set(key, String(value));
      }
    }

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
