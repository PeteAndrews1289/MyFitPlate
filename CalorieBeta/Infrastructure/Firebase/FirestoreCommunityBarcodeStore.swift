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
                  let calories = data["calories"] as? Double else {
                return nil
            }

            return CommunityBarcodeRules.communityFoodItem(
                name: name,
                calories: calories,
                protein: data["protein"] as? Double ?? 0,
                carbs: data["carbs"] as? Double ?? 0,
                fats: data["fats"] as? Double ?? 0,
                fiber: data["fiber"] as? Double,
                servingSize: data["servingSize"] as? String ?? "",
                servingWeight: data["servingWeight"] as? Double ?? 0,
                barcode: normalized
            )
        } catch {
            AppLog.data.error("Community barcode read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func contribute(_ item: FoodItem, barcode: String) async {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !normalized.isEmpty else { return }
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
}
