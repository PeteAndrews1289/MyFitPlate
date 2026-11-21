import Combine
import Foundation

public struct BulkIngredient: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let quantity: Double
    public let unit: String
    public let originalRecipes: [String]
    public var quantityUnknown: Bool = false
}

@MainActor
public class MealPrepService: ObservableObject {
    public init() {}

    @Published public var bulkIngredients: [String: [BulkIngredient]] = [:]
    @Published public var prepSteps: [(recipeName: String, step: String)] = []
    @Published public var structuredSteps: [CookingSessionStep] = []

    public func aggregate(days: [MealPlanDay], starting startDate: Date? = nil, selectedRequirementIDs: Set<String>? = nil) {
        var rawIngredients: [String: BulkIngredient] = [:]
        var allSteps: [(recipeName: String, step: String)] = []
        var structured: [CookingSessionStep] = []

        let requirements = MealPlanCookingRules.requirements(from: days, starting: startDate)

        for requirement in requirements {
            let recipeName = requirement.name

            if !requirement.ingredients.isEmpty, selectedRequirementIDs?.contains(requirement.id) ?? true {
                for parsed in requirement.ingredients {
                    guard !parsed.name.isEmpty else { continue }

                    let unknown = InventoryQuantityRules.explicitLeadingAmount(parsed.originalString) == nil
                    let key = GroceryListBuilder.requirementIdentity(name: parsed.name, unit: parsed.unit) + (unknown ? "|unknown" : "")

                    if let existing = rawIngredients[key] {
                        var combinedRecipes = existing.originalRecipes
                        if !combinedRecipes.contains(recipeName) {
                            combinedRecipes.append(recipeName)
                        }
                        rawIngredients[key] = BulkIngredient(
                            name: parsed.name,
                            quantity: existing.quantity + (InventoryQuantityRules.convert(parsed.quantity, from: parsed.unit, to: existing.unit) ?? parsed.quantity),
                            unit: existing.unit,
                            originalRecipes: combinedRecipes, quantityUnknown: unknown
                        )
                    } else {
                        rawIngredients[key] = BulkIngredient(
                            name: parsed.name,
                            quantity: parsed.quantity,
                            unit: parsed.unit,
                            originalRecipes: [recipeName], quantityUnknown: unknown
                        )
                    }
                }
            }

            // Explicit shared batches have already been deduplicated by the cooking rules.
            // Independent meals retain their own steps, even when their recipes are identical.
            if let instructions = requirement.instructions {
                structured += CookingSessionRules.steps(requirements: [requirement])
                for step in MealSuggestionReviewRules.instructionSteps(instructions) {
                    allSteps.append((recipeName: recipeName, step: step))
                }
            }
        }

        var grouped: [String: [BulkIngredient]] = [:]
        for bulkIngredient in rawIngredients.values {
            let category = IngredientCategoryMapper.mealPrepCategory(for: bulkIngredient.name)
            grouped[category, default: []].append(bulkIngredient)
        }

        for (category, items) in grouped {
            grouped[category] = items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        self.bulkIngredients = grouped
        self.prepSteps = allSteps
        self.structuredSteps = structured
    }
}
