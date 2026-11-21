import Foundation

public struct MealSuggestion: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let calories: Double
    public let mealName: String
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let ingredients: [String]
    public let instructions: String
    public let prepMinutes: Int?
    public let feasibility: MealSuggestionFeasibility?
    
    public init(id: UUID = UUID(), title: String, calories: Double, mealName: String, protein: Double, carbs: Double, fats: Double, ingredients: [String] = [], instructions: String = "", prepMinutes: Int? = nil, feasibility: MealSuggestionFeasibility? = nil) {
        self.id = id
        self.title = title
        self.calories = calories
        self.mealName = mealName
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.ingredients = ingredients
        self.instructions = instructions
        self.prepMinutes = prepMinutes; self.feasibility = feasibility
    }

    // The AI response contains only the keys the prompt asks for: mealName, calories,
    // protein, carbs, fats, ingredients, instructions. The synthesized decoder demanded
    // "id" and "title" too, so EVERY generated suggestion failed to decode — the feature
    // was dead on arrival. Decode defensively: id is minted locally, title falls back to
    // the meal name, and the optional extras tolerate absence.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mealName = try container.decode(String.self, forKey: .mealName)

        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.mealName = mealName
        self.title = (try? container.decode(String.self, forKey: .title)) ?? mealName
        self.calories = try container.decode(Double.self, forKey: .calories)
        self.protein = try container.decode(Double.self, forKey: .protein)
        self.carbs = try container.decode(Double.self, forKey: .carbs)
        self.fats = try container.decode(Double.self, forKey: .fats)
        self.ingredients = (try? container.decode([String].self, forKey: .ingredients)) ?? []
        self.instructions = (try? container.decode(String.self, forKey: .instructions)) ?? ""
        self.prepMinutes = try container.decodeIfPresent(Int.self, forKey: .prepMinutes)
        self.feasibility = try container.decodeIfPresent(MealSuggestionFeasibility.self, forKey: .feasibility)
    }
}

public extension MealSuggestion {
    func withGeneratedEvidence(now: Date = Date()) -> MealSuggestion {
        MealSuggestion(id: id, title: title, calories: calories, mealName: mealName, protein: protein, carbs: carbs, fats: fats,
            ingredients: ingredients, instructions: instructions, prepMinutes: prepMinutes,
            feasibility: MealSuggestionFeasibilityRules.generatedEvidence(for: self, now: now))
    }

    var recipeDraft: Recipe? {
        guard reviewFood != nil else { return nil }
        return Recipe(name: mealName, ingredients: ingredients, instructions: instructions.components(separatedBy: "\n").filter { !$0.isEmpty },
            nutrition: Nutrition(calories: calories, protein: protein, carbs: carbs, fats: fats), servings: 1,
            nutritionBasis: .perServing, nutritionOrigin: .aiEstimate, unresolvedIngredients: ingredients,
            nutritionNeedsReview: true, ingredientBasis: .wholeRecipe)
    }

    /// Provider identity is separate from the stable logging entry created by the review.
    var reviewFood: FoodItem? {
        guard !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [calories, protein, carbs, fats].allSatisfy({ $0.isFinite && $0 >= 0 }),
              calories > 0 || protein + carbs + fats > 0 else { return nil }
        var food = FoodItem(id: id.uuidString, name: mealName, calories: calories,
                        protein: protein, carbs: carbs, fats: fats,
                        servingSize: "1 serving (Maia estimate)", servingWeight: 0)
            .withAIEstimateSource(.aiChat, sourceName: "Maia Suggestion")
        food.sourceMetadata?.mealSuggestionEvidence = feasibility ?? MealSuggestionFeasibilityRules.generatedEvidence(for: self)
        return food
    }

    @MainActor
    func makeReview(userID: String, day: DiaryDayContext, source: String,
                    meal: String = DailyLogRules.determineMealType(),
                    trainingFuelTarget: TrainingFuelTarget? = nil,
                    store: EditorDraftStore = EditorDraftStore()) -> MealReviewSaveSession {
        MealReviewSaveSession(items: reviewFood.map { [$0] } ?? [], userID: userID,
                              date: day.originalDate, mealName: meal, source: source,
                              confirmingSourceType: .aiChat, dayContext: day, store: store,
                              trainingFuelTarget: trainingFuelTarget, mealSuggestion: self)
    }
}

public extension MealReviewSaveSession {
    @MainActor
    static func resumeMealSuggestion(source: String, userID: String?,
                                     store: EditorDraftStore = EditorDraftStore()) -> MealReviewSaveSession? {
        guard let userID, let saved = pendingReview(source: source, userID: userID, store: store),
              saved.mealSuggestion != nil else { return nil }
        return MealReviewSaveSession(items: [], userID: userID, date: saved.draft.date,
                                     mealName: saved.draft.mealName, source: source,
                                     confirmingSourceType: .aiChat, store: store)
    }
}
