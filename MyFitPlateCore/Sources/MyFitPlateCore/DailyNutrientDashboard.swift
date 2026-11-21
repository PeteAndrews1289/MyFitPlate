import Foundation

public struct DailyNutrientContribution: Identifiable, Sendable {
    public let id: String
    public let mealName: String
    public let food: FoodItem
    public let amount: Double?
    public let reportingComplete: Bool
    public let reportingNote: String?
}

public struct DailyNutrientEvidence: Sendable {
    public let key: MicronutrientKey
    public let amount: Double?
    public let coverage: MicronutrientCoverage
    public let contributions: [DailyNutrientContribution]
    public var isUpperLimit: Bool { key == .sodium }
    public var coverageDescription: String {
        if coverage.totalFoodCount == 0 { return "No foods recorded" }
        if amount == nil { return "Not reported by any of \(coverage.totalFoodCount) foods" }
        let partial = contributions.filter { $0.amount != nil && !$0.reportingComplete }.count
        if partial > 0 { return "Partial derived data · \(coverage.reportedFoodCount) of \(coverage.totalFoodCount) foods fully report; \(partial) contain missing component evidence" }
        if coverage.isComplete { return "Reported by all \(coverage.totalFoodCount) foods" }
        return "Partial data · \(coverage.reportedFoodCount) of \(coverage.totalFoodCount) foods report this nutrient"
    }
    public func exceedsLimit(_ limit: Double?) -> Bool {
        guard isUpperLimit, let amount, let limit, limit.isFinite, limit > 0 else { return false }
        return amount > limit
    }
}

public enum DailyNutrientDashboardRules {
    public static func evidence(for key: MicronutrientKey, log: DailyLog) -> DailyNutrientEvidence {
        let contributions = log.meals.flatMap { meal in
            meal.foodItems.enumerated().map { index, food in
                let value = food.micronutrientValue(for: key).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                let complete = reportingComplete(food, key: key, depth: 0)
                return DailyNutrientContribution(id: "\(meal.id)-\(food.id)-\(index)", mealName: meal.name, food: food, amount: value,
                    reportingComplete: complete,
                    reportingNote: value != nil && !complete ? "This logged amount includes partial or unavailable component reporting. Missing values were not assumed to be zero." : nil)
            }
        }.sorted { ($0.amount ?? -1) > ($1.amount ?? -1) }
        let completeCount = contributions.filter { $0.amount != nil && $0.reportingComplete }.count
        let amounts = contributions.compactMap(\.amount)
        return DailyNutrientEvidence(key: key, amount: amounts.isEmpty ? nil : amounts.reduce(0, +),
            coverage: MicronutrientCoverage(reportedFoodCount: completeCount, totalFoodCount: contributions.count), contributions: contributions)
    }
    private static func reportingComplete(_ food: FoodItem, key: MicronutrientKey, depth: Int) -> Bool {
        guard depth < 8, let value = food.micronutrientValue(for: key), value.isFinite, value >= 0 else { return false }
        if let composition = food.mealComposition {
            return !composition.components.isEmpty && composition.components.allSatisfy { reportingComplete($0, key: key, depth: depth + 1) }
        }
        if let recipe = food.recipePortionSnapshot {
            if let ingredients = recipe.adjustedIngredientFoods, recipe.adjustedIngredientBasis == .originalRecipeAmounts {
                return !ingredients.isEmpty && ingredients.allSatisfy { reportingComplete($0, key: key, depth: depth + 1) }
            }
            if recipe.nutritionAdjustedForThisLog { return false }
            if recipe.sourceNutritionDerivedFromIngredients == false { return true }
            guard recipe.sourceIngredientListComplete == true, let ingredients = recipe.sourceIngredientFoods, !ingredients.isEmpty else { return false }
            return ingredients.allSatisfy { reportingComplete($0, key: key, depth: depth + 1) }
        }
        return true
    }
}

@MainActor
public struct NutrientDashboardPinStore {
    private let userID: String?
    private let store: EditorDraftStore
    private let scope = "daily-nutrient-pins"
    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.store = store }
    public func pins() throws -> [MicronutrientKey] {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw LibraryMutationError.accountChanged }
        guard let saved = try store.load([String].self, userID: userID, scope: scope)?.value else { return [.fiber, .sodium, .potassium, .vitaminD] }
        return saved.compactMap(MicronutrientKey.init(rawValue:))
    }
    public func save(_ pins: [MicronutrientKey]) throws {
        guard let userID, userID == DIContainer.shared.authService.currentUserID,
              pins.count <= MicronutrientKey.allCases.count, Set(pins).count == pins.count else { throw LibraryMutationError.accountChanged }
        _ = try self.pins() // Do not silently overwrite an unreadable preference file.
        try store.save(pins.map(\.rawValue), userID: userID, scope: scope)
    }
    public func reset() throws {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw LibraryMutationError.accountChanged }
        try store.remove(userID: userID, scope: scope)
    }
}
