const test = require("node:test");
const assert = require("node:assert/strict");

const {
  COMMUNITY_BARCODE_MODEL_VERSION,
  buildCommunityBarcodeAggregate,
  isValidGTIN,
  parseCommunityBarcodeContribution,
} = require("../lib/communityBarcode.js");

const barcode = "0123456789012";

function payload(overrides = {}) {
  return {
    barcode,
    name: "Protein Bar",
    calories: 210,
    protein: 20,
    carbs: 22,
    fats: 7,
    fiber: 3,
    servingSize: "1 bar (60 g)",
    servingWeight: 60,
    ...overrides,
  };
}

function contribution(contributorKey, overrides = {}) {
  const parsed = parseCommunityBarcodeContribution(payload(overrides), contributorKey);
  assert.equal(parsed.ok, true);
  return parsed.contribution;
}

test("GTIN validation uses the GS1 check digit", () => {
  assert.equal(isValidGTIN(barcode), true);
  assert.equal(isValidGTIN("0123456789013"), false);
  assert.equal(isValidGTIN("12345"), false);
});

test("contribution parsing rejects unknown, non-finite, and implausible data", () => {
  assert.deepEqual(
    parseCommunityBarcodeContribution({ ...payload(), moderationBypass: true }, "alice"),
    { ok: false, reason: "unknown_field" }
  );
  assert.equal(parseCommunityBarcodeContribution(payload({ calories: Infinity }), "alice").ok, false);
  assert.equal(parseCommunityBarcodeContribution(payload({ name: "Private\nName" }), "alice").ok, false);
  assert.deepEqual(
    parseCommunityBarcodeContribution(payload({ protein: 80, servingWeight: 60 }), "alice"),
    { ok: false, reason: "nutrition_needs_review" }
  );
});

test("three agreeing contributors publish deterministic median nutrition", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice", { calories: 210, protein: 20, carbs: 22, fats: 7, servingWeight: 60 }),
    contribution("bob", { calories: 215, protein: 21, carbs: 21, fats: 7.5, servingWeight: 61 }),
    contribution("carol", { calories: 205, protein: 19, carbs: 23, fats: 6.5, servingWeight: 59 }),
  ]);

  assert.equal(result.status, "published");
  assert.equal(result.aggregate.modelVersion, COMMUNITY_BARCODE_MODEL_VERSION);
  assert.equal(result.aggregate.calories, 210);
  assert.equal(result.aggregate.protein, 20);
  assert.equal(result.aggregate.servingWeight, 60);
  assert.equal(result.aggregate.contributorCount, 3);
  assert.equal(result.aggregate.agreementCount, 3);
  assert.equal(result.aggregate.agreementRatio, 1);
});

test("two contributors are never enough to publish", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice"),
    contribution("bob", { calories: 215 }),
  ]);

  assert.equal(result.status, "insufficient");
  assert.equal(result.contributorCount, 2);
});

test("duplicate contributor keys cannot manufacture consensus", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice"),
    contribution("alice", { calories: 211 }),
    contribution("bob", { calories: 212 }),
  ]);

  assert.equal(result.status, "insufficient");
  assert.equal(result.contributorCount, 2);
  assert.equal(result.rejectedCount, 1);
});

test("a three-to-one consensus publishes while retaining aggregate conflict counts", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice"),
    contribution("bob", { calories: 215, protein: 21 }),
    contribution("carol", { calories: 205, protein: 19 }),
    contribution("dave", {
      name: "Different Product",
      calories: 420,
      protein: 5,
      carbs: 70,
      fats: 13,
      fiber: 8,
      servingSize: "1 package (100 g)",
      servingWeight: 100,
    }),
  ]);

  assert.equal(result.status, "published");
  assert.equal(result.aggregate.agreementCount, 3);
  assert.equal(result.aggregate.conflictCount, 1);
  assert.equal(result.aggregate.agreementRatio, 0.75);
});

test("split evidence is quarantined as conflict instead of choosing a side", () => {
  const firstProduct = [
    contribution("alice"),
    contribution("bob", { calories: 215 }),
  ];
  const secondProduct = [
    contribution("carol", {
      name: "Different Product",
      calories: 420,
      protein: 5,
      carbs: 70,
      fats: 13,
      fiber: 8,
      servingSize: "1 package (100 g)",
      servingWeight: 100,
    }),
    contribution("dave", {
      name: "Different Product",
      calories: 425,
      protein: 6,
      carbs: 69,
      fats: 13,
      fiber: 8,
      servingSize: "1 package (100 g)",
      servingWeight: 100,
    }),
  ];

  const result = buildCommunityBarcodeAggregate([...firstProduct, ...secondProduct]);
  assert.equal(result.status, "conflict");
  assert.equal(result.agreementCount, 2);
});

test("aggregate output never contains contributor identifiers", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("private-user-a"),
    contribution("private-user-b", { calories: 211 }),
    contribution("private-user-c", { calories: 212 }),
  ]);

  assert.equal(result.status, "published");
  const encoded = JSON.stringify(result.aggregate);
  assert.equal(encoded.includes("private-user"), false);
  assert.equal(encoded.includes("contributorKey"), false);
  assert.equal(encoded.includes("createdBy"), false);
});

test("aggregation is stable regardless of contribution arrival order", () => {
  const values = [
    contribution("alice", { calories: 210 }),
    contribution("bob", { calories: 215 }),
    contribution("carol", { calories: 205 }),
  ];
  const forward = buildCommunityBarcodeAggregate(values);
  const reverse = buildCommunityBarcodeAggregate([...values].reverse());

  assert.deepEqual(forward, reverse);
});

test("fiber is published only when the minimum contributor floor includes it", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice"),
    contribution("bob", { fiber: 4 }),
    contribution("carol", { fiber: undefined }),
  ]);

  assert.equal(result.status, "published");
  assert.equal(Object.hasOwn(result.aggregate, "fiber"), false);
});

test("a coordinate-wise median must still pass nutrition sanity checks", () => {
  const result = buildCommunityBarcodeAggregate([
    contribution("alice", {
      calories: 293.2, protein: 21.5, carbs: 34.4, fats: 9, servingWeight: 62.6,
    }),
    contribution("bob", {
      calories: 304.1, protein: 23.2, carbs: 37.6, fats: 8.3, servingWeight: 66.2,
    }),
    contribution("carol", {
      calories: 300.7, protein: 22.5, carbs: 27.7, fats: 8.9, servingWeight: 61.6,
    }),
  ]);

  assert.equal(result.status, "conflict");
  assert.equal(result.reason, "aggregate_nutrition_needs_review");
});
