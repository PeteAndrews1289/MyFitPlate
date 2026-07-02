import Foundation
@MainActor
public class DailyLogService: ObservableObject, DailyLogServicing {
    @Published public var currentDailyLog: DailyLog?
    @Published public var activelyViewedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published public var smartSuggestions: [FoodItem] = []
    
    private let recentFoodStore = DailyLogRecentFoodStore()
    public lazy var journalEntryStore: JournalEntryStore = { JournalEntryStore(dailyLogService: self) }()
    public lazy var exerciseLogStore: ExerciseLogStore = { ExerciseLogStore(dailyLogService: self) }()
    public let customFoodStore = CustomFoodStore()
    private var logListener: Any?
    private let customFoodsCollection = "customFoods"
    public weak var achievementService: AchievementService?
    public weak var bannerService: BannerService?
    public weak var goalSettings: GoalSettings?
    private var activeListenerDate: Date?

    public let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init() {}

    public func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService) {
        self.goalSettings = goalSettings
        self.bannerService = bannerService
        self.achievementService = achievementService
    }

    public func updateWidgetData() {
        syncCurrentDailyLogToWidgets()
    }

    public func publishCurrentDailyLog(_ log: DailyLog) {
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

    public func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String) {
        let sourceDay = Calendar.current.startOfDay(for: sourceDate)
        let targetDay = Calendar.current.startOfDay(for: targetDate)

        fetchLogInternal(for: userID, date: sourceDay) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let sourceLog):
                let mealGroups = DailyLogRules.repeatFoods(from: sourceLog)

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
                DIContainer.shared.analyticsManager?.logEvent("food_repeat_day", parameters: [
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

    public func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let dateToLog = self.activelyViewedDate

        do {
            var log = try await fetchLogInternalAsync(for: userID, date: dateToLog)

            let itemToAdd = DailyLogRules.addFoodToLog(log: &log, foodItem: foodItem, mealName: mealType, source: "manual_add")

            let updatedLog = log
            await MainActor.run {
                self.publishCurrentDailyLog(updatedLog)
            }

            let success = await updateDailyLogAsync(for: userID, updatedLog: updatedLog)

            if success {
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: "recipe")

                DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                    "source": "manual_add",
                    "meal_type": mealType,
                    "calories": itemToAdd.calories
                ])

                await MainActor.run {
                    ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
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

    public func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)? = nil) {
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



    public func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
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

    public func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: date, completion: completion)
    }

    public func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        fetchLog(for: userID, date: Date(), completion: completion)
    }


    public func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        DIContainer.shared.nutritionRepository.fetchRecommendedFoods(userID: userID, mealName: mealName, completion: completion)
    }

    public func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String = "unknown") {
        addFoodToLog(
            for: userID,
            date: activelyViewedDate,
            mealName: DailyLogRules.determineMealType(),
            foodItem: foodItem,
            source: source
        )
    }

    public func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String = "unknown") {
        let dateToLog = Calendar.current.startOfDay(for: date)
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let itemToAdd = DailyLogRules.addFoodToLog(log: &log, foodItem: foodItem, mealName: mealName, source: source)

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

                        DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                            "source": source,
                            "meal_type": mealName,
                            "calories": itemToAdd.calories
                        ])

                        Task { @MainActor in
                            ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
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

    public func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let (itemUpdated, previousItem) = DailyLogRules.updateFoodInLog(log: &log, updatedFoodItem: updatedFoodItem)
                let previousFoodItem = previousItem

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

    public func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        addMealToLog(for: userID, date: activelyViewedDate, mealName: mealName, foodItems: foodItems)
    }

    public func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String = "recipe") {
        addMealGroupsToLog(
            for: userID,
            date: date,
            mealGroups: [(mealName: mealName, foodItems: foodItems)],
            source: source
        )
    }

    public func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String = "recipe") {
        let dateToLog = Calendar.current.startOfDay(for: date)
        let nonEmptyGroups = mealGroups.filter { !$0.foodItems.isEmpty }
        guard !nonEmptyGroups.isEmpty else { return }

        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let (allItemsWithTimestamp, itemSource) = DailyLogRules.addMealGroupsToLog(log: &log, mealGroups: mealGroups, defaultSource: source)

                if Calendar.current.isDate(dateToLog, inSameDayAs: self.activelyViewedDate) {
                    DispatchQueue.main.async {
                        self.publishCurrentDailyLog(log)
                    }
                }

                self.updateDailyLog(for: userID, updatedLog: log) { success in
                    if success {
                        DIContainer.shared.analyticsManager?.logEvent("food_logged_bulk", parameters: [
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

    public func deleteFoodFromCurrentLog(for userID: String, foodItemID: String) {
        let dateToLog = self.activelyViewedDate
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                let (deleted, removedItem, name) = DailyLogRules.deleteFoodFromLog(log: &log, foodItemID: foodItemID)
                let removedFoodItem = removedItem
                let foodName = name
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

    public func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
         let dateToLog = self.activelyViewedDate
         fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
             guard let self = self else { return }
              switch result {
              case .success(var log):
                  DailyLogRules.addWaterToLog(log: &log, amount: amount, goalOunces: goalOunces, dateToLog: dateToLog)

                  DispatchQueue.main.async {
                      if let currentLog = self.currentDailyLog, currentLog.id == log.id {
                         self.publishCurrentDailyLog(log)
                      }

                      self.updateDailyLog(for: userID, updatedLog: log) { success in
                          if success && amount > 0 {
                              EcosystemSyncManager.shared.syncWaterToHealthKit(ounces: amount, date: dateToLog)
                              DIContainer.shared.analyticsManager?.logEvent("water_logged", parameters: ["amount": amount])
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

    public func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        addWorkoutToLog(
            for: userID,
            date: activelyViewedDate,
            exerciseName: exerciseName,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned
        )
    }

    public func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        let dateToLog = Calendar.current.startOfDay(for: date)
        fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(var log):
                DailyLogRules.addWorkoutToLog(log: &log, exerciseName: exerciseName, durationMinutes: durationMinutes, caloriesBurned: caloriesBurned)

                DispatchQueue.main.async {
                    if let currentLog = self.currentDailyLog, currentLog.id == log.id {
                        self.publishCurrentDailyLog(log)
                    }

                    self.updateDailyLog(for: userID, updatedLog: log) { success in
                        if success {
                            DIContainer.shared.analyticsManager?.logEvent("workout_logged_ai", parameters: nil)
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

    public func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        recentFoodStore.fetchRecentFoodItems(for: userID, completion: completion)
    }

    public func loadSmartSuggestions(for userID: String) {
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

    public func fetchDailyHistory(for userID: String, startDate: Date? = nil, endDate: Date? = nil) async -> Result<[DailyLog], Error> {
        do {
            let logs = try await DIContainer.shared.nutritionRepository.fetchDailyHistory(userID: userID, startDate: startDate, endDate: endDate)
            return .success(logs)
        } catch {
            return .failure(error)
        }
    }



}
