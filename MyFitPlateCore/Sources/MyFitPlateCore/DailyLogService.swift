import Foundation

private enum DailyLogMutationFailure: LocalizedError {
    case persistenceRejected

    var errorDescription: String? {
        "The nutrition repository rejected a serialized daily-log write."
    }
}

private enum DailyLogListenerFailure: LocalizedError {
    case accountChanged

    var errorDescription: String? {
        "The active account changed before the daily log finished loading."
    }
}

@MainActor
public class DailyLogService: ObservableObject, DailyLogServicing {
    @Published public var currentDailyLog: DailyLog?
    @Published public var activelyViewedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published public private(set) var activelyViewedDayContext: DiaryDayContext?
    @Published public private(set) var canUndoDiaryChange = false
    @Published public private(set) var undoChangeID: UUID?
    private var undoChange: DiaryUndoReceipt?
    @Published public private(set) var isUndoingDiaryChange = false
    @Published public private(set) var undoErrorMessage: String?
    private let undoStore: EditorDraftStore
    private let undoScope = "diary-undo"
    private var undoExpiryTask: Task<Void, Never>?
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
    public weak var trainingFuelPlanStore: TrainingFuelPlanStore?
    private var activeAccountID: String?
    private var activeListenerDate: Date?
    private var activeListenerDayContext: DiaryDayContext?
    private var activeListenerUserID: String?
    private var pendingLogCompletions: [(Result<DailyLog, Error>) -> Void] = []
    private var mutationTails: [String: Task<Void, Never>] = [:]
    private var mutationTokens: [String: Int] = [:]
    private var mutationSnapshots: [String: DailyLog] = [:]
    private var nextMutationToken = 0
    private var transferDaysInFlight = Set<String>()
    @Published public private(set) var diaryTransferErrorMessage: String?

    public let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(undoStore: EditorDraftStore = EditorDraftStore()) { self.undoStore = undoStore }

    public func activateAccount(_ userID: String?) {
        guard activeAccountID != userID else { return }

        canUndoDiaryChange = false
        undoChangeID = nil
        undoChange = nil
        isUndoingDiaryChange = false
        undoErrorMessage = nil
        undoExpiryTask?.cancel()
        cancelActiveLogListener()
        activeAccountID = userID
        currentDailyLog = nil
        activelyViewedDayContext = nil
        smartSuggestions = []
        activelyViewedDate = Calendar.current.startOfDay(for: Date())
        restoreUndo(for: userID)
        TransferHealthSyncQueue.shared.activateAccount(userID)
        InventoryHealthSyncQueue.shared.activateAccount(userID)
    }

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

    func publishCurrentDailyLog(_ log: DailyLog, for userID: String) {
        guard isActiveAccount(userID) else { return }
        publishCurrentDailyLog(log)
    }

    public func isActiveAccount(_ userID: String) -> Bool {
        activeAccountID == userID && DIContainer.shared.authService.currentUserID == userID
    }

    private func activateCurrentAccountIfNeeded(_ userID: String) {
        guard DIContainer.shared.authService.currentUserID == userID,
              activeAccountID != userID else { return }
        activateAccount(userID)
    }

    private func cancelActiveLogListener() {
        if let listener = logListener {
            DIContainer.shared.nutritionRepository.removeLogSnapshotListener(listener)
        }
        logListener = nil
        activeListenerDate = nil
        activeListenerDayContext = nil
        activeListenerUserID = nil

        let completions = pendingLogCompletions
        pendingLogCompletions = []
        completions.forEach { $0(.failure(DailyLogListenerFailure.accountChanged)) }
    }

    private func finishPendingLogLoads(with result: Result<DailyLog, Error>) {
        let completions = pendingLogCompletions
        pendingLogCompletions = []
        completions.forEach { $0(result) }
    }

    private func syncCurrentDailyLogToWidgets() {
        EcosystemSyncManager.shared.updateWidgetData(
            log: self.currentDailyLog,
            goals: self.goalSettings,
            trainingFuelPlan: trainingFuelPlanStore?.confirmedPlan
        )
    }

    private func normalizedFoodForLogging(_ foodItem: FoodItem, source: String) -> FoodItem {
        let normalizedItem = foodItem.normalizedForEstimatedSource(source)
        if abs(normalizedItem.calories - foodItem.calories) >= 1 {
            AppLog.data.info("Adjusted estimated food calories from \(foodItem.calories, privacy: .private) to \(normalizedItem.calories, privacy: .private) for source \(source, privacy: .public).")
        }
        return normalizedItem
    }

