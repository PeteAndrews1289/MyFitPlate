const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isAIModelAvailabilityError,
  isAIRequestRouteEnabled,
  isReasoningModel,
  isReasoningRoute,
  normalizeAIRequestKind,
  resolveAIRequestModels,
  resolveAIRequestRoute,
} = require("../lib/aiRequestRouting.js");

function assertStrictObjectContracts(schema) {
  if (!schema || typeof schema !== "object") return;

  if (schema.type === "object") {
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(
      [...schema.required].sort(),
      Object.keys(schema.properties).sort()
    );
    Object.values(schema.properties).forEach(assertStrictObjectContracts);
  }

  if (schema.type === "array") {
    assertStrictObjectContracts(schema.items);
  }
}

test("vision routes can be disabled independently without affecting general Maia", () => {
  const config = {
    meal_photo: false,
    nutrition_label: true,
    receipt_photo: false,
  };

  assert.equal(isAIRequestRouteEnabled("general", config), true);
  assert.equal(isAIRequestRouteEnabled("meal_photo", config), false);
  assert.equal(isAIRequestRouteEnabled("nutrition_label", config), true);
  assert.equal(isAIRequestRouteEnabled("menu_photo", config), true);
  assert.equal(isAIRequestRouteEnabled("receipt_photo", config), false);
  assert.equal(isAIRequestRouteEnabled("recipe_photo", undefined), true);
});

test("unknown request kinds stay on the inexpensive general route", () => {
  assert.equal(normalizeAIRequestKind("made_up"), "general");
  const route = resolveAIRequestRoute("made_up");
  assert.equal(route.model, "gpt-4o-mini");
  assert.equal(route.usageCollection, undefined);
  assert.equal(isReasoningRoute(route), false);
});

test("meal photos use the fixed Terra route and server-owned schema", () => {
  const route = resolveAIRequestRoute("meal_photo");
  assert.equal(route.model, "gpt-5.6-terra");
  assert.equal(route.reasoningEffort, "low");
  assert.equal(route.usageCollection, "aiVisionUsage");
  assert.equal(route.dailyLimit, 75);
  assert.equal(route.forcedResponseFormat.type, "json_schema");
  assert.equal(route.forcedResponseFormat.json_schema.strict, true);
  assert.equal(isReasoningRoute(route), true);
  assert.deepEqual(resolveAIRequestModels(route), ["gpt-5.6-terra", "gpt-4o-mini"]);
  assert.equal(isReasoningModel("gpt-4o-mini"), false);
});

test("extraction photos use bounded purpose-specific routes", () => {
  const label = resolveAIRequestRoute("nutrition_label");
  const receipt = resolveAIRequestRoute("receipt_photo");
  const menu = resolveAIRequestRoute("menu_photo");
  const recipe = resolveAIRequestRoute("recipe_photo");

  assert.equal(label.model, "gpt-5.6-luna");
  assert.equal(receipt.model, "gpt-5.6-luna");
  assert.equal(menu.model, "gpt-5.6-terra");
  assert.equal(recipe.model, "gpt-5.6-luna");
  assert.equal(label.forcedResponseFormat.type, "json_schema");
  assert.equal(label.forcedResponseFormat.json_schema.strict, true);
  assert.ok(
    label.forcedResponseFormat.json_schema.schema.required.includes("servingWeightGrams")
  );
  assert.equal(menu.forcedResponseFormat.type, "json_schema");
  assert.deepEqual(
    menu.forcedResponseFormat.json_schema.schema.properties.foods.items.properties.price.type,
    ["number", "null"]
  );
  assert.equal(receipt.forcedResponseFormat.type, "json_schema");
  assert.deepEqual(
    receipt.forcedResponseFormat.json_schema.schema.properties.items.items.required,
    ["name", "quantity", "unit", "category"]
  );
  assert.equal(recipe.forcedResponseFormat.type, "json_schema");
  assert.equal(recipe.forcedResponseFormat.json_schema.schema.properties.recipes.minItems, 3);
  assert.equal(recipe.forcedResponseFormat.json_schema.schema.properties.recipes.maxItems, 3);
  assert.equal(receipt.maxOutputTokens, 2400);
  assert.equal(menu.maxOutputTokens, 3000);
  assert.equal(recipe.reasoningEffort, "low");
});

test("every camera schema has complete strict object contracts", () => {
  for (const kind of [
    "meal_photo",
    "nutrition_label",
    "menu_photo",
    "receipt_photo",
    "recipe_photo",
  ]) {
    const format = resolveAIRequestRoute(kind).forcedResponseFormat;
    assert.equal(format.type, "json_schema");
    assert.equal(format.json_schema.strict, true);
    assertStrictObjectContracts(format.json_schema.schema);
  }
});

test("model availability failures can fall back without masking other provider errors", () => {
  assert.equal(isAIModelAvailabilityError({ status: 403 }), false);
  assert.equal(isAIModelAvailabilityError({ status: 403, code: "model_not_found" }), true);
  assert.equal(isAIModelAvailabilityError({ status: 404 }), true);
  assert.equal(isAIModelAvailabilityError({ status: 400, code: "model_not_found" }), true);
  assert.equal(isAIModelAvailabilityError({ status: 429 }), false);
  assert.equal(isAIModelAvailabilityError({ status: 500 }), false);
  assert.equal(isAIModelAvailabilityError(new Error("network unavailable")), false);
});

test("general Maia does not inherit a vision fallback", () => {
  const route = resolveAIRequestRoute("general");
  assert.deepEqual(resolveAIRequestModels(route), ["gpt-4o-mini"]);
});
