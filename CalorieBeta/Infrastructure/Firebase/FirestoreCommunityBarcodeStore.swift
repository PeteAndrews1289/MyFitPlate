import Foundation
import FirebaseFirestore
import MyFitPlateCore

/// Reads only server-owned, identifier-free consensus documents. Contributions go through an
/// authenticated App Check callable into a private per-user path; the client cannot write the
/// aggregate or private submission collections directly.
final class FirestoreCommunityBarcodeStore: CommunityBarcodeStoreProtocol, @unchecked Sendable {

    private var aggregatesCollection: CollectionReference {
        Firestore.firestore().collection("communityBarcodeAggregates")
    }

    func communityFood(for barcode: String) async -> FoodItem? {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard !normalized.isEmpty else { return nil }

        do {
            let document = try await aggregatesCollection.document(normalized).getDocument()
            guard let data = document.data(),
                  Set(data.keys).isSubset(of: Self.allowedAggregateFields),
                  let schemaVersion = intValue(data["schemaVersion"]),
                  let modelVersion = data["modelVersion"] as? String,
                  let status = data["status"] as? String,
                  let publishedBarcode = data["barcode"] as? String,
                  let contributorCount = intValue(data["contributorCount"]),
                  let agreementCount = intValue(data["agreementCount"]),
                  let conflictCount = intValue(data["conflictCount"]),
                  let agreementRatio = doubleValue(data["agreementRatio"]),
                  let revision = intValue(data["revision"]),
                  revision >= 1,
                  data["updatedAt"] is Timestamp,
                  let name = data["name"] as? String,
                  let calories = doubleValue(data["calories"]),
                  let protein = doubleValue(data["protein"]),
                  let carbs = doubleValue(data["carbs"]),
                  let fats = doubleValue(data["fats"]),
                  let servingSize = data["servingSize"] as? String,
                  let servingWeight = doubleValue(data["servingWeight"]) else {
                return nil
            }

            let aggregateDecision = CommunityBarcodeRules.aggregateDecision(
                CommunityBarcodeAggregateEvidence(
                    schemaVersion: schemaVersion,
                    modelVersion: modelVersion,
                    status: status,
                    barcode: publishedBarcode,
                    contributorCount: contributorCount,
                    agreementCount: agreementCount,
                    conflictCount: conflictCount,
                    agreementRatio: agreementRatio
                ),
                expectedBarcode: normalized
            )
            guard aggregateDecision.isEligible else { return nil }

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

        var payload: [String: Any] = [
            "barcode": normalized,
            "name": item.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "calories": item.calories,
            "protein": item.protein,
            "carbs": item.carbs,
            "fats": item.fats,
            "servingSize": item.servingSize,
            "servingWeight": item.servingWeight
        ]
        if let fiber = item.fiber {
            payload["fiber"] = fiber
        }

        do {
            let cloudFunctions: CloudFunctionServiceProtocol? = await MainActor.run {
                DIContainer.shared.cloudFunctionService
            }
            guard let cloudFunctions else { return }
            _ = try await cloudFunctions.callFunction(
                "submitCommunityBarcodeContribution",
                with: payload
            )
        } catch {
            AppLog.data.error("Community barcode contribution failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard !(value is Bool) else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func intValue(_ value: Any?) -> Int? {
        guard !(value is Bool), let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double >= 0, double <= 1_000_000 else {
            return nil
        }
        return Int(double)
    }

    private static let allowedAggregateFields: Set<String> = [
        "schemaVersion", "modelVersion", "status", "barcode", "name", "calories",
        "protein", "carbs", "fats", "fiber", "servingSize", "servingWeight",
        "contributorCount", "agreementCount", "conflictCount", "agreementRatio",
        "revision", "updatedAt"
    ]
}
