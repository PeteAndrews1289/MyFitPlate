import { HttpsError } from "firebase-functions/v2/https";

export function requireRecentAuthentication(authTime: unknown, now = Date.now()): void {
  const seconds = now / 1000;
  if (typeof authTime !== "number" || !Number.isFinite(authTime) ||
      authTime > seconds + 30 || seconds - authTime > 5 * 60) {
    throw new HttpsError("failed-precondition", "Sign in again before deleting your account.");
  }
}

// A conservative byte allowance, not a tokenizer estimate. Reserving bytes as tokens bounds
// multilingual input as well. Images get a separate fixed allowance and count ceiling.
export function aiInputAllowance(messages: any[]): number {
  let bytes = 0;
  let images = 0;
  for (const message of messages) {
    if (typeof message.content === "string") bytes += Buffer.byteLength(message.content, "utf8");
    else for (const part of message.content) {
      if (part.type === "text") bytes += Buffer.byteLength(part.text, "utf8");
      else if (part.type === "image_url") images += 1;
    }
  }
  if (bytes > 100_000 || images > 2) {
    throw new HttpsError("invalid-argument", "This request is too large. Shorten the conversation or send fewer photos.");
  }
  return bytes + images * 16_000;
}

export function aiBudgetLimit(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : fallback;
}
