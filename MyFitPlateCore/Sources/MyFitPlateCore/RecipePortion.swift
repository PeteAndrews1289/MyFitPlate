import Foundation

/// One save intent is separate from a content revision: deliberately restoring old
/// content is a new operation, while transport retry keeps this exact proposal.
public struct RecipeRevisionSaveProposal: Codable {
    public let schemaVersion: Int
    public let userID: String
    public let operationID: UUID
    public let expected: Recipe?
    public let updated: Recipe
    public var editorScope: String?
    public var editorIdentity: String?
    public var editorFingerprint: String?
    public init(userID: String, operationID: UUID, expected: Recipe?, updated: Recipe,
                editorScope: String? = nil, editorIdentity: String? = nil, editorFingerprint: String? = nil) {
        self.schemaVersion = 1
        self.userID = userID; self.operationID = operationID; self.expected = expected; self.updated = updated
        self.editorScope = editorScope; self.editorIdentity = editorIdentity; self.editorFingerprint = editorFingerprint
    }
}

public enum RecipePortionUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case servings, cookedGrams, batchFraction, savedAmount
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .servings: return "Servings"
        case .cookedGrams: return "Cooked grams"
        case .batchFraction: return "Batch fraction"
        case .savedAmount: return "Saved amounts"
        }
    }
    public var quantityUnit: String {
        switch self {
        case .servings: return "serving"
        case .cookedGrams: return "g"
        case .batchFraction: return "batch"
        case .savedAmount: return "saved amount"
        }
    }
}

public struct RecipePortionSelection: Codable, Equatable, Hashable, Sendable {
    public var unit: RecipePortionUnit
    public var amount: Double
    public init(unit: RecipePortionUnit, amount: Double = 1) { self.unit = unit; self.amount = amount }
}

/// Original numeric ingredient requirements, independent of rounded display strings.
public struct RecipeIngredientQuantitySnapshot: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let amount: Double?
    public let unit: String?
    public let originalText: String

    fileprivate func display(multiplier: Double) -> String {
        guard let amount, let unit else { return originalText }
        let number = (amount * multiplier).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
        return "\(number) \(unit == "item" ? "" : unit + " ")\(name)"
    }
}

/// Self-contained evidence for a new consumed/planned portion. It never consults the latest recipe.
/// Ingredient display text and the source nutrition remain frozen even after library edits.
public struct RecipePortionSnapshot: Codable, Equatable, Hashable, Sendable {
    public let schemaVersion: Int
    public let recipeID: String?
    public let recipeRevisionID: String
    public let recipeName: String
    public let ingredients: [String]
    public let ingredientQuantities: [RecipeIngredientQuantitySnapshot]?
    public let sourceNutrition: Nutrition
    public let sourceBasis: RecipeNutritionBasis?
    /// Nil preserves ingredient scaling from snapshots made before separate quantity bases.
    public let sourceIngredientBasis: RecipeNutritionBasis?
    public let yieldServings: Double?
    public let cookedBatchWeightGrams: Double?
    public let selection: RecipePortionSelection
    public let servingsEquivalent: Double?
    public let batchFraction: Double?
    public let cookedGrams: Double?
    public let selectedNutrition: Nutrition
    public let nutritionAdjustedForThisLog: Bool
    public let portionRequiresReview: Bool
    public var importProvenance: RecipeImportProvenance?
    public var sourceInstructions: [String]?
    public var adjustedIngredientFoods: [FoodItem]?
    public var adjustedIngredientBasis: RecipeIngredientAdjustmentBasis?
    public var sourceIngredientFoods: [FoodItem]?
    public var sourceNutritionDerivedFromIngredients: Bool?
    public var sourceIngredientListComplete: Bool?

