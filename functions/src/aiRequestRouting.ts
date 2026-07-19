export type AIRequestKind =
  | "general"
  | "meal_photo"
  | "nutrition_label"
  | "menu_photo"
  | "receipt_photo"
  | "recipe_photo";

export interface AIRequestRoute {
  kind: AIRequestKind;
  model: string;
  fallbackModels?: string[];
  maxOutputTokens: number;
  reasoningEffort?: "none" | "low";
  forcedResponseFormat?: Record<string, unknown>;
  usageCollection?: string;
  dailyLimit?: number;
}

export type AIVisionRouteConfiguration = Partial<Record<AIRequestKind, boolean>>;

const GENERAL_MODEL = "gpt-4o-mini";
const VISION_FALLBACK_MODEL = "gpt-4o-mini";
const VISION_USAGE_COLLECTION = "aiVisionUsage";
const VISION_DAILY_LIMIT = 75;

const mealPhotoResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "meal_photo_analysis",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: [
        "imageUsable",
        "overallConfidence",
        "analysisNotes",
        "clarificationQuestions",
        "foods",
      ],
      properties: {
        imageUsable: { type: "boolean" },
        overallConfidence: { type: "number", minimum: 0, maximum: 1 },
        analysisNotes: { type: "string" },
        clarificationQuestions: {
          type: "array",
          maxItems: 2,
          items: { type: "string" },
        },
        foods: {
          type: "array",
          maxItems: 20,
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "itemName",
              "preparation",
              "servingSize",
              "estimatedGrams",
              "portionLowGrams",
              "portionHighGrams",
              "calories",
              "protein",
              "carbs",
              "fats",
              "confidence",
              "visibleEvidence",
              "hiddenIngredientRisks",
              "requiresConfirmation",
              "clarificationQuestion",
            ],
            properties: {
              itemName: { type: "string" },
              preparation: { type: "string" },
              servingSize: { type: "string" },
              estimatedGrams: { type: ["number", "null"], minimum: 0 },
              portionLowGrams: { type: ["number", "null"], minimum: 0 },
              portionHighGrams: { type: ["number", "null"], minimum: 0 },
              calories: { type: "number", minimum: 0 },
              protein: { type: "number", minimum: 0 },
              carbs: { type: "number", minimum: 0 },
              fats: { type: "number", minimum: 0 },
              confidence: { type: "number", minimum: 0, maximum: 1 },
              visibleEvidence: { type: "string" },
              hiddenIngredientRisks: {
                type: "array",
                maxItems: 5,
                items: { type: "string" },
              },
              requiresConfirmation: { type: "boolean" },
              clarificationQuestion: { type: ["string", "null"] },
            },
          },
        },
      },
    },
  },
};

const nutritionLabelResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "nutrition_label_extraction",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: [
        "foodName",
        "servingDescription",
        "servingWeightGrams",
        "calories",
        "protein",
        "carbs",
        "fats",
        "saturatedFat",
        "polyunsaturatedFat",
        "monounsaturatedFat",
        "fiber",
        "calcium",
        "iron",
        "potassium",
        "sodium",
        "vitaminA",
        "vitaminC",
        "vitaminD",
        "vitaminB12",
        "folate",
        "magnesium",
        "phosphorus",
        "zinc",
        "copper",
        "manganese",
        "selenium",
        "vitaminB1",
        "vitaminB2",
        "vitaminB3",
        "vitaminB5",
        "vitaminB6",
        "vitaminE",
        "vitaminK",
      ],
      properties: {
        foodName: { type: "string" },
        servingDescription: { type: ["string", "null"] },
        servingWeightGrams: { type: ["number", "null"], minimum: 0 },
        calories: { type: "number", minimum: 0 },
        protein: { type: "number", minimum: 0 },
        carbs: { type: "number", minimum: 0 },
        fats: { type: "number", minimum: 0 },
        saturatedFat: { type: ["number", "null"], minimum: 0 },
        polyunsaturatedFat: { type: ["number", "null"], minimum: 0 },
        monounsaturatedFat: { type: ["number", "null"], minimum: 0 },
        fiber: { type: ["number", "null"], minimum: 0 },
        calcium: { type: ["number", "null"], minimum: 0 },
        iron: { type: ["number", "null"], minimum: 0 },
        potassium: { type: ["number", "null"], minimum: 0 },
        sodium: { type: ["number", "null"], minimum: 0 },
        vitaminA: { type: ["number", "null"], minimum: 0 },
        vitaminC: { type: ["number", "null"], minimum: 0 },
        vitaminD: { type: ["number", "null"], minimum: 0 },
        vitaminB12: { type: ["number", "null"], minimum: 0 },
        folate: { type: ["number", "null"], minimum: 0 },
        magnesium: { type: ["number", "null"], minimum: 0 },
        phosphorus: { type: ["number", "null"], minimum: 0 },
        zinc: { type: ["number", "null"], minimum: 0 },
        copper: { type: ["number", "null"], minimum: 0 },
        manganese: { type: ["number", "null"], minimum: 0 },
        selenium: { type: ["number", "null"], minimum: 0 },
        vitaminB1: { type: ["number", "null"], minimum: 0 },
        vitaminB2: { type: ["number", "null"], minimum: 0 },
        vitaminB3: { type: ["number", "null"], minimum: 0 },
        vitaminB5: { type: ["number", "null"], minimum: 0 },
        vitaminB6: { type: ["number", "null"], minimum: 0 },
        vitaminE: { type: ["number", "null"], minimum: 0 },
        vitaminK: { type: ["number", "null"], minimum: 0 },
      },
    },
  },
};

const menuPhotoResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "menu_photo_extraction",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["foods"],
      properties: {
        foods: {
          type: "array",
          maxItems: 80,
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "itemName",
              "servingSize",
              "calories",
              "protein",
              "carbs",
              "fats",
              "price",
            ],
            properties: {
              itemName: { type: "string" },
              servingSize: { type: "string" },
              calories: { type: "number", minimum: 0 },
              protein: { type: "number", minimum: 0 },
              carbs: { type: "number", minimum: 0 },
              fats: { type: "number", minimum: 0 },
              price: { type: ["number", "null"], minimum: 0 },
            },
          },
        },
      },
    },
  },
};

const receiptPhotoResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "receipt_photo_extraction",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["items"],
      properties: {
        items: {
          type: "array",
          maxItems: 120,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["name", "quantity", "unit", "category"],
            properties: {
              name: { type: "string" },
              quantity: { type: "number", minimum: 0 },
              unit: { type: "string" },
              category: { type: "string" },
            },
          },
        },
      },
    },
  },
};

const recipePhotoResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "pantry_recipe_photo_analysis",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["recipes"],
      properties: {
        recipes: {
          type: "array",
          minItems: 3,
          maxItems: 3,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["title", "description", "calories", "protein", "carbs", "fats"],
            properties: {
              title: { type: "string" },
              description: { type: "string" },
              calories: { type: "number", minimum: 0 },
              protein: { type: "number", minimum: 0 },
              carbs: { type: "number", minimum: 0 },
              fats: { type: "number", minimum: 0 },
            },
          },
        },
      },
    },
  },
};

export function normalizeAIRequestKind(value: unknown): AIRequestKind {
  switch (value) {
    case "meal_photo":
    case "nutrition_label":
    case "menu_photo":
    case "receipt_photo":
    case "recipe_photo":
      return value;
    default:
      return "general";
  }
}

export function resolveAIRequestRoute(value: unknown): AIRequestRoute {
  const kind = normalizeAIRequestKind(value);
  switch (kind) {
    case "meal_photo":
      return {
        kind,
        model: "gpt-5.6-terra",
        fallbackModels: [VISION_FALLBACK_MODEL],
        maxOutputTokens: 4_000,
        reasoningEffort: "low",
        forcedResponseFormat: mealPhotoResponseFormat,
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "menu_photo":
      return {
        kind,
        model: "gpt-5.6-terra",
        fallbackModels: [VISION_FALLBACK_MODEL],
        maxOutputTokens: 3_000,
        reasoningEffort: "low",
        forcedResponseFormat: menuPhotoResponseFormat,
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "nutrition_label":
      return {
        kind,
        model: "gpt-5.6-luna",
        fallbackModels: [VISION_FALLBACK_MODEL],
        maxOutputTokens: 3_000,
        reasoningEffort: "low",
        forcedResponseFormat: nutritionLabelResponseFormat,
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "receipt_photo":
      return {
        kind,
        model: "gpt-5.6-luna",
        fallbackModels: [VISION_FALLBACK_MODEL],
        maxOutputTokens: 2_400,
        reasoningEffort: "none",
        forcedResponseFormat: receiptPhotoResponseFormat,
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "recipe_photo":
      return {
        kind,
        model: "gpt-5.6-luna",
        fallbackModels: [VISION_FALLBACK_MODEL],
        maxOutputTokens: 2_400,
        reasoningEffort: "low",
        forcedResponseFormat: recipePhotoResponseFormat,
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "general":
      return {
        kind,
        model: GENERAL_MODEL,
        maxOutputTokens: 6_000,
      };
  }
}

export function isReasoningRoute(route: AIRequestRoute): boolean {
  return isReasoningModel(route.model);
}

export function isReasoningModel(model: string): boolean {
  return model.startsWith("gpt-5.");
}

export function resolveAIRequestModels(route: AIRequestRoute): string[] {
  return [route.model, ...(route.fallbackModels ?? [])]
    .filter((model, index, models) => models.indexOf(model) === index);
}

/// Only model-availability failures may move to a lower-cost fallback. Authentication,
/// quota, schema, and provider-service errors must remain visible instead of being masked.
export function isAIModelAvailabilityError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }

  const candidate = error as {
    status?: unknown;
    code?: unknown;
    error?: { code?: unknown; type?: unknown };
  };
  const status = typeof candidate.status === "number" ? candidate.status : undefined;
  const code = typeof candidate.code === "string"
    ? candidate.code
    : typeof candidate.error?.code === "string"
      ? candidate.error.code
      : undefined;

  return status === 404 || code === "model_not_found";
}

/// A missing document or field intentionally means enabled so a deployment does not depend on
/// operator configuration. Setting one route to false disables only that route.
export function isAIRequestRouteEnabled(
  kind: AIRequestKind,
  configuration: AIVisionRouteConfiguration | undefined
): boolean {
  if (kind === "general") {
    return true;
  }
  return configuration?.[kind] !== false;
}
