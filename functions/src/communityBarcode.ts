export const COMMUNITY_BARCODE_MODEL_VERSION = "community_consensus_v1";

const SUPPORTED_GTIN_LENGTHS = new Set([8, 12, 13, 14]);
const ALLOWED_PAYLOAD_KEYS = new Set([
  "barcode",
  "name",
  "calories",
  "protein",
  "carbs",
  "fats",
  "fiber",
  "servingSize",
  "servingWeight",
]);

export interface CommunityBarcodeContribution {
  contributorKey: string;
  barcode: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  fiber?: number;
  servingSize: string;
  servingWeight: number;
}

export interface CommunityBarcodeAggregate {
  schemaVersion: 1;
  modelVersion: string;
  status: "published";
  barcode: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  fiber?: number;
  servingSize: string;
  servingWeight: number;
  contributorCount: number;
  agreementCount: number;
  conflictCount: number;
  agreementRatio: number;
}

export type ContributionParseResult =
  | { ok: true; contribution: CommunityBarcodeContribution }
  | { ok: false; reason: string };

export type CommunityBarcodeAggregationResult =
  | {
      status: "published";
      aggregate: CommunityBarcodeAggregate;
      rejectedCount: number;
    }
  | {
      status: "insufficient" | "conflict";
      contributorCount: number;
      agreementCount: number;
      rejectedCount: number;
      reason: string;
    };

export function normalizeBarcode(value: string): string {
  const trimmed = value.trim();
  const digits = trimmed.replace(/[^0-9]/g, "");
  return digits.length > 0 ? digits : trimmed;
}

export function isValidGTIN(value: string): boolean {
  const barcode = normalizeBarcode(value);
  if (!SUPPORTED_GTIN_LENGTHS.has(barcode.length) || !/^[0-9]+$/.test(barcode)) {
    return false;
  }

  const checkDigit = Number(barcode[barcode.length - 1]);
  const payload = barcode.slice(0, -1).split("").reverse();
  const weightedSum = payload.reduce((sum, digit, index) => {
    return sum + Number(digit) * (index % 2 === 0 ? 3 : 1);
  }, 0);
  return (10 - (weightedSum % 10)) % 10 === checkDigit;
}

export function parseCommunityBarcodeContribution(
  payload: unknown,
  contributorKey: string
): ContributionParseResult {
  if (!isRecord(payload)) {
    return { ok: false, reason: "invalid_payload" };
  }
  if (Object.keys(payload).some((key) => !ALLOWED_PAYLOAD_KEYS.has(key))) {
    return { ok: false, reason: "unknown_field" };
  }
  if (typeof contributorKey !== "string" || contributorKey.length === 0) {
    return { ok: false, reason: "invalid_contributor" };
  }

  const barcodeValue = readString(payload, "barcode");
  const name = readCleanText(payload, "name", 140);
  const servingSize = readCleanText(payload, "servingSize", 80);
  const calories = readNumber(payload, "calories", 0, 5000);
  const protein = readNumber(payload, "protein", 0, 1000);
  const carbs = readNumber(payload, "carbs", 0, 1000);
  const fats = readNumber(payload, "fats", 0, 1000);
  const servingWeight = readNumber(payload, "servingWeight", 10, 5000);
  const fiber = payload.fiber === undefined
    ? undefined
    : readNumber(payload, "fiber", 0, 1000);

  if (barcodeValue === undefined || !isValidGTIN(barcodeValue)) {
    return { ok: false, reason: "invalid_barcode" };
  }
  if (name === undefined) {
    return { ok: false, reason: "invalid_name" };
  }
  if (servingSize === undefined) {
    return { ok: false, reason: "invalid_serving_size" };
  }
  if (calories === undefined) {
    return { ok: false, reason: "calories_out_of_range" };
  }
  if (protein === undefined || carbs === undefined || fats === undefined) {
    return { ok: false, reason: "macros_out_of_range" };
  }
  if (payload.fiber !== undefined && fiber === undefined) {
    return { ok: false, reason: "fiber_out_of_range" };
  }
  if (servingWeight === undefined) {
    return { ok: false, reason: "serving_weight_out_of_range" };
  }

  const contribution: CommunityBarcodeContribution = {
    contributorKey,
    barcode: normalizeBarcode(barcodeValue),
    name,
    calories,
    protein,
    carbs,
    fats,
    ...(fiber === undefined ? {} : { fiber }),
    servingSize,
    servingWeight,
  };
  if (!hasSaneNutrition(contribution)) {
    return { ok: false, reason: "nutrition_needs_review" };
  }
  return { ok: true, contribution };
}

