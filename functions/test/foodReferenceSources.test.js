const test = require("node:test");
const assert = require("node:assert/strict");

const {
  loadCanadianNutrientDataset,
  searchCanadianNutrientFile,
} = require("../lib/canadianNutrientFile.js");
const {
  lookupDietarySupplementBarcode,
  mapDSLDLabel,
  rankSupplementResults,
  searchDietarySupplements,
  supplementBarcodeSearchQueries,
} = require("../lib/dietarySupplementLabels.js");

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

test("CNF search understands ordinary cooked phrasing without returning raw foods", () => {
  const dataset = loadCanadianNutrientDataset();
  for (const query of ["salmon cooked", "cooked salmon", "ground beef cooked"]) {
    const results = searchCanadianNutrientFile(dataset, query, 5);
    assert.ok(results.length > 0, `Expected a result for ${query}`);
    assert.doesNotMatch(results[0].name.toLowerCase(), /\braw\b/);
  }
});

test("CNF token matching respects word boundaries and common plurals", () => {
  const dataset = loadCanadianNutrientDataset();
  const eggs = searchCanadianNutrientFile(dataset, "eggs boiled", 8);
  assert.ok(eggs.length > 0);
  assert.ok(eggs.every((result) => !result.name.toLowerCase().includes("eggplant")));
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

test("DSLD search ranking favors micronutrient-rich multivitamin labels", () => {
  const sparse = {
    id: "sparse",
    name: "Multivitamin",
    servingSize: "1 tablet",
    quantityValue: 1,
    servingUnit: "tablet",
    micronutrientCount: 3,
    nutrients: { vitaminC: 60, vitaminD: 10, zinc: 5 },
  };
  const rich = {
    id: "rich",
    name: "Daily Multivitamin and Mineral",
    servingSize: "2 tablets",
    quantityValue: 2,
    servingUnit: "tablets",
    micronutrientCount: 19,
    nutrients: { vitaminC: 90 },
  };

  assert.equal(rankSupplementResults("multivitamin", [sparse, rich])[0].id, "rich");
});

test("DSLD barcode lookup formats UPC-A the way label records store it", () => {
  const queries = supplementBarcodeSearchQueries("748927052497");
  assert.ok(queries.includes("\"7 48927 05249 7\""));
  assert.ok(queries.length <= 5);
});

function mockLabelCatalog(t, search, label) {
  t.mock.method(globalThis, "fetch", async (url) => {
    if (url.pathname.endsWith("/search-filter")) return search(url.searchParams.get("q"));
    assert.match(url.pathname, /\/label\/\d+$/);
    return label(Number(url.pathname.split("/").pop()));
  });
}

function labelHits(...ids) {
  return Response.json({ hits: ids.map(id => ({ _id: String(id) })) });
}

function capsuleLabel(id, barcode) {
  return Response.json({
    id, fullName: "Vitamin D3", brandName: "Example", upcSku: barcode,
    servingSizes: [{ order: 1, minQuantity: 1, unit: "capsule" }],
    ingredientRows: [{ name: "Vitamin D", quantity: [{ quantity: 25, unit: "mcg" }] }],
  });
}

test("DSLD search keeps available labels when a sibling detail request fails", async (t) => {
  mockLabelCatalog(t, () => labelHits(90001, 90002), id =>
    id === 90001 ? new Response(null, { status: 503 }) : capsuleLabel(id)
  );
  const results = await searchDietarySupplements("vitamin");
  assert.deepEqual(results.map(item => item.id), ["dsld_90002"]);
  assert.equal(results[0].servingSize, "1 capsule");
});

test("DSLD search distinguishes an unavailable catalog from a definitive empty result", async (t) => {
  mockLabelCatalog(t, q => {
    if (q === "malformed") return Response.json({});
    if (q === "malformed label") return labelHits(90007);
    if (q === "unavailable") return labelHits(90003, 90004);
    if (q === "removed") return labelHits(90004, 90005, 90006);
    return labelHits();
  }, id => {
    if (id === 90006) return Response.json({ id, fullName: "Retired", offMarket: 1 });
    if (id === 90007) return Response.json({});
    return new Response(null, { status: id === 90003 ? 503 : id === 90004 ? 404 : 410 });
  });
  await assert.rejects(searchDietarySupplements("unavailable"));
  await assert.rejects(searchDietarySupplements("malformed"));
  await assert.rejects(searchDietarySupplements("malformed label"));
  assert.deepEqual(await searchDietarySupplements("removed"), []);
  assert.deepEqual(await searchDietarySupplements("no hits"), []);
});

test("DSLD barcode lookup returns a verified match even if another spelling or label fails", async (t) => {
  const barcode = "012345678905";
  const [first] = supplementBarcodeSearchQueries(barcode);
  mockLabelCatalog(t, q => q === first ? labelHits(90101, 90102) : new Response(null, { status: 503 }),
    id => id === 90101 ? new Response(null, { status: 503 }) : capsuleLabel(id, barcode.padStart(14, "0"))
  );
  const match = await lookupDietarySupplementBarcode(barcode);
  assert.equal(match.id, "dsld_90102");
});

test("DSLD barcode lookup reports an incomplete lookup unless it found the exact package", async (t) => {
  const barcode = "012345678905";
  const [first] = supplementBarcodeSearchQueries(barcode);
  let failIndex = true;
  let failLabel = true;
  mockLabelCatalog(t, q => {
    if (q === first && failIndex) return new Response(null, { status: 503 });
    return labelHits(90103, 90104);
  }, id => id === 90103 ? capsuleLabel(id, "748927052497") : new Response(null, { status: failLabel ? 503 : 404 }));
  await assert.rejects(lookupDietarySupplementBarcode(barcode));
  failLabel = false;
  await assert.rejects(lookupDietarySupplementBarcode(barcode));
  failIndex = false;
  failLabel = true;
  await assert.rejects(lookupDietarySupplementBarcode(barcode));
  failLabel = false;
  assert.equal(await lookupDietarySupplementBarcode(barcode), undefined);
});