    public func scaled(by multiplier: Double, nutritionOverride: Nutrition? = nil) -> RecipePortionSnapshot? {
        guard schemaVersion == 1, multiplier.isFinite, multiplier > 0 else { return nil }
        let amount = selection.amount * multiplier
        guard amount.isFinite, amount > 0 else { return nil }
        return RecipePortionSnapshot(
            schemaVersion: schemaVersion, recipeID: recipeID, recipeRevisionID: recipeRevisionID,
            recipeName: recipeName, ingredients: ingredients, ingredientQuantities: ingredientQuantities, sourceNutrition: sourceNutrition,
            sourceBasis: sourceBasis, sourceIngredientBasis: sourceIngredientBasis,
            yieldServings: yieldServings, cookedBatchWeightGrams: cookedBatchWeightGrams,
            selection: RecipePortionSelection(unit: selection.unit, amount: amount),
            servingsEquivalent: servingsEquivalent.map { $0 * multiplier },
            batchFraction: batchFraction.map { $0 * multiplier }, cookedGrams: cookedGrams.map { $0 * multiplier },
            selectedNutrition: nutritionOverride ?? selectedNutrition.scaled(by: multiplier),
            nutritionAdjustedForThisLog: nutritionAdjustedForThisLog || nutritionOverride.map { $0 != selectedNutrition.scaled(by: multiplier) } == true,
            portionRequiresReview: portionRequiresReview, importProvenance: importProvenance,
            sourceInstructions: sourceInstructions, adjustedIngredientFoods: adjustedIngredientFoods,
            adjustedIngredientBasis: adjustedIngredientBasis, sourceIngredientFoods: sourceIngredientFoods,
            sourceNutritionDerivedFromIngredients: sourceNutritionDerivedFromIngredients,
            sourceIngredientListComplete: sourceIngredientListComplete
        )
    }
}

public enum RecipePortionError: Error, LocalizedError, Equatable {
    case invalidAmount, invalidYield, invalidCookedWeight, unconfirmedBasis, unsupportedUnit, invalidNutrition
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Enter a portion greater than zero within the supported range."
        case .invalidYield: return "Confirm a yield greater than zero, up to 100 servings."
        case .invalidCookedWeight: return "Enter the finished batch weight in grams, greater than zero."
        case .unconfirmedBasis: return "Confirm whether the saved nutrition describes the whole batch or one serving before using batch or gram portions."
        case .unsupportedUnit: return "This portion needs a confirmed yield and a measured cooked batch weight."
        case .invalidNutrition: return "Review the recipe nutrition before logging a portion."
        }
    }
}

public enum RecipePortionRules {
    public static func revisionID(for recipe: Recipe) throws -> String {
        var content = recipe
        // Identity is stored alongside the content revision. Retrieval/event clock values
        // cannot create a new recipe revision after Firestore's timestamp round trip.
        content.id = nil
        content.revisionID = nil
        content.libraryMetadata = nil
        if var provenance = content.importProvenance, let revisions = provenance.componentRevisions {
            provenance.componentRevisions = revisions.map { revision in
                var value = revision; value.generatedAt = canonicalProviderDate(value.generatedAt) ?? value.generatedAt
                return value
            }
            content.importProvenance = provenance
        }
        if let imported = content.importProvenance?.importedAt { content.importProvenance?.importedAt = Date(timeIntervalSince1970: (imported.timeIntervalSince1970 * 1_000).rounded() / 1_000) }
        if let reviewed = content.planningProfile?.reviewedAt { content.planningProfile?.reviewedAt = canonicalProviderDate(reviewed) }
        content.detailedIngredients = content.detailedIngredients?.map(revisionIngredient)
        content.linkedIngredients = content.linkedIngredients?.map(revisionIngredient)
        return try PlanFingerprint.make(content)
    }

