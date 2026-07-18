const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCOUNT_DELETION_USAGE_COLLECTIONS,
  aiUsageBreakdownDocumentID,
  aiUsageRequestPrefix,
  safeAIUsageCount,
} = require("../lib/aiUsageTelemetry.js");

test("account deletion covers every top-level usage collection", () => {
  assert.deepEqual(ACCOUNT_DELETION_USAGE_COLLECTIONS, [
    "aiUsage",
    "aiUsageBreakdown",
    "aiVisionUsage",
    "fatSecretUsage",
    "referenceFoodUsage",
    "supplementLookupUsage",
    "maiaSpeechUsage",
    "communityBarcodeUsage",
  ]);
});

test("AI usage prefixes remain stable for every request kind", () => {
  assert.equal(aiUsageRequestPrefix("general"), "general");
  assert.equal(aiUsageRequestPrefix("meal_photo"), "mealPhoto");
  assert.equal(aiUsageRequestPrefix("nutrition_label"), "nutritionLabel");
  assert.equal(aiUsageRequestPrefix("menu_photo"), "menuPhoto");
  assert.equal(aiUsageRequestPrefix("receipt_photo"), "receiptPhoto");
  assert.equal(aiUsageRequestPrefix("recipe_photo"), "recipePhoto");
});

test("AI usage counts clamp invalid values and round finite values", () => {
  assert.equal(safeAIUsageCount(undefined), 0);
  assert.equal(safeAIUsageCount(Number.NaN), 0);
  assert.equal(safeAIUsageCount(Number.POSITIVE_INFINITY), 0);
  assert.equal(safeAIUsageCount(-10), 0);
  assert.equal(safeAIUsageCount(10.6), 11);
});

test("AI usage breakdown identities are stable and isolate model changes", () => {
  const first = aiUsageBreakdownDocumentID(
    "user-1",
    "2026-07-15",
    "meal_photo",
    "gpt-5.6-terra"
  );
  const repeat = aiUsageBreakdownDocumentID(
    "user-1",
    "2026-07-15",
    "meal_photo",
    "gpt-5.6-terra"
  );
  const otherModel = aiUsageBreakdownDocumentID(
    "user-1",
    "2026-07-15",
    "meal_photo",
    "gpt-5.6-luna"
  );
  const otherRoute = aiUsageBreakdownDocumentID(
    "user-1",
    "2026-07-15",
    "menu_photo",
    "gpt-5.6-terra"
  );

  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(first, repeat);
  assert.notEqual(first, otherModel);
  assert.notEqual(first, otherRoute);
});
