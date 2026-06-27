import Foundation
import FirebaseFirestore

final class DailyLogRecentFoodStore {
    private let db: Firestore
    private let collectionName = "recentFoods"

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func addRecentFood(for userID: String, foodItem: FoodItem, source: String) {
        guard !userID.isEmpty else { return }

        let ref = db.collection(FirestoreCollection.users).document(userID).collection(collectionName)
        let timestamp = Timestamp(date: Date())
        let stableID = stableID(for: foodItem)

        // 1. Update local cache immediately
        updateLocalCache(userID: userID, adding: foodItem)

        // 2. Sync to Firestore
        do {
            var data = try Firestore.Encoder().encode(foodItem)
            data["timestamp"] = timestamp
            data["source"] = source

            ref.document(stableID).setData(data, merge: false) { error in
                if let error {
                    AppLog.data.error("Failed to add or update recent food: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            AppLog.data.error("Failed to encode recent food: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard !userID.isEmpty else {
            completion(.failure(NSError(domain: "DailyLogRecentFoodStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID is empty."])))
            return
        }

        // 1. Instantly return local cache
        let cacheKey = "recentFoods_\(userID)"
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cachedItems = try? JSONDecoder().decode([FoodItem].self, from: data) {
            completion(.success(cachedItems))
        }

        // 2. Fetch fresh data from Firestore in background
        db.collection(FirestoreCollection.users).document(userID).collection(collectionName)
            .order(by: "timestamp", descending: true)
            .limit(to: 10)
            .getDocuments { snapshot, error in
                if let error {
                    // Only surface the error if we didn't already succeed with cache
                    if UserDefaults.standard.data(forKey: cacheKey) == nil {
                        completion(.failure(error))
                    }
                    return
                }

                let foodItems: [FoodItem] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: FoodItem.self)
                } ?? []
                
                // Update local cache
                if let encoded = try? JSONEncoder().encode(foodItems) {
                    UserDefaults.standard.set(encoded, forKey: cacheKey)
                }

                completion(.success(foodItems))
            }
    }
    
    private func updateLocalCache(userID: String, adding newFood: FoodItem) {
        let cacheKey = "recentFoods_\(userID)"
        var currentItems: [FoodItem] = []
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            currentItems = decoded
        }
        
        // Remove existing item with same name if it exists (so it gets moved to top)
        currentItems.removeAll { $0.name.lowercased() == newFood.name.lowercased() }
        currentItems.insert(newFood, at: 0)
        
        // Keep only top 10 to match Firestore limit
        if currentItems.count > 10 {
            currentItems = Array(currentItems.prefix(10))
        }
        
        if let encoded = try? JSONEncoder().encode(currentItems) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    private func stableID(for foodItem: FoodItem) -> String {
        Data(foodItem.name.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
