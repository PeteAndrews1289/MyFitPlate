import Foundation

/// Cross-database agreement for food records. The Cross-Verified state requires recognized
/// databases to report comparable calories, protein, carbohydrate, and fat after serving-weight
/// normalization. Product-barcode matches and generic composition matches have different identity
/// strength, which the Trust Receipt explains. Agreement does not by itself prove independent
/// lineage: two providers may both reproduce a manufacturer label.
public enum FoodSourceAgreement {

    /// Databases report different serving sizes for the same product, so agreement is
    /// judged per 100g. Entries whose serving weight is unknown (placeholder ≤ this) can't
    /// be normalized and never agree.
    static let minimumComparableServingWeight = 10.0

    /// Calories agree within max(20 kcal, 12%) per 100g; each macro within max(2.5g, 20%).
    public static func agrees(_ a: FoodItem, _ b: FoodItem) -> Bool {
        guard hasComparableNutrition(a),
              hasComparableNutrition(b),
              !FoodDataSanity.isSuspicious(a),
              !FoodDataSanity.isSuspicious(b) else { return false }

        func per100g(_ value: Double, weight: Double) -> Double {
            value / weight * 100
        }

        let aCal = per100g(a.calories, weight: a.servingWeight)
        let bCal = per100g(b.calories, weight: b.servingWeight)
        guard withinTolerance(aCal, bCal, absolute: 20, relative: 0.12) else { return false }

        let macroPairs: [(Double, Double)] = [
            (per100g(a.protein, weight: a.servingWeight), per100g(b.protein, weight: b.servingWeight)),
            (per100g(a.carbs, weight: a.servingWeight), per100g(b.carbs, weight: b.servingWeight)),
            (per100g(a.fats, weight: a.servingWeight), per100g(b.fats, weight: b.servingWeight))
        ]
        return macroPairs.allSatisfy { withinTolerance($0.0, $0.1, absolute: 2.5, relative: 0.20) }
    }

    /// A much tighter comparison used only when deciding whether a user edit can retain
    /// previously earned agreement evidence. It allows serving rescaling and label rounding,
    /// but not a fresh nutrition correction that was never checked against the second source.
    public static func preservesAgreementEvidence(_ current: FoodItem, _ original: FoodItem) -> Bool {
        guard hasComparableNutrition(current),
              hasComparableNutrition(original),
              !FoodDataSanity.isSuspicious(current),
              !FoodDataSanity.isSuspicious(original) else {
            return false
        }

        func per100g(_ value: Double, weight: Double) -> Double {
            value / weight * 100
        }

        let caloriePair = (
            per100g(current.calories, weight: current.servingWeight),
            per100g(original.calories, weight: original.servingWeight)
        )
        guard withinTolerance(caloriePair.0, caloriePair.1, absolute: 2, relative: 0.02) else {
            return false
        }

        let macroPairs = [
            (current.protein, original.protein),
            (current.carbs, original.carbs),
            (current.fats, original.fats)
        ].map { pair in
            (
                per100g(pair.0, weight: current.servingWeight),
                per100g(pair.1, weight: original.servingWeight)
            )
        }
        return macroPairs.allSatisfy {
            withinTolerance($0.0, $0.1, absolute: 0.25, relative: 0.03)
        }
    }

    /// Names of the candidate sources whose entries agree with the primary hit.
    /// Pure so the tolerance/normalization behavior is unit-testable without the network.
    public static func agreeingSourceNames(
        primary: FoodItem,
        candidates: [(sourceName: String, item: FoodItem?)]
    ) -> [String] {
        agreeingEvidence(primary: primary, candidates: candidates).map(\.sourceName)
    }

