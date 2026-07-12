import Foundation

/// Privacy-safe dimensions for evaluating whether Trust bands predict later user corrections.
/// This deliberately carries categories only: never food identity, barcode, or nutrition values.
public struct FoodTrustCalibrationContext: Equatable, Sendable {
    public let source: String
    public let trustScore: Int
    public let trustLevel: String
    public let trustModelVersion: String
    public let requiresCorrection: Bool
    public let crossVerifiedCount: Int
    public let reviewStatus: String
    public let evidenceClass: String
    public let servingEvidence: String
    public let sanityProfile: String
    public let sanityFindingCount: Int

    public init(
        item: FoodItem,
        descriptor: FoodSourceDescriptor,
        metadata: FoodSourceMetadata?
    ) {
        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: metadata
        )
        let crossVerifiedCount = metadata?.validatedCrossVerifiedBy.count ?? 0
        let findings = FoodDataSanity.findings(for: item)

        self.source = descriptor.sourceKey
        self.trustScore = evaluation.score
        self.trustLevel = evaluation.level.rawValue
        self.trustModelVersion = String(FoodTrustEvaluation.modelVersion)
        self.requiresCorrection = evaluation.requiresCorrection
        self.crossVerifiedCount = crossVerifiedCount
        self.reviewStatus = metadata?.reviewStatus.rawValue ?? "none"
        self.evidenceClass = Self.evidenceClass(
            source: descriptor.sourceKey,
            isEstimated: descriptor.isEstimated,
            reviewStatus: metadata?.reviewStatus,
            crossVerifiedCount: crossVerifiedCount
        )
        self.servingEvidence = item.servingWeight.isFinite &&
            item.servingWeight >= FoodSourceAgreement.minimumComparableServingWeight
            ? "comparable"
            : "missing_or_too_small"
        self.sanityProfile = Self.sanityProfile(findings)
        self.sanityFindingCount = findings.count
    }

    public func analyticsParameters(
        action: String? = nil,
        correctionScope: String? = nil,
        resultingItem: FoodItem? = nil
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "source": source,
            "trust_score": trustScore,
            "trust_level": trustLevel,
            "trust_model_version": trustModelVersion,
            "requires_correction": requiresCorrection,
            "cross_verified": crossVerifiedCount > 0,
            "cross_verified_count": crossVerifiedCount,
            "review_status": reviewStatus,
            "evidence_class": evidenceClass,
            "serving_evidence": servingEvidence,
            "sanity_profile": sanityProfile,
            "sanity_finding_count": sanityFindingCount
        ]
        if let action {
            parameters["action"] = action
        }
        if let correctionScope {
            parameters["correction_scope"] = correctionScope
        }
        if let resultingItem {
            let findings = FoodDataSanity.findings(for: resultingItem)
            parameters["resulting_sanity"] = Self.sanityState(findings)
            parameters["resulting_sanity_profile"] = Self.sanityProfile(findings)
            parameters["resulting_sanity_finding_count"] = findings.count
            parameters["resulting_review_status"] =
                resultingItem.sourceMetadata?.reviewStatus.rawValue ?? "none"
        }
        return parameters
    }

    private static func evidenceClass(
        source: String,
        isEstimated: Bool,
        reviewStatus: FoodReviewStatus?,
        crossVerifiedCount: Int
    ) -> String {
        if crossVerifiedCount > 0 {
            return "independent_cross_verification"
        }
        if source == "community_barcode" {
            return "community_consensus"
        }
        if reviewStatus == .userEdited {
            return "user_edited"
        }
        if reviewStatus == .userConfirmed {
            return "user_confirmed"
        }
        if isEstimated {
            return "estimate"
        }
        switch source {
        case "usda", "fatsecret", "open_food_facts":
            return "single_database"
        case "custom_barcode", "manual", "chain_builder", "recipe":
            return "personal_or_curated"
        default:
            return "single_source"
        }
    }

    private static func sanityState(_ findings: [FoodDataSanity.Finding]) -> String {
        if findings.contains(where: { $0.severity == .warning }) {
            return "warning"
        }
        return findings.isEmpty ? "clear" : "information"
    }

    private static func sanityProfile(_ findings: [FoodDataSanity.Finding]) -> String {
        let orderedIDs = findings.sorted { left, right in
            if left.severity != right.severity {
                return left.severity == .warning
            }
            return left.id < right.id
        }.map(\.id)
        guard !orderedIDs.isEmpty else { return "none" }

        var included: [String] = []
        for id in orderedIDs {
            let candidate = (included + [id]).joined(separator: ",")
            guard candidate.utf8.count <= 96 else { break }
            included.append(id)
        }
        return included.joined(separator: ",")
    }
}

public enum FoodCorrectionTelemetry {
    /// Coarse field groups changed in the correction sheet. Actual values never leave the app.
    public static func scope(
        originalName: String,
        originalServing: ServingSizeOption,
        correctedName: String,
        correctedServing: ServingSizeOption
    ) -> String {
        var scopes: [String] = []

        if normalizedText(originalName) != normalizedText(correctedName) {
            scopes.append("identity")
        }
        if normalizedText(originalServing.description) != normalizedText(correctedServing.description) ||
            differs(originalServing.servingWeightGrams, correctedServing.servingWeightGrams) {
            scopes.append("serving")
        }
        if differs(originalServing.calories, correctedServing.calories) ||
            differs(originalServing.protein, correctedServing.protein) ||
            differs(originalServing.carbs, correctedServing.carbs) ||
            differs(originalServing.fats, correctedServing.fats) {
            scopes.append("core_nutrition")
        }

        let originalDetails = detailValues(originalServing)
        let correctedDetails = detailValues(correctedServing)
        if zip(originalDetails, correctedDetails).contains(where: differs) {
            scopes.append("detail_nutrition")
        }

        return scopes.isEmpty ? "no_material_change" : scopes.joined(separator: ",")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func differs(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return lhs != rhs }
        let tolerance = max(0.0001, max(abs(lhs), abs(rhs)) * 0.000001)
        return abs(lhs - rhs) > tolerance
    }

    private static func differs(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case let (lhs?, rhs?):
            return differs(lhs, rhs)
        case (.some, nil), (nil, .some):
            return true
        }
    }

    private static func detailValues(_ serving: ServingSizeOption) -> [Double?] {
        [
            serving.saturatedFat, serving.polyunsaturatedFat, serving.monounsaturatedFat,
            serving.fiber, serving.calcium, serving.iron, serving.potassium, serving.sodium,
            serving.vitaminA, serving.vitaminC, serving.vitaminD, serving.vitaminB12,
            serving.folate, serving.magnesium, serving.phosphorus, serving.zinc,
            serving.copper, serving.manganese, serving.selenium, serving.vitaminB1,
            serving.vitaminB2, serving.vitaminB3, serving.vitaminB5, serving.vitaminB6,
            serving.vitaminE, serving.vitaminK
        ]
    }
}
