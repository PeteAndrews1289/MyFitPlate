import Foundation

/// Cross-database agreement for barcode lookups. When two independent databases report the
/// same nutrition for a barcode, the entry is far more trustworthy than either alone — the
/// badge this powers ("Cross-Verified") is cheap for us and structurally hard for
/// single-database competitors to copy.
public enum FoodSourceAgreement {

    /// Databases report different serving sizes for the same product, so agreement is
    /// judged per 100g. Entries whose serving weight is unknown (placeholder ≤ this) can't
    /// be normalized and never agree.
    static let minimumComparableServingWeight = 10.0

    /// Calories agree within max(20 kcal, 12%) per 100g; each macro within max(2.5g, 20%).
    public static func agrees(_ a: FoodItem, _ b: FoodItem) -> Bool {
        guard a.servingWeight >= minimumComparableServingWeight,
              b.servingWeight >= minimumComparableServingWeight else { return false }

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

    /// Names of the candidate sources whose entries agree with the primary hit.
    /// Pure so the tolerance/normalization behavior is unit-testable without the network.
    public static func agreeingSourceNames(
        primary: FoodItem,
        candidates: [(sourceName: String, item: FoodItem?)]
    ) -> [String] {
        candidates.compactMap { candidate in
            guard let item = candidate.item, agrees(primary, item) else { return nil }
            return candidate.sourceName
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
}

public extension FoodItem {
    /// Attaches the list of independent databases that confirmed this entry's nutrition.
    /// No-op when nothing agreed, so callers can apply it unconditionally.
    func withCrossVerification(_ agreeingSourceNames: [String]) -> FoodItem {
        guard !agreeingSourceNames.isEmpty, var metadata = sourceMetadata else { return self }
        metadata.crossVerifiedBy = agreeingSourceNames
        return withSourceMetadata(metadata)
    }
}