export function buildCommunityBarcodeAggregate(
  rawContributions: readonly CommunityBarcodeContribution[],
  minimumContributors = 3,
  minimumAgreementRatio = 2 / 3
): CommunityBarcodeAggregationResult {
  const minimum = Math.max(3, Math.floor(minimumContributors));
  const ratioFloor = clamp(minimumAgreementRatio, 2 / 3, 1);
  const unique = new Map<string, CommunityBarcodeContribution>();
  let rejectedCount = 0;

  for (const contribution of rawContributions) {
    const parsed = parseCommunityBarcodeContribution(
      payloadFromContribution(contribution),
      contribution.contributorKey
    );
    if (!parsed.ok) {
      rejectedCount += 1;
      continue;
    }
    if (unique.has(parsed.contribution.contributorKey)) {
      rejectedCount += 1;
      continue;
    }
    unique.set(parsed.contribution.contributorKey, parsed.contribution);
  }

  const contributions = Array.from(unique.values()).sort((left, right) =>
    contributionFingerprint(left).localeCompare(contributionFingerprint(right))
  );
  if (contributions.length < minimum) {
    return {
      status: "insufficient",
      contributorCount: contributions.length,
      agreementCount: contributions.length,
      rejectedCount,
      reason: "minimum_contributors_not_met",
    };
  }

  const candidates = contributions.map((anchor) => ({
    anchor,
    matches: contributions.filter((candidate) => contributionsAgree(anchor, candidate)),
  }));
  candidates.sort((left, right) => {
    if (left.matches.length !== right.matches.length) {
      return right.matches.length - left.matches.length;
    }
    return contributionFingerprint(left.anchor).localeCompare(contributionFingerprint(right.anchor));
  });

  const consensus = candidates[0].matches;
  const agreementRatio = consensus.length / contributions.length;
  if (consensus.length < minimum || agreementRatio < ratioFloor) {
    return {
      status: "conflict",
      contributorCount: contributions.length,
      agreementCount: consensus.length,
      rejectedCount,
      reason: "consensus_threshold_not_met",
    };
  }

  const barcode = modeText(consensus.map((item) => item.barcode));
  const fiberValues = consensus
    .map((item) => item.fiber)
    .filter((value): value is number => value !== undefined);
  const aggregate: CommunityBarcodeAggregate = {
    schemaVersion: 1,
    modelVersion: COMMUNITY_BARCODE_MODEL_VERSION,
    status: "published",
    barcode,
    name: modeText(consensus.map((item) => item.name)),
    calories: roundedMedian(consensus.map((item) => item.calories)),
    protein: roundedMedian(consensus.map((item) => item.protein)),
    carbs: roundedMedian(consensus.map((item) => item.carbs)),
    fats: roundedMedian(consensus.map((item) => item.fats)),
    ...(fiberValues.length >= minimum ? { fiber: roundedMedian(fiberValues) } : {}),
    servingSize: modeText(consensus.map((item) => item.servingSize)),
    servingWeight: roundedMedian(consensus.map((item) => item.servingWeight)),
    contributorCount: contributions.length,
    agreementCount: consensus.length,
    conflictCount: contributions.length - consensus.length,
    agreementRatio: Math.round(agreementRatio * 1000) / 1000,
  };
  const aggregateNutrition: CommunityBarcodeContribution = {
    contributorKey: "server-aggregate",
    barcode: aggregate.barcode,
    name: aggregate.name,
    calories: aggregate.calories,
    protein: aggregate.protein,
    carbs: aggregate.carbs,
    fats: aggregate.fats,
    ...(aggregate.fiber === undefined ? {} : { fiber: aggregate.fiber }),
    servingSize: aggregate.servingSize,
    servingWeight: aggregate.servingWeight,
  };
  if (!hasSaneNutrition(aggregateNutrition)) {
    return {
      status: "conflict",
      contributorCount: contributions.length,
      agreementCount: consensus.length,
      rejectedCount,
      reason: "aggregate_nutrition_needs_review",
    };
  }
  return { status: "published", aggregate, rejectedCount };
}

