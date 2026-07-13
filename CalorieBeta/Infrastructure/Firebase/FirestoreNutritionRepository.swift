import Foundation
import MyFitPlateCore
import FirebaseFirestore
import OSLog

final class FirestoreNutritionRepository: NutritionRepositoryProtocol, @unchecked Sendable {
    private let db = Firestore.firestore()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {
        guard let logID = log.id else { completion(false); return }
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(logID)
        do {
            try ref.setData(from: log, merge: true) { err in
                completion(err == nil)
            }
        } catch {
            completion(false)
        }
    }
    
    func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let dateString = dateFormatter.string(from: startOfDay)
        let logRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(dateString)
        
        logRef.getDocument { [weak self] document, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            if let document = document, document.exists, let data = document.data() {
                do {
                    completion(.success(try self.decodeDailyLog(from: data, documentID: dateString)))
                } catch {
                    completion(.failure(error))
                }
            } else {
                let newLog = DailyLog(id: dateString, date: startOfDay, meals: [], journalEntries: [])
                do {
                    try logRef.setData(from: newLog, merge: true) { err in
                        if let err = err {
                            completion(.failure(err))
                        } else {
                            completion(.success(newLog))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let dateString = dateFormatter.string(from: startOfDay)
        let logRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs).document(dateString)
        
        let listener = logRef.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            if let error = error {
                onChange(.failure(error))
                return
            }
            guard let document = documentSnapshot else {
                onChange(.failure(NSError(domain: "App", code: -1, userInfo: [NSLocalizedDescriptionKey: "Snapshot nil for \(dateString)"])))
                return
            }
            if document.exists, let data = document.data() {
                do {
                    onChange(.success(try self.decodeDailyLog(from: data, documentID: dateString)))
                } catch {
                    onChange(.failure(error))
                }
            } else {
                let newLog = DailyLog(id: dateString, date: startOfDay, meals: [], journalEntries: [])
                do {
                    try logRef.setData(from: newLog, merge: true) { err in
                        if let err = err {
                            onChange(.failure(err))
                        } else {
                            onChange(.success(newLog))
                        }
                    }
                } catch {
                    onChange(.failure(error))
                }
            }
        }
        return listener
    }
    
    func removeLogSnapshotListener(_ handle: Any) {
        if let listener = handle as? ListenerRegistration {
            listener.remove()
        }
    }
    
    func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog] {
        var query: Query = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs)
        if let start = startDate { query = query.whereField("date", isGreaterThanOrEqualTo: Timestamp(date: start)) }
        if let end = endDate {
            let endOfQueryDay = Calendar.current.startOfDay(for: end).addingTimeInterval(86400)
            query = query.whereField("date", isLessThan: Timestamp(date: endOfQueryDay))
        }
        query = query.order(by: "date", descending: true)
        
        let snapshot = try await query.getDocuments()
        return try snapshot.documents.map { try self.decodeDailyLog(from: $0.data(), documentID: $0.documentID) }
    }
    
