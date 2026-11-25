import Foundation

/// A nutrition serving identifies the selected product, never the package quantity to buy.
public struct GroceryProductSnapshot: Codable, Equatable, Sendable {
    public var barcode: String
    public var name: String
    public var foodID: String?
    public var brand: String?
    public var reportedServingDescription: String?
    public var reportedServingWeightGrams: Double?
    /// Entered from the package label during explicit review; not inferred from a serving.
    public var packageQuantity: Double?
    public var packageUnit: String?
    public init(food: FoodItem, barcode: String) {
        self.barcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
        name = food.name; foodID = food.id; brand = food.sourceMetadata?.brandName
        reportedServingDescription = food.servingSize
        reportedServingWeightGrams = food.servingWeight.isFinite && food.servingWeight > 0 ? food.servingWeight : nil
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (packageQuantity.map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } ?? true)
            && (packageQuantity == nil || packageUnit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }
}
