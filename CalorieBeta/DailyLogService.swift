import Foundation
import FirebaseAuth
import FirebaseFirestore
import WidgetKit

class DailyLogService: ObservableObject {
    @Published var currentDailyLog: DailyLog?
    @Published var activelyViewedDate: Date = Calendar.current.startOfDay(for: Date())
    private let db = Firestore.firestore()
    private var logListener: ListenerRegistration?
    private let recentFoodsCollection = "recentFoods"
    private let customFoodsCollection = "customFoods"
    weak var achievementService: AchievementService?
    weak var bannerService: BannerService?
    weak var goalSettings: GoalSettings?

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {}

    func updateWidgetData() {
        guard let log = self.currentDailyLog, let goals = self.goalSettings else { return }

        let widgetData = WidgetData(
            calories: log.totalCalories(),
            calorieGoal: goals.calories ?? 0,
            protein: log.totalMacros().protein,
            proteinGoal: goals.protein,
            carbs: log.totalMacros().carbs,
            carbsGoal: goals.carbs,
            fats: log.totalMacros().fats,
            fatGoal: goals.fats
        )
        
        SharedDataManager.shared.saveData(widgetData)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)? = nil) {
        guard let logID = updatedLog.id else { completion?(false); return }
        let ref = db.collection("users").document(userID).collection("dailyLogs").document(logID)
        do {
            let data = try Firestore.Encoder().encode(updatedLog)
            ref.setData(data, merge: true) { err in
                 if err == nil {
                     self.currentDailyLog = updatedLog
                     self.updateWidgetData()
                     completion?(true)
                 } else {
                     completion?(false)
                 }
            }
        } catch {
            completion?(false)
        }
    }
    
    func saveCustomFood(for userID: String, foodItem: FoodItem, completion: @escaping (Bool) -> Void) {
        let ref = db.collection("users").document(userID).collection(customFoodsCollection).document(foodItem.id)
        do {
            try ref.setData(from: foodItem, merge: true) { error in
                if let error = error {
                    print("Error saving custom food: \(error.localizedDescription)")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        } catch {
            print("Error encoding custom food: \(error.localizedDescription)")
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

    func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let startOfDayForRequestedDate = Calendar.current.startOfDay(for: date)
        self.activelyViewedDate = startOfDayForRequestedDate
        let dateString = dateFormatter.string(from: startOfDayForRequestedDate)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)
        
        logListener?.remove()

        logListener = logRef.addSnapshotListener { documentSnapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let document = documentSnapshot else {
                completion(.failure(NSError(domain:"App", code: -1, userInfo: [NSLocalizedDescriptionKey:"Snapshot nil for \(dateString)"])))
                return
            }

            DispatchQueue.main.async {
                if document.exists, let data = document.data() {
                    let fetchedLog = self.decodeDailyLog(from: data, documentID: dateString)
                    self.currentDailyLog = fetchedLog
                    completion(.success(fetchedLog))
                } else {
                    let newLog = DailyLog(id: dateString, date: startOfDayForRequestedDate, meals: [], exercises: [])
                    let encodedLog = self.encodeDailyLog(newLog)
                    logRef.setData(encodedLog) { setError in
                        if let setError = setError {
                            completion(.failure(setError))
                        } else {
                            self.currentDailyLog = newLog
                            completion(.success(newLog))
                        }
                    }
                }
            }
        }
    }

    func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let dateString = dateFormatter.string(from: startOfDay)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)
        logRef.getDocument { document, error in
            if let e = error { completion(.failure(e)); return }
            if let d = document, d.exists, let data = d.data() {
                completion(.success(self.decodeDailyLog(from: data, documentID: dateString)))
            } else {
                let newLog = DailyLog(id: dateString, date: startOfDay, meals: [], exercises: [])
                completion(.success(newLog))
            }
        }
    }

    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        fetchLog(for: userID, date: Date(), completion: completion)
    }

    func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String = "unknown") {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                var itemToAdd = foodItem
                if itemToAdd.timestamp == nil { itemToAdd.timestamp = Date() }
                let mealName = self.determineMealType()
                if let index = log.meals.firstIndex(where: { $0.name == mealName }) {
                    log.meals[index].foodItems.append(itemToAdd)
                } else {
                    log.meals.append(Meal(name: mealName, foodItems: [itemToAdd]))
                }
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        self.addRecentFood(for: userID, foodItem: itemToAdd, source: source)
                        Task { @MainActor in
                            self.bannerService?.showBanner(title: "Success", message: "\(foodItem.name) logged!")
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                        }
                    }
                }
            case .failure(let e):
                print("Error fetching log for adding food: \(e.localizedDescription)")
            }
        }
    }
    
    func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                var itemUpdated = false
                for i in 0..<log.meals.count {
                    if let index = log.meals[i].foodItems.firstIndex(where: { $0.id == updatedFoodItem.id }) {
                        log.meals[i].foodItems[index] = updatedFoodItem
                        itemUpdated = true
                        break
                    }
                }
                
                if itemUpdated {
                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success {
                            Task { @MainActor in
                                self.bannerService?.showBanner(title: "Success", message: "\(updatedFoodItem.name) updated!")
                                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                            }
                        }
                    }
                }
            case .failure(let e):
                print("Error fetching log for updating food: \(e.localizedDescription)")
            }
        }
    }

    func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let itemsWithTimestamp = foodItems.map { item -> FoodItem in var mutableItem = item; if mutableItem.timestamp == nil { mutableItem.timestamp = Date() }; return mutableItem }
                let newMeal = Meal(name: mealName, foodItems: itemsWithTimestamp)
                log.meals.append(newMeal)
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        itemsWithTimestamp.forEach { item in
                            var itemSource: String
                            if mealName.lowercased().contains("ai") { itemSource = "ai" } else { itemSource = "recipe" }
                            self.addRecentFood(for: userID, foodItem: item, source: itemSource)
                        }
                        Task { @MainActor in
                            self.bannerService?.showBanner(title: "Success", message: "\(mealName) logged!")
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                        }
                    }
                }
            case .failure(let e):
                 print("Error fetching log for adding meal: \(e.localizedDescription)")
            }
        }
    }
    
    func deleteFoodFromCurrentLog(for userID: String, foodItemID: String) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                var deleted = false
                for i in log.meals.indices { let initialCount = log.meals[i].foodItems.count; log.meals[i].foodItems.removeAll { $0.id == foodItemID }; if log.meals[i].foodItems.count < initialCount { deleted = true } }
                if deleted { self.updateDailyLog(for: userID, updatedLog: log) }
            case .failure(let e): print("Error fetching log for delete: \(e.localizedDescription)")
            }
        }
    }

    func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
        DispatchQueue.main.async {
            guard var log = self.currentDailyLog else {
                return
            }
            
            let startOfDay = Calendar.current.startOfDay(for: self.activelyViewedDate)
            guard Calendar.current.isDate(log.date, inSameDayAs: startOfDay) else {
                return
            }

            if var waterTracker = log.waterTracker {
                waterTracker.totalOunces += amount
                if waterTracker.totalOunces < 0 {
                    waterTracker.totalOunces = 0
                }
                waterTracker.goalOunces = goalOunces
                log.waterTracker = waterTracker
            } else {
                let initialAmount = max(0, amount)
                log.waterTracker = WaterTracker(totalOunces: initialAmount, goalOunces: goalOunces, date: startOfDay)
            }
            
            self.currentDailyLog = log
            
            self.updateDailyLog(for: userID, updatedLog: log)
        }
    }
    
    func addExerciseToLog(for userID: String, exercise: LoggedExercise) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                if log.exercises == nil { log.exercises = [] }
                var exerciseToLog = exercise
                exerciseToLog.date = dateToLog
                log.exercises?.append(exerciseToLog)
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        Task { @MainActor in
                            self.achievementService?.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
                        }
                        NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                    }
                }
            case .failure(let error): print("Error fetching log for adding exercise: \(error.localizedDescription)")
            }
        }
    }

    func deleteExerciseFromLog(for userID: String, exerciseID: String) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let initialCount = log.exercises?.count ?? 0
                log.exercises?.removeAll { $0.id == exerciseID }
                if (log.exercises?.count ?? 0) < initialCount {
                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success { NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil) }
                    }
                }
            case .failure(let error): print("Error fetching log for deleting exercise: \(error.localizedDescription)")
            }
        }
    }
    
    func addOrUpdateHealthKitWorkouts(for userID: String, exercises: [LoggedExercise], date: Date, completion: (() -> Void)? = nil) {
        let dateToLog = Calendar.current.startOfDay(for: date)
        
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            switch result {
            case .success(var log):
                if log.exercises == nil {
                    log.exercises = []
                }
                
                log.exercises?.removeAll { $0.source == "HealthKit" }
                
                log.exercises?.append(contentsOf: exercises)
                
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                        }
                    }
                    completion?()
                }
            case .failure(let error):
                completion?()
            }
        }
    }

    private func addRecentFood(for userID: String, foodItem: FoodItem, source: String) {
        guard !userID.isEmpty else { return }
        let ref = db.collection("users").document(userID).collection(recentFoodsCollection)
        let ts = Timestamp(date: Date())

        do {
            var data = try Firestore.Encoder().encode(foodItem)
            data["timestamp"] = ts
            data["source"] = source
            
            ref.document(foodItem.id).setData(data, merge: true) { error in
                if let error = error {
                    print("Error adding recent food: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error encoding recent food: \(error.localizedDescription)")
        }
    }
    
    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard !userID.isEmpty else {
            completion(.failure(NSError(domain: "DailyLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID is empty."])))
            return
        }
        let ref = db.collection("users").document(userID).collection(recentFoodsCollection).order(by: "timestamp", descending: true).limit(to: 10)
        ref.getDocuments { snapshot, error in
            if let e = error {
                completion(.failure(e))
                return
            }
            let foodItems: [FoodItem] = snapshot?.documents.compactMap { doc in
                try? doc.data(as: FoodItem.self)
            } ?? []
            completion(.success(foodItems))
        }
    }
    
    func fetchDailyHistory(for userID: String, startDate: Date? = nil, endDate: Date? = nil, completion: @escaping (Result<[DailyLog], Error>) -> Void) {
        var query: Query = db.collection("users").document(userID).collection("dailyLogs")
        let queryStartDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        let queryEndDate = endDate.map { Calendar.current.startOfDay(for: $0) }

        if let start = queryStartDate { query = query.whereField("date", isGreaterThanOrEqualTo: Timestamp(date: start)) }
        if let end = queryEndDate {
            let endOfQueryDay = Calendar.current.date(byAdding: .day, value: 1, to: end)!
            query = query.whereField("date", isLessThan: Timestamp(date: endOfQueryDay))
        }
        query = query.order(by: "date", descending: true)
        query.getDocuments { snapshot, error in if let e = error { completion(.failure(e)); return }; let logs: [DailyLog] = snapshot?.documents.compactMap { d in self.decodeDailyLog(from: d.data(), documentID: d.documentID) } ?? []; completion(.success(logs)) }
    }

    private func encodeDailyLog(_ log: DailyLog) -> [String: Any] {
        do {
            return try Firestore.Encoder().encode(log)
        } catch {
            return [:]
        }
    }


     private func decodeDailyLog(from data: [String: Any], documentID: String) -> DailyLog {
        do {
            var decodedLog = try Firestore.Decoder().decode(DailyLog.self, from: data)
            decodedLog.id = documentID
            return decodedLog
        } catch {
            let dateFromDocID = dateFormatter.date(from: documentID) ?? Calendar.current.startOfDay(for: Date())
            return DailyLog(id: documentID, date: dateFromDocID, meals: [])
        }
     }
    
      private func determineMealType() -> String {
          let hour = Calendar.current.component(.hour, from: Date()); switch hour { case 0..<4: return "Snack"; case 4..<11: return "Breakfast"; case 11..<16: return "Lunch"; case 16..<21: return "Dinner"; default: return "Snack" }
      }
}

extension Notification.Name {
    static let didUpdateExerciseLog = Notification.Name("didUpdateExerciseLog")
}
