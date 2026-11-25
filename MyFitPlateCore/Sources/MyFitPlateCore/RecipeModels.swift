import Foundation
public struct Nutrition: Codable, Equatable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fats: Double
    public var saturatedFat: Double?
    public var polyunsaturatedFat: Double?
    public var monounsaturatedFat: Double?
    public var fiber: Double?
    public var calcium: Double?
    public var iron: Double?
    public var potassium: Double?
    public var sodium: Double?
    public var vitaminA: Double?
    public var vitaminC: Double?
    public var vitaminD: Double?
    public var vitaminB12: Double?
    public var folate: Double?
    public var magnesium: Double?
    public var phosphorus: Double?
    public var zinc: Double?
    public var copper: Double?
    public var manganese: Double?
    public var selenium: Double?
    public var vitaminB1: Double?
    public var vitaminB2: Double?
    public var vitaminB3: Double?
    public var vitaminB5: Double?
    public var vitaminB6: Double?
    public var vitaminE: Double?
    public var vitaminK: Double?

    public init(
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fats: Double = 0,
        saturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        fiber: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        potassium: Double? = nil,
        sodium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        vitaminB12: Double? = nil,
        folate: Double? = nil,
        magnesium: Double? = nil,
        phosphorus: Double? = nil,
        zinc: Double? = nil,
        copper: Double? = nil,
        manganese: Double? = nil,
        selenium: Double? = nil,
        vitaminB1: Double? = nil,
        vitaminB2: Double? = nil,
        vitaminB3: Double? = nil,
        vitaminB5: Double? = nil,
        vitaminB6: Double? = nil,
        vitaminE: Double? = nil,
        vitaminK: Double? = nil
    ) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
        self.saturatedFat = saturatedFat; self.polyunsaturatedFat = polyunsaturatedFat; self.monounsaturatedFat = monounsaturatedFat; self.fiber = fiber
        self.calcium = calcium; self.iron = iron; self.potassium = potassium; self.sodium = sodium
        self.vitaminA = vitaminA; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminB12 = vitaminB12; self.folate = folate
        self.magnesium = magnesium; self.phosphorus = phosphorus; self.zinc = zinc; self.copper = copper; self.manganese = manganese; self.selenium = selenium
        self.vitaminB1 = vitaminB1; self.vitaminB2 = vitaminB2; self.vitaminB3 = vitaminB3; self.vitaminB5 = vitaminB5; self.vitaminB6 = vitaminB6
        self.vitaminE = vitaminE; self.vitaminK = vitaminK
    }

    public static var zero: Nutrition {
        Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0)
    }

    public var reportedVitaminMineralCount: Int {
        [
            calcium, iron, potassium, sodium, vitaminA, vitaminC, vitaminD, vitaminB12,
            folate, magnesium, phosphorus, zinc, copper, manganese, selenium, vitaminB1,
            vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminE, vitaminK
        ].compactMap { $0 }.count
    }

    public static func total(for foods: [FoodItem]) -> Nutrition {
        func optionalTotal(_ keyPath: KeyPath<FoodItem, Double?>) -> Double? {
            let values = foods.compactMap { $0[keyPath: keyPath] }
            return values.isEmpty ? nil : values.reduce(0, +)
        }

        return Nutrition(
            calories: foods.reduce(0) { $0 + $1.calories },
            protein: foods.reduce(0) { $0 + $1.protein },
            carbs: foods.reduce(0) { $0 + $1.carbs },
            fats: foods.reduce(0) { $0 + $1.fats },
            saturatedFat: optionalTotal(\.saturatedFat),
            polyunsaturatedFat: optionalTotal(\.polyunsaturatedFat),
            monounsaturatedFat: optionalTotal(\.monounsaturatedFat),
            fiber: optionalTotal(\.fiber),
            calcium: optionalTotal(\.calcium),
            iron: optionalTotal(\.iron),
            potassium: optionalTotal(\.potassium),
            sodium: optionalTotal(\.sodium),
            vitaminA: optionalTotal(\.vitaminA),
            vitaminC: optionalTotal(\.vitaminC),
            vitaminD: optionalTotal(\.vitaminD),
            vitaminB12: optionalTotal(\.vitaminB12),
            folate: optionalTotal(\.folate),
            magnesium: optionalTotal(\.magnesium),
            phosphorus: optionalTotal(\.phosphorus),
            zinc: optionalTotal(\.zinc),
            copper: optionalTotal(\.copper),
            manganese: optionalTotal(\.manganese),
            selenium: optionalTotal(\.selenium),
            vitaminB1: optionalTotal(\.vitaminB1),
            vitaminB2: optionalTotal(\.vitaminB2),
            vitaminB3: optionalTotal(\.vitaminB3),
            vitaminB5: optionalTotal(\.vitaminB5),
            vitaminB6: optionalTotal(\.vitaminB6),
            vitaminE: optionalTotal(\.vitaminE),
            vitaminK: optionalTotal(\.vitaminK)
        )
    }
}

