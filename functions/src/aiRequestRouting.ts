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
  maxOutputTokens: number;
  reasoningEffort?: "none" | "low";
  forcedResponseFormat?: Record<string, unknown>;
  usageCollection?: string;
  dailyLimit?: number;
}

const GENERAL_MODEL = "gpt-4o-mini";
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
        maxOutputTokens: 3_000,
        reasoningEffort: "low",
        forcedResponseFormat: { type: "json_object" },
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "nutrition_label":
      return {
        kind,
        model: "gpt-5.6-luna",
        maxOutputTokens: 3_000,
        reasoningEffort: "low",
        forcedResponseFormat: { type: "json_object" },
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "receipt_photo":
      return {
        kind,
        model: "gpt-5.6-luna",
        maxOutputTokens: 2_400,
        reasoningEffort: "none",
        forcedResponseFormat: { type: "json_object" },
        usageCollection: VISION_USAGE_COLLECTION,
        dailyLimit: VISION_DAILY_LIMIT,
      };
    case "recipe_photo":
      return {
        kind,
        model: "gpt-5.6-luna",
        maxOutputTokens: 2_400,
        reasoningEffort: "low",
        forcedResponseFormat: { type: "json_object" },
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
  return route.model.startsWith("gpt-5.");
}
