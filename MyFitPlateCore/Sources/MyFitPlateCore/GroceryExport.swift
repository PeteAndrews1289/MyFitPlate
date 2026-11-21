import Foundation

public struct GroceryExportRow: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let category: String
    public let unit: String
    public let required: Double?
    public let confirmedStock: Double?
    public let netToBuy: Double?
    public let bought: Double?
    public let checked: Bool
    public let skipped: Bool
    public let barcode: String?
    public let packageQuantity: Double?
    public let packageUnit: String?
    public let override: GroceryRequirementOverride?
    public let unconvertedPurchases: [GroceryPurchaseAmount]?
}

public struct GroceryExportDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let periodStart: Date
    public let periodEnd: Date
    public let includesChecked: Bool
    public let includesProductCodes: Bool
    public let containsPendingChanges: Bool
    public let stockCoverageAvailable: Bool
    public let notes: String
    public let rows: [GroceryExportRow]
    public var plainText: String {
        var lines = ["Shopping checklist", "\(periodStart.formatted(date: .abbreviated, time: .omitted)) – \(periodEnd.formatted(date: .abbreviated, time: .omitted))",
            containsPendingChanges ? "Includes local changes awaiting account acknowledgement." : "Shopping snapshot; sharing does not synchronize a household.",
            stockCoverageAvailable ? "Pantry uses confirmed compatible amounts." : "Pantry coverage unavailable; review stock separately."]
        for category in Set(rows.map(\.category)).sorted() {
            lines.append("\n\(category)")
            for row in rows.filter({ $0.category == category }) {
                let amount = row.netToBuy.map { $0.formatted(.number.precision(.fractionLength(0...3))) + " " + row.unit } ?? "amount unconfirmed"
                let state = row.skipped ? " [skipped]" : row.checked ? " [checked]" : ""
                lines.append("☐ \(row.name): \(amount)\(state)")
                if let required = row.required { lines.append("   Required \(required.formatted()) \(row.unit); confirmed stock \(row.confirmedStock?.formatted() ?? "unavailable")") }
                if let bought = row.bought { lines.append("   Recorded bought \(bought.formatted()) \(row.unit)") }
                for bought in row.unconvertedPurchases ?? [] {
                    lines.append("   Earlier recorded bought \(bought.quantity.formatted()) \(bought.unit); conversion to \(row.unit) unconfirmed")
                }
                if let code = row.barcode { lines.append("   Product code \(code)") }
                if let package = row.packageQuantity, let unit = row.packageUnit { lines.append("   Reviewed package size \(package.formatted()) \(unit)") }
                if let override = row.override { lines.append("   Personal override: \(override.reason)\(override.requiresReview ? " · needs review" : "")") }
                if let override = row.override {
                    lines.append("   Original plan: \(override.sourceQuantity?.formatted() ?? "amount unconfirmed") \(override.sourceUnit); personal buy amount: \(override.buyQuantity.formatted()) \(override.buyUnit)")
                }
            }
        }
        if !notes.isEmpty { lines.append("\nNotes\n\(notes)") }
        return lines.joined(separator: "\n")
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum GroceryExportRules {
    public static func document(items: [GroceryListItem], stock: [PantryItem], starting: Date,
                                includeChecked: Bool = false, includeProductCodes: Bool = false, pendingChanges: Bool = false,
                                stockCoverageAvailable: Bool = true, notes: String = "", now: Date = Date()) -> GroceryExportDocument {
        let rows = InventoryPlanningRules.coverage(items: items, stock: stockCoverageAvailable ? stock : [])
            .filter { includeChecked || (!$0.item.isCompleted && $0.item.skippedForPlan != true) }
            .sorted { $0.item.category == $1.item.category ? $0.item.name < $1.item.name : $0.item.category < $1.item.category }
            .map { coverage in
                let item = coverage.item, known = item.quantityUnknown != true
                let requirement: Double?
                if let override = item.quantityOverride {
                    requirement = override.sourceQuantity.flatMap { InventoryQuantityRules.convert($0, from: override.sourceUnit, to: item.unit) }
                } else { requirement = known ? item.quantity : nil }
                return GroceryExportRow(id: item.id, name: item.name, category: item.category, unit: item.unit,
                    required: requirement, confirmedStock: stockCoverageAvailable && known ? coverage.available : nil,
                    netToBuy: known ? coverage.needToBuy : nil, bought: item.purchasedQuantity,
                    checked: item.isCompleted, skipped: item.skippedForPlan == true,
                    barcode: includeProductCodes ? item.barcode : nil, packageQuantity: item.productSnapshot?.packageQuantity,
                    packageUnit: item.productSnapshot?.packageUnit, override: item.quantityOverride,
                    unconvertedPurchases: item.unconvertedPurchases)
            }
        let start = Calendar.current.startOfDay(for: starting)
        return GroceryExportDocument(schemaVersion: 1, generatedAt: now, periodStart: start,
            periodEnd: Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start,
            includesChecked: includeChecked, includesProductCodes: includeProductCodes,
            containsPendingChanges: pendingChanges, stockCoverageAvailable: stockCoverageAvailable,
            notes: String(notes.prefix(2_000)), rows: rows)
    }
}