public struct Recipe: Identifiable, Codable, Equatable, Sendable {
    public var id: String?
    public let name: String
    public let ingredients: [String]
    public var detailedIngredients: [FoodItem]?
    public let instructions: [String]
    public var nutrition: Nutrition
    public var servings: Double?
    public var imageURL: String?
    /// Nil is a legacy stored amount. Never reinterpret it using the old `servings` field.
    public var nutritionBasis: RecipeNutritionBasis?
    /// Quantity basis of the ingredient list, independent of the nutrition panel.
    /// Nil retains the recipe's original nutrition-basis ingredient behavior.
    public var ingredientBasis: RecipeNutritionBasis?
    public var nutritionOrigin: RecipeNutritionOrigin?
    /// Explicitly unresolved source text, separate from real zero-nutrient foods.
    public var unresolvedIngredients: [String]?
    /// Partial matches cannot occupy `detailedIngredients`: older clients treat that field as complete.
    public var linkedIngredients: [FoodItem]?
    public var nutritionNeedsReview: Bool?
    /// Measured weight of the finished, edible batch. Never inferred from raw ingredients.
    public var cookedWeightGrams: Double?
    /// Content revision for new edits. Legacy recipes retain an absent revision until edited.
    public var revisionID: String?
    public var planningProfile: RecipePlanningProfile?
    public var importProvenance: RecipeImportProvenance?
    /// Library organization never changes the recipe's nutritional content revision.
    public var libraryMetadata: RecipeLibraryMetadata?
    
    public init(id: String? = nil, name: String, ingredients: [String], detailedIngredients: [FoodItem]? = nil, instructions: [String], nutrition: Nutrition, servings: Double? = nil, imageURL: String? = nil, nutritionBasis: RecipeNutritionBasis? = nil, nutritionOrigin: RecipeNutritionOrigin? = nil, unresolvedIngredients: [String]? = nil, linkedIngredients: [FoodItem]? = nil, nutritionNeedsReview: Bool? = nil, cookedWeightGrams: Double? = nil, revisionID: String? = nil, ingredientBasis: RecipeNutritionBasis? = nil, libraryMetadata: RecipeLibraryMetadata? = nil) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
        self.detailedIngredients = detailedIngredients
        self.instructions = instructions
        self.nutrition = nutrition
        self.servings = servings
        self.imageURL = imageURL
        self.nutritionBasis = nutritionBasis
        self.ingredientBasis = ingredientBasis
        self.libraryMetadata = libraryMetadata
        self.nutritionOrigin = nutritionOrigin
        self.unresolvedIngredients = unresolvedIngredients
        self.linkedIngredients = linkedIngredients
        self.nutritionNeedsReview = nutritionNeedsReview
        self.cookedWeightGrams = cookedWeightGrams
        self.revisionID = revisionID
    }

    public var unresolvedIngredientTexts: [String] {
        unresolvedIngredients ?? (detailedIngredients?.isEmpty != false ? ingredients : [])
    }

    public var hasCompleteIngredientNutrition: Bool {
        unresolvedIngredientTexts.isEmpty && !resolvedIngredientFoods.isEmpty
    }

    public var resolvedIngredientFoods: [FoodItem] { linkedIngredients ?? detailedIngredients ?? [] }

    public var nutritionPerPortion: Nutrition {
        guard nutritionBasis == .wholeRecipe, let servings, servings.isFinite, servings > 0 else { return nutrition }
        return nutrition.scaled(by: 1 / servings)
    }

    public var portionUnit: String { nutritionBasis == nil ? "saved amount" : "serving" }

    public var nutritionBasisLabel: String {
        if importProvenance?.missingNutritionFields?.isEmpty == false { return "Nutrition incomplete · match ingredients before logging" }
        switch nutritionBasis {
        case .wholeRecipe:
            guard let servings, servings.isFinite, servings > 0 else { return "Whole-recipe nutrition · yield needs review" }
            return "Per serving · \(servings.formatted(.number.precision(.fractionLength(0...2)))) servings per recipe"
        case .perServing: return "Per serving"
        case nil: return "Saved nutrition · original serving basis unconfirmed"
        }
    }

    public var loggingSourceMetadata: FoodSourceMetadata {
        let estimated = nutritionOrigin != .ingredients || nutritionNeedsReview == true
            || resolvedIngredientFoods.contains(where: {
                $0.sourceMetadata == nil || $0.sourceMetadata?.confidence == .estimated
                    || $0.sourceMetadata?.confidence == .needsReview
                    || $0.sourceMetadata?.effectiveEvidenceLineage == .modelEstimate
            })
        return FoodSourceMetadata(
            sourceType: .recipe,
            originSourceType: nutritionOrigin == .aiEstimate ? .aiText : nil,
            confidence: estimated ? .estimated : .databaseMatch,
            reviewStatus: estimated ? .unreviewed : .notRequired,
            sourceName: nutritionOrigin == .aiEstimate ? "AI recipe estimate" : estimated ? "Recipe · source not confirmed" : "Recipe ingredients",
            sourceID: id,
            evidenceLineage: nutritionOrigin == .aiEstimate ? .modelEstimate : estimated ? .unknown : .derivedEntry,
            notes: nutritionBasisLabel
        )
    }
}

