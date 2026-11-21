import CryptoKit
import Foundation

public struct PantryReceiptHistoryRecord: Codable, Identifiable {
    public let id: UUID
    public let sourceDigest: String?
    public let contentSignature: String
    public let purchaseDate: Date
    public let items: [PantryItem]
    public let separateImportID: UUID?
    public let recordedAt: Date
    public var purchaseDayKey: String?
}

public enum PantryReceiptIdentityRules {
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func contentSignature(items: [PantryItem], purchaseDate: Date, purchaseDayKey: String? = nil) throws -> String {
        struct Row: Encodable { let name: String; let quantity: Double?; let unit: String; let barcode: String? }
        struct Basis: Encodable { let day: String?; let rows: [Row] }
        let mapped: [Row] = items.map { item in
            var quantity: Double? = item.quantityUnknown == true ? nil : item.quantity
            var unit = IngredientUnitNormalizer.normalized(item.unit)
            if let amount = quantity, let grams = InventoryQuantityRules.convert(amount, from: unit, to: "g") {
                quantity = (grams * 1_000_000).rounded() / 1_000_000; unit = "g"
            } else if let amount = quantity, let milliliters = InventoryQuantityRules.convert(amount, from: unit, to: "ml") {
                quantity = (milliliters * 1_000_000).rounded() / 1_000_000; unit = "ml"
            }
            let code = BarcodeCorrectionRules.normalizedBarcode(item.productSnapshot?.barcode ?? "")
            return Row(name: InventoryQuantityRules.ingredientIdentity(item.name), quantity: quantity, unit: unit,
                barcode: code.isEmpty ? nil : code)
        }
        let rows = mapped.sorted { left, right in
            if left.name != right.name { return left.name < right.name }
            if left.unit != right.unit { return left.unit < right.unit }
            if left.quantity != right.quantity { return (left.quantity ?? -1) < (right.quantity ?? -1) }
            return (left.barcode ?? "") < (right.barcode ?? "")
        }
        return try PlanFingerprint.make(Basis(day: purchaseDayKey ?? DiaryDayContext.dayKey(for: purchaseDate), rows: rows))
    }
    public static func sourceKey(digest: String?, signature: String, separateImportID: UUID?) -> String {
        "receipt-source-\(digest ?? signature)" + (separateImportID.map { "-separate-\($0.uuidString.lowercased())" } ?? "")
    }
}
