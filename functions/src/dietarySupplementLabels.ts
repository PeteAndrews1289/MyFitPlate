export interface SupplementSearchResult {
  id: string;
  name: string;
  servingSize: string;
  quantityValue: number;
  servingUnit: string;
  barcode?: string;
  entryDate?: string;
  productType?: string;
  micronutrientCount: number;
  nutrients: Record<string, number>;
}

interface DSLDSearchHit {
  _id?: string;
}

interface DSLDSearchResponse {
  hits?: DSLDSearchHit[];
}

interface DSLDQuantity {
  servingSizeOrder?: number;
  operator?: string;
  quantity?: number;
  unit?: string;
}

interface DSLDIngredientRow {
  order?: number;
  name?: string;
  ingredientGroup?: string;
  quantity?: DSLDQuantity[];
}

interface DSLDServingSize {
  order?: number;
  minQuantity?: number;
  maxQuantity?: number;
  unit?: string;
}

export interface DSLDLabel {
  id?: number;
  fullName?: string;
  bundleName?: string;
  brandName?: string;
  upcSku?: string;
  entryDate?: string;
  offMarket?: number;
  servingSizes?: DSLDServingSize[];
  ingredientRows?: DSLDIngredientRow[];
  productType?: {
    langualCodeDescription?: string;
  };
}

const API_BASE = "https://api.ods.od.nih.gov/dsld/v9";
const REQUEST_TIMEOUT_MS = 8_000;
const labelCache = new Map<string, SupplementSearchResult>();

export async function searchDietarySupplements(
  query: string,
  limit = 6
): Promise<SupplementSearchResult[]> {
  const ids = await searchLabelIDs(query, Math.min(Math.max(limit + 2, 4), 10));
  const records = await Promise.all(ids.map((id) => getSupplement(id)));
  return records.filter((record): record is SupplementSearchResult => record !== undefined).slice(0, limit);
}

export async function lookupDietarySupplementBarcode(
  barcode: string
): Promise<SupplementSearchResult | undefined> {
  const normalized = normalizeBarcode(barcode);
  if (normalized.length < 8) {
    return undefined;
  }
  const candidates = equivalentBarcodes(normalized);
  const idGroups = await Promise.all(candidates.map((candidate) => searchLabelIDs(candidate, 10)));
  const ids = [...new Set(idGroups.flat())].slice(0, 20);
  const records = await Promise.all(ids.map((id) => getSupplement(id)));
  return records.find((record) => record?.barcode && candidates.includes(record.barcode));
}

export function mapDSLDLabel(label: DSLDLabel): SupplementSearchResult | undefined {
  const id = label.id;
  const fullName = cleanText(label.fullName || label.bundleName || "");
  if (!id || !fullName || label.offMarket === 1) {
    return undefined;
  }

  const serving = [...(label.servingSizes ?? [])].sort((left, right) =>
    (left.order ?? 0) - (right.order ?? 0)
  )[0];
  const servingOrder = serving?.order ?? 1;
  const quantityValue = positiveNumber(serving?.minQuantity) ?? 1;
  const servingUnit = cleanText(serving?.unit || "serving");
  const servingSize = formatServing(quantityValue, servingUnit);
  const nutrients: Record<string, number> = {};

  for (const row of [...(label.ingredientRows ?? [])].sort((left, right) =>
    (left.order ?? 0) - (right.order ?? 0)
  )) {
    const key = nutrientKey(row.ingredientGroup || row.name || "");
    if (!key || nutrients[key] !== undefined) {
      continue;
    }
    const quantity = row.quantity?.find((candidate) =>
      (candidate.servingSizeOrder ?? servingOrder) === servingOrder &&
      (candidate.operator === undefined || candidate.operator === "=" || candidate.operator === "~")
    );
    const value = normalizeNutrientValue(key, quantity?.quantity, quantity?.unit, row.name || "");
    if (value !== undefined) {
      nutrients[key] = value;
    }
  }

  if (Object.keys(nutrients).length === 0) {
    return undefined;
  }

  const brand = cleanText(label.brandName || "");
  const name = brand && !fullName.toLowerCase().includes(brand.toLowerCase())
    ? `${brand} ${fullName}`
    : fullName;
  const barcode = normalizeBarcode(label.upcSku || "");

  return {
    id: `dsld_${id}`,
    name,
    servingSize,
    quantityValue,
    servingUnit,
    ...(barcode ? { barcode } : {}),
    ...(label.entryDate ? { entryDate: label.entryDate } : {}),
    ...(label.productType?.langualCodeDescription
      ? { productType: cleanText(label.productType.langualCodeDescription) }
      : {}),
    micronutrientCount: Object.keys(nutrients).length,
    nutrients,
  };
}

async function searchLabelIDs(query: string, size: number): Promise<string[]> {
  const url = new URL(`${API_BASE}/search-filter`);
  url.searchParams.set("q", query);
  url.searchParams.set("size", String(size));
  url.searchParams.set("status", "1");
  url.searchParams.set("sort_by", "_score");
  url.searchParams.set("sort_order", "desc");
  const response = await fetchJSON<DSLDSearchResponse>(url);
  return (response.hits ?? [])
    .map((hit) => hit._id)
    .filter((id): id is string => typeof id === "string" && /^\d+$/.test(id));
}

async function getSupplement(id: string): Promise<SupplementSearchResult | undefined> {
  const cached = labelCache.get(id);
  if (cached) {
    return cached;
  }
  try {
    const label = await fetchJSON<DSLDLabel>(new URL(`${API_BASE}/label/${id}`));
    const mapped = mapDSLDLabel(label);
    if (mapped) {
      labelCache.set(id, mapped);
    }
    return mapped;
  } catch {
    return undefined;
  }
}

