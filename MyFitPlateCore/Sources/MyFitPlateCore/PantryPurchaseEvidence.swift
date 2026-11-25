import Foundation

/// A reviewed receipt line. Purchase price describes the printed transaction line;
/// it never supplies a stock quantity, a package size, or nutrition.
public struct PantryPurchaseEvidence: Codable, Equatable, Sendable {
    public var storeName: String?
    public var printedLinePrice: Double?
    public var printedLinePriceText: String?
    public var currency: String?
    public var originalReceiptName: String?
    public var receiptRowQuantity: Double?
    public var receiptRowUnit: String?
    public init(storeName: String? = nil, printedLinePrice: Double? = nil, currency: String? = nil,
                originalReceiptName: String? = nil, receiptRowQuantity: Double? = nil, receiptRowUnit: String? = nil) {
        self.storeName = storeName; self.printedLinePrice = printedLinePrice; self.currency = currency
        self.originalReceiptName = originalReceiptName; self.receiptRowQuantity = receiptRowQuantity; self.receiptRowUnit = receiptRowUnit
    }
    public var reviewedPrice: Double? {
        if let raw = printedLinePriceText {
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            return AYCESessionInputRules.decimal(from: raw)
        }
        return printedLinePrice
    }
    public var isValid: Bool {
        if let raw = printedLinePriceText, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reviewedPrice == nil { return false }
        if let price = reviewedPrice, !price.isFinite || abs(price) > 1_000_000_000 { return false }
        if let currency, !currency.isEmpty {
            guard currency.count == 3, currency.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else { return false }
        }
        return receiptRowQuantity.map { $0.isFinite && $0 >= 0 } != false
    }
}
