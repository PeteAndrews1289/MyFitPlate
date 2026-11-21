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
  resolveAICompletionTokenLimit,
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
  assert.equal(route.model, "gpt-6-luna");
  assert.equal(route.usageCollection, undefined);
  assert.equal(isReasoningRoute(route), true);
});

test("meal photos use the fixed Sol route and server-owned schema", () => {
  const route = resolveAIRequestRoute("meal_photo");
  assert.equal(route.model, "gpt-6.1-sol");
  assert.equal(route.reasoningEffort, "low");
  assert.equal(route.usageCollection, "aiVisionUsage");
  assert.equal(route.dailyLimit, 75);
  assert.equal(route.forcedResponseFormat.type, "json_schema");
  assert.equal(route.forcedResponseFormat.json_schema.strict, true);
  assert.equal(isReasoningRoute(route), true);
  assert.deepEqual(resolveAIRequestModels(route), ["gpt-6.1-sol", "gpt-6-sol"]);
  assert.equal(isReasoningModel("gpt-6-luna"), true);
});

test("extraction photos use bounded purpose-specific routes", () => {
  const label = resolveAIRequestRoute("nutrition_label");
  const receipt = resolveAIRequestRoute("receipt_photo");
  const menu = resolveAIRequestRoute("menu_photo");
  const recipe = resolveAIRequestRoute("recipe_photo");

  assert.equal(label.model, "gpt-6-luna");
  assert.equal(receipt.model, "gpt-6-luna");
  assert.equal(menu.model, "gpt-6.1-sol");
  assert.equal(recipe.model, "gpt-6.1-sol");
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
    ["name", "quantity", "unit", "category", "originalName", "printedLinePrice", "currency"]
  );
  assert.equal(recipe.forcedResponseFormat.type, "json_schema");
  assert.equal(recipe.forcedResponseFormat.json_schema.schema.properties.recipes.minItems, 3);
  assert.equal(recipe.forcedResponseFormat.json_schema.schema.properties.recipes.maxItems, 3);
  assert.equal(receipt.maxOutputTokens, 8000);
  assert.equal(menu.maxOutputTokens, 9000);
  assert.equal(recipe.reasoningEffort, "low");
});

test("every camera schema has complete strict object contracts", () => {
  for (const kind of [
    "meal_photo",
    "nutrition_label",
    "menu_photo",
    "receipt_photo",
    "recipe_photo",
    "pantry_observation",
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
  assert.deepEqual(resolveAIRequestModels(route), ["gpt-6-luna", "gpt-6-sol"]);
});

test("coaching and planning prioritize quality with supported fallbacks", () => {
  for (const kind of ["coaching", "planning"]) {
    const route = resolveAIRequestRoute(kind);
    assert.equal(normalizeAIRequestKind(kind), kind);
    assert.deepEqual(resolveAIRequestModels(route), ["gpt-6-astra", "gpt-6.1-sol"]);
    assert.equal(route.reasoningEffort, kind === "planning" ? "medium" : "low");
    assert.equal(isReasoningModel(route.model), true);
  }
});

test("reasoning gets room beyond the visible-answer budget without exceeding route caps", () => {
  const planning = resolveAIRequestRoute("planning");
  assert.equal(resolveAICompletionTokenLimit(planning, 5000), 11000);
  assert.equal(resolveAICompletionTokenLimit(planning, 999999), 12000);
  assert.equal(resolveAICompletionTokenLimit(planning, NaN), 12000);
  assert.equal(resolveAICompletionTokenLimit(planning, 0.5), 12000);
  assert.equal(resolveAICompletionTokenLimit(resolveAIRequestRoute("general"), 1000.9), 1000);
});

test("all production routes are free of retired compatibility models", () => {
  for (const kind of ["general", "coaching", "planning", "meal_photo", "menu_photo", "recipe_photo", "nutrition_label", "receipt_photo", "pantry_observation"]) {
    assert.ok(resolveAIRequestModels(resolveAIRequestRoute(kind)).every(model => model.startsWith("gpt-6")));
  }
});


test("pantry observations cannot inherit the legacy three-recipe output contract", () => {
  const observed = resolveAIRequestRoute("pantry_observation");
  const legacy = resolveAIRequestRoute("recipe_photo");
  assert.equal(observed.kind, "pantry_observation");
  assert.equal(observed.usageCollection, "aiVisionUsage");
  assert.equal(observed.dailyLimit, legacy.dailyLimit);
  const schema = observed.forcedResponseFormat.json_schema.schema;
  assert.deepEqual(Object.keys(schema.properties), ["ingredients"]);
  assert.deepEqual(schema.required, ["ingredients"]);
  assert.equal(schema.properties.ingredients.minItems, 0);
  assert.equal(schema.properties.ingredients.maxItems, 40);
  assert.equal(schema.properties.ingredients.items.type, "string");
  assert.equal(legacy.forcedResponseFormat.json_schema.schema.properties.recipes.minItems, 3);
  assert.equal(isAIRequestRouteEnabled("pantry_observation", { pantry_observation: false }), false);
  assert.equal(isAIRequestRouteEnabled("recipe_photo", { pantry_observation: false }), true);
});


test("receipt context and printed line amounts remain nullable and independent from stock quantities", () => {
  const schema = resolveAIRequestRoute("receipt_photo").forcedResponseFormat.json_schema.schema;
  assert.deepEqual(schema.required, ["items", "storeName", "currency"]);
  assert.deepEqual(schema.properties.storeName.type, ["string", "null"]);
  assert.deepEqual(schema.properties.currency.type, ["string", "null"]);
  const row = schema.properties.items.items;
  assert.deepEqual(row.properties.printedLinePrice.type, ["number", "null"]);
  assert.equal(row.properties.printedLinePrice.minimum, undefined, "A clearly printed credit/discount remains separate from positive purchased quantity");
  assert.equal(row.properties.quantity.minimum, 0);
  assert.deepEqual(row.properties.originalName.type, ["string", "null"]);
  assert.equal(schema.properties.items.maxItems, 120);
});


test("menu price wording and explicit currency survive strict extraction without inventing a comparable price", () => {
  const route = resolveAIRequestRoute("menu_photo");
  const row = route.forcedResponseFormat.json_schema.schema.properties.foods.items;
  assert.ok(row.required.includes("currency"));
  assert.ok(row.required.includes("priceText"));
  assert.deepEqual(row.properties.currency.type, ["string", "null"]);
  assert.deepEqual(row.properties.priceText.type, ["string", "null"]);
  assert.deepEqual(row.properties.price.type, ["number", "null"]);
  assert.equal(route.maxOutputTokens, 9000);
});
