import Foundation

public struct RecipeComponentRevision: Codable, Equatable, Hashable, Sendable {
    public var component: String
    public var generatedAt: Date
    public var promptSchemaVersion: Int
    public var sourceContentRevision: String
    public init(component: String, generatedAt: Date = Date(), promptSchemaVersion: Int = 1, sourceContentRevision: String) {
        self.component = component
        self.generatedAt = Date(timeIntervalSince1970: (generatedAt.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        self.promptSchemaVersion = promptSchemaVersion; self.sourceContentRevision = sourceContentRevision
    }
}

public enum RecipeIngredientAdjustmentBasis: String, Codable, Equatable, Hashable, Sendable {
    /// Foods describe the original recipe ingredient list, before the eaten-portion multiplier.
    case originalRecipeAmounts
}

public enum RecipeVariationRules {
    public static func variation(from food: FoodItem) throws -> Recipe {
        guard let snapshot = food.recipePortionSnapshot,
              snapshot.adjustedIngredientBasis == .originalRecipeAmounts,
              let ingredients = snapshot.adjustedIngredientFoods, !ingredients.isEmpty,
              ingredients.allSatisfy(MyFoodsLibraryRules.isValidSavedSnapshot) else { throw RecipeIntegrityError.incompleteIngredients }
        let basis = snapshot.sourceIngredientBasis ?? snapshot.sourceBasis ?? .wholeRecipe
        let source = Recipe(name: snapshot.recipeName + " variation", ingredients: ingredients.map(\.name),
            detailedIngredients: ingredients, instructions: snapshot.sourceInstructions ?? [],
            nutrition: Nutrition.total(for: ingredients), servings: snapshot.yieldServings ?? 1,
            nutritionBasis: basis, nutritionOrigin: .ingredients, unresolvedIngredients: [], ingredientBasis: basis)
        var edit = RecipeEditingState(recipe: source)
        edit.nutritionChoice = .recalculate; edit.ingredientBasis = basis; edit.cookedWeightGrams = nil
        var result = try edit.makeRecipe(name: source.name, instructions: source.instructions)
        result.id = nil; result.libraryMetadata = nil
        result.importProvenance = snapshot.importProvenance
        if result.importProvenance != nil {
            var revisions = result.importProvenance?.componentRevisions ?? []
            revisions.append(RecipeComponentRevision(component: "ingredientAmounts", promptSchemaVersion: 0,
                sourceContentRevision: snapshot.recipeRevisionID))
            result.importProvenance?.componentRevisions = revisions
            result.importProvenance?.missingNutritionFields = nil
        }
        result.revisionID = try RecipePortionRules.revisionID(for: result)
        return result
    }
}

public enum RecipeComponentRules {
    public enum Component: String, CaseIterable, Identifiable, Sendable {
        case title, instructions, ingredientNutrition
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .title: "Title"
            case .instructions: "Instructions"
            case .ingredientNutrition: "Recalculate ingredient nutrition"
            }
        }
    }
    public static func applying(_ component: Component, from generated: Recipe?, to original: Recipe) throws -> Recipe {
        if component == .ingredientNutrition {
            var edit = RecipeEditingState(recipe: original); edit.nutritionChoice = .recalculate
            var updated = try edit.makeRecipe(name: original.name, instructions: original.instructions)
            updated.cookedWeightGrams = original.cookedWeightGrams
            return try stamped(updated, source: original, component: component, schema: 0)
        }
        guard let generated else { throw RecipeIntegrityError.incompleteIngredients }
        if component == .instructions {
            let normalize: (String) -> String = { $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            guard RecipePortionRules.originalIngredientLines(for: original).map(normalize) == generated.ingredients.map(normalize) else {
                throw RecipeComponentError.changedIngredients
            }
        }
        let name = component == .title ? generated.name.trimmingCharacters(in: .whitespacesAndNewlines) : original.name
        let instructions = component == .instructions ? generated.instructions : original.instructions
        guard !name.isEmpty, name.count <= 200, !instructions.isEmpty,
              instructions.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 10_000 }) else { throw RecipeIntegrityError.incompleteIngredients }
        var updated = Recipe(id: original.id, name: name, ingredients: original.ingredients,
            detailedIngredients: original.detailedIngredients, instructions: instructions, nutrition: original.nutrition,
            servings: original.servings, imageURL: original.imageURL, nutritionBasis: original.nutritionBasis,
            nutritionOrigin: original.nutritionOrigin, unresolvedIngredients: original.unresolvedIngredients,
            linkedIngredients: original.linkedIngredients, nutritionNeedsReview: original.nutritionNeedsReview,
            cookedWeightGrams: original.cookedWeightGrams, ingredientBasis: original.ingredientBasis)
        updated.planningProfile = original.planningProfile
        updated.planningProfile?.reviewedAt = nil; updated.planningProfile?.contentFingerprint = nil
        updated.libraryMetadata = original.libraryMetadata
        return try stamped(updated, source: original, component: component, schema: 1)
    }
    private static func stamped(_ updated: Recipe, source: Recipe, component: Component, schema: Int) throws -> Recipe {
        var result = updated
        if source.importProvenance == nil && schema == 0 {
            result.importProvenance = nil
            result.revisionID = try RecipePortionRules.revisionID(for: result)
            return result
        }
        result.importProvenance = source.importProvenance ?? RecipeImportProvenance(kind: .ai)
        var revisions = result.importProvenance?.componentRevisions ?? []
        revisions.append(RecipeComponentRevision(component: component.rawValue, promptSchemaVersion: schema,
            sourceContentRevision: try RecipePortionRules.revisionID(for: source)))
        result.importProvenance?.componentRevisions = revisions
        result.revisionID = try RecipePortionRules.revisionID(for: result)
        return result
    }
}

public enum RecipeComponentError: Error, LocalizedError {
    case changedIngredients
    public var errorDescription: String? {
        "Maia changed the ingredient list while revising instructions. The original recipe is kept. Retry or edit the instructions manually; new ingredients cannot inherit the saved nutrition."
    }
}
