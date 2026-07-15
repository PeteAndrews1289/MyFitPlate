const test = require("node:test");
const assert = require("node:assert/strict");

const {
  loadCanadianNutrientDataset,
  searchCanadianNutrientFile,
} = require("../lib/canadianNutrientFile.js");
const { mapDSLDLabel } = require("../lib/dietarySupplementLabels.js");

test("CNF asset includes the complete 2026 food catalog", () => {
  const dataset = loadCanadianNutrientDataset();
  assert.equal(dataset.schema, 1);
  assert.equal(dataset.release, "2026-05-14");
  assert.equal(dataset.foods.length, 5993);
});

test("CNF search returns normalized per-100g nutrition with broad micronutrient coverage", () => {
  const results = searchCanadianNutrientFile(
    loadCanadianNutrientDataset(),
    "chicken breast",
    5
  );
  assert.ok(results.length > 0);
  assert.equal(results[0].servingSize, "100 g");
  assert.equal(results[0].servingWeight, 100);
  assert.ok(results[0].nutrients.calories > 0);
  assert.ok(results[0].micronutrientCount >= 15);
  assert.equal(results[0].datasetRelease, "2026-05-14");
  assert.match(results[0].name.toLowerCase(), /raw|roasted|grilled|stewed|braised/);
  assert.doesNotMatch(results[0].name.toLowerCase(), /breaded|deli|stuff/);
});

test("CNF search is accent and punctuation tolerant", () => {
  const results = searchCanadianNutrientFile(
    loadCanadianNutrientDataset(),
    "cheese souffle",
    3
  );
  assert.equal(results[0].name, "Cheese souffle");
});

test("DSLD mapping preserves label serving and converts only unambiguous units", () => {
  const supplement = mapDSLDLabel({
    id: 42,
    fullName: "Daily Multi",
    brandName: "Example",
    upcSku: "0-12345-67890-5",
    entryDate: "2026-05-01",
    offMarket: 0,
    servingSizes: [{ order: 1, minQuantity: 2, unit: "Capsules" }],
    productType: { langualCodeDescription: "Multi-Vitamin and Mineral (MVM)" },
    ingredientRows: [
      {
        order: 1,
        name: "Vitamin A",
        ingredientGroup: "Vitamin A",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 5000, unit: "IU" }],
      },
      {
        order: 2,
        name: "Vitamin D3",
        ingredientGroup: "Vitamin D",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 800, unit: "IU" }],
      },
      {
        order: 3,
        name: "Vitamin C",
        ingredientGroup: "Vitamin C",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 60, unit: "mg" }],
      },
      {
        order: 4,
        name: "Copper",
        ingredientGroup: "Copper",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 2, unit: "mg" }],
      },
      {
        order: 5,
        name: "Vitamin E",
        ingredientGroup: "Vitamin E",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 30, unit: "IU" }],
      },
      {
        order: 6,
        name: "Total Carbohydrate",
        ingredientGroup: "Total Carbohydrate",
        quantity: [{ servingSizeOrder: 1, operator: "=", quantity: 3, unit: "g" }],
      },
    ],
  });

  assert.ok(supplement);
  assert.equal(supplement.name, "Example Daily Multi");
  assert.equal(supplement.servingSize, "2 Capsules");
  assert.equal(supplement.barcode, "012345678905");
  assert.equal(supplement.nutrients.vitaminD, 20);
  assert.equal(supplement.nutrients.vitaminC, 60);
  assert.equal(supplement.nutrients.copper, 2000);
  assert.equal(supplement.nutrients.vitaminA, undefined);
  assert.equal(supplement.nutrients.vitaminE, undefined);
  assert.equal(supplement.nutrients.carbs, 3);
});

test("DSLD mapping rejects off-market and nutrient-empty labels", () => {
  assert.equal(mapDSLDLabel({ id: 1, fullName: "Old", offMarket: 1 }), undefined);
  assert.equal(mapDSLDLabel({ id: 2, fullName: "Empty", offMarket: 0 }), undefined);
});
