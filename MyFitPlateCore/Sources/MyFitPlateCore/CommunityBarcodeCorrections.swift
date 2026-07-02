import Foundation

/// The community correction pool: sanity-checked barcode fixes shared across all users via
/// the validated `barcodes` Firestore collection. Every user's "Remember"/"Fix" on a barcode
/// can improve the next user's scan — the flywheel single-database apps can't spin. Gated
/// behind the `communityBarcodeCorrections` feature flag (default off) until the rules
/// deploy and a soak period say otherwise.
public protocol CommunityBarcodeStoreProtocol: Sendable {
    func communityFood(for barcode: String) async -> FoodItem?
    func contribute(_ item: FoodItem, barcode: String) async
}

public enum CommunityBarcodeRules {
    /// Source name that marks a community-pool match. Deliberately NOT a new
    /// `FoodSourceType` case: community entries ride `.custom`, so metadata stored by this
    /// version still decodes on older app versions.
    public static let sourceName = "MyFitPlate Community"

    /// Contribution gate. Everything must pass before a correction leaves the device:
    /// the feature flag, a non-empty barcode, the sanity checker (never pool data that
    /// fails nutrition math), and the shared collection's field limits.
    public static func isEligibleForContribution(
        _ item: FoodItem,
        barcode: String,
        flagEnabled: Bool
    ) -> Bool {
        guard flagEnabled else { return false }
        guard !BarcodeCorrectionRules.normalizedBarcode(barcode).isEmpty else { return false }
        guard !FoodDataSanity.isSuspicious(item) else { return false }

        let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 140 else { return false }
        guard item.calories >= 0, item.calories <= 5000 else { return false }
        guard [item.protein, item.carbs, item.fats].allSatisfy({ $0 >= 0 && $0 <= 1000 }) else { return false }
        return true
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
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: sourceName,
                sourceID: "community_\(normalized)",
                barcode: normalized
            )
        )
    }

    public static func isCommunityMatch(_ metadata: FoodSourceMetadata?) -> Bool {
        metadata?.sourceName == sourceName
    }
}