    private func recordFoodLoggingSuccess(source: String) {
        ProductEngagementTelemetry.recordFoodLoggingDay(source: source)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged)
        AppReviewPromptQueue.shared.recordLoggingDay()
    }

    private func recordDailyLogMutationFailure(_ error: Error, stage: String) {
        guard let crashManager = DIContainer.shared.crashManager else { return }
        ReleaseHealth.recordNonFatal(
            error,
            area: .nutrition,
            operation: "daily_log_mutation",
            metadata: ["stage": stage],
            crashManager: crashManager,
            analyticsManager: DIContainer.shared.analyticsManager
        )
    }

    public func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String) {
        guard isActiveAccount(userID) else { return }
        let sourceDay = Calendar.current.startOfDay(for: sourceDate)
        let targetDay = Calendar.current.startOfDay(for: targetDate)

        fetchLogInternal(for: userID, date: sourceDay) { [weak self] result in
            guard let self, self.isActiveAccount(userID) else { return }

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
                    self.bannerService?.showBanner(title: "Could not repeat meals", message: "Yesterday's log could not be loaded.", iconName: "xmark.circle.fill", iconColor: AppPalette.critical)
                }
            }
        }
    }

    public func fetchYesterdayMeal(for userID: String, mealName: String, completion: @escaping ([FoodItem]) -> Void) {
        guard isActiveAccount(userID) else {
            completion([])
            return
        }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86400)
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)

        fetchLogInternal(for: userID, date: yesterdayStart) { [weak self] result in
            guard let self, self.isActiveAccount(userID) else {
                completion([])
                return
            }
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
                onSuccess: { [weak self] itemToAdd, acceptedLog in
                    guard let self else { return }
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                    self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: "manual_add")
                    self.achievementService?.checkAcceptedFood(userID: userID, food: itemToAdd, date: dateToLog, source: "manual_add", dayKey: acceptedLog.id)

                DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                    "source": "manual_add",
                    "meal_type": mealType,
                    "calories": itemToAdd.calories
                ])

                    self.recordFoodLoggingSuccess(source: "manual_add")
                    self.bannerService?.showBanner(title: "Success", message: "\(foodItem.name) logged to \(mealType)!")
                    self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog, dayKey: acceptedLog.id)
                    self.rescheduleDailyReminder()
                },
                completion: { _ in continuation.resume() }
            )
        }
    }

    /// Workout capture uses its own timestamp, independent of the diary page being viewed.
    /// A stable session entry ID makes a retry after partial completion harmless.
    public func saveWorkoutExercise(for userID: String, exercise: LoggedExercise) async -> Bool {
        await withCheckedContinuation { continuation in
            enqueueDailyLogMutation(
                for: userID, date: exercise.date, dayContext: DiaryDayContext(userID: userID, date: exercise.date), failureMessage: "Could not save the workout to your diary.",
                recordsUndo: false,
                mutation: { log in
                    if log.exercises == nil { log.exercises = [] }
                    let alreadySaved = log.exercises?.contains {
                        $0.id == exercise.id || (exercise.sessionID != nil && $0.sessionID == exercise.sessionID)
                    } == true
                    if !alreadySaved { log.exercises?.append(exercise) }
                    return !alreadySaved
                },
                onSuccess: { isNew, _ in
                    if isNew {
                        NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                    }
                },
                completion: { continuation.resume(returning: $0) }
            )
        }
    }

    /// A history correction only replaces its unchanged generated diary mirror.
    /// Missing/deleted entries, manual totals, and explicit Health overrides stay intact.
    public func reconcileWorkoutExercise(
        for userID: String, sessionID: String, originalDate: Date,
        expected: LoggedExercise?, updated: LoggedExercise?
    ) async -> WorkoutDiaryReconciliation {
        await withCheckedContinuation { continuation in
            var outcome = WorkoutDiaryReconciliation.failed
            enqueueDailyLogMutation(
                for: userID, date: originalDate, dayContext: DiaryDayContext(userID: userID, date: originalDate), failureMessage: "Workout history is saved. Retry to update its diary estimate.",
                recordsUndo: false, shouldPersist: { $0 == .updated },
                mutation: { log -> WorkoutDiaryReconciliation? in
                    guard let index = log.exercises?.firstIndex(where: { $0.sessionID == sessionID || $0.id == sessionID }),
                          var stored = log.exercises?[index] else { return .missing }
                    guard stored.source == "routine", stored.hasLocalHealthKitEdits != true,
                          let expected, let updated,
                          Calendar.current.isDate(originalDate, inSameDayAs: updated.date) else { return .preservedOverride }
                    if WorkoutDiaryProjectionRules.matches(stored, updated) { return .alreadyCurrent }
                    guard WorkoutDiaryProjectionRules.matches(stored, expected) else { return .preservedOverride }
                    stored.caloriesBurned = updated.caloriesBurned
                    stored.durationMinutes = updated.durationMinutes
                    stored.date = updated.date
                    log.exercises?[index] = stored
                    return .updated
                },
                onSuccess: { value, _ in
                    outcome = value
                    if value == .updated { NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil) }
                },
                completion: { continuation.resume(returning: $0 ? outcome : .failed) }
            )
        }
    }

    /// The exact Health UUID/day and complete snapshots are checked again by the
    /// repository transaction. A device queue acknowledgment cannot accept this edit.
    public func reconcileRunActivity(for userID: String, day: DiaryDayContext, operationID: String,
                                     expected: LoggedExercise, updated: LoggedExercise,
                                     allowsOwnedOverride: Bool = false) async -> WorkoutDiaryReconciliation {
        guard isActiveAccount(userID), day.isOwned(by: userID), !operationID.isEmpty,
              expected.source == "HealthKit", updated.source == "HealthKit",
              expected.id == updated.id, expected.date == updated.date,
              expected.workoutID == updated.workoutID, expected.sessionID == updated.sessionID,
              updated.caloriesBurned.isFinite, updated.caloriesBurned > 0,
              updated.durationMinutes.map({ $0 > 0 }) == true else { return .failed }
        return await withCheckedContinuation { continuation in
            var outcome = WorkoutDiaryReconciliation.failed
            enqueueDailyLogMutation(for: userID, date: day.originalDate, dayContext: day,
                failureMessage: "The linked run correction is still pending. Original run evidence stays intact.",
                recordsUndo: false, shouldPersist: { $0 == .updated || $0 == .alreadyCurrent },
                mutation: { log -> WorkoutDiaryReconciliation? in
                    let indices = (log.exercises ?? []).indices.filter { log.exercises?[$0].id == expected.id }
                    guard indices.count == 1, let index = indices.first, let actual = log.exercises?[index] else { return .missing }
                    let already = ActivityEditPrecondition.sameSnapshot(actual, updated)
                    guard already || (ActivityEditPrecondition.sameSnapshot(actual, expected)
                        && (actual.hasLocalHealthKitEdits != true || allowsOwnedOverride)) else { return .preservedOverride }
                    log.exercises?[index] = updated
                    log.pendingMutationID = operationID
                    log.pendingActivityEdit = ActivityEditPrecondition(expected: expected, desired: updated)
                    return already ? .alreadyCurrent : .updated
                }, onSuccess: { value, _ in
                    outcome = value
                    if value == .updated { NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil) }
                }, completion: { continuation.resume(returning: $0 ? outcome : .failed) })
        }
    }

    /// Manual activity saves share the serialized diary pipeline. The entry's captured date,
    /// never the currently viewed page, determines its destination. Edits replace the existing
    /// identity in place and retain source/session links from the stored record.
    public func saveActivityExercise(
        for userID: String,
        exercise: LoggedExercise,
        replacing original: LoggedExercise? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              exercise.caloriesBurned.isFinite, exercise.caloriesBurned > 0,
              exercise.date.timeIntervalSinceReferenceDate.isFinite,
              exercise.durationMinutes.map({ $0 > 0 }) ?? true,
              original.map({ $0.id == exercise.id && Calendar.current.isDate($0.date, inSameDayAs: exercise.date) }) ?? true else {
            completion(false)
            return
        }
        enqueueDailyLogMutation(
            for: userID, date: original?.date ?? exercise.date,
            failureMessage: "Could not save the activity. Your changes are still available to retry.",
            recordsUndo: false,
            mutation: { log -> Bool? in
                if let index = log.exercises?.firstIndex(where: { $0.id == exercise.id }),
                   var stored = log.exercises?[index] {
                    stored.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    stored.durationMinutes = exercise.durationMinutes
                    stored.caloriesBurned = exercise.caloriesBurned
                    stored.date = exercise.date
                    if stored.source == "HealthKit" { stored.hasLocalHealthKitEdits = true }
                    log.exercises?[index] = stored
                    return false
                }
                guard original == nil else { return nil }
                if log.exercises == nil { log.exercises = [] }
                var entry = exercise
                entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                log.exercises?.append(entry)
                return true
            },
            onSuccess: { [weak self] isNew, _ in
                guard let self else { return }
                if isNew {
                    self.achievementService?.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
                    DIContainer.shared.analyticsManager?.logEvent("exercise_logged", parameters: [
                        "source": exercise.source,
                        "duration": exercise.durationMinutes ?? 0
                    ])
                }
                NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
            },
            completion: completion
        )
    }

    public func deleteActivityExercise(
        for userID: String, exerciseID: String, date: Date,
        completion: ((Bool) -> Void)? = nil
    ) {
        enqueueDailyLogMutation(
            for: userID, date: date, failureMessage: "Could not delete the activity. Try again.",
            recordsUndo: false,
            mutation: { log -> Bool? in
                guard let entry = log.exercises?.first(where: { $0.id == exerciseID }),
                      entry.source != "HealthKit" else { return nil }
                log.exercises?.removeAll { $0.id == exerciseID }
                return true
            },
            onSuccess: { _, _ in
                NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
            },
            completion: completion
        )
    }

    /// Import refreshes share the activity queue so a refresh cannot race an accepted correction.
    /// The stable Health ID retains local edits while that original workout remains in Health.
    func syncHealthKitExercises(
        for userID: String, exercises: [LoggedExercise], date: Date,
        completion: @escaping (Bool) -> Void
    ) {
        enqueueDailyLogMutation(
            for: userID, date: date, dayContext: DiaryDayContext(userID: userID, date: date), failureMessage: "Could not refresh imported activities. Try again.",
            recordsUndo: false,
            mutation: { log -> Bool? in
                let stored = log.exercises ?? []
                var correctedByID: [String: LoggedExercise] = [:]
                for entry in stored where entry.source == "HealthKit" && entry.hasLocalHealthKitEdits == true {
                    correctedByID[entry.id] = entry
                }
                var seenIDs = Set<String>()
                let refreshed = exercises.filter { seenIDs.insert($0.id).inserted }.map { correctedByID[$0.id] ?? $0 }
                log.exercises = stored.filter { $0.source != "HealthKit" } + refreshed
                return true
            },
            onSuccess: { _, _ in
                DIContainer.shared.analyticsManager?.logEvent("healthkit_sync_workouts", parameters: ["count": exercises.count])
                NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
            }, completion: completion
        )
    }

    public func moveFood(for userID: String, foodID: String, date: Date, to mealName: String) {
        let reviewed = currentDailyLog?.meals.flatMap(\.foodItems).first { $0.id == foodID }
        enqueueDailyLogMutation(
            for: userID, date: date, failureMessage: "Could not move the food. Try again.",
            mutation: { (log: inout DailyLog) -> FoodItem? in
                guard let sourceIndex = log.meals.firstIndex(where: { $0.foodItems.contains { $0.id == foodID } }),
                      log.meals[sourceIndex].name != mealName,
                      let food = log.meals[sourceIndex].foodItems.first(where: { $0.id == foodID }) else { return nil }
                if let reviewed, !FoodEditPrecondition.sameSnapshot(reviewed, food) { return nil }
                let originalMealID = log.meals[sourceIndex].id
                log.mutationBase = try? JSONEncoder().encode(log)
                log.pendingMutationID = UUID().uuidString
                log.meals[sourceIndex].foodItems.removeAll { $0.id == foodID }
                if let destination = log.meals.firstIndex(where: { $0.name == mealName }) {
                    log.meals[destination].foodItems.append(food)
                } else { log.meals.append(Meal(name: mealName, foodItems: [food])) }
                guard let destinationMeal = log.meals.first(where: { $0.foodItems.contains { $0.id == foodID } }) else { return nil }
                log.pendingFoodEdit = FoodEditPrecondition(foodID: foodID, expected: food, desired: food,
                    expectedMealID: originalMealID, desiredMealID: destinationMeal.id)
                return food
            },
            onSuccess: { [weak self] _, _ in
                self?.bannerService?.showBanner(title: "Food moved", message: "Moved to \(mealName). Undo is available.")
            }
        )
    }



    /// Transfer acceptance is a remote atomic acknowledgement, never queue acceptance.
    public func performDiaryTransfer(_ session: DiaryTransferSession, undo: Bool = false) async -> DiaryTransferResult? {
        diaryTransferErrorMessage = nil
        let userID = session.userID
        guard isActiveAccount(userID), let draft = session.draft else {
            diaryTransferErrorMessage = DiaryTransferError.accountChanged.localizedDescription; return nil
        }
        let keys = Set([draft.source.dayKey, draft.destination.dayKey].map { "\(userID):\($0)" })
        guard keys.isDisjoint(with: transferDaysInFlight), keys.allSatisfy({ mutationTails[$0] == nil }) else {
            diaryTransferErrorMessage = "These days have another save in progress. Your transfer is kept; retry after it finishes."
            return nil
        }
        transferDaysInFlight.formUnion(keys)
        defer { transferDaysInFlight.subtract(keys) }
        let repository = DIContainer.shared.nutritionRepository!
        let publishedBeforeTransfer = diarySnapshotBytes(currentDailyLog)
        let result = undo ? await session.undo(using: repository) : await session.submit(using: repository)
        guard let result, isActiveAccount(userID) else { return nil }
        reconcileTransferResult(result, userID: userID, previousSnapshot: publishedBeforeTransfer)
        return result
    }

    /// A failed command stays captured until the server verifies its terminal state.
    public func resolveDiaryTransferStatus(_ session: DiaryTransferSession, cancelPending: Bool = false) async -> Bool {
        diaryTransferErrorMessage = nil
        guard isActiveAccount(session.userID) else { return false }
        let before = diarySnapshotBytes(currentDailyLog)
        let cancelled: Bool
        if cancelPending {
            cancelled = await session.cancelUnaccepted(using: DIContainer.shared.nutritionRepository)
        } else {
            _ = await session.refresh(using: DIContainer.shared.nutritionRepository)
            cancelled = false
        }
        guard isActiveAccount(session.userID) else { return false }
        if let result = session.lastVerifiedResult {
            // Status transactions read canonical server records. Refresh through the
            // normal repository read so accepted local outbox entries stay visible.
            _ = TransferHealthSyncQueue.shared.reconcile(result: result, userID: session.userID)
            InventoryHealthSyncQueue.shared.reconcileMove(result, userID: session.userID)
            let days = [result.receipt.command.source, result.receipt.command.destination]
            for day in days where mutationTails["\(session.userID):\(day.dayKey)"] == nil {
                mutationSnapshots["\(session.userID):\(day.dayKey)"] = nil
            }
            if let selected = days.first(where: { $0.dayKey == (activelyViewedDayContext?.dayKey ?? currentDailyLog?.id) }),
               let log = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<DailyLog, Error>) in
                   fetchLogInternal(for: session.userID, day: selected) { continuation.resume(with: $0) }
               }), isActiveAccount(session.userID), log.id == selected.dayKey,
               (activelyViewedDayContext?.dayKey ?? currentDailyLog?.id) == selected.dayKey,
               let before, diarySnapshotBytes(currentDailyLog) == before {
                publishCurrentDailyLog(log.rememberingMutationBase())
            }
        }
        diaryTransferErrorMessage = session.errorMessage
        return cancelled
    }

    private func reconcileTransferResult(_ result: DiaryTransferResult, userID: String, previousSnapshot: Data?) {
        for day in [result.receipt.command.source, result.receipt.command.destination] {
            mutationSnapshots["\(userID):\(day.dayKey)"] = nil
        }
        let selectedKey = activelyViewedDayContext?.dayKey ?? currentDailyLog?.id
        // A newer listener snapshot may already contain unrelated remote changes.
        // Never replace it with the transaction's earlier commit snapshot.
        if let previousSnapshot, diarySnapshotBytes(currentDailyLog) == previousSnapshot {
            if selectedKey == result.destinationLog.id { publishCurrentDailyLog(result.destinationLog.rememberingMutationBase()) } else if selectedKey == result.sourceLog.id { publishCurrentDailyLog(result.sourceLog.rememberingMutationBase()) }
        }
        _ = TransferHealthSyncQueue.shared.reconcile(result: result, userID: userID)
        InventoryHealthSyncQueue.shared.reconcileMove(result, userID: userID)
        if result.newlyApplied, result.receipt.undoneAt == nil, result.receipt.command.mode == .copy {
            recordFoodLoggingSuccess(source: "diary_copy")
        }
    }

    private func diarySnapshotBytes(_ log: DailyLog?) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(log)
    }

    public func retryDiaryTransferHealth(_ receipt: DiaryTransferReceipt) async {
        diaryTransferErrorMessage = nil
        guard isActiveAccount(receipt.command.userID), receipt.command.mode == .copy else { return }
        do {
            let result = try await DIContainer.shared.nutritionRepository.fetchDiaryTransfer(
                userID: receipt.command.userID, command: receipt.command)
            guard isActiveAccount(receipt.command.userID) else { return }
            _ = TransferHealthSyncQueue.shared.reconcile(result: result, userID: receipt.command.userID)
            TransferHealthSyncQueue.shared.retryPending(userID: receipt.command.userID)
        } catch { diaryTransferErrorMessage = "The diary change is saved. Health export could not be retried yet." }
    }

    private func fetchLogInternalAsync(for userID: String, date: Date) async throws -> DailyLog {
        if activeAccountID == userID,
           Calendar.current.isDate(date, inSameDayAs: activelyViewedDate),
           let currentLog = currentDailyLog {
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
        dayContext: DiaryDayContext? = nil,
        failureMessage: String,
        recordsUndo: Bool = true,
        shouldRecordUndo: @escaping (Value) -> Bool = { _ in true },
        shouldPersist: @escaping (Value) -> Bool = { _ in true },
        mutation: @escaping @MainActor (inout DailyLog) -> Value?,
        onSuccess: @escaping @MainActor (Value, DailyLog) -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        activateCurrentAccountIfNeeded(userID)
        guard isActiveAccount(userID) else {
            completion?(false)
            return
        }
        guard let capturedDay = dayContext ?? diaryDayContext(for: userID, date: date), capturedDay.isOwned(by: userID) else {
            completion?(false); return
        }
        let normalizedDate = capturedDay.originalDate
        let key = "\(userID):\(capturedDay.dayKey)"
        guard !transferDaysInFlight.contains(key) else {
            bannerService?.showBanner(title: "Food transfer in progress", message: "Your edit is kept. Finish the current transfer, then retry.")
            completion?(false); return
        }
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
                } else if self.activeAccountID == userID,
                          let currentLog = self.currentDailyLog,
                          currentLog.id == capturedDay.dayKey {
                    log = currentLog
                } else {
                    log = try await withCheckedThrowingContinuation { continuation in
                        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, day: capturedDay) {
                            continuation.resume(with: $0)
                        }
                    }
                }
                let original = log
                guard let value = mutation(&log) else {
                    completion?(false)
                    self.finishMutation(key: key, token: token)
                    return
                }

                if !shouldPersist(value) {
                    onSuccess(value, original)
                    completion?(true)
                    self.finishMutation(key: key, token: token)
                    return
                }

                let checkedDayReview = NutritionDayReviewRules.requiresCheckedCommit(log)
                let intendedReviewLog = log
                var dayReviewConfirmed = !checkedDayReview
                let success = await self.updateDailyLogAsync(for: userID, updatedLog: log)
                let checkedActivity = log.pendingActivityEdit
                var activityConfirmed = checkedActivity == nil
                if success {
                    let checkedFoods = (log.pendingFoodEdit.map { [$0] } ?? []) + (log.pendingFoodEdits ?? [])
                    let intakeCandidate = checkedFoods.contains { $0.foodID.hasPrefix("stock-") || $0.foodID.hasPrefix("planned-") }
                    var canonicalMatchesReview = true
                    if intakeCandidate || checkedActivity != nil || checkedDayReview {
                        // A permanent accepted receipt can predate newer food edits.
                        // Refresh the current day; never publish the old expected proposal.
                        let publicationBase = self.diarySnapshotBytes(self.currentDailyLog)
                        let canonical = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DailyLog, Error>) in
                            self.fetchLogInternal(for: userID, day: capturedDay) { continuation.resume(with: $0) }
                        }
                        guard self.isActiveAccount(userID) else {
                            completion?(false); self.finishMutation(key: key, token: token); return
                        }
                        if self.diarySnapshotBytes(self.currentDailyLog) != publicationBase,
                           let newer = self.currentDailyLog, newer.id == capturedDay.dayKey { log = newer } else { log = canonical }
                        canonicalMatchesReview = checkedFoods.allSatisfy { edit in
                            let actual = log.meals.flatMap(\.foodItems).first { $0.id == edit.foodID }
                            return (try? InventorySnapshotRules.fingerprint(actual)) == (try? InventorySnapshotRules.fingerprint(edit.desired))
                        }
                    }
                    if checkedDayReview {
                        dayReviewConfirmed = NutritionDayReviewRules.sameReviewedState(intendedReviewLog, log)
                        canonicalMatchesReview = canonicalMatchesReview && dayReviewConfirmed
                    }
                    if let checkedActivity {
                        let matches = (log.exercises ?? []).filter { $0.id == checkedActivity.desired.id }
                        activityConfirmed = matches.count == 1 && matches.first.map { ActivityEditPrecondition.sameSnapshot($0, checkedActivity.desired) } == true
                    }
                    if let id = log.pendingMutationID, !(log.appliedMutationIDs ?? []).contains(id) {
                        log.appliedMutationIDs = (log.appliedMutationIDs ?? []) + [id]
                    }
                    if recordsUndo, shouldRecordUndo(value), canonicalMatchesReview, self.isActiveAccount(userID) {
                        self.rememberUndo(userID: userID, before: original, after: checkedDayReview ? intendedReviewLog : log)
                    }
                    log = log.rememberingMutationBase()
                    self.mutationSnapshots[key] = log
                    if self.isActiveAccount(userID) {
                        if self.activelyViewedDayContext?.dayKey == capturedDay.dayKey
                            || (self.activelyViewedDayContext == nil && Calendar.current.isDate(normalizedDate, inSameDayAs: self.activelyViewedDate)) {
                            self.publishCurrentDailyLog(log)
                        }
                        if intakeCandidate { self.reconcileIntakeNutritionToCanonical(checkedFoods, log: log, userID: userID) } else { onSuccess(value, log) }
                    }
                } else {
                    self.recordDailyLogMutationFailure(
                        DailyLogMutationFailure.persistenceRejected,
                        stage: "persist"
                    )
                    if self.isActiveAccount(userID) {
                        self.bannerService?.showBanner(
                            title: "Error",
                            message: failureMessage,
                            iconName: "xmark.circle.fill",
                            iconColor: AppPalette.critical
                        )
                    }
                }
                completion?(success && activityConfirmed && dayReviewConfirmed)
            } catch {
                AppLog.data.error("Daily log mutation failed: \(error.localizedDescription, privacy: .public)")
                self.recordDailyLogMutationFailure(error, stage: "prepare")
                if self.isActiveAccount(userID) {
                    self.bannerService?.showBanner(
                        title: "Error",
                        message: failureMessage,
                        iconName: "xmark.circle.fill",
                        iconColor: AppPalette.critical
                    )
                }
                completion?(false)
            }
            self.finishMutation(key: key, token: token)
        }
        mutationTails[key] = task
    }

    public func setNutritionDayStatus(_ status: NutritionDayStatus, for userID: String, date: Date, reviewedLog: DailyLog? = nil, completion: @escaping (Bool) -> Void) {
        guard let day = DiaryDayContext(userID: userID, date: reviewedLog?.date ?? date, dayKey: reviewedLog?.id),
              !day.isFuture() else { completion(false); return }
        let visible = reviewedLog ?? currentDailyLog.flatMap { NutritionDayReviewRules.key($0) == day.dayKey ? $0 : nil }
        enqueueDailyLogMutation(
            for: userID, date: day.originalDate, dayContext: day, failureMessage: "Could not save the day's review. Please retry.",
            mutation: { log -> Bool? in
                if let visible, !NutritionDayReviewRules.sameReviewedState(visible, log) { return nil }
                guard NutritionDayReviewRules.key(log, timeZone: day.timeZone) == day.dayKey,
                      let receipt = try? NutritionDayReview(ownerID: userID, day: day, status: status, log: log) else { return nil }
                // This command changes only the assertion. Capture its exact current
                // baseline even when a legacy/local caller has not retained one.
                log = log.rememberingMutationBase()
                guard log.mutationBase != nil else { return nil }
                log.nutritionDayStatus = status; log.nutritionDayReview = receipt
                return true
            },
            onSuccess: { _, _ in }, completion: completion
        )
    }

    private func reconcileIntakeNutritionToCanonical(_ edits: [FoodEditPrecondition], log: DailyLog, userID: String) {
        guard isActiveAccount(userID) else { return }
        let foods = log.meals.flatMap(\.foodItems)
        for edit in edits {
            guard let prior = edit.expected ?? edit.desired else { continue }
            _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [edit.foodID], userID: userID)
            if let current = foods.first(where: { $0.id == edit.foodID }) {
                EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: prior, newItem: current)
            } else { EcosystemSyncManager.shared.deleteNutritionFromHealthKit(item: prior) }
        }
    }

    /// Only offer this addition's Undo while the active receipt still covers its exact foods.
    public func undoID(forAddedFoods ids: Set<String>, userID: String) -> UUID? {
        guard !ids.isEmpty, isActiveAccount(userID), canUndoDiaryChange,
              let receipt = undoChange, receipt.userID == userID else { return nil }
        let before = Set(receipt.before.meals.flatMap(\.foodItems).map(\.id))
        let after = Set(receipt.after.meals.flatMap(\.foodItems).map(\.id))
        return before.isSubset(of: after) && after.subtracting(before) == ids ? receipt.id : nil
    }

    private func rememberUndo(userID: String, before: DailyLog, after: DailyLog) {
        // Water and workout reversals require their own HealthKit receipts. Offer food/journal undo.
        guard before.waterTracker == after.waterTracker, before.exercises == after.exercises else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard (try? encoder.encode(before.meals)) != (try? encoder.encode(after.meals)) || before.journalEntries != after.journalEntries
                || before.nutritionDayStatus != after.nutritionDayStatus || before.nutritionDayReview != after.nutritionDayReview else { return }
        // An unresolved submitted Undo keeps its identity until its outcome is known.
        guard undoChange?.isSubmitted != true else { return }
        let receipt = DiaryUndoReceipt(id: UUID(), userID: userID, before: before, after: after,
                                       expiresAt: Date().addingTimeInterval(30), isSubmitted: false)
        do {
            try undoStore.save(receipt, userID: userID, scope: undoScope)
            exposeUndo(receipt)
        } catch {
            undoErrorMessage = "The change was saved, but Undo could not be kept on this device."
        }
    }

    private func restoreUndo(for userID: String?) {
        guard let userID else { return }
        do {
            if let receipt = try undoStore.load(DiaryUndoReceipt.self, userID: userID, scope: undoScope)?.value,
               receipt.userID == userID, receipt.isSubmitted || receipt.expiresAt > Date() {
                exposeUndo(receipt)
            }
        } catch { undoErrorMessage = "The saved Undo could not be opened. It has been kept on this device." }
    }

    private func exposeUndo(_ receipt: DiaryUndoReceipt) {
        undoExpiryTask?.cancel()
        undoChange = receipt; undoChangeID = receipt.id; canUndoDiaryChange = true
        if receipt.isSubmitted { return }
        let delay = max(0, receipt.expiresAt.timeIntervalSinceNow)
        undoExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.undoChange?.id == receipt.id, self.undoChange?.isSubmitted == false else { return }
            self.canUndoDiaryChange = false; self.undoChange = nil; self.undoChangeID = nil
        }
    }

    public func undoLastDiaryChange(for userID: String, completion: ((Bool) -> Void)? = nil) {
        guard var change = undoChange, canUndoDiaryChange, !isUndoingDiaryChange,
              change.userID == userID, isActiveAccount(userID) else { completion?(false); return }
        do {
            change.isSubmitted = true
            try undoStore.save(change, userID: userID, scope: undoScope)
            let reversal = try change.reversal()
            undoChange = change
            undoExpiryTask?.cancel()
            isUndoingDiaryChange = true; canUndoDiaryChange = false; undoErrorMessage = nil
            enqueueDailyLogMutation(
                for: userID, date: change.after.date,
                dayContext: DiaryDayContext(userID: userID, date: change.after.date, dayKey: change.after.id), failureMessage: "Could not undo that change. Please retry.", recordsUndo: false,
                mutation: { (log: inout DailyLog) -> Bool? in
                    let alreadyApplied = (log.appliedMutationIDs ?? []).contains(change.operationID)
                    let base = log
                    let newerReview = log.nutritionDayStatus != change.after.nutritionDayStatus || log.nutritionDayReview != change.after.nutritionDayReview
                    let status = log.nutritionDayStatus
                    let review = log.nutritionDayReview
                    do { log = try reversal.applying(to: log, checkingFoodEdits: true) } catch {
                        let linkedCandidate = (reversal.foodEditPreconditions ?? []).contains { $0.foodID.hasPrefix("stock-") || $0.foodID.hasPrefix("planned-") }
                        guard linkedCandidate else { return nil }
                        // An accepted stock-linked Undo may have lost its ack before
                        // later work. Forward its frozen intent for read-only receipt
                        // verification; an unaccepted stale Undo still fails on server.
                        log = base; log.mutationBase = try? JSONEncoder().encode(base)
                        log.pendingMutationID = change.operationID; log.pendingFoodEdits = reversal.foodEditPreconditions
                        return false
                    }
                    if newerReview { log.nutritionDayStatus = status; log.nutritionDayReview = review }
                    log.mutationBase = try? JSONEncoder().encode(base)
                    log.pendingMutationID = change.operationID
                    log.pendingFoodEdits = reversal.foodEditPreconditions
                    log.pendingDayReviewUndo = reversal.dayReviewUndo
                    return !alreadyApplied
                },
                onSuccess: { wasNew, _ in
                    guard wasNew else { return }
                    let savedFoods = change.after.meals.flatMap(\.foodItems)
                    let originalFoods = change.before.meals.flatMap(\.foodItems)
                    for food in savedFoods where !originalFoods.contains(where: { $0.id == food.id }) {
                        _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [food.id], userID: userID)
                        EcosystemSyncManager.shared.deleteNutritionFromHealthKit(item: food)
                    }
                    for food in originalFoods {
                        if let saved = savedFoods.first(where: { $0.id == food.id }) {
                            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                            if (try? encoder.encode(saved)) != (try? encoder.encode(food)) {
                                _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [saved.id], userID: userID)
                                EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: saved, newItem: food)
                            }
                        } else { EcosystemSyncManager.shared.syncNutritionToHealthKit(item: food) }
                    }
                },
                completion: { [weak self] accepted in
                    guard let self else { completion?(false); return }
                    if accepted {
                        do { try self.undoStore.remove(userID: userID, scope: self.undoScope) } catch {
                            if self.isActiveAccount(userID) {
                                self.isUndoingDiaryChange = false; self.exposeUndo(change)
                                self.undoErrorMessage = "Undo was saved. Retry to clear its receipt; it will not run twice."
                            }
                            completion?(false); return
                        }
                    }
                    if self.isActiveAccount(userID), self.undoChange?.id == change.id {
                        self.isUndoingDiaryChange = false
                        if accepted { self.undoChange = nil; self.undoChangeID = nil; self.canUndoDiaryChange = false } else {
                            self.exposeUndo(change); self.undoErrorMessage = "Could not save Undo. Your original action and retry are kept."
                        }
                    }
                    completion?(accepted)
                }
            )
        } catch {
            undoErrorMessage = "Could not keep Undo on this device. Nothing was reversed; retry safely."
            completion?(false)
        }
    }

    private func finishMutation(key: String, token: Int) {
        guard mutationTokens[key] == token else { return }
        mutationTokens[key] = nil
        mutationTails[key] = nil
        mutationSnapshots[key] = nil
    }

    public func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)? = nil) {
        guard DIContainer.shared.authService.currentUserID == userID else {
            completion?(false)
            return
        }
        DIContainer.shared.nutritionRepository.updateDailyLog(userID: userID, log: updatedLog) { [weak self] success in
            if success {
                DispatchQueue.main.async {
                    guard let self, self.isActiveAccount(userID) else { return }
                    self.syncCurrentDailyLogToWidgets()
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



    /// Existing document paths win; a matching open day retains its captured timezone.
    public func diaryDayContext(for userID: String, date: Date, existingLog: DailyLog? = nil) -> DiaryDayContext? {
        guard DIContainer.shared.authService.currentUserID == userID else { return nil }
        if let existingLog, let key = existingLog.id {
            return DiaryDayContext(userID: userID, date: existingLog.date,
                timeZone: activelyViewedDayContext?.timeZone ?? .current, dayKey: key)
        }
        if let context = activelyViewedDayContext, context.isOwned(by: userID),
           context.calendar.isDate(date, inSameDayAs: context.originalDate) { return context }
        if let current = currentDailyLog, let key = current.id,
           Calendar.current.isDate(current.date, inSameDayAs: date) {
            return DiaryDayContext(userID: userID, date: current.date, dayKey: key)
        }
        return DiaryDayContext(userID: userID, date: date)
    }

    public func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        activateCurrentAccountIfNeeded(userID)
        guard let context = diaryDayContext(for: userID, date: date) else {
            completion(.failure(DailyLogListenerFailure.accountChanged)); return
        }
        fetchLog(for: userID, day: context, completion: completion)
    }

    public func fetchLog(for userID: String, day: DiaryDayContext,
                         completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard day.isOwned(by: userID), DIContainer.shared.authService.currentUserID == userID else {
            completion(.failure(DailyLogListenerFailure.accountChanged)); return
        }
        activateCurrentAccountIfNeeded(userID)
        if activeListenerUserID == userID, activeListenerDayContext == day {
            if let log = currentDailyLog, log.id == day.dayKey { completion(.success(log)) } else { pendingLogCompletions.append(completion) }
            return
        }
        cancelActiveLogListener()
        activelyViewedDate = day.originalDate
        activelyViewedDayContext = day
        pendingLogCompletions = [completion]
        activeListenerUserID = userID
        activeListenerDate = day.originalDate
        activeListenerDayContext = day
        logListener = DIContainer.shared.nutritionRepository.addLogSnapshotListener(userID: userID, day: day) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isActiveAccount(userID), self.activeListenerDayContext == day,
                      self.activelyViewedDayContext == day else { return }
                switch result {
                case .success(let log):
                    guard log.id == day.dayKey else {
                        self.finishPendingLogLoads(with: .failure(DailyLogListenerFailure.accountChanged)); return
                    }
                    self.publishCurrentDailyLog(log)
                    self.finishPendingLogLoads(with: .success(log))
                case .failure(let error): self.finishPendingLogLoads(with: .failure(error))
                }
            }
        }
    }

    public func fetchLogInternal(for userID: String, day: DiaryDayContext,
                                 completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard day.isOwned(by: userID), DIContainer.shared.authService.currentUserID == userID else {
            completion(.failure(DailyLogListenerFailure.accountChanged)); return
        }
        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, day: day) { result in
            Task { @MainActor in
                guard DIContainer.shared.authService.currentUserID == userID else {
                    completion(.failure(DailyLogListenerFailure.accountChanged)); return
                }
                completion(result)
            }
        }
    }

    public func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard DIContainer.shared.authService.currentUserID == userID else {
            completion(.failure(DailyLogListenerFailure.accountChanged))
            return
        }
        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: date) { result in
            Task { @MainActor in
                guard DIContainer.shared.authService.currentUserID == userID else {
                    completion(.failure(DailyLogListenerFailure.accountChanged))
                    return
                }
                completion(result)
            }
        }
    }

    public func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        fetchLog(for: userID, date: Date(), completion: completion)
    }


    public func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard isActiveAccount(userID) else {
            completion(.failure(DailyLogListenerFailure.accountChanged))
            return
        }

        DIContainer.shared.nutritionRepository.fetchRecommendedFoods(userID: userID, mealName: mealName) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isActiveAccount(userID) else {
                    completion(.failure(DailyLogListenerFailure.accountChanged))
                    return
                }
                completion(result)
            }
        }
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
            onSuccess: { [weak self] itemToAdd, acceptedLog in
                guard let self else { return }
                DailyLogNotifications.postFoodLogged(itemToAdd, userID: userID)
                EcosystemSyncManager.shared.syncNutritionToHealthKit(item: itemToAdd)
                self.recentFoodStore.addRecentFood(for: userID, foodItem: itemToAdd, source: source)
                self.achievementService?.checkAcceptedFood(userID: userID, food: itemToAdd, date: dateToLog, source: source, dayKey: acceptedLog.id)
                DIContainer.shared.analyticsManager?.logEvent("food_logged", parameters: [
                    "source": source,
                    "meal_type": mealName,
                    "calories": itemToAdd.calories
                ])
                self.recordFoodLoggingSuccess(source: source)
                self.bannerService?.showBanner(title: "Success", message: "\(itemToAdd.name) logged!")
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog, dayKey: acceptedLog.id)
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
                _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [previousFoodItem.id], userID: userID)
                EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: previousFoodItem, newItem: updatedFoodItem)
                self.bannerService?.showBanner(title: "Success", message: "\(updatedFoodItem.name) updated!")
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog)
            }
        )
    }

    /// Updates the immutable historical target and rejects a concurrent edit to that entry.
    /// An identical replay is accepted without repeating integration side effects or Undo.
    public func updateFood(for userID: String, date: Date, original: FoodItem, updated: FoodItem,
                           operationID: String? = nil, dayContext: DiaryDayContext? = nil,
                           completion: @escaping (Bool) -> Void) {
        guard original.id == updated.id else { completion(false); return }
        enqueueDailyLogMutation(
            for: userID, date: date, dayContext: dayContext, failureMessage: "Could not update this food. Its original entry may have changed.",
            shouldRecordUndo: { $0 != nil },
            mutation: { (log: inout DailyLog) -> FoodItem?? in
                let current = log.meals.flatMap(\.foodItems).first(where: { $0.id == original.id })
                // Only known stock/planned occurrence IDs need an accepted-receipt
                // check after a later edit or deletion. No local stale replacement occurs.
                let mayHaveIntakeReceipt = original.id.hasPrefix("stock-") || original.id.hasPrefix("planned-")
                let matchesReview = current.map { FoodEditPrecondition.sameSnapshot($0, updated) || FoodEditPrecondition.sameSnapshot($0, original) } ?? false
                guard matchesReview || mayHaveIntakeReceipt else { return nil }
                log.mutationBase = try? JSONEncoder().encode(log)
                log.pendingMutationID = operationID ?? UUID().uuidString
                log.pendingFoodEdit = FoodEditPrecondition(original: original, desired: updated)
                // The repository accepts an immutable existing receipt read-only, or
                // rejects the original/desired precondition atomically if not accepted.
                guard let current, matchesReview else { return .some(nil) }
                if FoodEditPrecondition.sameSnapshot(current, updated) { return .some(nil) }
                let result = DailyLogRules.updateFoodInLog(log: &log, updatedFoodItem: updated)
                return result.updated ? .some(current) : nil
            },
            onSuccess: { previous, _ in
                if let previous {
                    _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [previous.id], userID: userID)
                    EcosystemSyncManager.shared.replaceNutritionInHealthKit(oldItem: previous, newItem: updated)
                }
            }, completion: completion
        )
    }

    public func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        addMealToLog(for: userID, date: activelyViewedDate, mealName: mealName, foodItems: foodItems)
    }

    public func addMealToCurrentLog(
        for userID: String,
        mealName: String,
        foodItems: [FoodItem],
        completion: @escaping (Bool) -> Void
    ) {
        addMealToLog(
            for: userID,
            date: activelyViewedDate,
            mealName: mealName,
            foodItems: foodItems,
            source: "recipe",
            completion: completion
        )
    }

    public func addMealToLog(
        for userID: String,
        date: Date,
        mealName: String,
        foodItems: [FoodItem],
        source: String = "recipe"
    ) {
        addMealGroupsToLog(
            for: userID,
            date: date,
            mealGroups: [(mealName: mealName, foodItems: foodItems)],
            source: source
        )
    }

    public func addMealToLog(
        for userID: String,
        date: Date,
        mealName: String,
        foodItems: [FoodItem],
        source: String,
        completion: @escaping (Bool) -> Void
    ) {
        addMealGroupsToLog(
            for: userID,
            date: date,
            mealGroups: [(mealName: mealName, foodItems: foodItems)],
            source: source,
            completion: completion
        )
    }

    public func addMealGroupsToLog(
        for userID: String,
        date: Date,
        mealGroups: [(mealName: String, foodItems: [FoodItem])],
        source: String = "recipe"
    ) {
        addMealGroupsToLog(
            for: userID,
            date: date,
            mealGroups: mealGroups,
            source: source,
            completion: nil
        )
    }

    public func addMealGroupsToLog(
        for userID: String,
        date: Date,
        mealGroups: [(mealName: String, foodItems: [FoodItem])],
        source: String,
        deduplicateFoodIDs: Bool = false,
        dayContext: DiaryDayContext? = nil,
        completion: ((Bool) -> Void)?
    ) {
        let capturedDay = dayContext ?? diaryDayContext(for: userID, date: date)
        guard let capturedDay, capturedDay.isOwned(by: userID), !capturedDay.isFuture() else { completion?(false); return }
        let dateToLog = capturedDay.originalDate
        let nonEmptyGroups = mealGroups.filter { !$0.foodItems.isEmpty }
        guard !nonEmptyGroups.isEmpty else {
            completion?(false)
            return
        }

        enqueueDailyLogMutation(
            for: userID,
            date: dateToLog,
            dayContext: capturedDay,
            failureMessage: "Couldn't save the meal. Please try again.",
            shouldRecordUndo: { !$0.addedItems.isEmpty },
            mutation: { log in
                var existingIDs = Set(log.meals.flatMap(\.foodItems).map(\.id))
                let groups = deduplicateFoodIDs ? mealGroups.map { group in
                    (mealName: group.mealName, foodItems: group.foodItems.filter { existingIDs.insert($0.id).inserted })
                } : mealGroups
                let result = DailyLogRules.addMealGroupsToLog(
                    log: &log,
                    mealGroups: groups,
                    defaultSource: source
                )
                return result.addedItems.isEmpty && !deduplicateFoodIDs ? nil : result
            },
            onSuccess: { [weak self] result, _ in
                guard let self else { return }
                guard !result.addedItems.isEmpty else { return }
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
                    self.achievementService?.checkAcceptedFood(userID: userID, food: item, date: dateToLog, source: source, dayKey: capturedDay.dayKey)
                }
                self.recordFoodLoggingSuccess(source: result.sourceUsed)
                let message = nonEmptyGroups.count == 1
                    ? "\(nonEmptyGroups[0].mealName) logged!"
                    : "Planned day logged!"
                self.bannerService?.showBanner(title: "Success", message: message)
                self.achievementService?.checkAchievementsOnLogUpdate(userID: userID, logDate: dateToLog, dayKey: capturedDay.dayKey)
            },
            completion: completion
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
                _ = TransferHealthSyncQueue.shared.invalidateCopiedFoods(ids: [result.food.id], userID: userID)
                EcosystemSyncManager.shared.deleteNutritionFromHealthKit(item: result.food)
                self?.bannerService?.showBanner(title: "Deleted", message: "\(result.name) removed from log.")
            }
        )
    }

    public func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
        addWaterToLog(for: userID, amount: amount, goalOunces: goalOunces, capturedAt: activelyViewedDate)
    }

    public func addWaterToLog(
        for userID: String, amount: Double, goalOunces: Double,
        capturedAt: Date, entryID: String? = nil, completion: ((Bool) -> Void)? = nil
    ) {
        guard amount.isFinite, goalOunces.isFinite else { completion?(false); return }
        let waterReceiptID = entryID ?? UUID().uuidString
        enqueueDailyLogMutation(
            for: userID,
            date: capturedAt,
            failureMessage: "Could not save water. Your queued entry is available to retry.",
            mutation: { log in
                if let entryID, (log.appliedMutationIDs ?? []).contains(entryID) {
                    log.pendingMutationID = entryID
                    return 0.0
                }
                log.pendingMutationID = entryID
                DailyLogRules.addWaterToLog(log: &log, amount: amount, goalOunces: goalOunces, dateToLog: capturedAt)
                return amount
            },
            onSuccess: { loggedAmount, acceptedLog in
                if loggedAmount > 0 {
                    if let dayKey = acceptedLog.id ?? DiaryDayContext.dayKey(for: capturedAt) {
                        try? ReminderWaterEvidenceStore.shared.recordAccepted(ownerID: userID,
                            currentUserID: DIContainer.shared.authService.currentUserID, entryID: waterReceiptID,
                            dayKey: dayKey, totalAfterOunces: acceptedLog.waterTracker?.totalOunces ?? 0)
                    }
                    NotificationCenter.default.post(name: .reminderEvidenceChanged, object: userID)
                    EcosystemSyncManager.shared.syncWaterToHealthKit(ounces: loggedAmount, date: capturedAt)
                    DIContainer.shared.analyticsManager?.logEvent("water_logged", parameters: ["amount": loggedAmount])
                }
            },
            completion: completion
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
        addWorkoutToLog(
            for: userID, date: date, exerciseName: exerciseName, durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned, completion: nil
        )
    }

    public func addWorkoutToLog(
        for userID: String, date: Date, exerciseName: String, durationMinutes: Int?,
        caloriesBurned: Double, completion: ((Bool) -> Void)?
    ) {
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
            },
            completion: completion
        )
    }

    public func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard isActiveAccount(userID) else {
            completion(.failure(DailyLogListenerFailure.accountChanged))
            return
        }

        recentFoodStore.fetchRecentFoodItems(for: userID) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isActiveAccount(userID) else {
                    completion(.failure(DailyLogListenerFailure.accountChanged))
                    return
                }
                completion(result)
            }
        }
    }

    public func loadSmartSuggestions(for userID: String) {
        activateCurrentAccountIfNeeded(userID)
        fetchRecentFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.isActiveAccount(userID) else { return }
                switch result {
                case .success(let items):
                    self.smartSuggestions = SmartSuggestionBuilder.uniqueRecentFoods(from: items)
                case .failure(let error):
                    AppLog.data.error("Failed to load smart suggestions: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    public func fetchDailyHistory(for userID: String, startDate: Date? = nil, endDate: Date? = nil) async -> Result<[DailyLog], Error> {
        guard DIContainer.shared.authService.currentUserID == userID else {
            return .failure(DailyLogListenerFailure.accountChanged)
        }
        do {
            let logs = try await DIContainer.shared.nutritionRepository.fetchDailyHistory(userID: userID, startDate: startDate, endDate: endDate)
            guard DIContainer.shared.authService.currentUserID == userID else {
                return .failure(DailyLogListenerFailure.accountChanged)
            }
            return .success(logs)
        } catch {
            return .failure(error)
        }
    }



}