    static func revisionIngredient(_ ingredient: FoodItem) -> FoodItem {
        var food = ingredient
        food.timestamp = nil
        if let imported = food.recipePortionSnapshot?.importProvenance?.importedAt {
            food.recipePortionSnapshot?.importProvenance?.importedAt = Date(timeIntervalSince1970: (imported.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        }
        if var metadata = food.sourceMetadata {
            metadata.createdAt = nil
            metadata.sourceObservedAt = nil
            metadata.sourceUpdatedAt = canonicalProviderDate(metadata.sourceUpdatedAt)
            metadata.crossVerificationEvidence = metadata.crossVerificationEvidence?.map { evidence in
                var value = evidence; value.observedAt = nil
                value.sourceUpdatedAt = canonicalProviderDate(value.sourceUpdatedAt)
                return value
            }
            if var evidence = metadata.nutrientReferenceEvidence {
                evidence.observedAt = nil
                evidence.sourceUpdatedAt = canonicalProviderDate(evidence.sourceUpdatedAt)
                metadata.nutrientReferenceEvidence = evidence
            }
            food.sourceMetadata = metadata
        }
        return food
    }

    private static func canonicalProviderDate(_ date: Date?) -> Date? {
        date.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 * 1_000).rounded() / 1_000) }
    }

    public static func availableUnits(for recipe: Recipe) -> [RecipePortionUnit] {
        guard recipe.nutritionBasis != nil, validYield(recipe.servings) else { return [.savedAmount] }
        var units: [RecipePortionUnit] = [.servings, .batchFraction]
        if validCookedWeight(recipe.cookedWeightGrams) { units.append(.cookedGrams) }
        return units
    }

    public static func defaultSelection(for recipe: Recipe) -> RecipePortionSelection {
        RecipePortionSelection(unit: availableUnits(for: recipe).first ?? .savedAmount)
    }

    public static func snapshot(
        for recipe: Recipe, selection: RecipePortionSelection,
        finalNutritionOverride: Nutrition? = nil, ingredientsAdjusted: Bool = false,
        adjustedIngredientFoods: [FoodItem]? = nil
    ) throws -> RecipePortionSnapshot {
        guard recipe.ingredientBasis == nil || recipe.nutritionBasis != nil else {
            throw RecipePortionError.unconfirmedBasis
        }
        guard recipe.importProvenance?.missingNutritionFields?.isEmpty != false || recipe.nutritionOrigin == .ingredients else {
            throw RecipePortionError.invalidNutrition
        }
        guard selection.amount.isFinite, selection.amount > 0,
              selection.amount <= (selection.unit == .cookedGrams ? 1_000_000 : 1_000) else {
            throw RecipePortionError.invalidAmount
        }
        let yield = validYield(recipe.servings) ? recipe.servings : nil
        let weight = validCookedWeight(recipe.cookedWeightGrams) ? recipe.cookedWeightGrams : nil
        var servings: Double?
        var fraction: Double?
        switch selection.unit {
        case .savedAmount:
            // An unconfirmed legacy yield is deliberately not adopted here.
            guard recipe.nutritionBasis == nil || !validYield(recipe.servings) else {
                throw RecipePortionError.unsupportedUnit
            }
        case .servings:
            guard recipe.nutritionBasis != nil, let yield else { throw RecipePortionError.unconfirmedBasis }
            servings = selection.amount; fraction = selection.amount / yield
        case .batchFraction:
            guard recipe.nutritionBasis != nil, let yield else { throw RecipePortionError.unconfirmedBasis }
            fraction = selection.amount; servings = selection.amount * yield
        case .cookedGrams:
            guard recipe.nutritionBasis != nil, let yield, let weight else { throw RecipePortionError.unsupportedUnit }
            fraction = selection.amount / weight; servings = selection.amount * yield / weight
        }
        let nutritionMultiplier: Double
        switch recipe.nutritionBasis {
        case .wholeRecipe: nutritionMultiplier = fraction ?? selection.amount
        case .perServing: nutritionMultiplier = servings ?? selection.amount
        case nil: nutritionMultiplier = selection.amount
        }
        let nutrition = finalNutritionOverride ?? recipe.nutrition.scaled(by: nutritionMultiplier)
        guard [nutrition.calories, nutrition.protein, nutrition.carbs, nutrition.fats].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw RecipePortionError.invalidNutrition
        }
        let grams = fraction.flatMap { fraction in weight.map { $0 * fraction } }
        return RecipePortionSnapshot(
            schemaVersion: 1, recipeID: recipe.id, recipeRevisionID: try revisionID(for: recipe),
            recipeName: recipe.name, ingredients: recipe.ingredients, ingredientQuantities: originalIngredientQuantities(for: recipe), sourceNutrition: recipe.nutrition,
            sourceBasis: recipe.nutritionBasis, sourceIngredientBasis: recipe.ingredientBasis,
            yieldServings: recipe.nutritionBasis == nil ? nil : yield,
            cookedBatchWeightGrams: recipe.nutritionBasis == nil ? nil : weight,
            selection: selection, servingsEquivalent: servings, batchFraction: fraction, cookedGrams: grams,
            selectedNutrition: nutrition, nutritionAdjustedForThisLog: ingredientsAdjusted, portionRequiresReview: false,
            importProvenance: recipe.importProvenance, sourceInstructions: recipe.instructions,
            adjustedIngredientFoods: adjustedIngredientFoods,
            adjustedIngredientBasis: adjustedIngredientFoods == nil ? nil : .originalRecipeAmounts,
            sourceIngredientFoods: recipe.resolvedIngredientFoods,
            sourceNutritionDerivedFromIngredients: recipe.nutritionOrigin.map { $0 == .ingredients }
                ?? (recipe.importProvenance?.kind == .structuredURL ? false : nil),
            sourceIngredientListComplete: recipe.hasCompleteIngredientNutrition
        )
    }

    public static func foodItem(
        for recipe: Recipe, selection: RecipePortionSelection, entryID: String = UUID().uuidString,
        finalNutritionOverride: Nutrition? = nil, ingredientsAdjusted: Bool = false,
        adjustedIngredientFoods: [FoodItem]? = nil
    ) throws -> FoodItem {
        let snapshot = try snapshot(for: recipe, selection: selection,
                                    finalNutritionOverride: finalNutritionOverride, ingredientsAdjusted: ingredientsAdjusted,
                                    adjustedIngredientFoods: adjustedIngredientFoods)
        var food = recipe.foodItemForLogging(portions: snapshot.servingsEquivalent ?? selection.amount,
                                             nutritionOverride: snapshot.selectedNutrition, entryID: entryID)
        food.quantityValue = selection.amount
        food.servingUnit = selection.unit.quantityUnit
        food.servingSize = "\(selection.amount.formatted(.number.precision(.fractionLength(0...3)))) \(selection.unit.quantityUnit)"
        food.servingWeight = snapshot.cookedGrams ?? 0
        food.recipePortionSnapshot = snapshot
        return food
    }

    public static func ingredients(for recipe: Recipe, selection: RecipePortionSelection) throws -> [String] {
        let snapshot = try snapshot(for: recipe, selection: selection)
        // Start from original recipe quantities, never from a rounded one-serving string.
        let multiplier = (recipe.ingredientBasis ?? recipe.nutritionBasis) == .wholeRecipe
            ? snapshot.batchFraction ?? selection.amount : snapshot.servingsEquivalent ?? selection.amount
        return originalIngredientQuantities(for: recipe).map { $0.display(multiplier: multiplier) }
    }

    public static func originalIngredientLines(for recipe: Recipe) -> [String] {
        originalIngredientQuantities(for: recipe).map { $0.display(multiplier: 1) }
    }

    public static func plannedIngredients(for snapshot: RecipePortionSnapshot, multiplier: Double) -> [ParsedIngredient]? {
        guard snapshot.schemaVersion == 1, !snapshot.portionRequiresReview, !snapshot.nutritionAdjustedForThisLog,
              multiplier.isFinite, multiplier > 0, let quantities = snapshot.ingredientQuantities,
              quantities.allSatisfy({ $0.amount.map { $0.isFinite && $0 > 0 } == true && $0.unit != nil }) else { return nil }
        let base = (snapshot.sourceIngredientBasis ?? snapshot.sourceBasis) == .wholeRecipe ? snapshot.batchFraction
            : snapshot.servingsEquivalent
        let factor = (base ?? snapshot.selection.amount) * multiplier
        guard factor.isFinite, factor > 0 else { return nil }
        return quantities.compactMap { ingredient in
            guard let amount = ingredient.amount, let unit = ingredient.unit else { return nil }
            return ParsedIngredient(quantity: amount * factor, unit: unit, name: ingredient.name,
                originalString: ingredient.display(multiplier: factor))
        }
    }

    private static func originalIngredientQuantities(for recipe: Recipe) -> [RecipeIngredientQuantitySnapshot] {
        let unresolved = recipe.unresolvedIngredientTexts.map { text in
            let parsed = IngredientParser.parse(text)
            let known = hasLeadingQuantity(text) && parsed.quantity.isFinite && parsed.quantity > 0
            return RecipeIngredientQuantitySnapshot(name: known ? parsed.name : text,
                amount: known ? parsed.quantity : nil, unit: known ? parsed.unit : nil, originalText: text)
        }
        let resolved = recipe.resolvedIngredientFoods.map { food -> RecipeIngredientQuantitySnapshot in
            let original = "\(food.servingSize) \(food.name)"
            if food.servingWeight.isFinite, food.servingWeight > 0 {
                return RecipeIngredientQuantitySnapshot(name: food.name, amount: food.servingWeight, unit: "g", originalText: original)
            }
            if let quantity = food.quantityValue, quantity.isFinite, quantity > 0,
               let unit = food.servingUnit, !unit.isEmpty {
                return RecipeIngredientQuantitySnapshot(name: food.name, amount: quantity, unit: unit, originalText: original)
            }
            let parsed = IngredientParser.parse(food.servingSize)
            let known = hasLeadingQuantity(food.servingSize) && parsed.quantity.isFinite && parsed.quantity > 0
            return RecipeIngredientQuantitySnapshot(name: known ? "\(parsed.name) \(food.name)" : food.name,
                amount: known ? parsed.quantity : nil, unit: known ? parsed.unit : nil, originalText: original)
        }
        return unresolved + resolved
    }

    private static func hasLeadingQuantity(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).first.map { $0.isNumber || "½⅓⅔¼¾⅛⅜⅝⅞".contains($0) } == true
    }

    private static func validYield(_ value: Double?) -> Bool {
        value.map { $0.isFinite && $0 > 0 && $0 <= 100 } ?? false
    }
    private static func validCookedWeight(_ value: Double?) -> Bool {
        value.map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } ?? false
    }
}

