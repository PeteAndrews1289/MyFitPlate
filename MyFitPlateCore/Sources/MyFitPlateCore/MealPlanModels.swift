import Foundation
public struct PlannedMeal: Identifiable, Codable, Sendable {
    public var id: String
    public var mealType: String
    public var recipeID: String?
    public var foodItem: FoodItem?
    public var ingredients: [String]?
    public var instructions: String?
    /// Personal portions relative to the original food and ingredient amounts. Legacy plans use one.
    public var portionMultiplier: Double?
    public var planningEvidence: PlannedMealEvidence?
    /// An explicitly planned household batch. Personal nutrition still uses `portionMultiplier`.
    public var cookingBatch: MealCookingBatch?
    public var preparedStock: PreparedMealStockReference?
    
    public init(id: String = UUID().uuidString, mealType: String, recipeID: String? = nil, foodItem: FoodItem? = nil, ingredients: [String]? = nil, instructions: String? = nil, portionMultiplier: Double? = nil, cookingBatch: MealCookingBatch? = nil) {
        self.id = id
        self.mealType = mealType
        self.recipeID = recipeID
        self.foodItem = foodItem
        self.ingredients = ingredients
        self.instructions = instructions
        self.portionMultiplier = portionMultiplier
        self.cookingBatch = cookingBatch
    }

    public var portions: Double {
        guard let value = portionMultiplier, value.isFinite, (0.25...8).contains(value) else { return 1 }
        return value
    }

    public var plannedFood: FoodItem? {
        foodItem.flatMap { FoodRepeatRules.adjusting($0, by: portions) }
    }

    public var plannedIngredients: [ParsedIngredient] {
        if let snapshot = foodItem?.recipePortionSnapshot,
           let ingredients = RecipePortionRules.plannedIngredients(for: snapshot, multiplier: portions) { return ingredients }
        return legacyPlannedIngredients
    }

    private var legacyPlannedIngredients: [ParsedIngredient] {
        (ingredients ?? []).map {
            let parsed = IngredientLineParser.normalizedIngredient(from: $0)
            return ParsedIngredient(quantity: parsed.quantity * portions, unit: parsed.unit,
                                    name: parsed.name, originalString: parsed.originalString)
        }
    }
}

public struct MealPlanDay: Identifiable, Codable, Sendable {
    public var id: String
    public var date: Date
    public var meals: [PlannedMeal]
    
    public init(id: String, date: Date, meals: [PlannedMeal]) {
        self.id = id
        self.date = date
        self.meals = meals
    }
}

public struct GroceryListItem: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var quantity: Double
    public var unit: String
    public var isCompleted: Bool = false
    public var category: String = "Misc"
    public var source: String?
    public var sourcePlanStart: Date?
    public var barcode: String?
    /// Explicitly reviewed purchased and transferred amounts; checking alone does not infer stock.
    public var purchasedQuantity: Double?
    public var transferredToPantryQuantity: Double?
    public var skippedForPlan: Bool?
    public var requirementKey: String?
    /// Unknown source ingredient quantities never become exact purchases from parser defaults.
    public var quantityUnknown: Bool?
    public var productSnapshot: GroceryProductSnapshot?
    public var quantityOverride: GroceryRequirementOverride?
    public var revisionID: String?
    public var unconvertedPurchases: [GroceryPurchaseAmount]?

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unit: String,
        isCompleted: Bool = false,
        category: String = "Misc",
        source: String? = nil,
        sourcePlanStart: Date? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isCompleted = isCompleted
        self.category = category
        self.source = source
        self.sourcePlanStart = sourcePlanStart
        self.barcode = barcode
    }
}

public enum GroceryUnitSystem: String, Codable {
    case imperial
    case metric
}