async function fetchJSON<T>(url: URL): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`DSLD returned ${response.status}.`);
    }
    return await response.json() as T;
  } finally {
    clearTimeout(timeout);
  }
}

function nutrientKey(value: string): string | undefined {
  const normalized = value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  if (/^calories?$/.test(normalized) || normalized === "energy") return "calories";
  if (normalized === "protein") return "protein";
  if (normalized === "carbohydrate" || normalized === "total carbohydrate") return "carbs";
  if (normalized === "fat" || normalized === "total fat") return "fat";
  if (normalized.includes("dietary fiber") || normalized === "fiber") return "fiber";
  if (normalized.startsWith("vitamin a")) return "vitaminA";
  if (normalized.startsWith("vitamin c")) return "vitaminC";
  if (normalized.startsWith("vitamin d")) return "vitaminD";
  if (normalized.startsWith("vitamin e")) return "vitaminE";
  if (normalized.startsWith("vitamin k")) return "vitaminK";
  if (normalized === "thiamin" || normalized === "thiamine") return "vitaminB1";
  if (normalized === "riboflavin") return "vitaminB2";
  if (normalized.startsWith("niacin")) return "vitaminB3";
  if (normalized.startsWith("pantothenic acid")) return "vitaminB5";
  if (normalized.startsWith("vitamin b6")) return "vitaminB6";
  if (normalized.startsWith("vitamin b12")) return "vitaminB12";
  if (normalized === "folate" || normalized === "folic acid") return "folate";
  if (normalized === "calcium") return "calcium";
  if (normalized === "iron") return "iron";
  if (normalized === "magnesium") return "magnesium";
  if (normalized === "phosphorus" || normalized === "phosphorous") return "phosphorus";
  if (normalized === "potassium") return "potassium";
  if (normalized === "sodium") return "sodium";
  if (normalized === "zinc") return "zinc";
  if (normalized === "copper") return "copper";
  if (normalized === "manganese") return "manganese";
  if (normalized === "selenium") return "selenium";
  return undefined;
}

function normalizeNutrientValue(
  key: string,
  rawValue: number | undefined,
  rawUnit: string | undefined,
  ingredientName: string
): number | undefined {
  const value = positiveNumber(rawValue, true);
  if (value === undefined) {
    return undefined;
  }
  const unit = (rawUnit ?? "").toLowerCase().replace(/μ/g, "u").replace(/µ/g, "u").trim();

  if (key === "calories") {
    return ["cal", "calorie", "calories", "kcal"].includes(unit) ? value : undefined;
  }
  if (key === "protein" || key === "carbs" || key === "fat" || key === "fiber") {
    if (unit === "g" || unit === "gram" || unit === "grams") return value;
    if (unit === "mg") return value / 1_000;
    return undefined;
  }
  if (key === "vitaminA") {
    // IU-to-RAE depends on whether the label uses retinol or carotenoids. Keep only
    // directly stated mass values instead of inventing precision from an ambiguous form.
    if (unit.includes("mcg") || unit.includes("ug")) return value;
    return undefined;
  }
  if (key === "vitaminD") {
    if (unit === "iu") return value / 40;
    return toMicrograms(value, unit);
  }
  if (key === "vitaminE" && unit === "iu") {
    // Natural and synthetic vitamin E use different IU conversions.
    return undefined;
  }

  const microgramKeys = new Set(["vitaminB12", "folate", "copper", "selenium", "vitaminK"]);
  if (microgramKeys.has(key)) {
    return toMicrograms(value, unit);
  }

  const milligramValue = toMilligrams(value, unit);
  if (milligramValue === undefined) {
    return undefined;
  }
  // Vitamin E stated as alpha-tocopherol mass is compatible with the app's mg unit.
  if (key === "vitaminE" && !ingredientName.toLowerCase().includes("vitamin e")) {
    return undefined;
  }
  return milligramValue;
}

function toMilligrams(value: number, unit: string): number | undefined {
  if (unit === "mg" || unit.startsWith("milligram")) return value;
  if (unit === "g" || unit.startsWith("gram")) return value * 1_000;
  if (unit.includes("mcg") || unit.includes("ug") || unit.startsWith("microgram")) return value / 1_000;
  return undefined;
}

function toMicrograms(value: number, unit: string): number | undefined {
  if (unit.includes("mcg") || unit.includes("ug") || unit.startsWith("microgram")) return value;
  if (unit === "mg" || unit.startsWith("milligram")) return value * 1_000;
  if (unit === "g" || unit.startsWith("gram")) return value * 1_000_000;
  return undefined;
}

function formatServing(quantity: number, unit: string): string {
  const amount = Number.isInteger(quantity) ? String(quantity) : String(quantity);
  return `${amount} ${unit}`.trim();
}

function positiveNumber(value: number | undefined, allowZero = false): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }
  if (allowZero ? value < 0 : value <= 0) {
    return undefined;
  }
  return value;
}

function normalizeBarcode(value: string): string {
  return value.replace(/\D/g, "");
}

function equivalentBarcodes(barcode: string): string[] {
  const canonical = barcode.padStart(14, "0");
  const lengths = [barcode.length, 8, 12, 13, 14];
  const results: string[] = [];
  for (const length of lengths) {
    const prefixLength = canonical.length - length;
    if (prefixLength < 0 || !/^0*$/.test(canonical.slice(0, prefixLength))) {
      continue;
    }
    const candidate = canonical.slice(prefixLength);
    if (!results.includes(candidate)) {
      results.push(candidate);
    }
  }
  return results;
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}