public extension FoodItem {
    /// Detail/custom-food editors construct a fresh value. Keep recipe evidence and reconcile
    /// the new amount without changing the source recipe or pretending an unknown unit converts.
    func preservingRecipePortion(from original: FoodItem, quantity: Double, unit: String) -> FoodItem {
        guard let snapshot = original.recipePortionSnapshot else { return self }
        var updated = self
        updated.recipePortionSnapshot = snapshot
        updated.quantityValue = quantity
        updated.servingUnit = unit
        guard snapshot.schemaVersion == 1 else {
            updated.sourceMetadata?.confidence = .needsReview
            updated.sourceMetadata?.notes = "Recipe portion evidence uses an unsupported version. Its source is kept; review the changed amount with a compatible app."
            return updated
        }
        let selected = Nutrition.total(for: [updated])
        let sameUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == (original.servingUnit ?? snapshot.selection.unit.quantityUnit).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let multiplier: Double?
        if updated.servingWeight.isFinite, updated.servingWeight > 0, original.servingWeight.isFinite, original.servingWeight > 0 {
            multiplier = updated.servingWeight / original.servingWeight
        } else if sameUnit, quantity.isFinite, quantity > 0,
                  let old = original.quantityValue, old.isFinite, old > 0 {
            multiplier = quantity / old
        } else { multiplier = nil }
        if let multiplier, let adjusted = snapshot.scaled(by: multiplier, nutritionOverride: selected) {
            updated.recipePortionSnapshot = adjusted
        } else {
            updated.recipePortionSnapshot = RecipePortionSnapshot(
                schemaVersion: snapshot.schemaVersion, recipeID: snapshot.recipeID,
                recipeRevisionID: snapshot.recipeRevisionID, recipeName: snapshot.recipeName,
                ingredients: snapshot.ingredients, ingredientQuantities: snapshot.ingredientQuantities, sourceNutrition: snapshot.sourceNutrition, sourceBasis: snapshot.sourceBasis,
                sourceIngredientBasis: snapshot.sourceIngredientBasis,
                yieldServings: snapshot.yieldServings, cookedBatchWeightGrams: snapshot.cookedBatchWeightGrams,
                selection: RecipePortionSelection(unit: .savedAmount, amount: quantity),
                servingsEquivalent: nil, batchFraction: nil, cookedGrams: nil, selectedNutrition: selected,
                nutritionAdjustedForThisLog: true, portionRequiresReview: true,
                importProvenance: snapshot.importProvenance, sourceInstructions: snapshot.sourceInstructions,
                adjustedIngredientFoods: snapshot.adjustedIngredientFoods, adjustedIngredientBasis: snapshot.adjustedIngredientBasis,
                sourceIngredientFoods: snapshot.sourceIngredientFoods,
                sourceNutritionDerivedFromIngredients: snapshot.sourceNutritionDerivedFromIngredients,
                sourceIngredientListComplete: snapshot.sourceIngredientListComplete
            )
            updated.sourceMetadata?.confidence = .needsReview
            updated.sourceMetadata?.notes = "The edited amount cannot be converted to the original recipe batch. Source recipe nutrition is retained separately."
        }
        return updated
    }
}
