import Foundation
import FirebaseAnalytics

class CustomFoodStore {
    private let customFoodsCollection = "customFoods"

    func saveCustomFood(for userID: String, foodItem: FoodItem, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.saveCustomFood(userID: userID, foodItem: foodItem)
                Analytics.logEvent("custom_food_saved", parameters: nil)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func deleteCustomFood(for userID: String, foodItemID: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.deleteCustomFood(userID: userID, foodItemID: foodItemID)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func fetchMyFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        Task {
            do {
                let items = try await DIContainer.shared.nutritionRepository.fetchCustomFoods(userID: userID)
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
