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
    private var mutationTails: [String: Task<Void, Never>] = [:]
    private var mutationTokens: [String: Int] = [:]
    private var mutationSnapshots: [String: DailyLog] = [:]
    private var nextMutationToken = 0

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

    public func fetchYesterdayMeal(for userID: String, mealName: String, completion: @escaping ([FoodItem]) -> Void) {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86400)
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)

        fetchLogInternal(for: userID, date: yesterdayStart) { result in
            switch result {
            case .success(let log):
                let items = DailyLogRules.repeatMeal(from: log, mealName: mealName)
                completion(items)
            case .failure:
                completion([])
            }
        }
    }

    public func repeatYesterdayMeal(for userID: String, mealName: String, targetDate: Date, completion: @escaping (Bool) -> Void) {
        fetchYesterdayMeal(for: userID, mealName: mealName) { [weak self] items in
            guard let self, !items.isEmpty else {
                Task { @MainActor in
                    self?.bannerService?.showBanner(title: "Nothing to repeat", message: "Yesterday had no \(mealName.lowercased()) logged.")
                }
                completion(false)
                return
            }
            let targetDay = Calendar.current.startOfDay(for: targetDate)
            self.addMealGroupsToLog(
                for: userID,
                date: targetDay,
                mealGroups: [(mealName: mealName, foodItems: items)],
                source: "repeat_yesterday_meal"
            )
            DIContainer.shared.analyticsManager?.logEvent("food_repeat_meal", parameters: [
                "meal_name": mealName,
                "item_count": items.count
            ])
            Task { @MainActor in
                self.bannerService?.showBanner(title: "Repeated \(mealName)", message: "Added yesterday's items to today's log.", iconName: "checkmark.circle.fill", iconColor: .accentPositive)
            }
            completion(true)
        }
    }

    public func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let dateToLog = self.activelyViewedDate
        await withCheckedContinuation { continuation in
            enqueueDailyLogMutation(
                for: userID,
                date: dateToLog,
                failureMessage: "Failed to log food.",
                mutation: { log in
                    DailyLogRules.addFoodToLog(
                        log: &log,
                        foodItem: foodItem,
                        mealName: mealType,
                        source: "manual_add"
                    )
                },
                onSuccess: { [weak self] itemToAdd, _ in
                    guard let self else { return }
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                    self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: "manual_add")

                DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                    "source": "manual_add",
                    "meal_type": mealType,
                    "calories": itemToAdd.calories
                ])

                    ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
                    self.bannerService?.showBanner(title: "Success", message: "\(foodItem.name) logged to \(mealType)!")
                    self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                    self.rescheduleDailyReminder()
                },
                completion: { _ in continuation.resume() }
            )
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

    private func fetchRepositoryLogAsync(for userID: String, date: Date) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: date) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func enqueueDailyLogMutation<Value>(
        for userID: String,
        date: Date,
        failureMessage: String,
        mutation: @escaping @MainActor (inout DailyLog) -> Value?,
        onSuccess: @escaping @MainActor (Value, DailyLog) -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let key = "\(userID):\(dateFormatter.string(from: normalizedDate))"
        let previous = mutationTails[key]
        nextMutationToken += 1
        let token = nextMutationToken
        mutationTokens[key] = token

        let task = Task { @MainActor [weak self] in
            if let previous { await previous.value }
            guard let self else {
                completion?(false)
                return
            }

            do {
                var log: DailyLog
                if let snapshot = self.mutationSnapshots[key] {
                    log = snapshot
                } else if let currentLog = self.currentDailyLog,
                          Calendar.current.isDate(currentLog.date, inSameDayAs: normalizedDate) {
                    log = currentLog
                } else {
                    log = try await self.fetchRepositoryLogAsync(for: userID, date: normalizedDate)
                }
                guard let value = mutation(&log) else {
                    completion?(false)
                    self.finishMutation(key: key, token: token)
                    return
                }

                let success = await self.updateDailyLogAsync(for: userID, updatedLog: log)
                if success {
                    self.mutationSnapshots[key] = log
                    if Calendar.current.isDate(normalizedDate, inSameDayAs: self.activelyViewedDate) {
                        self.publishCurrentDailyLog(log)
                    }
                    onSuccess(value, log)
                } else {
                    self.bannerService?.showBanner(
                        title: "Error",
                        message: failureMessage,
                        iconName: "xmark.circle.fill",
                        iconColor: .red
                    )
                }
                completion?(success)
            } catch {
                AppLog.data.error("Daily log mutation failed: \(error.localizedDescription, privacy: .public)")
                self.bannerService?.showBanner(
                    title: "Error",
                    message: failureMessage,
                    iconName: "xmark.circle.fill",
                    iconColor: .red
                )
                completion?(false)
            }
            self.finishMutation(key: key, token: token)
        }
        mutationTails[key] = task
    }

    private func finishMutation(key: String, token: Int) {
        guard mutationTokens[key] == token else { return }
        mutationTokens[key] = nil
        mutationTails[key] = nil
        mutationSnapshots[key] = nil
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

    /// Adds one item through the per-user/day mutation queue. Rapid taps, watch transfers, and
    /// overlapping app actions are serialized so they cannot overwrite one another.
    public func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String = "unknown") {
        let dateToLog = Calendar.current.startOfDay(for: date)
        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Failed to log \(foodItem.name).",
            mutation: { log in
                DailyLogRules.addFoodToLog(
                    log: &log,
                    foodItem: foodItem,
                    mealName: mealName,
                    source: source
                )
            },
            onSuccess: { [weak self] itemToAdd, _ in
                guard let self else { return }
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: source)
                DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                    "source": source,
                    "meal_type": mealName,
                    "calories": itemToAdd.calories
                ])
                ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
                self.bannerService?.showBanner(title: "Success", message: "\(itemToAdd.name) logged!")
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
                self.rescheduleDailyReminder()
            }
        )
    }

    public func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem) {
        let dateToLog = self.activelyViewedDate
        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Failed to update \(updatedFoodItem.name).",
            mutation: { log in
                let result = DailyLogRules.updateFoodInLog(log: &log, updatedFoodItem: updatedFoodItem)
                return result.updated ? result.previousFoodItem : nil
            },
            onSuccess: { [weak self] previousFoodItem, _ in
                guard let self else { return }
                EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: previousFoodItem, newItem: updatedFoodItem)
                self.bannerService?.showBanner(title: "Success", message: "\(updatedFoodItem.name) updated!")
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
            }
        )
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

        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Failed to log planned meals.",
            mutation: { log in
                let result = DailyLogRules.addMealGroupsToLog(
                    log: &log,
                    mealGroups: mealGroups,
                    defaultSource: source
                )
                return result.addedItems.isEmpty ? nil : result
            },
            onSuccess: { [weak self] result, _ in
                guard let self else { return }
                DIContainer.shared.analyticsManager?.logEvent("food_logged_bulk", parameters: [
                    "source": result.sourceUsed,
                    "item_count": result.addedItems.count,
                    "meal_count": nonEmptyGroups.count,
                    "meal_type": nonEmptyGroups.map { $0.mealName }.joined(separator: ",")
                ])
                result.addedItems.forEach { item in
                    DailyLogNotifications.postFoodLogged(item, userID: userID)
                    EcosystemSyncManager.shared.syncNutritionToHealthKit(item: item)
                    self.recentFoodStore.addRecentFood(for: userID, foodItem: item, source: result.sourceUsed)
                }
                ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
                let message = nonEmptyGroups.count == 1
                    ? "\(nonEmptyGroups[0].mealName) logged!"
                    : "Planned day logged!"
                self.bannerService?.showBanner(title: "Success", message: message)
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
            }
        )
    }

    public func deleteFoodFromCurrentLog(for userID: String, foodItemID: String) {
        let dateToLog = self.activelyViewedDate
        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Failed to delete item.",
            mutation: { log -> (food: FoodItem, name: String)? in
                let result = DailyLogRules.deleteFoodFromLog(log: &log, foodItemID: foodItemID)
                guard result.deleted, let removed = result.removedFoodItem else { return nil }
                return (food: removed, name: result.foodName ?? "Item")
            },
            onSuccess: { [weak self] result, _ in
                EcosystemSyncManager.shared.deleteNutritionFromHealthKit(item: result.food)
                self?.bannerService?.showBanner(title: "Deleted", message: "\(result.name) removed from log.")
            }
        )
    }

    public func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
        let dateToLog = self.activelyViewedDate
        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Could not update water intake.",
            mutation: { log in
                DailyLogRules.addWaterToLog(
                    log: &log,
                    amount: amount,
                    goalOunces: goalOunces,
                    dateToLog: dateToLog
                )
                return amount
            },
            onSuccess: { loggedAmount, _ in
                if loggedAmount > 0 {
                    EcosystemSyncManager.shared.syncWaterToHealthKit(ounces: loggedAmount, date: dateToLog)
                    DIContainer.shared.analyticsManager?.logEvent("water_logged", parameters: ["amount": loggedAmount])
                }
            }
        )
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
        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            failureMessage: "Could not log workout.",
            mutation: { log in
                DailyLogRules.addWorkoutToLog(log: &log, exerciseName: exerciseName, durationMinutes: durationMinutes, caloriesBurned: caloriesBurned)
                return true
            },
            onSuccess: { _, _ in
                DIContainer.shared.analyticsManager?.logEvent("workout_logged_ai", parameters: nil)
            }
        )
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
