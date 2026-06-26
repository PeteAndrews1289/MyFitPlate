import Foundation
import FirebaseFirestore
import FirebaseAnalytics

class CustomFoodStore {
    private let db = Firestore.firestore()
    private let customFoodsCollection = "customFoods"

    func saveCustomFood(for userID: String, foodItem: FoodItem, completion: @escaping (Bool) -> Void) {
        let ref = db.collection("users").document(userID).collection(customFoodsCollection).document(foodItem.id)
        do {
            try ref.setData(from: foodItem, merge: true) { error in
                if error == nil {
                    Analytics.logEvent("custom_food_saved", parameters: nil)
                }
                completion(error == nil)
            }
        } catch {
            completion(false)
        }
    }

    func deleteCustomFood(for userID: String, foodItemID: String, completion: @escaping (Bool) -> Void) {
        let ref = db.collection("users").document(userID).collection(customFoodsCollection).document(foodItemID)
        ref.delete { error in
            completion(error == nil)
        }
    }

    func fetchMyFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        let ref = db.collection("users").document(userID).collection(customFoodsCollection).order(by: "name")
        ref.getDocuments { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let foodItems: [FoodItem] = snapshot?.documents.compactMap { doc in
                try? doc.data(as: FoodItem.self)
            } ?? []
            completion(.success(foodItems))
        }
    }
}
