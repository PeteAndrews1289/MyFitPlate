import Foundation

/// Private corrections feed a server-owned aggregate. A single submission is never exposed or
/// treated as verification; the client only reads an identifier-free consensus document.
public protocol CommunityBarcodeStoreProtocol: Sendable {
    func communityFood(for barcode: String) async -> FoodItem?
    func contribute(_ item: FoodItem, barcode: String) async
}

public struct CommunityBarcodeContributionDecision: Equatable, Sendable {
    public let isEligible: Bool
    public let reason: String

    public init(isEligible: Bool, reason: String) {
        self.isEligible = isEligible
        self.reason = reason
    }
}

public struct CommunityBarcodeAggregateEvidence: Equatable, Sendable {
    public let schemaVersion: Int
    public let modelVersion: String
    public let status: String
    public let barcode: String
    public let contributorCount: Int
    public let agreementCount: Int
    public let conflictCount: Int
    public let agreementRatio: Double

    public init(
        schemaVersion: Int,
        modelVersion: String,
        status: String,
        barcode: String,
        contributorCount: Int,
        agreementCount: Int,
        conflictCount: Int,
        agreementRatio: Double
    ) {
        self.schemaVersion = schemaVersion
        self.modelVersion = modelVersion
        self.status = status
        self.barcode = barcode
        self.contributorCount = contributorCount
        self.agreementCount = agreementCount
        self.conflictCount = conflictCount
        self.agreementRatio = agreementRatio
    }
}

public enum CommunityBarcodeRules {
    /// Source name that marks a community-pool match. Deliberately NOT a new
    /// `FoodSourceType` case: community entries ride `.custom`, so metadata stored by this
    /// version still decodes on older app versions.
    public static let sourceName = "MyFitPlate Community"
    public static let aggregateModelVersion = "community_consensus_v1"
    public static let minimumAggregateContributors = 3
    public static let maximumAggregateContributors = 250
    public static let minimumAggregateAgreementRatio = 2.0 / 3.0

    /// Contribution gate. Everything must pass before a correction leaves the device:
    /// the feature flag, a non-empty barcode, shared collection field limits, and the
    /// sanity checker (never pool data that fails nutrition math).
    public static func isEligibleForContribution(
        _ item: FoodItem,
        barcode: String,
        flagEnabled: Bool
    ) -> Bool {
        contributionDecision(item, barcode: barcode, flagEnabled: flagEnabled).isEligible
    }

    public static func contributionDecision(
        _ item: FoodItem,
        barcode: String,
        flagEnabled: Bool
    ) -> CommunityBarcodeContributionDecision {
        guard flagEnabled else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "feature_flag_disabled")
        }
        let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !normalizedBarcode.isEmpty else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "empty_barcode")
        }
        guard isSupportedBarcode(normalizedBarcode) else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_barcode")
        }
        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 140 else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_name")
        }
        guard item.calories.isFinite, item.calories >= 0, item.calories <= 5000 else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "calories_out_of_range")
        }
        guard [item.protein, item.carbs, item.fats].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1000 }) else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "macros_out_of_range")
        }
        if let fiber = item.fiber, !fiber.isFinite || fiber < 0 || fiber > 1000 {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "fiber_out_of_range")
        }
        let servingSize = item.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !servingSize.isEmpty, servingSize.count <= 80 else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_serving_size")
        }
        guard item.servingWeight.isFinite,
              item.servingWeight >= FoodSourceAgreement.minimumComparableServingWeight,
              item.servingWeight <= 5000 else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "serving_weight_missing")
        }

        let findings = FoodDataSanity.findings(for: item)
        guard !findings.contains(where: { $0.severity == .warning }) else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "suspicious_food")
        }
        guard findings.isEmpty else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "nutrition_needs_review")
        }
        return CommunityBarcodeContributionDecision(isEligible: true, reason: "eligible")
    }

    /// Builds the community-pool match returned by a lookup, from the fields the shared
    /// collection stores. Pure so parsing/labeling is unit-testable without Firestore.
    public static func communityFoodItem(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        fiber: Double?,
        servingSize: String,
        servingWeight: Double,
        barcode: String
    ) -> FoodItem {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        return FoodItem(
            id: "community_\(normalized)",
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            fiber: fiber,
            servingSize: servingSize.isEmpty ? "1 serving" : servingSize,
            servingWeight: servingWeight > 0 ? servingWeight : 1.0,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .needsReview,
                reviewStatus: .unreviewed,
                sourceName: sourceName,
                sourceID: "community_\(normalized)",
                barcode: normalized
            )
        )
    }

    public static func isCommunityMatch(_ metadata: FoodSourceMetadata?) -> Bool {
        metadata?.sourceName == sourceName
    }

    public static func aggregateDecision(
        _ evidence: CommunityBarcodeAggregateEvidence,
        expectedBarcode: String
    ) -> CommunityBarcodeContributionDecision {
        guard evidence.schemaVersion == 1,
              evidence.modelVersion == aggregateModelVersion,
              evidence.status == "published" else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_aggregate_model")
        }
        let expected = BarcodeCorrectionRules.normalizedBarcode(expectedBarcode)
        let published = BarcodeCorrectionRules.normalizedBarcode(evidence.barcode)
        guard BarcodeCorrectionRules.isValidGTIN(expected), published == expected else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "aggregate_barcode_mismatch")
        }
        guard evidence.contributorCount >= minimumAggregateContributors,
              evidence.contributorCount <= maximumAggregateContributors,
              evidence.agreementCount >= minimumAggregateContributors,
              evidence.agreementCount <= evidence.contributorCount,
              evidence.conflictCount == evidence.contributorCount - evidence.agreementCount else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_aggregate_counts")
        }
        let computedRatio = Double(evidence.agreementCount) / Double(evidence.contributorCount)
        guard evidence.agreementRatio.isFinite,
              evidence.agreementRatio >= minimumAggregateAgreementRatio,
              evidence.agreementRatio <= 1,
              abs(evidence.agreementRatio - computedRatio) <= 0.001 else {
            return CommunityBarcodeContributionDecision(isEligible: false, reason: "invalid_aggregate_ratio")
        }
        return CommunityBarcodeContributionDecision(isEligible: true, reason: "eligible_aggregate")
    }

    private static func isSupportedBarcode(_ barcode: String) -> Bool {
        BarcodeCorrectionRules.isValidGTIN(barcode)
    }
}
