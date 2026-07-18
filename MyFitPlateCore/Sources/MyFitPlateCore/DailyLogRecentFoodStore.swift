import Foundation

@MainActor
final class DailyLogRecentFoodStore {
    private let collectionName = "recentFoods"
    private let defaults: UserDefaults
    private let cacheKeyPrefix = "recentFoods"

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    public func addRecentFood(for userID: String, foodItem: FoodItem, source: String) {
        guard !userID.isEmpty,
              DIContainer.shared.authService.currentUserID == userID,
              let cacheKey = prepareCache(for: userID) else { return }
        
        let stableID = stableID(for: foodItem)

        // 1. Update local cache immediately
        updateLocalCache(cacheKey: cacheKey, adding: foodItem)

        // 2. Sync to Firestore
        Task {
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            do {
                try await DIContainer.shared.nutritionRepository.saveRecentFood(userID: userID, foodItem: foodItem, source: source, stableID: stableID)
            } catch {
                AppLog.data.error("Failed to encode recent food: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard !userID.isEmpty,
              DIContainer.shared.authService.currentUserID == userID,
              let cacheKey = prepareCache(for: userID) else {
            completion(.failure(NSError(domain: "DailyLogRecentFoodStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID is empty."])))
            return
        }

        // 1. Instantly return local cache
        if let data = defaults.data(forKey: cacheKey),
           let cachedItems = try? JSONDecoder().decode([FoodItem].self, from: data) {
            completion(.success(cachedItems))
        }

        // 2. Fetch fresh data from Firestore in background
        Task {
            do {
                let foodItems = try await DIContainer.shared.nutritionRepository.fetchRecentFoods(userID: userID, limit: 10)
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                
                // Update local cache
                if let encoded = try? JSONEncoder().encode(foodItems) {
                    defaults.set(encoded, forKey: cacheKey)
                }

                DispatchQueue.main.async {
                    guard DIContainer.shared.authService.currentUserID == userID else { return }
                    completion(.success(foodItems))
                }
            } catch {
                // Only surface the error if we didn't already succeed with cache
                if defaults.data(forKey: cacheKey) == nil {
                    DispatchQueue.main.async {
                        guard DIContainer.shared.authService.currentUserID == userID else { return }
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    private func updateLocalCache(cacheKey: String, adding newFood: FoodItem) {
        var currentItems: [FoodItem] = []
        if let data = defaults.data(forKey: cacheKey),
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
            defaults.set(encoded, forKey: cacheKey)
        }
    }

    private func prepareCache(for userID: String) -> String? {
        guard let key = AccountScopedStorageKey.make(prefix: cacheKeyPrefix, userID: userID) else {
            return nil
        }
        let legacyKey = "recentFoods_\(userID)"
        if defaults.data(forKey: key) == nil,
           let legacyData = defaults.data(forKey: legacyKey) {
            defaults.set(legacyData, forKey: key)
        }
        defaults.removeObject(forKey: legacyKey)
        return key
    }

    private func stableID(for foodItem: FoodItem) -> String {
        Data(foodItem.name.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
