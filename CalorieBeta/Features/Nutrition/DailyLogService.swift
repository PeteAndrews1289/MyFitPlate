import Foundation
import FirebaseAuth
import FirebaseAnalytics

@MainActor
class DailyLogService: ObservableObject, DailyLogServicing {
    @Published var currentDailyLog: DailyLog?
    @Published var activelyViewedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var smartSuggestions: [FoodItem] = []
    
    private let recentFoodStore = DailyLogRecentFoodStore()
    lazy var journalEntryStore: JournalEntryStore = { JournalEntryStore(dailyLogService: self) }()
    lazy var exerciseLogStore: ExerciseLogStore = { ExerciseLogStore(dailyLogService: self) }()
    let customFoodStore = CustomFoodStore()
    private var logListener: Any?
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

    func publishCurrentDailyLog(_ log: DailyLog) {
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
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: "recipe")

                Analytics.logEvent("food_logged", parameters: [
                    "source": "manual_add",
                    "meal_type": mealType,
                    "calories": itemToAdd.calories
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
        DIContainer.shared.nutritionRepository.updateDailyLog(userID: userID, log: updatedLog) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    self?.syncCurrentDailyLogToWidgets()
                }
            } else {
                AppLog.data.error("Failed to update daily log via repository")
            }
            completion?(success)
        }
    }

    private func rescheduleDailyReminder() {
        // Refresh the reminder (its body shows remaining calories) at the user's CHOSEN time and
        // only if they've enabled it — the old hard-coded 20:00 clobbered the Settings time on
        // every food log.
        NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
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

        if let listener = logListener {
            DIContainer.shared.nutritionRepository.removeLogSnapshotListener(listener)
        }
        self.activeListenerDate = startOfDayForRequestedDate

        logListener = DIContainer.shared.nutritionRepository.addLogSnapshotListener(userID: userID, date: startOfDayForRequestedDate) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedLog):
                    if Calendar.current.isDate(fetchedLog.date, inSameDayAs: self.activelyViewedDate) {
                        self.publishCurrentDailyLog(fetchedLog)
                        completion(.success(fetchedLog))
                    }
                case .failure(let error):
                    AppLog.data.error("Daily log listener failed: \(error.localizedDescription, privacy: .public)")
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: date, completion: completion)
    }

    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        fetchLog(for: userID, date: Date(), completion: completion)
    }


    func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        DIContainer.shared.nutritionRepository.fetchRecommendedFoods(userID: userID, mealName: mealName, completion: completion)
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
                        DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                        EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                        self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: source)

                        Analytics.logEvent("food_logged", parameters: [
                            "source": source,
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
                            DailyLogNotifications.postFoodLogged(item, userID: userID)
                            EcosystemSyncManager.shared.syncNutritionToHealthKit(item: item)
                            self.recentFoodStore.addRecentFood(for: userID, foodItem: item, source: itemSource)
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
                              EcosystemSyncManager.shared.syncWaterToHealthKit(ounces: amount, date: dateToLog)
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

    func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        addWorkoutToLog(
            for: userID,
            date: activelyViewedDate,
            exerciseName: exerciseName,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned
        )
    }

    func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        let dateToLog = Calendar.current.startOfDay(for: date)
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let exercise = LoggedExercise(
                    name: exerciseName,
                    durationMinutes: durationMinutes,
                    caloriesBurned: caloriesBurned,
                    date: Date(),
                    source: "ai_chat"
                )
                
                if log.exercises == nil {
                    log.exercises = []
                }
                log.exercises?.append(exercise)

                DispatchQueue.main.async {
                    if let currentLog = self.currentDailyLog, currentLog.id == log.id {
                        self.publishCurrentDailyLog(log)
                    }

                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success {
                            Analytics.logEvent("workout_logged_ai", parameters: nil)
                        }
                    }
                }
            case .failure(let error):
                AppLog.data.error("Failed to fetch log for adding workout: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    self.bannerService?.showBanner(title: "Error", message: "Could not log workout.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }

    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        recentFoodStore.fetchRecentFoodItems(for: userID, completion: completion)
    }

    func loadSmartSuggestions(for userID: String) {
        fetchRecentFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    self?.smartSuggestions = SmartSuggestionBuilder.uniqueRecentFoods(from: items)
                case .failure(let error):
                    AppLog.data.error("Failed to load smart suggestions: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func fetchDailyHistory(for userID: String, startDate: Date? = nil, endDate: Date? = nil) async -> Result<[DailyLog], Error> {
        do {
            let logs = try await DIContainer.shared.nutritionRepository.fetchDailyHistory(userID: userID, startDate: startDate, endDate: endDate)
            return .success(logs)
        } catch {
            return .failure(error)
        }
    }



      private func determineMealType() -> String {
          let hour = Calendar.current.component(.hour, from: Date()); switch hour { case 0..<4: return "Snack"; case 4..<11: return "Breakfast"; case 11..<16: return "Lunch"; case 16..<21: return "Dinner"; default: return "Snack" }
      }
}
