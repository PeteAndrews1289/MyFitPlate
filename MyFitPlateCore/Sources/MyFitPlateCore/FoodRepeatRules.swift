import Foundation

public enum FoodRepeatRules {
    /// A zero amount omits a food. A changed amount keeps all nutrient fields and the
    /// structured serving quantity in agreement so reopening the entry does not double-scale it.
    public static func adjusting(_ food: FoodItem, by multiplier: Double) -> FoodItem? {
        guard multiplier.isFinite, multiplier > 0 else { return nil }
        var adjusted = food.scalingNutritionAndServing(by: multiplier)
        if multiplier != 1 {
            let parsed = ServingNutritionCalculator.parseQuantity(from: food.servingSize)
            let quantity = (food.quantityValue ?? parsed.quantity) * multiplier
            let unit = food.servingUnit ?? (parsed.baseDescription.isEmpty ? "original serving" : parsed.baseDescription)
            adjusted.quantityValue = quantity
            adjusted.servingUnit = unit
            let amount = quantity.formatted(.number.precision(.fractionLength(0...2)))
            adjusted.servingSize = "\(amount) x \(unit)"
        }
        return adjusted
    }
}