public enum RecipeNutritionBasis: String, Codable, Hashable, Sendable {
    case wholeRecipe
    case perServing
}

public enum RecipeNutritionOrigin: String, Codable, Sendable {
    case ingredients
    case aiEstimate
}

public extension Nutrition {
    func scaled(by multiplier: Double) -> Nutrition {
        var result = self
        result.calories *= multiplier; result.protein *= multiplier
        result.carbs *= multiplier; result.fats *= multiplier
        let optionalFields: [WritableKeyPath<Nutrition, Double?>] = [
            \.saturatedFat, \.polyunsaturatedFat, \.monounsaturatedFat, \.fiber,
            \.calcium, \.iron, \.potassium, \.sodium, \.vitaminA, \.vitaminC,
            \.vitaminD, \.vitaminB12, \.folate, \.magnesium, \.phosphorus,
            \.zinc, \.copper, \.manganese, \.selenium, \.vitaminB1, \.vitaminB2,
            \.vitaminB3, \.vitaminB5, \.vitaminB6, \.vitaminE, \.vitaminK
        ]
        for field in optionalFields { result[keyPath: field] = self[keyPath: field].map { $0 * multiplier } }
        return result
    }
}

/// A recipe edit never fabricates zero-nutrient placeholders for unresolved ingredients.
public struct RecipeEditingState {
    public enum NutritionChoice: String, CaseIterable { case keepSaved, recalculate }
    public enum YieldChoice: String, CaseIterable { case keepSaved, wholeRecipe, perServing }
    public var original: Recipe?
    public var ingredients: [FoodItem]
    public var unresolvedIngredients: [String]
    public var nutritionChoice: NutritionChoice
    public var servings: Double
    public var yieldChoice: YieldChoice
    public var cookedWeightGrams: Double?
    public var ingredientBasis: RecipeNutritionBasis?

    public init(recipe: Recipe? = nil) {
        original = recipe
        ingredients = recipe?.resolvedIngredientFoods ?? []
        unresolvedIngredients = recipe?.unresolvedIngredientTexts ?? []
        nutritionChoice = recipe == nil ? .recalculate : .keepSaved
        // An unused legacy yield must not retroactively divide its saved amount.
        servings = recipe?.nutritionBasis != nil ? recipe?.servings ?? 1 : 1
        yieldChoice = .keepSaved
        cookedWeightGrams = recipe?.cookedWeightGrams
        ingredientBasis = recipe?.ingredientBasis
    }

    public var canRecalculate: Bool { unresolvedIngredients.isEmpty && !ingredients.isEmpty }

    public var nutrition: Nutrition {
        nutritionChoice == .keepSaved ? original?.nutrition ?? .zero : Nutrition.total(for: ingredients)
    }

