import Foundation
public class CustomFoodStore {
    private let customFoodsCollection = "customFoods"

    private enum StoreError: LocalizedError {
        case missingBarcode
        case missingRepository

        var errorDescription: String? {
            switch self {
            case .missingBarcode:
                return "A barcode is required to save this correction."
            case .missingRepository:
                return "Custom foods are temporarily unavailable."
            }
        }
    }

    public init() {}

    public func saveCustomFood(for userID: String, foodItem: FoodItem, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.saveCustomFood(userID: userID, foodItem: foodItem)
                await DIContainer.shared.analyticsManager?.logEvent("custom_food_saved", parameters: nil)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    public func saveBarcodeCorrection(
        for userID: String,
        foodItem: FoodItem,
        completion: @escaping (Result<FoodItem, Error>) -> Void
    ) {
        Task {
            do {
                guard let repository = await DIContainer.shared.nutritionRepository else {
                    throw StoreError.missingRepository
                }
                let barcode = BarcodeCorrectionRules.normalizedBarcode(
                    foodItem.sourceMetadata?.barcode ?? ""
                )
                guard !barcode.isEmpty else { throw StoreError.missingBarcode }

                let existingFoods = try await repository.fetchCustomFoods(userID: userID)
                let matches = existingFoods.filter {
                    BarcodeCorrectionRules.matches($0, barcode: barcode)
                }
                let stableID = Self.stableBarcodeCorrectionID(for: barcode)
                let preferredExisting = matches.first(where: { $0.id == foodItem.id })
                    ?? matches.first(where: { $0.id == stableID })
                    ?? BarcodeCorrectionRules.bestCorrectedFood(in: matches, barcode: barcode)

                var persistedItem = foodItem
                persistedItem.id = preferredExisting?.id ?? stableID
                persistedItem = persistedItem.savedAsCustomFood(barcode: barcode)

                let duplicateIDs = matches
                    .map(\.id)
                    .filter { $0 != persistedItem.id }
                try await repository.saveCustomFoodReplacingDuplicates(
                    userID: userID,
                    foodItem: persistedItem,
                    removingFoodIDs: duplicateIDs
                )
                await DIContainer.shared.analyticsManager?.logEvent(
                    "custom_food_saved",
                    parameters: ["kind": "barcode_correction"]
                )
                DispatchQueue.main.async { completion(.success(persistedItem)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    public func deleteCustomFood(for userID: String, foodItemID: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.deleteCustomFood(userID: userID, foodItemID: foodItemID)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    public func removeBarcodeAssociation(for userID: String, foodItemID: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.removeCustomFoodBarcode(
                    userID: userID,
                    foodItemID: foodItemID
                )
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    public func mergeCustomFoods(
        for userID: String,
        keepingFoodID: String,
        removingFoodIDs: [String],
        completion: @escaping (Bool) -> Void
    ) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.mergeCustomFoods(
                    userID: userID,
                    keepingFoodID: keepingFoodID,
                    removingFoodIDs: removingFoodIDs
                )
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    public func fetchMyFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        Task {
            do {
                let items = try await DIContainer.shared.nutritionRepository.fetchCustomFoods(userID: userID)
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private static func stableBarcodeCorrectionID(for barcode: String) -> String {
        let candidates = BarcodeCorrectionRules.lookupCandidates(for: barcode)
        let identity = candidates.first(where: { $0.count == 14 }) ?? barcode
        let encoded = Data(identity.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "barcode-\(encoded)"
    }
}