    /// Durable evidence records for agreeing candidates, including provider lineage and dates.
    public static func agreeingEvidence(
        primary: FoodItem,
        candidates: [(sourceName: String, item: FoodItem?)]
    ) -> [FoodVerificationEvidence] {
        let primaryIdentity = sourceIdentity(for: primary.sourceMetadata?.sourceType)
        var seen = Set<String>()
        var result: [FoodVerificationEvidence] = []

        for candidate in candidates {
            guard let item = candidate.item,
                  agrees(primary, item),
                  let canonical = canonicalSource(for: candidate.sourceName),
                  canonical.identity != primaryIdentity,
                  seen.insert(canonical.identity).inserted else {
                continue
            }
            let sourceType = item.sourceMetadata?.sourceType ?? sourceType(for: canonical.identity)
            let lineage = item.sourceMetadata?.effectiveEvidenceLineage ??
                FoodSourceMetadata.inferredLineage(sourceType: sourceType)
            result.append(FoodVerificationEvidence(
                sourceName: canonical.displayName,
                sourceType: sourceType,
                lineage: lineage,
                sourceID: item.sourceMetadata?.sourceID ?? item.id,
                observedAt: item.sourceMetadata?.sourceObservedAt ?? item.sourceMetadata?.createdAt,
                sourceUpdatedAt: item.sourceMetadata?.sourceUpdatedAt
            ))
            if result.count == 2 { break }
        }
        return result
    }

    /// Only recognized database names can become durable verification evidence.
    /// This intentionally ignores arbitrary strings and cross-check metadata attached to custom,
    /// planned, community, or estimated foods.
    public static func validatedSourceNames(
        _ sourceNames: [String],
        for metadata: FoodSourceMetadata?
    ) -> [String] {
        guard let metadata else { return [] }
        switch metadata.sourceType {
        case .usda, .healthCanadaCNF, .fatSecret, .openFoodFacts:
            break
        default:
            return []
        }
        switch metadata.confidence {
        case .verified, .databaseMatch:
            break
        case .estimated, .needsReview, .userVerified:
            return []
        }

        return canonicalizedSourceNames(
            sourceNames,
            excluding: sourceIdentity(for: metadata.sourceType)
        )
    }

    public static func validatedEvidence(
        _ evidence: [FoodVerificationEvidence],
        sourceNames: [String],
        for metadata: FoodSourceMetadata?
    ) -> [FoodVerificationEvidence] {
        let validatedNames = validatedSourceNames(sourceNames, for: metadata)
        return validatedNames.compactMap { name in
            guard let canonical = canonicalSource(for: name) else { return nil }
            let expectedType = sourceType(for: canonical.identity)
            if let stored = evidence.first(where: {
                canonicalSource(for: $0.sourceName)?.identity == canonical.identity &&
                    $0.sourceType == expectedType
            }) {
                return FoodVerificationEvidence(
                    sourceName: canonical.displayName,
                    sourceType: stored.sourceType,
                    lineage: stored.lineage,
                    sourceID: stored.sourceID,
                    observedAt: stored.observedAt,
                    sourceUpdatedAt: stored.sourceUpdatedAt
                )
            }
            return FoodVerificationEvidence(
                sourceName: canonical.displayName,
                sourceType: expectedType,
                lineage: FoodSourceMetadata.inferredLineage(sourceType: expectedType)
            )
        }
    }

    private static func withinTolerance(
        _ a: Double,
        _ b: Double,
        absolute: Double,
        relative: Double
    ) -> Bool {
        let delta = abs(a - b)
        if delta <= absolute { return true }
        let denominator = max(abs(a), abs(b))
        guard denominator > 0 else { return true }
        return delta / denominator <= relative
    }

    private static func hasComparableNutrition(_ item: FoodItem) -> Bool {
        let values = [item.calories, item.protein, item.carbs, item.fats, item.servingWeight]
        return item.servingWeight >= minimumComparableServingWeight &&
            values.allSatisfy { $0.isFinite && $0 >= 0 }
    }

