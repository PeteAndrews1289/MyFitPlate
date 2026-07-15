import * as fs from "node:fs";
import * as path from "node:path";

export interface CompactCanadianFood {
  i: number;
  n: string;
  a?: string;
  f: number;
  d: string;
  q?: number[];
  v: Record<string, number>;
}

export interface CanadianNutrientDataset {
  schema: number;
  release: string;
  source: string;
  foods: CompactCanadianFood[];
}

export interface CanadianFoodSearchResult {
  id: string;
  name: string;
  servingSize: string;
  servingWeight: number;
  nutrients: Record<string, number>;
  datasetRelease: string;
  recordUpdatedAt: string;
  foodSourceCode: number;
  foodSourceSummary: string;
  micronutrientCount: number;
}

const DETAIL_KEYS = new Set([
  "fiber",
  "calcium",
  "iron",
  "magnesium",
  "phosphorus",
  "potassium",
  "sodium",
  "zinc",
  "copper",
  "manganese",
  "selenium",
  "vitaminA",
  "vitaminC",
  "vitaminD",
  "vitaminB1",
  "vitaminB2",
  "vitaminB3",
  "vitaminB5",
  "vitaminB6",
  "vitaminB12",
  "vitaminE",
  "vitaminK",
  "folate",
  "saturatedFat",
  "monounsaturatedFat",
  "polyunsaturatedFat",
]);

const FOOD_SOURCE_SUMMARIES: Record<number, string> = {
  0: "Based on unchanged USDA composition data",
  1: "USDA composition adjusted for Canadian regulations",
  3: "Includes nutrients analyzed in a Canadian product",
  4: "Includes nutrients calculated for a Canadian product",
  6: "Includes Canadian manufacturer-supplied values",
  9: "Supplied by an international composition database",
  10: "Includes Canadian analysis of a retired USDA food",
  11: "Based on a food retired from USDA",
  12: "Based on USDA survey composition data",
  20: "Based on the Nutrition Canada Survey",
  23: "Major nutrients analyzed in a Canadian product",
  24: "Major nutrients calculated for a Canadian product",
  26: "Canadian manufacturer-supplied composition data",
  28: "Traditional food composition record",
  35: "Health Canada recipe compilation",
  37: "Health Canada sampling and analysis program",
};

const PROCESSED_FORM_TERMS = new Set([
  "batter",
  "breaded",
  "canned",
  "deli",
  "fast",
  "flavoured",
  "fried",
  "frozen",
  "nugget",
  "sandwich",
  "seasoned",
  "stuffed",
  "stuffing",
  "tender",
  "tenders",
]);

const SIMPLE_FORM_TERMS = new Set([
  "baked",
  "boiled",
  "braised",
  "broiled",
  "grilled",
  "raw",
  "roasted",
  "steamed",
  "stewed",
]);

let cachedDataset: CanadianNutrientDataset | undefined;

export function loadCanadianNutrientDataset(): CanadianNutrientDataset {
  if (cachedDataset) {
    return cachedDataset;
  }
  const dataPath = path.join(__dirname, "../data/cnf-2026.json");
  const parsed = JSON.parse(fs.readFileSync(dataPath, "utf8")) as CanadianNutrientDataset;
  if (parsed.schema !== 1 || !Array.isArray(parsed.foods) || parsed.foods.length < 5000) {
    throw new Error("Canadian Nutrient File asset is missing or invalid.");
  }
  cachedDataset = parsed;
  return parsed;
}

export function searchCanadianNutrientFile(
  dataset: CanadianNutrientDataset,
  query: string,
  limit = 12
): CanadianFoodSearchResult[] {
  const normalizedQuery = normalize(query);
  if (normalizedQuery.length < 2 || limit <= 0) {
    return [];
  }
  const queryTokens = normalizedQuery.split(" ").filter(Boolean);

  return dataset.foods
    .map((food) => ({ food, score: searchScore(food, normalizedQuery, queryTokens) }))
    .filter((candidate) => candidate.score > 0)
    .sort((left, right) => {
      if (left.score === right.score) {
        return left.food.i - right.food.i;
      }
      return right.score - left.score;
    })
    .slice(0, Math.min(limit, 20))
    .map(({ food }) => result(food, dataset.release));
}

function searchScore(food: CompactCanadianFood, query: string, tokens: string[]): number {
  const name = normalize(food.n);
  const alternate = normalize(food.a ?? "");
  const nameTokens = name.split(" ");
  const queryTokenSet = new Set(tokens);
  let score = 0;

  if (name === query || alternate === query) {
    score = 10_000;
  } else if (name.startsWith(query) || alternate.startsWith(query)) {
    score = 8_000;
  } else if (name.includes(query) || alternate.includes(query)) {
    score = 6_500;
  } else if (tokens.every((token) => name.includes(token) || alternate.includes(token))) {
    score = 5_500;
  } else {
    return 0;
  }

  const detailCount = Object.keys(food.v).filter((key) => DETAIL_KEYS.has(key)).length;
  const hasCanadianAnalysis = (food.q ?? []).some((code) => [3, 7, 17].includes(code));
  const processedTermsNotRequested = nameTokens.filter((token) =>
    PROCESSED_FORM_TERMS.has(token) && !queryTokenSet.has(token)
  ).length;
  const simpleFormBonus = nameTokens.some((token) => SIMPLE_FORM_TERMS.has(token)) ? 180 : 0;
  const genericFoodBonus = nameTokens.includes(tokens[0]) && tokens.every((token) => nameTokens.includes(token))
    ? 300
    : 0;

  return score +
    detailCount * 5 +
    (hasCanadianAnalysis ? 75 : 0) +
    simpleFormBonus +
    genericFoodBonus -
    processedTermsNotRequested * 1_700;
}

function result(food: CompactCanadianFood, release: string): CanadianFoodSearchResult {
  return {
    id: `cnf_${food.i}`,
    name: food.n,
    servingSize: "100 g",
    servingWeight: 100,
    nutrients: food.v,
    datasetRelease: release,
    recordUpdatedAt: food.d,
    foodSourceCode: food.f,
    foodSourceSummary: FOOD_SOURCE_SUMMARIES[food.f] ?? "Health Canada composition record",
    micronutrientCount: Object.keys(food.v).filter((key) => DETAIL_KEYS.has(key)).length,
  };
}

function normalize(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}