    public func makeRecipe(name: String, instructions: [String]) throws -> Recipe {
        guard nutritionChoice != .recalculate || (canRecalculate && servings.isFinite && servings > 0 && servings <= 100) else {
            throw RecipeIntegrityError.incompleteIngredients
        }
        let recalculating = nutritionChoice == .recalculate
        let confirmedIngredientBasis = ingredientBasis ?? (recalculating ? .wholeRecipe : original?.ingredientBasis)
        let confirmsYield = recalculating || yieldChoice != .keepSaved
        if confirmsYield {
            guard servings.isFinite, servings > 0, servings <= 100 else { throw RecipePortionError.invalidYield }
        }
        if let cookedWeightGrams {
            guard cookedWeightGrams.isFinite, cookedWeightGrams > 0, cookedWeightGrams <= 1_000_000 else {
                throw RecipePortionError.invalidCookedWeight
            }
            guard recalculating || yieldChoice != .keepSaved || original?.nutritionBasis != nil else {
                throw RecipePortionError.unconfirmedBasis
            }
        }
        let changed = try original.map {
            let before = try PlanFingerprint.make($0.resolvedIngredientFoods)
            let after = try PlanFingerprint.make(ingredients)
            return $0.ingredients != unresolvedIngredients + ingredients.map(\.name) || before != after
        } ?? false
        let aiIngredient = ingredients.contains { $0.sourceMetadata?.effectiveEvidenceLineage == .modelEstimate }
        let estimatedIngredient = aiIngredient || ingredients.contains {
            $0.sourceMetadata == nil || $0.sourceMetadata?.confidence == .estimated || $0.sourceMetadata?.confidence == .needsReview
        }
        var result = Recipe(
            id: original?.id, name: name,
            ingredients: unresolvedIngredients + ingredients.map(\.name),
            detailedIngredients: !unresolvedIngredients.isEmpty || ingredients.isEmpty ? nil : ingredients,
            instructions: instructions, nutrition: nutrition,
            servings: confirmsYield ? servings : original?.servings,
            imageURL: original?.imageURL,
            nutritionBasis: recalculating ? confirmedIngredientBasis : yieldChoice == .wholeRecipe ? .wholeRecipe
                : yieldChoice == .perServing ? .perServing : original?.nutritionBasis,
            nutritionOrigin: recalculating ? (aiIngredient ? .aiEstimate : .ingredients) : original?.nutritionOrigin,
            unresolvedIngredients: unresolvedIngredients,
            linkedIngredients: unresolvedIngredients.isEmpty || ingredients.isEmpty ? nil : ingredients,
            nutritionNeedsReview: recalculating ? estimatedIngredient : (original?.nutritionNeedsReview == true || changed || !unresolvedIngredients.isEmpty),
            cookedWeightGrams: cookedWeightGrams,
            ingredientBasis: confirmedIngredientBasis
        )
        result.importProvenance = original?.importProvenance
        result.libraryMetadata = original?.libraryMetadata
        if recalculating { result.importProvenance?.missingNutritionFields = nil }
        result.planningProfile = changed || instructions != original?.instructions ? nil : original?.planningProfile
        result.revisionID = try RecipePortionRules.revisionID(for: result)
        return result
    }
}

public enum RecipeIntegrityError: Error { case incompleteIngredients }

public enum RecipeIngredientQuantityRules {
    public static func adjustedIngredient(_ ingredient: FoodItem, newQuantity: Double) -> FoodItem? {
        guard newQuantity.isFinite, newQuantity > 0 else { return nil }
        let fallbackQuantity = ingredient.servingWeight > 0 ? ingredient.servingWeight : 1
        let oldQuantity = ingredient.quantityValue ?? fallbackQuantity
        guard oldQuantity.isFinite, oldQuantity > 0 else { return nil }

        var adjusted = ingredient.scalingNutritionAndServing(by: newQuantity / oldQuantity)
        adjusted.quantityValue = newQuantity
        return adjusted
    }
}

public extension Recipe {
    func foodItemForLogging(portions: Double = 1, nutritionOverride: Nutrition? = nil, entryID: String? = nil) -> FoodItem {
        let nutrition = nutritionOverride ?? nutritionPerPortion.scaled(by: portions)
        var food = FoodItem(
            id: entryID ?? id ?? UUID().uuidString,
            name: name,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbs: nutrition.carbs,
            fats: nutrition.fats,
            saturatedFat: nutrition.saturatedFat,
            polyunsaturatedFat: nutrition.polyunsaturatedFat,
            monounsaturatedFat: nutrition.monounsaturatedFat,
            fiber: nutrition.fiber,
            servingSize: "\(portions.formatted(.number.precision(.fractionLength(0...2)))) \(portionUnit)",
            servingWeight: 0,
            timestamp: nil,
            sourceMetadata: loggingSourceMetadata,
            calcium: nutrition.calcium,
            iron: nutrition.iron,
            potassium: nutrition.potassium,
            sodium: nutrition.sodium,
            vitaminA: nutrition.vitaminA,
            vitaminC: nutrition.vitaminC,
            vitaminD: nutrition.vitaminD,
            vitaminB12: nutrition.vitaminB12,
            folate: nutrition.folate,
            magnesium: nutrition.magnesium,
            phosphorus: nutrition.phosphorus,
            zinc: nutrition.zinc,
            copper: nutrition.copper,
            manganese: nutrition.manganese,
            selenium: nutrition.selenium,
            vitaminB1: nutrition.vitaminB1,
            vitaminB2: nutrition.vitaminB2,
            vitaminB3: nutrition.vitaminB3,
            vitaminB5: nutrition.vitaminB5,
            vitaminB6: nutrition.vitaminB6,
            vitaminE: nutrition.vitaminE,
            vitaminK: nutrition.vitaminK
        )
        food.quantityValue = portions
        food.servingUnit = portionUnit
        let selection = RecipePortionSelection(unit: nutritionBasis == nil ? .savedAmount : .servings, amount: portions)
        food.recipePortionSnapshot = try? RecipePortionRules.snapshot(for: self, selection: selection, finalNutritionOverride: nutrition)
        food.servingWeight = food.recipePortionSnapshot?.cookedGrams ?? 0
        return food
    }
}