    private static func canonicalizedSourceNames(
        _ sourceNames: [String],
        excluding primaryIdentity: String?
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for sourceName in sourceNames {
            guard let source = canonicalSource(for: sourceName),
                  source.identity != primaryIdentity,
                  seen.insert(source.identity).inserted else {
                continue
            }
            result.append(source.displayName)
            if result.count == 2 { break }
        }
        return result
    }

    static func canonicalSource(for sourceName: String) -> (identity: String, displayName: String)? {
        let normalized = sourceName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")

        if normalized == "usda" || normalized == "usda fooddata central" || normalized == "fooddata central" {
            return ("usda", "USDA")
        }
        if normalized == "fatsecret" || normalized == "fat secret" {
            return ("fatsecret", "FatSecret")
        }
        if normalized == "health canada" ||
            normalized == "health canada cnf" ||
            normalized == "canadian nutrient file" {
            return ("health_canada_cnf", "Health Canada CNF")
        }
        if normalized == "open food facts" {
            return ("open_food_facts", "Open Food Facts")
        }
        return nil
    }

    static func sourceIdentity(for sourceType: FoodSourceType?) -> String? {
        switch sourceType {
        case .usda:
            return "usda"
        case .healthCanadaCNF:
            return "health_canada_cnf"
        case .fatSecret:
            return "fatsecret"
        case .openFoodFacts:
            return "open_food_facts"
        default:
            return nil
        }
    }

    private static func sourceType(for identity: String) -> FoodSourceType {
        switch identity {
        case "usda": return .usda
        case "health_canada_cnf": return .healthCanadaCNF
        case "fatsecret": return .fatSecret
        case "open_food_facts": return .openFoodFacts
        default: return .unknown
        }
    }
}

public extension FoodSourceMetadata {
    var validatedCrossVerifiedBy: [String] {
        FoodSourceAgreement.validatedSourceNames(crossVerifiedBy ?? [], for: self)
    }

    var validatedCrossVerificationEvidence: [FoodVerificationEvidence] {
        let sourceNames = crossVerifiedBy?.isEmpty == false
            ? (crossVerifiedBy ?? [])
            : (crossVerificationEvidence ?? []).map(\.sourceName)
        return FoodSourceAgreement.validatedEvidence(
            crossVerificationEvidence ?? [],
            sourceNames: sourceNames,
            for: self
        )
    }

    var hasCrossDatabaseAgreement: Bool {
        !validatedCrossVerificationEvidence.isEmpty
    }

    /// Kept for source compatibility. Cross-database agreement does not necessarily imply
    /// independent upstream lineage.
    var hasIndependentCrossVerification: Bool {
        hasCrossDatabaseAgreement
    }
}

public extension FoodItem {
    /// Attaches the list of databases that confirmed this entry's core nutrition.
    /// Clears stale or invalid evidence when nothing agreed.
    func withCrossVerification(_ agreeingSourceNames: [String]) -> FoodItem {
        guard var metadata = sourceMetadata else { return self }
        let validatedNames = FoodSourceAgreement.validatedSourceNames(
            agreeingSourceNames,
            for: metadata
        )
        metadata.crossVerifiedBy = validatedNames.isEmpty ? nil : validatedNames
        metadata.crossVerificationEvidence = validatedNames.isEmpty ? nil :
            FoodSourceAgreement.validatedEvidence(
                [],
                sourceNames: validatedNames,
                for: metadata
            )
        return withSourceMetadata(metadata)
    }

    func withCrossVerificationEvidence(_ evidence: [FoodVerificationEvidence]) -> FoodItem {
        guard var metadata = sourceMetadata else { return self }
        let sourceNames = evidence.map(\.sourceName)
        let validatedEvidence = FoodSourceAgreement.validatedEvidence(
            evidence,
            sourceNames: sourceNames,
            for: metadata
        )
        metadata.crossVerifiedBy = validatedEvidence.isEmpty ? nil : validatedEvidence.map(\.sourceName)
        metadata.crossVerificationEvidence = validatedEvidence.isEmpty ? nil : validatedEvidence
        return withSourceMetadata(metadata)
    }
}
