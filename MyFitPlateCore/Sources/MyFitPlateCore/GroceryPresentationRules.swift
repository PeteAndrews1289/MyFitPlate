import Foundation

/// A display conversion is never a stock mutation or a new canonical measurement.
public enum GroceryPresentationRules {
    public static func canonicalized(_ display: [GroceryListItem], against basis: [GroceryListItem]) -> [GroceryListItem] {
        display.map { item in
            guard let original = basis.first(where: { $0.id == item.id }),
                  let amount = InventoryQuantityRules.convert(item.quantity, from: item.unit, to: original.unit) else { return item }
            var value = item
            let expected = InventoryQuantityRules.convert(original.quantity, from: original.unit, to: item.unit)
            value.quantity = expected == item.quantity ? original.quantity : amount
            value.purchasedQuantity = canonicalAmount(item.purchasedQuantity, from: item.unit, original: original.purchasedQuantity, unit: original.unit)
            value.transferredToPantryQuantity = canonicalAmount(item.transferredToPantryQuantity, from: item.unit, original: original.transferredToPantryQuantity, unit: original.unit)
            value.unit = original.unit
            return value
        }
    }
    private static func canonicalAmount(_ value: Double?, from: String, original: Double?, unit: String) -> Double? {
        guard let value else { return nil }
        if let original, InventoryQuantityRules.convert(original, from: unit, to: from) == value { return original }
        return InventoryQuantityRules.convert(value, from: from, to: unit)
    }
    public static func shareText(items: [GroceryListItem], stock: [PantryItem], starting: Date, includeChecked: Bool) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: starting) ?? starting
        let rows = InventoryPlanningRules.coverage(items: items, stock: stock).filter { includeChecked || (!$0.item.isCompleted && $0.item.skippedForPlan != true) }
        var lines = ["Shopping list · \(starting.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))",
                     "Snapshot of this shopping period. Pantry coverage uses confirmed compatible quantities; unknown/package weights stay unknown."]
        for category in Set(rows.map { $0.item.category }).sorted() {
            lines.append("\n\(category)")
            for row in rows.filter({ $0.item.category == category }).sorted(by: { $0.item.name < $1.item.name }) {
                if row.item.quantityUnknown == true {
                    let bought = row.item.purchasedQuantity.map { " · explicitly recorded bought \($0.formatted(.number.precision(.fractionLength(0...3)))) \(row.item.unit)" } ?? ""
                    lines.append("- \(row.item.name): amount unconfirmed; review before buying\(bought)")
                    continue
                }
                let amount = row.needToBuy.formatted(.number.precision(.fractionLength(0...3)))
                let required = row.item.quantity.formatted(.number.precision(.fractionLength(0...3)))
                let have = row.available.formatted(.number.precision(.fractionLength(0...3)))
                let status = row.item.skippedForPlan == true ? " · skipped" : row.item.isCompleted ? " · checked" : ""
                let bought = row.item.purchasedQuantity.map { " · recorded bought \($0.formatted(.number.precision(.fractionLength(0...3)))) \(row.item.unit)" } ?? ""
                lines.append("- \(row.item.name): buy \(amount) \(row.item.unit) · required \(required), pantry \(have)\(bought)\(status)")
            }
        }
        if rows.isEmpty { lines.append("No remaining items in this snapshot.") }
        return lines.joined(separator: "\n")
    }
}
