const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isAIRequestRouteEnabled,
  isReasoningRoute,
  normalizeAIRequestKind,
  resolveAIRequestRoute,
} = require("../lib/aiRequestRouting.js");

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
  assert.equal(label.forcedResponseFormat.type, "json_object");
  assert.equal(receipt.maxOutputTokens, 2400);
  assert.equal(menu.maxOutputTokens, 3000);
  assert.equal(recipe.reasoningEffort, "low");
});
