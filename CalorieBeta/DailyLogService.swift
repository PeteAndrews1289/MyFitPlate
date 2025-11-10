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
    private var activeListenerDate: Date?

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {}

    func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService) {
        self.goalSettings = goalSettings
        self.bannerService = bannerService
        self.achievementService = achievementService
    }

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

    func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let dateToLog = self.activelyViewedDate

        do {
            var log = try await fetchLogInternalAsync(for: userID, date: dateToLog)

            var itemToAdd = foodItem
            if itemToAdd.timestamp == nil { itemToAdd.timestamp = Date() }

            if let index = log.meals.firstIndex(where: { $0.name == mealType }) {
                log.meals[index].foodItems.append(itemToAdd)
            } else {
                log.meals.append(Meal(name: mealType, foodItems: [itemToAdd]))
            }

            await MainActor.run {
                self.currentDailyLog = log
                self.updateWidgetData()
            }

            let success = await updateDailyLogAsync(for: userID, updatedLog: log)

            if success {
                HealthKitManager.shared.saveNutrition(for: itemToAdd)
                self.addRecentFood(for: userID, foodItem: itemToAdd, source: "recipe")

                await MainActor.run {
                    self.bannerService?.showBanner(title: "Success", message: "\(foodItem.name) logged to \(mealType)!")
                    self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                    self.rescheduleDailyReminder()
                }
            } else {
                 await MainActor.run {
                     self.bannerService?.showBanner(title: "Error", message: "Failed to log food.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
            }
        } catch {
            print("Error fetching log for adding food: \(error.localizedDescription)")
             await MainActor.run {
                  self.bannerService?.showBanner(title: "Error", message: "Failed to log food.", iconName: "xmark.circle.fill", iconColor: .red)
             }
        }
    }

     func addJournalEntry(for userID: String, entry: JournalEntry) async {
        let dateToLog = self.activelyViewedDate
        let dateString = dateFormatter.string(from: dateToLog)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)

        do {
            let encodedEntry = try Firestore.Encoder().encode(entry)

            if self.currentDailyLog?.date == dateToLog {
                await MainActor.run {
                    if self.currentDailyLog?.journalEntries == nil {
                        self.currentDailyLog?.journalEntries = []
                    }
                    self.currentDailyLog?.journalEntries?.append(entry)
                }
            }

            try await logRef.updateData([
                "journalEntries": FieldValue.arrayUnion([encodedEntry])
            ])
             await MainActor.run {
                self.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
            }

        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.notFound.rawValue {
            let newLog = DailyLog(id: dateString, date: dateToLog, meals: [], journalEntries: [entry])
            
             await MainActor.run {
                 self.currentDailyLog = newLog
                 self.updateWidgetData()
             }
            
            do {
                try logRef.setData(from: newLog)
                 await MainActor.run {
                    self.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
                }
            } catch {
                print("Error setting new log document with journal entry: \(error.localizedDescription)")
                 await MainActor.run {
                    self.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
            }
        } catch {
            print("Error updating journal entries: \(error.localizedDescription)")
             await MainActor.run {
                self.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }
    
    // *** NEW FUNCTION TO DELETE JOURNAL ENTRY ***
    func deleteJournalEntry(for userID: String, entry: JournalEntry) {
        let dateToLog = self.activelyViewedDate
        let dateString = dateFormatter.string(from: dateToLog)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)

        // Optimistic local update
        if self.currentDailyLog?.date == dateToLog,
           let index = self.currentDailyLog?.journalEntries?.firstIndex(where: { $0.id == entry.id }) {
            DispatchQueue.main.async {
                self.currentDailyLog?.journalEntries?.remove(at: index)
            }
        }

        // Update Firestore using arrayRemove
        do {
            let encodedEntry = try Firestore.Encoder().encode(entry)
            logRef.updateData([
                "journalEntries": FieldValue.arrayRemove([encodedEntry])
            ]) { error in
                Task { @MainActor in
                    if let error = error {
                        self.bannerService?.showBanner(title: "Error", message: "Failed to delete entry.", iconName: "xmark.circle.fill", iconColor: .red)
                        // Note: If this fails, the local UI and remote are out of sync.
                        // A more robust solution would re-fetch the log here.
                        print("Error deleting journal entry: \(error.localizedDescription)")
                    } else {
                        // Success, no banner needed as UI already updated.
                    }
                }
            }
        } catch {
            // Error encoding the entry to delete
            Task { @MainActor in
                self.bannerService?.showBanner(title: "Error", message: "Failed to encode entry for deletion.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }
    // *** END NEW FUNCTION ***

    private func fetchLogInternalAsync(for userID: String, date: Date) async throws -> DailyLog {
        if Calendar.current.isDate(date, inSameDayAs: activelyViewedDate), let currentLog = currentDailyLog {
            return currentLog
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            fetchLogInternal(for: userID, date: date) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func updateDailyLogAsync(for userID: String, updatedLog: DailyLog) async -> Bool {
        return await withCheckedContinuation { continuation in
            updateDailyLog(for: userID, updatedLog: updatedLog) { success in
                continuation.resume(returning: success)
            }
        }
    }

    func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)? = nil) {
        guard let logID = updatedLog.id else { completion?(false); return }
        let ref = db.collection("users").document(userID).collection("dailyLogs").document(logID)
        do {
            try ref.setData(from: updatedLog, merge: true) { err in
                 if err == nil {
                     DispatchQueue.main.async {
                        self.updateWidgetData()
                     }
                     completion?(true)
                 } else {
                     print("Error updating daily log: \(err!.localizedDescription)")
                     completion?(false)
                 }
            }
        } catch {
             print("Error encoding daily log for update: \(error.localizedDescription)")
            completion?(false)
        }
    }

    private func rescheduleDailyReminder() {
        NotificationManager.shared.scheduleCalendarNotification(.dailyLogReminder(hour: 20, minute: 00))
    }

    func saveCustomFood(for userID: String, foodItem: FoodItem, completion: @escaping (Bool) -> Void) {
        let ref = db.collection("users").document(userID).collection(customFoodsCollection).document(foodItem.id)
        do {
            try ref.setData(from: foodItem, merge: true) { error in
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

    func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let startOfDayForRequestedDate = Calendar.current.startOfDay(for: date)

        if let listeningDate = activeListenerDate, Calendar.current.isDate(listeningDate, inSameDayAs: startOfDayForRequestedDate) {
            if let log = self.currentDailyLog, Calendar.current.isDate(log.date, inSameDayAs: startOfDayForRequestedDate) {
                 completion(.success(log))
            }
            return
        }

        self.activelyViewedDate = startOfDayForRequestedDate
        let dateString = dateFormatter.string(from: startOfDayForRequestedDate)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)

        logListener?.remove()
        self.activeListenerDate = startOfDayForRequestedDate

        logListener = logRef.addSnapshotListener { [weak self] documentSnapshot, error in
             guard let self = self else { return }

            if let error = error {
                 print("Listener Error for \(dateString): \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let document = documentSnapshot else {
                 print("Listener Error: Snapshot nil for \(dateString)")
                completion(.failure(NSError(domain:"App", code: -1, userInfo: [NSLocalizedDescriptionKey:"Snapshot nil for \(dateString)"])))
                return
            }

             DispatchQueue.main.async {
                if document.exists, let data = document.data() {
                    let fetchedLog = self.decodeDailyLog(from: data, documentID: dateString)
                    if Calendar.current.isDate(fetchedLog.date, inSameDayAs: self.activelyViewedDate) {
                        self.currentDailyLog = fetchedLog
                        self.updateWidgetData()
                        completion(.success(fetchedLog))
                    }
                } else {
                    let newLog = DailyLog(id: dateString, date: startOfDayForRequestedDate, meals: [], journalEntries: [])
                    do {
                         try logRef.setData(from: newLog) { setError in
                             DispatchQueue.main.async {
                                if let setError = setError {
                                    print("Error setting new log document \(dateString): \(setError.localizedDescription)")
                                    completion(.failure(setError))
                                } else {
                                    if Calendar.current.isDate(newLog.date, inSameDayAs: self.activelyViewedDate) {
                                        self.currentDailyLog = newLog
                                        self.updateWidgetData()
                                        completion(.success(newLog))
                                    }
                                }
                            }
                        }
                    } catch {
                         print("Error encoding new log for \(dateString): \(error.localizedDescription)")
                         completion(.failure(error))
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
                let newLog = DailyLog(id: dateString, date: startOfDay, meals: [], journalEntries: [])
                completion(.success(newLog))
            }
        }
    }

    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        fetchLog(for: userID, date: Date(), completion: completion)
    }


    func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) else {
            completion(.success([]))
            return
        }

        db.collection("users").document(userID).collection("dailyLogs")
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

                let logs = documents.compactMap { try? $0.data(as: DailyLog.self) }

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
                
                DispatchQueue.main.async {
                    self.currentDailyLog = log
                    self.updateWidgetData()
                }
                
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        HealthKitManager.shared.saveNutrition(for: itemToAdd)
                        self.addRecentFood(for: userID, foodItem: itemToAdd, source: source)
                        Task { @MainActor in
                            self.bannerService?.showBanner(title: "Success", message: "\(foodItem.name) logged!")
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                            self.rescheduleDailyReminder()
                        }
                    } else {
                         Task { @MainActor in
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log \(foodItem.name).", iconName: "xmark.circle.fill", iconColor: .red)
                         }
                    }
                }
            case .failure(let e):
                print("Error fetching log for adding food: \(e.localizedDescription)")
                 Task { @MainActor in
                     self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to add food.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
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
                    DispatchQueue.main.async {
                        self.currentDailyLog = log
                        self.updateWidgetData()
                    }
                    
                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success {
                            Task { @MainActor in
                                self.bannerService?.showBanner(title: "Success", message: "\(updatedFoodItem.name) updated!")
                                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                            }
                        } else {
                             Task { @MainActor in
                                self.bannerService?.showBanner(title: "Error", message: "Failed to update \(updatedFoodItem.name).", iconName: "xmark.circle.fill", iconColor: .red)
                            }
                        }
                    }
                }
            case .failure(let e):
                print("Error fetching log for updating food: \(e.localizedDescription)")
                 Task { @MainActor in
                     self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to update food.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
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

                if let index = log.meals.firstIndex(where: { $0.name == mealName }) {
                    log.meals[index].foodItems.append(contentsOf: itemsWithTimestamp)
                } else {
                    let newMeal = Meal(name: mealName, foodItems: itemsWithTimestamp)
                    log.meals.append(newMeal)
                }

                DispatchQueue.main.async {
                    self.currentDailyLog = log
                    self.updateWidgetData()
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        itemsWithTimestamp.forEach { item in
                            HealthKitManager.shared.saveNutrition(for: item)
                            var itemSource: String
                            if mealName.lowercased().contains("ai") { itemSource = "ai" } else { itemSource = "recipe" }
                            self.addRecentFood(for: userID, foodItem: item, source: itemSource)
                        }
                        Task { @MainActor in
                            self.bannerService?.showBanner(title: "Success", message: "\(mealName) logged!")
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                        }
                    } else {
                         Task { @MainActor in
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log \(mealName).", iconName: "xmark.circle.fill", iconColor: .red)
                         }
                    }
                }
            case .failure(let e):
                 print("Error fetching log for adding meal: \(e.localizedDescription)")
                  Task { @MainActor in
                     self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to add meal.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
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
                var foodName: String?
                for i in log.meals.indices {
                     let initialCount = log.meals[i].foodItems.count
                     if let itemToRemove = log.meals[i].foodItems.first(where: { $0.id == foodItemID }) {
                         foodName = itemToRemove.name
                     }
                     log.meals[i].foodItems.removeAll { $0.id == foodItemID }
                     if log.meals[i].foodItems.count < initialCount { deleted = true }
                 }
                if deleted {
                     DispatchQueue.main.async {
                         self.currentDailyLog = log
                         self.updateWidgetData()
                     }
                     
                     self.updateDailyLog(for: userID, updatedLog: log) { success in
                          Task { @MainActor in
                              if success {
                                  self.bannerService?.showBanner(title: "Deleted", message: "\(foodName ?? "Item") removed from log.")
                              } else {
                                  self.bannerService?.showBanner(title: "Error", message: "Failed to delete item.", iconName: "xmark.circle.fill", iconColor: .red)
                              }
                          }
                     }
                 }
            case .failure(let e): print("Error fetching log for delete: \(e.localizedDescription)")
             Task { @MainActor in
                 self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to delete item.", iconName: "xmark.circle.fill", iconColor: .red)
             }
            }
        }
    }

    func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
         let dateToLog = self.activelyViewedDate
         fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
             guard let self = self else { return }
              switch result {
              case .success(var log):
                  if var waterTracker = log.waterTracker {
                      waterTracker.totalOunces += amount
                      if waterTracker.totalOunces < 0 {
                          waterTracker.totalOunces = 0
                      }
                      waterTracker.goalOunces = goalOunces
                      log.waterTracker = waterTracker
                  } else {
                      let initialAmount = max(0, amount)
                      log.waterTracker = WaterTracker(totalOunces: initialAmount, goalOunces: goalOunces, date: Calendar.current.startOfDay(for: dateToLog))
                  }

                  DispatchQueue.main.async {
                      if let currentLog = self.currentDailyLog, currentLog.id == log.id {
                         self.currentDailyLog = log
                      }
                      // *** NOTE: This function already updates locally AND remotely ***
                      self.updateDailyLog(for: userID, updatedLog: log) { success in
                      }
                  }
              case .failure(let error):
                  print("Error fetching log for adding water: \(error.localizedDescription)")
                   Task { @MainActor in
                     self.bannerService?.showBanner(title: "Error", message: "Could not update water intake.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
              }
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
                
                DispatchQueue.main.async {
                    self.currentDailyLog = log
                    self.updateWidgetData()
                }
                
                self.updateDailyLog(for: userID, updatedLog: log) { success in
                     Task { @MainActor in
                        if success {
                            self.bannerService?.showBanner(title: "Success", message: "\(exercise.name) logged!")
                            self.achievementService?.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                        } else {
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log \(exercise.name).", iconName: "xmark.circle.fill", iconColor: .red)
                        }
                    }
                }
            case .failure(let error): print("Error fetching log for adding exercise: \(error.localizedDescription)")
                Task { @MainActor in
                    self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to add exercise.", iconName: "xmark.circle.fill", iconColor: .red)
                }
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
                var exerciseName: String?
                 if let exToRemove = log.exercises?.first(where: { $0.id == exerciseID }) {
                     exerciseName = exToRemove.name
                 }
                log.exercises?.removeAll { $0.id == exerciseID }
                if (log.exercises?.count ?? 0) < initialCount {
                    
                    DispatchQueue.main.async {
                        self.currentDailyLog = log
                        self.updateWidgetData()
                    }
                    
                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                         Task { @MainActor in
                            if success {
                                 self.bannerService?.showBanner(title: "Deleted", message: "\(exerciseName ?? "Exercise") removed.")
                                NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                             } else {
                                self.bannerService?.showBanner(title: "Error", message: "Failed to delete exercise.", iconName: "xmark.circle.fill", iconColor: .red)
                            }
                        }
                    }
                }
            case .failure(let error): print("Error fetching log for deleting exercise: \(error.localizedDescription)")
             Task { @MainActor in
                 self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to delete exercise.", iconName: "xmark.circle.fill", iconColor: .red)
             }
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

                DispatchQueue.main.async {
                    if Calendar.current.isDate(log.date, inSameDayAs: self.activelyViewedDate) {
                        self.currentDailyLog = log
                        self.updateWidgetData()
                    }
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    DispatchQueue.main.async {
                         if success {
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                         }
                         completion?()
                    }
                }
            case .failure(let error):
                 print("Error fetching log for HealthKit sync: \(error.localizedDescription)")
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
                    print("Error adding/updating recent food: \(error.localizedDescription)")
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

    func fetchDailyHistory(for userID: String, startDate: Date? = nil, endDate: Date? = nil) async -> Result<[DailyLog], Error> {
        var query: Query = db.collection("users").document(userID).collection("dailyLogs")
        let queryStartDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        let queryEndDate = endDate.map { Calendar.current.startOfDay(for: $0) }

        if let start = queryStartDate { query = query.whereField("date", isGreaterThanOrEqualTo: Timestamp(date: start)) }
        if let end = queryEndDate {
            let endOfQueryDay = Calendar.current.date(byAdding: .day, value: 1, to: end)!
            query = query.whereField("date", isLessThan: Timestamp(date: endOfQueryDay))
        }
        query = query.order(by: "date", descending: true)

        do {
            let snapshot = try await query.getDocuments()
            let logs: [DailyLog] = snapshot.documents.compactMap { d in self.decodeDailyLog(from: d.data(), documentID: d.documentID) }
            return .success(logs)
        } catch {
            return .failure(error)
        }
    }

    private func encodeDailyLog(_ log: DailyLog) -> [String: Any] {
        do {
            return try Firestore.Encoder().encode(log)
        } catch {
            print("Error encoding DailyLog: \(error)")
            return [:]
        }
    }

     private func decodeDailyLog(from data: [String: Any], documentID: String) -> DailyLog {
        do {
            // This will now correctly decode journalEntries if it exists, or set it to nil if not.
            let decodedLog = try Firestore.Decoder().decode(DailyLog.self, from: data)
            return decodedLog
        } catch {
            print("Error decoding DailyLog \(documentID): \(error). Returning default.")
            let dateFromDocID = dateFormatter.date(from: documentID) ?? Calendar.current.startOfDay(for: Date())
            // Return a default log, ensuring journalEntries is nil or empty
            return DailyLog(id: documentID, date: dateFromDocID, meals: [], journalEntries: [])
        }
     }

      private func determineMealType() -> String {
          let hour = Calendar.current.component(.hour, from: Date()); switch hour { case 0..<4: return "Snack"; case 4..<11: return "Breakfast"; case 11..<16: return "Lunch"; case 16..<21: return "Dinner"; default: return "Snack" }
      }
}

extension Notification.Name {
    static let didUpdateExerciseLog = Notification.Name("didUpdateExerciseLog")
}
