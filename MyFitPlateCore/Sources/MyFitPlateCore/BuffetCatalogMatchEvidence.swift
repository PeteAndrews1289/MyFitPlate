import Foundation

/// Frozen evidence for an explicitly reviewed generic match. Personal amount is
/// independent of the source unit; neither a match nor price review verifies nutrition.
public struct AYCECatalogMatchEvidence: Codable, Equatable, Sendable {
    public let catalogVersion: String
    public let sourceItemID: String
    public let sourceName: String
    public let sourceUnit: String
    public let caloriesPerSourceUnit: Double
    public let proteinPerSourceUnit: Double
    public let carbsPerSourceUnit: Double
    public let fatsPerSourceUnit: Double
    public let piecesPerSourceUnit: Int?
    public let cookedGramsPerSourceUnit: Double?
    public let originalText: String?
    public var personalAmount: Double
    public init(item: AYCECatalogItem, originalText: String?, personalAmount: Double,
                catalogVersion: String = AYCEStableRoundRules.catalogVersion) {
        self.catalogVersion = catalogVersion; sourceItemID = item.id; sourceName = item.name; sourceUnit = item.unit
        caloriesPerSourceUnit = item.calories; proteinPerSourceUnit = item.protein
        carbsPerSourceUnit = item.carbs; fatsPerSourceUnit = item.fats
        piecesPerSourceUnit = item.piecesPerUnit; cookedGramsPerSourceUnit = item.cookedGramsPerUnit
        self.originalText = originalText; self.personalAmount = personalAmount
    }
    public var isValid: Bool {
        !catalogVersion.isEmpty && !sourceItemID.isEmpty && !sourceName.isEmpty && !sourceUnit.isEmpty &&
            AYCEPortionRules.isValid(personalAmount) && [caloriesPerSourceUnit, proteinPerSourceUnit, carbsPerSourceUnit, fatsPerSourceUnit].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}
