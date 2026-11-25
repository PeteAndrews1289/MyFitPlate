import Foundation

public enum RestaurantRankingObjective: String, Codable, CaseIterable, Identifiable {
    case proteinValue, calorieBudget, balanced
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .proteinValue: return "Protein value"
        case .calorieBudget: return "Within calorie budget"
        case .balanced: return "Protein value + density"
        }
    }
    public var explanation: String {
        switch self {
        case .proteinValue: return "More estimated protein per currency unit. This is not a health rating."
        case .calorieBudget: return "Dishes within your stated calorie budget first, then protein per currency unit."
        case .balanced: return "Protein per currency unit × protein per 100 calories. A personal comparison, not a health rating."
        }
    }
}
public struct RestaurantComparisonRow: Codable, Identifiable, Hashable {
    public var id: String { food.id }
    public var food: FoodItem
    public var listedPrice: Double?
    public var currency: String
    public var priceNote: String
    public var priceConfirmed: Bool
    public init(food: FoodItem, listedPrice: Double?, currency: String = "USD", priceNote: String = "", priceConfirmed: Bool = false) {
        self.food = food; self.listedPrice = listedPrice; self.currency = currency
        self.priceNote = priceNote; self.priceConfirmed = priceConfirmed
    }
    public var validPrice: Double? {
        guard priceConfirmed, let price = listedPrice, price.isFinite, price > 0, price < 1_000_000,
              currency.count == 3, currency.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
        return price
    }
}
public struct RestaurantComparison: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var restaurantName = ""
    public var scannedAt = Date()
    public var rows: [RestaurantComparisonRow] = []
    public var objective = RestaurantRankingObjective.proteinValue
    public var calorieBudget = 800.0
    public var isDemo = false
    public init() {}
    public func ranked(currency: String) -> [RestaurantComparisonRow] {
        rows.sorted { left, right in
            let leftRank = rankingValue(left, currency: currency), rightRank = rankingValue(right, currency: currency)
            if leftRank != rightRank { return leftRank > rightRank }
            return left.id < right.id
        }
    }
    private func rankingValue(_ row: RestaurantComparisonRow, currency: String) -> Double {
        guard row.currency == currency, let price = row.validPrice,
              row.food.protein.isFinite, row.food.protein >= 0,
              row.food.calories.isFinite, row.food.calories >= 0 else { return -.infinity }
        let value = row.food.protein / price
        switch objective {
        case .proteinValue: return value
        case .calorieBudget: return (row.food.calories <= calorieBudget ? 1_000_000 : 0) + value
        case .balanced: return row.food.calories > 0 ? value * row.food.protein / row.food.calories * 100 : 0
        }
    }
}
public struct RestaurantComparisonWorkspace: Codable, Equatable {
    public var draft: RestaurantComparison?
    public var saved: [RestaurantComparison] = []
    public init() {}
}
public final class RestaurantComparisonStore {
    private let store: EditorDraftStore
    private let userID: String
    public init(userID: String, store: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.store = store }
    public func load() throws -> RestaurantComparisonWorkspace {
        try store.load(RestaurantComparisonWorkspace.self, userID: userID, scope: "restaurant-value-comparisons")?.value ?? RestaurantComparisonWorkspace()
    }
    public func save(_ next: RestaurantComparisonWorkspace, replacing old: RestaurantComparisonWorkspace) throws {
        guard try load() == old, next.saved.count <= 50,
              (next.saved + [next.draft].compactMap { $0 }).allSatisfy({ $0.rows.count <= 100 &&
                  $0.rows.allSatisfy { row in row.food.calories.isFinite && row.food.protein.isFinite &&
                      row.listedPrice.map { $0.isFinite && $0 >= 0 } != false } }) else { throw CocoaError(.fileWriteFileExists) }
        try store.save(next, userID: userID, scope: "restaurant-value-comparisons")
    }
}
