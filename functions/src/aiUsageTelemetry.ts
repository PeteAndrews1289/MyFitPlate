import { createHash } from "node:crypto";
import { AIRequestKind } from "./aiRequestRouting";

export const ACCOUNT_DELETION_USAGE_COLLECTIONS = [
  "aiUsage",
  "aiUsageBreakdown",
  "aiVisionUsage",
  "fatSecretUsage",
  "referenceFoodUsage",
  "supplementLookupUsage",
  "maiaSpeechUsage",
  "communityBarcodeUsage",
] as const;

export function aiUsageRequestPrefix(kind: AIRequestKind): string {
  switch (kind) {
    case "meal_photo": return "mealPhoto";
    case "nutrition_label": return "nutritionLabel";
    case "menu_photo": return "menuPhoto";
    case "receipt_photo": return "receiptPhoto";
    case "recipe_photo": return "recipePhoto";
    case "general": return "general";
  }
}

export function safeAIUsageCount(value: number | undefined): number {
  return Math.max(
    0,
    Math.round(typeof value === "number" && Number.isFinite(value) ? value : 0)
  );
}

export function aiUsageBreakdownDocumentID(
  uid: string,
  day: string,
  requestKind: AIRequestKind,
  model: string
): string {
  return createHash("sha256")
    .update([uid, day, requestKind, model].join("\u001f"))
    .digest("hex");
}
