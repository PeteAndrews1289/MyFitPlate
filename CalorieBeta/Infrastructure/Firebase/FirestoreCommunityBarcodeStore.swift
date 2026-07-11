import Foundation
import FirebaseFirestore
import MyFitPlateCore

/// Firestore-backed community barcode-correction pool. One document per normalized barcode
/// in the top-level `barcodes` collection; writes are schema-validated by security rules
/// (see firestore.rules `validBarcodeWrite`). Reads/writes are best-effort: any failure
/// just means the lookup chain falls through to the external databases.
final class FirestoreCommunityBarcodeStore: CommunityBarcodeStoreProtocol, @unchecked Sendable {

    private var barcodesCollection: CollectionReference {
        Firestore.firestore().collection("barcodes")
    }

    func communityFood(for barcode: String) async -> FoodItem? {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !normalized.isEmpty else { return nil }

        do {
            let document = try await barcodesCollection.document(normalized).getDocument()
            guard let data = document.data(),
                  let name = data["name"] as? String,
                  let calories = doubleValue(data["calories"]),
                  let protein = doubleValue(data["protein"]),
                  let carbs = doubleValue(data["carbs"]),
                  let fats = doubleValue(data["fats"]),
                  let servingSize = data["servingSize"] as? String,
                  let servingWeight = doubleValue(data["servingWeight"]) else {
                return nil
            }

            let item = CommunityBarcodeRules.communityFoodItem(
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: fats,
                fiber: doubleValue(data["fiber"]),
                servingSize: servingSize,
                servingWeight: servingWeight,
                barcode: normalized
            )
            let decision = CommunityBarcodeRules.contributionDecision(
                item,
                barcode: normalized,
                flagEnabled: true
            )
            return decision.isEligible ? item : nil
        } catch {
            AppLog.data.error("Community barcode read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func contribute(_ item: FoodItem, barcode: String) async {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        let decision = CommunityBarcodeRules.contributionDecision(
            item,
            barcode: normalized,
            flagEnabled: true
        )
        guard decision.isEligible else { return }
        let createdBy = await MainActor.run { DIContainer.shared.authService?.currentUserID }
        guard let createdBy else { return }

        var fields: [String: Any] = [
            "name": item.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "calories": item.calories,
            "protein": item.protein,
            "carbs": item.carbs,
            "fats": item.fats,
            "servingSize": item.servingSize,
            "servingWeight": item.servingWeight,
            "createdBy": createdBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let fiber = item.fiber {
            fields["fiber"] = fiber
        }

        do {
            try await barcodesCollection.document(normalized).setData(fields)
        } catch {
            // Expected for docs another user created (rules allow creator-only updates).
            AppLog.data.error("Community barcode contribution failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard !(value is Bool) else { return nil }
        return (value as? NSNumber)?.doubleValue
    }
}
