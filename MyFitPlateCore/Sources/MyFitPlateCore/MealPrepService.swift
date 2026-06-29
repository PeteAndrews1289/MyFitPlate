import Combine
import Foundation

public struct BulkIngredient: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let quantity: Double
    public let unit: String
    public let originalRecipes: [String]
}

@MainActor
public class MealPrepService: ObservableObject {
    public init() {}

    @Published public var bulkIngredients: [String: [BulkIngredient]] = [:]
    @Published public var prepSteps: [(recipeName: String, step: String)] = []

    public func aggregate(days: [MealPlanDay]) {
        var rawIngredients: [String: BulkIngredient] = [:]
        var allSteps: [(recipeName: String, step: String)] = []

        let allMeals = days.flatMap { $0.meals }

        for meal in allMeals {
            let recipeName = meal.foodItem?.name ?? meal.mealType

            if let ingredients = meal.ingredients {
                for ingredient in ingredients {
                    let parsed = IngredientLineParser.normalizedIngredient(from: ingredient)
                    guard !parsed.name.isEmpty else { continue }

                    let key = "\(IngredientNameMatcher.normalized(parsed.name))_\(parsed.unit)"

                    if let existing = rawIngredients[key] {
                        var combinedRecipes = existing.originalRecipes
                        if !combinedRecipes.contains(recipeName) {
                            combinedRecipes.append(recipeName)
                        }
                        rawIngredients[key] = BulkIngredient(
                            name: parsed.name,
                            quantity: existing.quantity + parsed.quantity,
                            unit: parsed.unit,
                            originalRecipes: combinedRecipes
                        )
                    } else {
                        rawIngredients[key] = BulkIngredient(
                            name: parsed.name,
                            quantity: parsed.quantity,
                            unit: parsed.unit,
                            originalRecipes: [recipeName]
                        )
                    }
                }
            }

            if let instructions = meal.instructions {
                let steps = instructions
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for step in steps {
                    let cleanStep = step
                        .replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)

                    if !cleanStep.isEmpty {
                        allSteps.append((recipeName: recipeName, step: cleanStep))
                    }
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
    }
}