function hasSaneNutrition(contribution: CommunityBarcodeContribution): boolean {
  const macroMass = contribution.protein + contribution.carbs + contribution.fats;
  if (macroMass > contribution.servingWeight * 1.05) {
    return false;
  }
  if (contribution.calories > contribution.servingWeight * 9.5) {
    return false;
  }
  if (contribution.fiber !== undefined && contribution.fiber > contribution.carbs * 1.1 + 1) {
    return false;
  }

  const proteinAndFatCalories = contribution.protein * 4 + contribution.fats * 9;
  if (
    proteinAndFatCalories - contribution.calories >= 20 &&
    contribution.calories < proteinAndFatCalories * 0.8
  ) {
    return false;
  }
  const macroCalories = proteinAndFatCalories + contribution.carbs * 4;
  if (
    contribution.calories >= 80 &&
    macroCalories > 0 &&
    contribution.calories > macroCalories * 2.2
  ) {
    return false;
  }
  return true;
}

function contributionsAgree(
  left: CommunityBarcodeContribution,
  right: CommunityBarcodeContribution
): boolean {
  return left.barcode === right.barcode &&
    withinTolerance(left.servingWeight, right.servingWeight, 0.10, 2) &&
    withinTolerance(left.calories, right.calories, 0.15, 20) &&
    withinTolerance(left.protein, right.protein, 0.20, 2) &&
    withinTolerance(left.carbs, right.carbs, 0.20, 2) &&
    withinTolerance(left.fats, right.fats, 0.20, 2) &&
    optionalValuesAgree(left.fiber, right.fiber);
}

function optionalValuesAgree(left: number | undefined, right: number | undefined): boolean {
  if (left === undefined || right === undefined) {
    return true;
  }
  return withinTolerance(left, right, 0.25, 2);
}

function withinTolerance(
  left: number,
  right: number,
  relativeTolerance: number,
  absoluteTolerance: number
): boolean {
  const allowed = Math.max(absoluteTolerance, Math.max(Math.abs(left), Math.abs(right)) * relativeTolerance);
  return Math.abs(left - right) <= allowed;
}

function payloadFromContribution(
  contribution: CommunityBarcodeContribution
): Record<string, unknown> {
  return {
    barcode: contribution.barcode,
    name: contribution.name,
    calories: contribution.calories,
    protein: contribution.protein,
    carbs: contribution.carbs,
    fats: contribution.fats,
    ...(contribution.fiber === undefined ? {} : { fiber: contribution.fiber }),
    servingSize: contribution.servingSize,
    servingWeight: contribution.servingWeight,
  };
}

function contributionFingerprint(contribution: CommunityBarcodeContribution): string {
  return [
    contribution.barcode,
    normalizeText(contribution.name),
    contribution.calories.toFixed(3),
    contribution.protein.toFixed(3),
    contribution.carbs.toFixed(3),
    contribution.fats.toFixed(3),
    contribution.fiber?.toFixed(3) ?? "",
    normalizeText(contribution.servingSize),
    contribution.servingWeight.toFixed(3),
  ].join("|");
}

function roundedMedian(values: readonly number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  const value = sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
  return Math.round(value * 10) / 10;
}

function modeText(values: readonly string[]): string {
  const grouped = new Map<string, string[]>();
  for (const value of values) {
    const normalized = normalizeText(value);
    const originals = grouped.get(normalized) ?? [];
    originals.push(value.trim());
    grouped.set(normalized, originals);
  }
  const groups = Array.from(grouped.entries()).sort((left, right) => {
    if (left[1].length !== right[1].length) {
      return right[1].length - left[1].length;
    }
    return left[0].localeCompare(right[0]);
  });
  return [...groups[0][1]].sort((left, right) => left.localeCompare(right))[0];
}

function normalizeText(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLocaleLowerCase("en-US");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  return typeof record[key] === "string" ? record[key] : undefined;
}

function readCleanText(
  record: Record<string, unknown>,
  key: string,
  maximumLength: number
): string | undefined {
  const rawValue = readString(record, key);
  if (rawValue === undefined || /[\u0000-\u001F\u007F]/.test(rawValue)) {
    return undefined;
  }
  const value = rawValue.trim().replace(/\s+/g, " ");
  if (!value || value.length > maximumLength) {
    return undefined;
  }
  return value;
}

function readNumber(
  record: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number
): number | undefined {
  const value = record[key];
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    return undefined;
  }
  return value;
}

function clamp(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) {
    return minimum;
  }
  return Math.min(Math.max(value, minimum), maximum);
}
