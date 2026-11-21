import Foundation

public struct GroceryRequirementOverride: Codable, Equatable, Sendable {
    public var sourceQuantity: Double?
    public var sourceUnit: String
    public var buyQuantity: Double
    public var buyUnit: String
    public var reason: String
    public var requiresReview: Bool
    public init(sourceQuantity: Double?, sourceUnit: String, buyQuantity: Double, buyUnit: String,
                reason: String = "Personal shopping amount", requiresReview: Bool = false) {
        self.sourceQuantity = sourceQuantity; self.sourceUnit = sourceUnit
        self.buyQuantity = buyQuantity; self.buyUnit = buyUnit; self.reason = reason; self.requiresReview = requiresReview
    }
    public var isValid: Bool {
        (sourceQuantity.map { $0.isFinite && $0 >= 0 } ?? true) && buyQuantity.isFinite && buyQuantity >= 0
            && !sourceUnit.isEmpty && !buyUnit.isEmpty && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum GroceryOverrideRules {
    public static func applying(_ override: GroceryRequirementOverride, generated: GroceryListItem) -> GroceryListItem {
        guard override.isValid else { return generated }
        var item = generated, updated = override
        let baseline = override.sourceQuantity.flatMap { InventoryQuantityRules.convert($0, from: override.sourceUnit, to: generated.unit) }
        let changedDimension = override.sourceQuantity != nil && baseline == nil
        let increased = generated.quantityUnknown != true && baseline.map { generated.quantity > $0 + 0.0001 } == true
        updated.requiresReview = updated.requiresReview || changedDimension || increased
        item.quantityOverride = updated
        if !updated.requiresReview {
            item.quantity = updated.buyQuantity; item.unit = updated.buyUnit; item.quantityUnknown = false
        } else { item.skippedForPlan = false; item.isCompleted = false }
        return item
    }
}

public struct GroceryPurchaseAmount: Codable, Equatable, Sendable {
    public var quantity: Double
    public var unit: String
    public var transferredToPantryQuantity: Double?
    public init(quantity: Double, unit: String, transferredToPantryQuantity: Double? = nil) {
        self.quantity = quantity; self.unit = unit; self.transferredToPantryQuantity = transferredToPantryQuantity
    }
}
