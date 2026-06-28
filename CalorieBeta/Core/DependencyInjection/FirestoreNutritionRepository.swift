import Foundation
import FirebaseFirestore
import OSLog

class FirestoreNutritionRepository: NutritionRepositoryProtocol {
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
                completion(.success(self.decodeDailyLog(from: data, documentID: dateString)))
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
                onChange(.failure(NSError(domain:"App", code: -1, userInfo: [NSLocalizedDescriptionKey:"Snapshot nil for \(dateString)"])))
                return
            }
            if document.exists, let data = document.data() {
                onChange(.success(self.decodeDailyLog(from: data, documentID: dateString)))
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
        return snapshot.documents.map { self.decodeDailyLog(from: $0.data(), documentID: $0.documentID) }
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
                let logs = documents.compactMap { try? Firestore.Decoder().decode(DailyLog.self, from: $0.data()) }

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
    
    private func decodeDailyLog(from data: [String: Any], documentID: String) -> DailyLog {
        do {
            let decodedLog = try Firestore.Decoder().decode(DailyLog.self, from: data)
            return decodedLog
        } catch {
            AppLog.data.error("Failed to decode DailyLog \(documentID, privacy: .public). Returning default: \(error.localizedDescription, privacy: .public)")
            let dateFromDocID = dateFormatter.date(from: documentID) ?? Calendar.current.startOfDay(for: Date())
            return DailyLog(id: documentID, date: dateFromDocID, meals: [], journalEntries: [])
        }
    }
    
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
        guard let planID = plan.id else { return }
        let planRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans).document(planID)
        let data = try Firestore.Encoder().encode(MealPlanPayload(date: plan.date, meals: plan.meals))
        try await planRef.setData(data, merge: true)
    }
    
    func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        let batch = db.batch()
        let collectionRef = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.mealPlans)
        
        for plan in plans {
            if let dayId = plan.id {
                let data = try Firestore.Encoder().encode(MealPlanPayload(date: plan.date, meals: plan.meals))
                batch.setData(data, forDocument: collectionRef.document(dayId), merge: true)
            }
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
        try ref.setData(from: foodItem, merge: true)
    }
    
    func deleteCustomFood(userID: String, foodItemID: String) async throws {
        try await db.collection(FirestoreCollection.users).document(userID).collection("customFoods").document(foodItemID).delete()
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
