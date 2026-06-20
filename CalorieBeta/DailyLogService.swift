import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseAnalytics

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
        syncCurrentDailyLogToWidgets()
    }

    private func publishCurrentDailyLog(_ log: DailyLog) {
        self.currentDailyLog = log
        syncCurrentDailyLogToWidgets()
    }

    private func syncCurrentDailyLogToWidgets() {
        EcosystemSyncManager.shared.updateWidgetData(log: self.currentDailyLog, goals: self.goalSettings)
    }

    private func normalizedFoodForLogging(_ foodItem: FoodItem, source: String) -> FoodItem {
        let normalizedItem = foodItem.normalizedForEstimatedSource(source)
        if abs(normalizedItem.calories - foodItem.calories) >= 1 {
            AppLog.data.info("Adjusted estimated food calories from \(foodItem.calories, privacy: .public) to \(normalizedItem.calories, privacy: .public) for source \(source, privacy: .public).")
        }
        return normalizedItem
    }

    func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String) {
        let sourceDay = Calendar.current.startOfDay(for: sourceDate)
        let targetDay = Calendar.current.startOfDay(for: targetDate)

        fetchLogInternal(for: userID, date: sourceDay) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let sourceLog):
                let mealGroups: [(mealName: String, foodItems: [FoodItem])] = sourceLog.meals.compactMap { meal in
                    let repeatedItems = meal.foodItems.map { item -> FoodItem in
                        var repeated = item
                        repeated.id = UUID().uuidString
                        repeated.timestamp = Date()
                        return repeated
                    }
                    return repeatedItems.isEmpty ? nil : (mealName: meal.name, foodItems: repeatedItems)
                }

                guard !mealGroups.isEmpty else {
                    Task { @MainActor in
                        self.bannerService?.showBanner(title: "Nothing to repeat", message: "Yesterday has no foods to copy.")
                    }
                    return
                }

                self.addMealGroupsToLog(
                    for: userID,
                    date: targetDay,
                    mealGroups: mealGroups,
                    source: "repeat_yesterday"
                )
                Analytics.logEvent("food_repeat_day", parameters: [
                    "meal_count": mealGroups.count,
                    "item_count": mealGroups.reduce(0) { $0 + $1.foodItems.count }
                ])

            case .failure(let error):
                AppLog.data.error("Failed to fetch source day for repeat logging: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.bannerService?.showBanner(title: "Could not repeat meals", message: "Yesterday's log could not be loaded.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }

    func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let dateToLog = self.activelyViewedDate

        do {
            var log = try await fetchLogInternalAsync(for: userID, date: dateToLog)

            var itemToAdd = normalizedFoodForLogging(foodItem, source: "manual_add")
            if itemToAdd.timestamp == nil { itemToAdd.timestamp = Date() }

            if let index = log.meals.firstIndex(where: { $0.name == mealType }) {
                log.meals[index].foodItems.append(itemToAdd)
            } else {
                log.meals.append(Meal(name: mealType, foodItems: [itemToAdd]))
            }

            let updatedLog = log
            await MainActor.run {
                self.publishCurrentDailyLog(updatedLog)
            }

            let success = await updateDailyLogAsync(for: userID, updatedLog: updatedLog)

            if success {
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                self.addRecentFood(for: userID, foodItem: itemToAdd, source: "recipe")

                Analytics.logEvent("food_logged", parameters: [
                    "source": "manual_add",
                    "meal_type": mealType,
                    "calories": itemToAdd.calories,
                    "item_name": itemToAdd.name
                ])

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
            AppLog.data.error("Failed to fetch log for adding food: \(error.localizedDescription, privacy: .public)")
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

            Analytics.logEvent("journal_entry_added", parameters: [
                "category": entry.category
            ])

             await MainActor.run {
                self.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
            }

        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.notFound.rawValue {
            let newLog = DailyLog(id: dateString, date: dateToLog, meals: [], journalEntries: [entry])

             await MainActor.run {
                 self.publishCurrentDailyLog(newLog)
             }

            do {
                try logRef.setData(from: newLog)

                Analytics.logEvent("journal_entry_added", parameters: [
                    "category": entry.category
                ])

                await MainActor.run {
                   self.bannerService?.showBanner(title: "Success", message: "Journal entry saved!")
                }
            } catch {
                AppLog.data.error("Failed to create log document for journal entry: \(error.localizedDescription, privacy: .public)")
                 await MainActor.run {
                    self.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
            }
        } catch {
            AppLog.data.error("Failed to update journal entries: \(error.localizedDescription, privacy: .public)")
             await MainActor.run {
                self.bannerService?.showBanner(title: "Error", message: "Failed to save journal entry.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }

    func deleteJournalEntry(for userID: String, entry: JournalEntry) {
        let dateToLog = self.activelyViewedDate
        let dateString = dateFormatter.string(from: dateToLog)
        let logRef = db.collection("users").document(userID).collection("dailyLogs").document(dateString)

        if self.currentDailyLog?.date == dateToLog,
           let index = self.currentDailyLog?.journalEntries?.firstIndex(where: { $0.id == entry.id }) {
            DispatchQueue.main.async {
                self.currentDailyLog?.journalEntries?.remove(at: index)
            }
        }

        do {
            let encodedEntry = try Firestore.Encoder().encode(entry)
            logRef.updateData([
                "journalEntries": FieldValue.arrayRemove([encodedEntry])
            ]) { error in
                Task { @MainActor in
                    if let error = error {
                        self.bannerService?.showBanner(title: "Error", message: "Failed to delete entry.", iconName: "xmark.circle.fill", iconColor: .red)
                        AppLog.data.error("Failed to delete journal entry: \(error.localizedDescription, privacy: .public)")
                    } else {
                        AppLog.data.info("Journal entry deleted.")
                    }
                }
            }
        } catch {
            Task { @MainActor in
                self.bannerService?.showBanner(title: "Error", message: "Failed to encode entry for deletion.", iconName: "xmark.circle.fill", iconColor: .red)
            }
        }
    }

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
                        self.syncCurrentDailyLogToWidgets()
                     }
                     completion?(true)
                 } else {
                     AppLog.data.error("Failed to update daily log: \(err?.localizedDescription ?? "Unknown error", privacy: .public)")
                     completion?(false)
                 }
            }
        } catch {
            AppLog.data.error("Failed to encode daily log for update: \(error.localizedDescription, privacy: .public)")
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
                if error == nil {
                    Analytics.logEvent("custom_food_saved", parameters: ["item_name": foodItem.name])
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
                AppLog.data.error("Daily log listener failed for \(dateString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
                return
            }
            guard let document = documentSnapshot else {
                AppLog.data.error("Daily log listener returned nil snapshot for \(dateString, privacy: .public)")
                completion(.failure(NSError(domain:"App", code: -1, userInfo: [NSLocalizedDescriptionKey:"Snapshot nil for \(dateString)"])))
                return
            }

             DispatchQueue.main.async {
                if document.exists, let data = document.data() {
                    let fetchedLog = self.decodeDailyLog(from: data, documentID: dateString)
                    if Calendar.current.isDate(fetchedLog.date, inSameDayAs: self.activelyViewedDate) {
                        self.publishCurrentDailyLog(fetchedLog)
                        completion(.success(fetchedLog))
                    }
                } else {
                    let newLog = DailyLog(id: dateString, date: startOfDayForRequestedDate, meals: [], journalEntries: [])
                    do {
                         try logRef.setData(from: newLog) { setError in
                             DispatchQueue.main.async {
                                if let setError = setError {
                                    AppLog.data.error("Failed to create new log document \(dateString, privacy: .public): \(setError.localizedDescription, privacy: .public)")
                                    completion(.failure(setError))
                                } else {
                                    if Calendar.current.isDate(newLog.date, inSameDayAs: self.activelyViewedDate) {
                                        self.publishCurrentDailyLog(newLog)
                                        completion(.success(newLog))
                                    }
                                }
                            }
                        }
                    } catch {
                        AppLog.data.error("Failed to encode new log for \(dateString, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        addFoodToLog(
            for: userID,
            date: activelyViewedDate,
            mealName: determineMealType(),
            foodItem: foodItem,
            source: source
        )
    }

    func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String = "unknown") {
        let dateToLog = Calendar.current.startOfDay(for: date)
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                var itemToAdd = normalizedFoodForLogging(foodItem, source: source)
                if itemToAdd.timestamp == nil { itemToAdd.timestamp = Date() }
                if let index = log.meals.firstIndex(where: { $0.name == mealName }) {
                    log.meals[index].foodItems.append(itemToAdd)
                } else {
                    log.meals.append(Meal(name: mealName, foodItems: [itemToAdd]))
                }

                if Calendar.current.isDate(dateToLog, inSameDayAs: self.activelyViewedDate) {
                    DispatchQueue.main.async {
                        self.publishCurrentDailyLog(log)
                    }
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                        self.addRecentFood(for: userID, foodItem: itemToAdd, source: source)

                        Analytics.logEvent("food_logged", parameters: [
                            "source": source,
                            "item_name": itemToAdd.name,
                            "meal_type": mealName,
                            "calories": itemToAdd.calories
                        ])

                        Task { @MainActor in
                            self.bannerService?.showBanner(title: "Success", message: "\(itemToAdd.name) logged!")
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                            self.rescheduleDailyReminder()
                        }
                    } else {
                         Task { @MainActor in
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log \(itemToAdd.name).", iconName: "xmark.circle.fill", iconColor: .red)
                         }
                    }
                }
            case .failure(let e):
                AppLog.data.error("Failed to fetch log for adding food: \(e.localizedDescription, privacy: .public)")
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
                var previousFoodItem: FoodItem?
                for i in 0..<log.meals.count {
                    if let index = log.meals[i].foodItems.firstIndex(where: { $0.id == updatedFoodItem.id }) {
                        previousFoodItem = log.meals[i].foodItems[index]
                        log.meals[i].foodItems[index] = updatedFoodItem
                        itemUpdated = true
                        break
                    }
                }

                if itemUpdated {
                    DispatchQueue.main.async {
                        self.publishCurrentDailyLog(log)
                    }

                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success {
                            if let previousFoodItem {
                                EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: previousFoodItem, newItem: updatedFoodItem)
                            }
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
                AppLog.data.error("Failed to fetch log for updating food: \(e.localizedDescription, privacy: .public)")
                 Task { @MainActor in
                     self.bannerService?.showBanner(title: "Error", message: "Could not fetch log to update food.", iconName: "xmark.circle.fill", iconColor: .red)
                 }
            }
        }
    }

    func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        addMealToLog(for: userID, date: activelyViewedDate, mealName: mealName, foodItems: foodItems)
    }

    func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String = "recipe") {
        addMealGroupsToLog(
            for: userID,
            date: date,
            mealGroups: [(mealName: mealName, foodItems: foodItems)],
            source: source
        )
    }

    func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String = "recipe") {
        let dateToLog = Calendar.current.startOfDay(for: date)
        let nonEmptyGroups = mealGroups.filter { !$0.foodItems.isEmpty }
        guard !nonEmptyGroups.isEmpty else { return }
        let itemSource = nonEmptyGroups.contains(where: { $0.mealName.lowercased().contains("ai") }) ? "ai_bulk" : source

        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                var allItemsWithTimestamp: [FoodItem] = []

                for group in nonEmptyGroups {
                    let itemsWithTimestamp = group.foodItems.map { item -> FoodItem in
                        var mutableItem = self.normalizedFoodForLogging(item, source: itemSource)
                        if mutableItem.timestamp == nil { mutableItem.timestamp = Date() }
                        return mutableItem
                    }
                    allItemsWithTimestamp.append(contentsOf: itemsWithTimestamp)

                    if let index = log.meals.firstIndex(where: { $0.name == group.mealName }) {
                        log.meals[index].foodItems.append(contentsOf: itemsWithTimestamp)
                    } else {
                        let newMeal = Meal(name: group.mealName, foodItems: itemsWithTimestamp)
                        log.meals.append(newMeal)
                    }
                }

                if Calendar.current.isDate(dateToLog, inSameDayAs: self.activelyViewedDate) {
                    DispatchQueue.main.async {
                        self.publishCurrentDailyLog(log)
                    }
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        Analytics.logEvent("food_logged_bulk", parameters: [
                            "source": itemSource,
                            "item_count": allItemsWithTimestamp.count,
                            "meal_count": nonEmptyGroups.count,
                            "meal_type": nonEmptyGroups.map { $0.mealName }.joined(separator: ",")
                        ])

                        allItemsWithTimestamp.forEach { item in
                            EcosystemSyncManager.shared.syncNutritionToHealthKit(item: item)
                            self.addRecentFood(for: userID, foodItem: item, source: itemSource)
                        }
                        Task { @MainActor in
                            let message = nonEmptyGroups.count == 1 ? "\(nonEmptyGroups[0].mealName) logged!" : "Planned day logged!"
                            self.bannerService?.showBanner(title: "Success", message: message)
                            self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                        }
                    } else {
                         Task { @MainActor in
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log planned meals.", iconName: "xmark.circle.fill", iconColor: .red)
                         }
                    }
                }
            case .failure(let e):
                AppLog.data.error("Failed to fetch log for adding meal: \(e.localizedDescription, privacy: .public)")
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
                var removedFoodItem: FoodItem?
                for i in log.meals.indices {
                     let initialCount = log.meals[i].foodItems.count
                     if let itemToRemove = log.meals[i].foodItems.first(where: { $0.id == foodItemID }) {
                         foodName = itemToRemove.name
                         removedFoodItem = itemToRemove
                     }
                     log.meals[i].foodItems.removeAll { $0.id == foodItemID }
                     if log.meals[i].foodItems.count < initialCount { deleted = true }
                 }
                if deleted {
                     DispatchQueue.main.async {
                         self.publishCurrentDailyLog(log)
                     }

                     self.updateDailyLog(for: userID, updatedLog: log) { success in
                          Task { @MainActor in
                              if success {
                                  if let removedFoodItem {
                                      EcosystemSyncManager.shared.deleteNutritionFromHealthKit(item: removedFoodItem)
                                  }
                                  self.bannerService?.showBanner(title: "Deleted", message: "\(foodName ?? "Item") removed from log.")
                              } else {
                                  self.bannerService?.showBanner(title: "Error", message: "Failed to delete item.", iconName: "xmark.circle.fill", iconColor: .red)
                              }
                          }
                     }
                 }
            case .failure(let e):
                AppLog.data.error("Failed to fetch log for deleting food: \(e.localizedDescription, privacy: .public)")
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
                         self.publishCurrentDailyLog(log)
                      }

                      self.updateDailyLog(for: userID, updatedLog: log) { success in
                          if success && amount > 0 {
                              Analytics.logEvent("water_logged", parameters: ["amount": amount])
                          }
                      }
                  }
              case .failure(let error):
                  AppLog.data.error("Failed to fetch log for adding water: \(error.localizedDescription, privacy: .public)")
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
                    self.publishCurrentDailyLog(log)
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                     Task { @MainActor in
                        if success {
                            Analytics.logEvent("exercise_logged", parameters: [
                                "source": exercise.source,
                                "duration": exercise.durationMinutes ?? 0,
                                "exercise_name": exercise.name,
                                "calories": exercise.caloriesBurned
                            ])

                            self.bannerService?.showBanner(title: "Success", message: "\(exercise.name) logged!")
                            self.achievementService?.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                        } else {
                             self.bannerService?.showBanner(title: "Error", message: "Failed to log \(exercise.name).", iconName: "xmark.circle.fill", iconColor: .red)
                        }
                    }
                }
            case .failure(let error):
                AppLog.data.error("Failed to fetch log for adding exercise: \(error.localizedDescription, privacy: .public)")
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
                        self.publishCurrentDailyLog(log)
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
            case .failure(let error):
                AppLog.data.error("Failed to fetch log for deleting exercise: \(error.localizedDescription, privacy: .public)")
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
                        self.publishCurrentDailyLog(log)
                    }
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    DispatchQueue.main.async {
                         if success {
                            Analytics.logEvent("healthkit_sync_workouts", parameters: [
                                "count": exercises.count
                            ])
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                         }
                         completion?()
                    }
                }
            case .failure(let error):
                AppLog.health.error("Failed to fetch log for HealthKit workout sync: \(error.localizedDescription, privacy: .public)")
                completion?()
            }
        }
    }

    private func addRecentFood(for userID: String, foodItem: FoodItem, source: String) {
        guard !userID.isEmpty else { return }
        let ref = db.collection("users").document(userID).collection(recentFoodsCollection)
        let ts = Timestamp(date: Date())

        let stableIDString = foodItem.name
        let stableID = Data(stableIDString.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")

        do {
            var data = try Firestore.Encoder().encode(foodItem)
            data["timestamp"] = ts
            data["source"] = source

            ref.document(stableID).setData(data, merge: false) { error in
                if let error = error {
                    AppLog.data.error("Failed to add or update recent food: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            AppLog.data.error("Failed to encode recent food: \(error.localizedDescription, privacy: .public)")
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
            let endOfQueryDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
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
            AppLog.data.error("Failed to encode DailyLog: \(error.localizedDescription, privacy: .public)")
            return [:]
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

      private func determineMealType() -> String {
          let hour = Calendar.current.component(.hour, from: Date()); switch hour { case 0..<4: return "Snack"; case 4..<11: return "Breakfast"; case 11..<16: return "Lunch"; case 16..<21: return "Dinner"; default: return "Snack" }
      }
}

extension Notification.Name {
    static let didUpdateExerciseLog = Notification.Name("didUpdateExerciseLog")
}