    func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) else {
            completion(.success([]))
            return
        }

        db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.dailyLogs)
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("date", isLessThanOrEqualTo: Timestamp(date: endDate))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }

                var foodFrequency: [String: (food: FoodItem, count: Int)] = [:]
                let logs: [DailyLog]
                do {
                    logs = try documents.map {
                        try self.decodeDailyLog(from: $0.data(), documentID: $0.documentID)
                    }
                } catch {
                    completion(.failure(error))
                    return
                }

                for log in logs {
                    if let meal = log.meals.first(where: { $0.name.lowercased() == mealName.lowercased() }) {
                        for food in meal.foodItems {
                            if var entry = foodFrequency[food.name] {
                                entry.count += 1
                                foodFrequency[food.name] = entry
                            } else {
                                foodFrequency[food.name] = (food: food, count: 1)
                            }
                        }
                    }
                }

                let sortedFoods = foodFrequency.values
                    .sorted { $0.count > $1.count }
                    .map { $0.food }

                completion(.success(Array(sortedFoods.prefix(10))))
            }
    }
    
    private func decodeDailyLog(from data: [String: Any], documentID: String) throws -> DailyLog {
        do {
            return try Firestore.Decoder().decode(DailyLog.self, from: data)
        } catch {
            AppLog.data.error("Failed to decode DailyLog \(documentID, privacy: .public). Preserving remote document: \(error.localizedDescription, privacy: .public)")
            throw FirestoreNutritionRepositoryError.dailyLogDecodeFailed(documentID: documentID, underlying: error)
        }
    }
    
    func saveDailyLog(userID: String, log: DailyLog) async throws {
        let db = Firestore.firestore()
        let ref = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection(FirestoreCollection.dailyLogs)
            .document(log.id ?? "")
            
        try ref.setData(from: log)
    }
    
    // MARK: - Generic Firestore Fetch (Internal)y List
    
    // MARK: - Meal Plans & Grocery List
    
    func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? {
        let planRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans).document(dateString)
        return try await planRef.getDocument(as: MealPlanDay.self)
    }
    
    private struct MealPlanPayload: Codable {
        let date: Timestamp
        let meals: [PlannedMeal]
    }
    
    func saveMealPlan(userID: String, plan: MealPlanDay) async throws {
        let planID = plan.id
        let planRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans).document(planID)
        let data = try Firestore.Encoder().encode(MealPlanPayload(date: Timestamp(date: plan.date), meals: plan.meals))
        try await planRef.setData(data, merge: true)
    }
    
    func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        let batch = db.batch()
        let collectionRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans)
        
        for plan in plans {
            let dayId = plan.id
            let data = try Firestore.Encoder().encode(MealPlanPayload(date: Timestamp(date: plan.date), meals: plan.meals))
            batch.setData(data, forDocument: collectionRef.document(dayId), merge: true)
        }
        
        try await batch.commit()
    }
    
    func fetchGroceryList(userID: String) async throws -> [GroceryListItem] {
        let listRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        let document = try await listRef.getDocument()
        guard let data = document.data(), let itemsData = data["items"] as? [[String: Any]] else { return [] }
        
        return itemsData.compactMap { itemData in
            try? Firestore.Decoder().decode(GroceryListItem.self, from: itemData)
        }
    }
    
    func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {
        let listRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.userSettings).document(FirestoreDocument.groceryList)
        let listData = try items.map { try Firestore.Encoder().encode($0) }
        try await listRef.setData(["items": listData, "lastUpdated": Timestamp(date: Date())], merge: true)
    }
    
    // MARK: - Pantry
    
    func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems)
        return ref.addSnapshotListener { snapshot, error in
            if let error = error {
                onChange(.failure(error))
                return
            }
            guard let documents = snapshot?.documents else { return }
            let items = documents.compactMap { try? $0.data(as: PantryItem.self) }
            onChange(.success(items))
        }
    }
    
    func removePantrySnapshotListener(_ handle: Any) {
        if let registration = handle as? ListenerRegistration {
            registration.remove()
        }
    }
    
    func savePantryItem(userID: String, item: PantryItem) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(item.id.uuidString)
        try ref.setData(from: item)
    }
    
    func deletePantryItem(userID: String, itemID: String) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(itemID)
        try await ref.delete()
    }
    
    // MARK: - Recipes
    
    func fetchRecipes(userID: String) async throws -> [Recipe] {
        let collection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        let snapshot = try await collection.getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Recipe.self) }
    }
    
    func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe {
        let collection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        var recipeToSave = recipe
        if let id = recipeToSave.id {
            try collection.document(id).setData(from: recipeToSave)
        } else {
            let newDocRef = collection.document()
            recipeToSave.id = newDocRef.documentID
            try newDocRef.setData(from: recipeToSave)
        }
        return recipeToSave
    }
    
    func deleteRecipe(userID: String, recipeID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes).document(recipeID).delete()
    }
    
    // MARK: - Custom Foods
    
    func saveCustomFood(userID: String, foodItem: FoodItem) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("customFoods").document(foodItem.id)
        // Custom-food edits are complete replacements. Merge would retain cleared optional fields
        // such as saturated fat or barcode associations when Firestore.Encoder omits nil values.
        try ref.setData(from: foodItem, merge: false)
    }
    
    func deleteCustomFood(userID: String, foodItemID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).collection("customFoods").document(foodItemID).delete()
    }

    func removeCustomFoodBarcode(userID: String, foodItemID: String) async throws {
        let ref = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection("customFoods")
            .document(foodItemID)
        try await ref.updateData(["sourceMetadata.barcode": FieldValue.delete()])
    }

    func mergeCustomFoods(userID: String, keepingFoodID: String, removingFoodIDs: [String]) async throws {
        let uniqueIDs = Array(Set(removingFoodIDs)).filter { $0 != keepingFoodID }
        guard !uniqueIDs.isEmpty else { return }
        guard uniqueIDs.count <= 499 else {
            throw NSError(
                domain: "MyFoodsLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Too many duplicate foods to merge at once."]
            )
        }

        let collection = db.collection(FirestoreCollection.users)
            .document(userID)
            .collection("customFoods")
        let batch = db.batch()
        for foodID in uniqueIDs {
            batch.deleteDocument(collection.document(foodID))
        }
        try await batch.commit()
    }
    
    func fetchCustomFoods(userID: String) async throws -> [FoodItem] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("customFoods").order(by: "name").getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodItem.self) }
    }
    
    // MARK: - Recent Foods
    
    func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection("recentFoods").document(stableID)
        var data = try Firestore.Encoder().encode(foodItem)
        data["timestamp"] = Timestamp(date: Date())
        data["source"] = source
        try await ref.setData(data, merge: false)
    }
    
    func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem] {
        let snapshot = try await db.collection(FirestoreCollection.users).document(userID).collection("recentFoods")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodItem.self) }
    }
}

private enum FirestoreNutritionRepositoryError: LocalizedError {
    case dailyLogDecodeFailed(documentID: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .dailyLogDecodeFailed(let documentID, _):
            return "The daily log for \(documentID) could not be read. Its stored data was left unchanged."
        }
    }
}
