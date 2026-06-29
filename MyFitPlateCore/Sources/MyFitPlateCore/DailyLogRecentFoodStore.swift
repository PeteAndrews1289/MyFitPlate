import Foundation

final class DailyLogRecentFoodStore {
    private let collectionName = "recentFoods"

    public init() {
    }

    public func addRecentFood(for userID: String, foodItem: FoodItem, source: String) {
        guard !userID.isEmpty else { return }
        
        let stableID = stableID(for: foodItem)

        // 1. Update local cache immediately
        updateLocalCache(userID: userID, adding: foodItem)

        // 2. Sync to Firestore
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.saveRecentFood(userID: userID, foodItem: foodItem, source: source, stableID: stableID)
            } catch {
                AppLog.data.error("Failed to encode recent food: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
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
        Task {
            do {
                let foodItems = try await DIContainer.shared.nutritionRepository.fetchRecentFoods(userID: userID, limit: 10)
                
                // Update local cache
                if let encoded = try? JSONEncoder().encode(foodItems) {
                    UserDefaults.standard.set(encoded, forKey: cacheKey)
                }

                DispatchQueue.main.async { completion(.success(foodItems)) }
            } catch {
                // Only surface the error if we didn't already succeed with cache
                if UserDefaults.standard.data(forKey: cacheKey) == nil {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
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
