#if DEBUG
import Foundation
import Combine

public final class MockNutritionRepository: NutritionRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public init() {}
    public var planningWorkspaceError: Error?
    public var planningWorkspaceFailureAfterCommit: Error?
    public var planningWorkspaceAccountID: String?
    public var savedMealCompositionsByUserID: [String: [SavedMealComposition]] = [:]
    public var savedMealWeekTemplatesByUserID: [String: [SavedMealWeekTemplate]] = [:]
    private var planningWorkspaceReceipts: [String: Data] = [:]
    public var libraryMutationError: Error?
    public var libraryMutationFailureAfterCommit: Error?
    public var libraryMutationAccountID: String?
    public var recipeLibrariesByUserID: [String: [Recipe]] = [:]
    public var foodLibrariesByUserID: [String: [FoodItem]] = [:]
    private var recipeSeedOwnerID: String?
    private var foodSeedOwnerID: String?
    private var libraryMutationReceipts: [String: LibraryMutationReceipt] = [:]
    private var libraryUndoLocks: [String: UUID] = [:]
    public var groceryMutationAccountID: String?
    public var groceryMutationFailureAfterCommit: Error?
    private var groceryReceipts: [String: GroceryMutationReceipt] = [:]
    private var groceryUndoLocks: [String: UUID] = [:]
    private var groceryRowsByUserID: [String: [GroceryListItem]] = [:]
    private var grocerySeedOwnerID: String?
    private var cookingDefinitionsByUserID: [String: [String: MealCookingBatch]] = [:]
    private var activeCookingDefinitionsByUserID: [String: Set<String>] = [:]
    
    // Properties for testing
    public var lastUpdatedLog: DailyLog?
    public var savedDailyLogs: [DailyLog] = []
    public var savedDailyLogUserIDs: [String] = []
    public var saveDailyLogError: Error?
    public var updateLogSuccess: Bool = true
    /// Opt-in committed storage for persistence/retry tests. Existing mock behavior is unchanged.
    public var persistsDailyLogUpdates = false
    public var dailyLogUpdateUserIDs: [String] = []
    private var persistedDailyLogs: [String: [Date: DailyLog]] = [:]
    private var persistedDailyLogsByKey: [String: [String: DailyLog]] = [:]
    /// Seeds canonical records for integration fixtures without creating save receipts.
    /// Enable `persistsDailyLogUpdates` separately when exercising subsequent writes.
    public func seedCommittedDailyLogs(userID: String, logs: [DailyLog]) {
        lock.withLock {
            for log in logs {
                let stored = log.rememberingMutationBase()
                persistedDailyLogs[userID, default: [:]][Calendar.current.startOfDay(for: log.date)] = stored
                if let key = log.id { persistedDailyLogsByKey[userID, default: [:]][key] = stored }
            }
        }
    }
    private var diaryTransferReceipts: [String: [UUID: DiaryTransferReceipt]] = [:]
    private var diaryTransferCancellations: [String: [UUID: DiaryTransferCancellation]] = [:]
    public var diaryTransferError: Error?
    public var diaryTransferFailureAfterCommit: Error?
    public var diaryTransferDelayNanoseconds: UInt64 = 0
    public var diaryTransferAccountID: String?
    public var diaryTransferBlockedUserIDs = Set<String>()
    public var diaryTransferPendingDayKeys = Set<String>()
    public var appliedDiaryTransferIDs: [UUID] = []
    public var undoneDiaryTransferIDs: [UUID] = []
    public var fetchedDiaryDayKeys: [String] = []
    public var logSnapshotListenerDayKeys: [String] = []
    public var mockFetchLogResult: Result<DailyLog, Error>?
    public var mockFetchDailyHistoryResult: Result<[DailyLog], Error>?
    public var mockFetchDailyHistoryResultsByUserID: [String: Result<[DailyLog], Error>] = [:]
    public var fetchDailyHistoryDelayNanoseconds: UInt64 = 0
    public var mockFetchDailyHistoryResultsByStartDate: [Date: Result<[DailyLog], Error>] = [:]
    public var fetchDailyHistoryDelayNanosecondsByStartDate: [Date: UInt64] = [:]
    public var mockLogsByDay: [DailyLog] = []
    public var filtersHistoryByRequestedRange = false
    public var mockRecommendedFoods: [FoodItem] = []
    public var shouldDeferRecommendedFoodCallbacks = false
    public var recommendedFoodCallbacks: [(Result<[FoodItem], Error>) -> Void] = []
    public var shouldDeferLogSnapshotCallbacks = false
    public var logSnapshotListenerUserIDs: [String] = []
    public var logSnapshotCallbacks: [String: (Result<DailyLog, Error>) -> Void] = [:]
    public var shouldDeferDailyLogUpdateCompletions = false
    public var deferredDailyLogUpdateCompletions: [(Bool) -> Void] = []
    
    public func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {
        lastUpdatedLog = log
        dailyLogUpdateUserIDs.append(userID)
        let finish: (Bool) -> Void = { [self] accepted in
            guard accepted else { completion(false); return }
            do {
                if persistsDailyLogUpdates, log.pendingFoodEdit != nil || !(log.pendingFoodEdits ?? []).isEmpty || log.pendingActivityEdit != nil || NutritionDayReviewRules.requiresCheckedCommit(log) {
                    if let stock = try commitMockDiaryAndIntake(userID: userID, log: log) { emitPantrySnapshot(.success(stock), for: userID) }
                } else { try persistDailyLogIfEnabled(userID: userID, log: log) }
            } catch { completion(false); return }
            completion(accepted)
        }
        if shouldDeferDailyLogUpdateCompletions {
            deferredDailyLogUpdateCompletions.append(finish)
        } else {
            finish(updateLogSuccess)
        }
    }
    public func saveDailyLog(userID: String, log: DailyLog) async throws {
        if let saveDailyLogError { throw saveDailyLogError }
        lastUpdatedLog = log
        savedDailyLogs.append(log)
        savedDailyLogUserIDs.append(userID)
        try persistDailyLogIfEnabled(userID: userID, log: log)
    }
    private func persistDailyLogIfEnabled(userID: String, log: DailyLog) throws {
        let knownLinked = lock.withLock { () -> Bool in
            let ids = Set(log.meals.flatMap(\.foodItems).map(\.id))
                .union(log.mutationBase.flatMap { try? JSONDecoder().decode(DailyLog.self, from: $0) }?.meals.flatMap(\.foodItems).map(\.id) ?? [])
            return inventoryIntakeLinks.values.contains { $0.userID == userID && ids.contains($0.foodID) }
                || inventoryReceipts.values.contains { receipt in
                    receipt.userID == userID && (try? receipt.mutation().diary.map { ids.contains($0.foodID) }) == true
                }
        }
        guard persistsDailyLogUpdates || knownLinked else { return }
        if log.mutationBase != nil {
            if let stock = try commitMockDiaryAndIntake(userID: userID, log: log) { emitPantrySnapshot(.success(stock), for: userID) }
            return
        }
        lock.withLock {
            // Production commits the operation ID in the same transaction as its
            // payload. Do not drop that receipt when simulating a process restart.
            var committed = log
            if let operationID = committed.pendingMutationID, !(committed.appliedMutationIDs ?? []).contains(operationID) {
                committed.appliedMutationIDs = (committed.appliedMutationIDs ?? []) + [operationID]
            }
            persistedDailyLogs[userID, default: [:]][Calendar.current.startOfDay(for: log.date)] = committed.rememberingMutationBase()
            if let key = committed.id { persistedDailyLogsByKey[userID, default: [:]][key] = committed.rememberingMutationBase() }
        }
    }
    public func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        if let result = mockFetchLogResult {
            completion(result)
        } else if let log = lock.withLock({ persistedDailyLogs[userID]?[Calendar.current.startOfDay(for: date)] }) {
            completion(.success(log))
        } else if let log = mockLogsByDay.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            completion(.success(log))
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            completion(.success(emptyLog))
        }
    }
    public func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any { 
        inventoryObservedDay[userID] = DiaryDayContext.dayKey(for: date)
        logSnapshotListenerUserIDs.append(userID)
        logSnapshotCallbacks[userID] = onChange
        if shouldDeferLogSnapshotCallbacks {
            return UUID()
        } else if let result = mockFetchLogResult {
            onChange(result)
        } else if let log = lock.withLock({ persistedDailyLogs[userID]?[Calendar.current.startOfDay(for: date)] }) {
            onChange(.success(log))
        } else if let log = mockLogsByDay.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            onChange(.success(log))
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            onChange(.success(emptyLog))
        }
        return UUID() 
    }
    public func removeLogSnapshotListener(_ handle: Any) {}
    public func fetchLogInternal(userID: String, day: DiaryDayContext, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard day.isOwned(by: userID) else { completion(.failure(DiaryTransferError.accountChanged)); return }
        fetchedDiaryDayKeys.append(day.dayKey)
        if let result = mockFetchLogResult { completion(result); return }
        completion(.success(lock.withLock { diaryLog(userID: userID, day: day) }))
    }
    public func addLogSnapshotListener(userID: String, day: DiaryDayContext, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any {
        guard day.isOwned(by: userID) else { onChange(.failure(DiaryTransferError.accountChanged)); return UUID() }
        logSnapshotListenerUserIDs.append(userID); logSnapshotListenerDayKeys.append(day.dayKey)
        inventoryObservedDay[userID] = day.dayKey
        logSnapshotCallbacks[userID] = onChange
        if !shouldDeferLogSnapshotCallbacks {
            if let result = mockFetchLogResult { onChange(result) } else { onChange(.success(lock.withLock { diaryLog(userID: userID, day: day) })) }
        }
        return UUID()
    }

    private func diaryLog(userID: String, day: DiaryDayContext) -> DailyLog {
        persistedDailyLogsByKey[userID]?[day.dayKey]
            ?? mockLogsByDay.first { $0.id == day.dayKey }
            ?? DailyLog(id: day.dayKey, date: day.startOfDay, meals: [])
    }

    public func applyDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult {
        if diaryTransferDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: diaryTransferDelayNanoseconds) }
        let result = try lock.withLock { () throws -> DiaryTransferResult in
            try validateTransferOwner(userID: userID, command: command)
            if let diaryTransferError { throw diaryTransferError }
            if let cancellation = diaryTransferCancellations[userID]?[command.id] {
                try cancellation.validate(for: command); throw DiaryTransferError.cancelled
            }
            let source = diaryLog(userID: userID, day: command.source)
            let destination = diaryLog(userID: userID, day: command.destination)
            if let receipt = diaryTransferReceipts[userID]?[command.id] {
                guard receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
                return DiaryTransferResult(receipt: receipt, sourceLog: source, destinationLog: destination, newlyApplied: false)
            }
            let result = try DiaryTransferRules.apply(command, source: source, destination: destination)
            commitTransfer(result, userID: userID)
            appliedDiaryTransferIDs.append(command.id)
            return result
        }
        if let diaryTransferFailureAfterCommit { throw diaryTransferFailureAfterCommit }
        return result
    }

    public func undoDiaryTransfer(userID: String, receipt: DiaryTransferReceipt) async throws -> DiaryTransferResult {
        if diaryTransferDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: diaryTransferDelayNanoseconds) }
        let result = try lock.withLock { () throws -> DiaryTransferResult in
            try validateTransferOwner(userID: userID, command: receipt.command)
            if let diaryTransferError { throw diaryTransferError }
            guard let accepted = diaryTransferReceipts[userID]?[receipt.id],
                  accepted.commandFingerprint == receipt.commandFingerprint else { throw DiaryTransferError.receiptMismatch }
            let result = try DiaryTransferRules.undo(accepted,
                source: diaryLog(userID: userID, day: receipt.command.source),
                destination: diaryLog(userID: userID, day: receipt.command.destination))
            if result.newlyApplied { commitTransfer(result, userID: userID); undoneDiaryTransferIDs.append(receipt.id) }
            return result
        }
        if let diaryTransferFailureAfterCommit { throw diaryTransferFailureAfterCommit }
        return result
    }

    public func fetchDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult {
        try lock.withLock {
            try validateTransferOwner(userID: userID, command: command, allowingPending: true)
            if let diaryTransferError { throw diaryTransferError }
            if let cancellation = diaryTransferCancellations[userID]?[command.id] {
                try cancellation.validate(for: command); throw DiaryTransferError.cancelled
            }
            guard let receipt = diaryTransferReceipts[userID]?[command.id] else { throw DiaryTransferError.receiptMissing }
            guard receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
            try receipt.validate()
            return DiaryTransferResult(receipt: receipt, sourceLog: diaryLog(userID: userID, day: command.source),
                destinationLog: diaryLog(userID: userID, day: command.destination), newlyApplied: false)
        }
    }

    public func cancelDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult? {
        let result = try lock.withLock { () throws -> DiaryTransferResult? in
            try validateTransferOwner(userID: userID, command: command, allowingPending: true)
            if let diaryTransferError { throw diaryTransferError }
            if let receipt = diaryTransferReceipts[userID]?[command.id] {
                try receipt.validate()
                guard receipt.commandFingerprint == (try command.fingerprint()) else { throw DiaryTransferError.receiptMismatch }
                return DiaryTransferResult(receipt: receipt, sourceLog: diaryLog(userID: userID, day: command.source),
                    destinationLog: diaryLog(userID: userID, day: command.destination), newlyApplied: false)
            }
            if let cancellation = diaryTransferCancellations[userID]?[command.id] { try cancellation.validate(for: command) } else {
                diaryTransferCancellations[userID, default: [:]][command.id] = try DiaryTransferCancellation(command: command)
            }
            return nil
        }
        if let diaryTransferFailureAfterCommit { throw diaryTransferFailureAfterCommit }
        return result
    }

    private func validateTransferOwner(userID: String, command: DiaryTransferCommand, allowingPending: Bool = false) throws {
        guard command.userID == userID, diaryTransferAccountID == nil || diaryTransferAccountID == userID,
              !diaryTransferBlockedUserIDs.contains(userID) else { throw DiaryTransferError.accountChanged }
        guard allowingPending || (!diaryTransferPendingDayKeys.contains(command.source.dayKey) &&
              !diaryTransferPendingDayKeys.contains(command.destination.dayKey)) else { throw DiaryTransferError.pendingWrites }
        try command.validate()
    }

    private func commitTransfer(_ result: DiaryTransferResult, userID: String) {
        for log in [result.sourceLog, result.destinationLog] {
            if let key = log.id { persistedDailyLogsByKey[userID, default: [:]][key] = log }
            persistedDailyLogs[userID, default: [:]][Calendar.current.startOfDay(for: log.date)] = log
        }
        diaryTransferReceipts[userID, default: [:]][result.receipt.id] = result.receipt
    }
    public func emitLogSnapshot(_ result: Result<DailyLog, Error>, for userID: String) {
        logSnapshotCallbacks[userID]?(result)
    }
    public func completeDeferredDailyLogUpdates(success: Bool? = nil) {
        let completions = deferredDailyLogUpdateCompletions
        deferredDailyLogUpdateCompletions = []
        completions.forEach { $0(success ?? updateLogSuccess) }
    }
    public func fetchDailyHistoryForReview(userID: String, startDate: Date, endDate: Date) async throws -> [DailyLog] {
        try await fetchDailyHistory(userID: userID, startDate: startDate, endDate: endDate)
    }

    public func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog] { 
        let normalizedStartDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        let requestDelay = normalizedStartDate.flatMap { fetchDailyHistoryDelayNanosecondsByStartDate[$0] }
            ?? fetchDailyHistoryDelayNanoseconds
        if requestDelay > 0 {
            try await Task.sleep(nanoseconds: requestDelay)
        }
        let dateResult = normalizedStartDate.flatMap { mockFetchDailyHistoryResultsByStartDate[$0] }
        if let mock = dateResult ?? mockFetchDailyHistoryResultsByUserID[userID] ?? mockFetchDailyHistoryResult {
            var logs = try mock.get()
            for (key, _) in inventoryDiaryLogs where key.hasPrefix(userID + "|") {
                let dayKey = String(key.dropFirst(userID.count + 1))
                if let current = persistedDailyLogsByKey[userID]?[dayKey] {
                    logs.removeAll { $0.id == dayKey || Calendar.current.isDate($0.date, inSameDayAs: current.date) }
                    logs.append(current)
                }
            }
            guard filtersHistoryByRequestedRange else { return logs }
            let calendar = Calendar.current
            let start = startDate.map { calendar.startOfDay(for: $0) }
            let end = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
            return logs.filter { log in
                let day = calendar.startOfDay(for: log.date)
                return start.map { day >= $0 } ?? true && end.map { day < $0 } ?? true
            }
        }
        return [] 
    }
    public func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        if shouldDeferRecommendedFoodCallbacks {
            recommendedFoodCallbacks.append(completion)
        } else {
            completion(.success(mockRecommendedFoods))
        }
    }
    public func completeDeferredRecommendedFoodFetches(with result: Result<[FoodItem], Error>? = nil) {
        let callbacks = recommendedFoodCallbacks
        recommendedFoodCallbacks = []
        let resolvedResult = result ?? .success(mockRecommendedFoods)
        callbacks.forEach { $0(resolvedResult) }
    }
    public var mockFetchMealPlanResult: MealPlanDay?
    public var mockMealPlansByDateString: [String: MealPlanDay] = [:]
    public var mockFetchGroceryListResult: [GroceryListItem] = []
    public var savedMealPlans: [MealPlanDay] = []
    public var savedGroceryLists: [GroceryListItem] = []
    public var grocerySaveSnapshots: [[GroceryListItem]] = []
    public var grocerySaveDelayNanoseconds: UInt64 = 0
    public var groceryListError: Error?
    public var groceryMutationError: Error?
    public var appliedGroceryMutationIDs: Set<UUID> = []
    public var batchSavedMealPlans: [MealPlanDay] = []
    public var discardedMealPlanDateStrings: [String] = []
    public var discardedMealPlanUserIDs: [String] = []
    public var mealPlanError: Error?
    public var mealPlanEditError: Error?
    public var mealPlanChangeFailureAfterCommit: Error?
    public var mealPlanChangeAccountID: String?
    public var mealPlanChangeReceipts: [String: MealPlanChangeReceipt] = [:]
    public var appliedMealPlanChangeIDs: [UUID] = []
    
    public func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? { 
        if let mealPlanError { throw mealPlanError }
        return mockMealPlansByDateString[dateString] ?? mockFetchMealPlanResult
    }
    public func fetchMealPlansForStockReservations(userID: String) async throws -> [MealPlanDay] {
        if let mealPlanError { throw mealPlanError }
        guard !userID.isEmpty, mealPlanChangeAccountID == nil || mealPlanChangeAccountID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        var plans = mockMealPlansByDateString
        if let single = mockFetchMealPlanResult, plans[single.id] == nil { plans[single.id] = single }
        return plans.values.sorted { $0.id < $1.id }
    }
    public func saveMealPlan(userID: String, plan: MealPlanDay) async throws {
        if let mealPlanError { throw mealPlanError }
        savedMealPlans.append(plan)
    }
    public func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        if let mealPlanError { throw mealPlanError }
        batchSavedMealPlans.append(contentsOf: plans)
    }
    public func applyMealPlanChange(userID: String, change: MealPlanChange) async throws {
        guard try JSONEncoder().encode(change).count <= 750_000 else { throw MealPlanChangeReceiptError.invalid }
        if let mealPlanError { throw mealPlanError }
        guard mealPlanChangeAccountID == nil || mealPlanChangeAccountID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        try MealPlanEditingRules.validate(change)
        let acceptedReceipt = try MealPlanChangeReceipt(userID: userID, change: change, status: .accepted)
        try lock.withLock {
            let key = "\(userID)|\(change.id.uuidString)"
            if let receipt = mealPlanChangeReceipts[key] {
                try receipt.validate(userID: userID, change: change)
                guard receipt.status == .accepted else { throw MealPlanChangeReceiptError.cancelled }
                return
            }
            if let mealPlanEditError { throw mealPlanEditError }
            for day in change.before {
                let actual = mockMealPlansByDateString[MealPlanEditingRules.dayID(day.date)] ?? mockFetchMealPlanResult
                guard MealPlanEditingRules.matches(actual, expected: day) else { throw MealPlanEditError.changed }
            }
            try mockCheckCookedBatchChanges(userID: userID, change: change)
            batchSavedMealPlans.append(contentsOf: change.after)
            for day in change.after { mockMealPlansByDateString[MealPlanEditingRules.dayID(day.date)] = day }
            mealPlanChangeReceipts[key] = acceptedReceipt
            appliedMealPlanChangeIDs.append(change.id)
            if let mealPlanChangeFailureAfterCommit { throw mealPlanChangeFailureAfterCommit }
        }
    }
    public func resolveMealPlanChange(userID: String, change: MealPlanChange, cancelPending: Bool) async throws -> MealPlanChangeResolution {
        if let mealPlanError { throw mealPlanError }
        guard mealPlanChangeAccountID == nil || mealPlanChangeAccountID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        try MealPlanChangeReceipt.validateEnvelope(userID: userID, change: change)
        return try lock.withLock {
            let key = "\(userID)|\(change.id.uuidString)"
            if let receipt = mealPlanChangeReceipts[key] {
                try receipt.validate(userID: userID, change: change)
                return receipt.resolution
            }
            guard cancelPending else { return .pending }
            let receipt = try MealPlanChangeReceipt(userID: userID, change: change, status: .cancelled)
            mealPlanChangeReceipts[key] = receipt
            return .cancelled
        }
    }
    public func discardMealPlans(
        userID: String,
        dateStrings: [String],
        retainingGroceryItems: [GroceryListItem]
    ) async throws {
        if let mealPlanError { throw mealPlanError }
        try lock.withLock {
            let dates = Set(dateStrings)
            let current = dateStrings.compactMap { mockMealPlansByDateString[$0] ?? mockFetchMealPlanResult }
            try MealPlanDiscardRules.validate(plans: current, deleting: dates)
            // Current storage wins over the caller's stale checklist snapshot.
            let retained = mockFetchGroceryListResult.filter { !MealPlanDiscardRules.removes($0, deleting: dates) }
            discardedMealPlanUserIDs.append(userID)
            discardedMealPlanDateStrings = dateStrings
            dateStrings.forEach { mockMealPlansByDateString.removeValue(forKey: $0) }
            savedGroceryLists = retained
            mockFetchGroceryListResult = retained
        }
    }
    public func fetchGroceryList(userID: String) async throws -> [GroceryListItem] { 
        if let groceryListError { throw groceryListError }
        return lock.withLock { mockGroceryRows(userID: userID) }
    }
    public func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {
        if grocerySaveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: grocerySaveDelayNanoseconds)
        }
        grocerySaveSnapshots.append(items)
        savedGroceryLists = items
    }
    public func applyGroceryMutation(userID: String, mutation: GroceryListMutation) async throws -> [GroceryListItem] {
        if let groceryMutationError { throw groceryMutationError }
        let result: ([GroceryListItem], Bool) = try lock.withLock {
            guard groceryMutationAccountID == nil || groceryMutationAccountID == userID else { throw GroceryChecklistError.accountChanged }
            let key = "\(userID)|\(mutation.id.uuidString)"
            if let receipt = groceryReceipts[key] {
                try receipt.validate(userID: userID, mutation: mutation)
                guard receipt.status == .accepted else { throw GroceryChecklistError.cancelled }
                return (mockGroceryRows(userID: userID), false)
            }
            if let originalID = mutation.undoingID {
                let originalKey = "\(userID)|\(originalID.uuidString)"
                guard let receipt = groceryReceipts[originalKey], groceryUndoLocks[originalKey] == nil else { throw GroceryChecklistError.changed }
                try mutation.validateInverse(of: receipt.mutation())
            }
            let changed = try mutation.applying(to: mockGroceryRows(userID: userID))
            groceryReceipts[key] = try GroceryMutationReceipt(userID: userID, mutation: mutation, status: .accepted)
            if let originalID = mutation.undoingID { groceryUndoLocks["\(userID)|\(originalID.uuidString)"] = mutation.id }
            updateMockGroceryRows(userID: userID, rows: changed)
            appliedGroceryMutationIDs.insert(mutation.id); savedGroceryLists = changed
            return (changed, true)
        }
        if result.1, let groceryMutationFailureAfterCommit { throw groceryMutationFailureAfterCommit }
        return result.0
    }
    public func resolveGroceryMutation(userID: String, mutation: GroceryListMutation, cancelPending: Bool) async throws -> GroceryMutationResolution {
        if let groceryMutationError { throw groceryMutationError }
        return try lock.withLock {
            guard groceryMutationAccountID == nil || groceryMutationAccountID == userID else { throw GroceryChecklistError.accountChanged }
            let key = "\(userID)|\(mutation.id.uuidString)"
            if let receipt = groceryReceipts[key] { try receipt.validate(userID: userID, mutation: mutation); return receipt.status }
            guard cancelPending else { return .pending }
            groceryReceipts[key] = try GroceryMutationReceipt(userID: userID, mutation: mutation, status: .cancelled)
            return .cancelled
        }
    }
    private func mockGroceryRows(userID: String) -> [GroceryListItem] {
        if grocerySeedOwnerID == userID || grocerySeedOwnerID == nil { return mockFetchGroceryListResult }
        return groceryRowsByUserID[userID] ?? []
    }
    private func updateMockGroceryRows(userID: String, rows: [GroceryListItem]) {
        if grocerySeedOwnerID == nil { grocerySeedOwnerID = userID }
        groceryRowsByUserID[userID] = rows
        if grocerySeedOwnerID == userID { mockFetchGroceryListResult = rows }
    }
    public var mockPantrySnapshotResult: Result<[PantryItem], Error>?
    public var shouldDeferPantrySnapshotCallbacks = false
    public var pantrySnapshotCallbacks: [String: (Result<[PantryItem], Error>) -> Void] = [:]
    public var pantryListenerUserIDs: [String] = []
    public var removedPantryListenerHandles: [Any] = []
    public var savedPantryItems: [PantryItem] = []
    public var savedPantryUserIDs: [String] = []
    public var deletedPantryItemIDs: [String] = []
    public var deletedPantryUserIDs: [String] = []
    public var pantryItemError: Error?
    public var pantryItemErrors: [UUID: Error] = [:]
    public var pantryErrorAfterCommitIDs: Set<UUID> = []
    private var pantryReceiptKeys = Set<String>()
    public var mockPantryItemsByID: [UUID: PantryItem] = [:]
    public var pantrySaveDelayNanoseconds: UInt64 = 0

    public var inventoryIntakeLinks: [String: InventoryIntakeLink] = [:]
    public var inventoryIntakeRevisionReceipts: [String: InventoryIntakeRevisionReceipt] = [:]
    public var inventoryReceipts: [String: InventoryReceipt] = [:]
    public var inventorySourceLocks: [String: UUID] = [:]
    public var inventoryFailureBeforeCommit: Error?
    public var inventoryFailureAfterCommit: Error?
    public var inventoryResolutionError: Error?
    private var inventoryObservedDay: [String: String] = [:]
    public var inventoryAccountID: String?
    public var inventoryDiaryLogs: [String: DailyLog] = [:]
    public var appliedInventoryIDs: [UUID] = []
    private var inventoryByOwner: [String: [UUID: PantryItem]] = [:]
    private var initialInventoryOwner: String?
    private func inventoryItems(for userID: String) -> [UUID: PantryItem] {
        if let saved = inventoryByOwner[userID] { return saved }
        if initialInventoryOwner == nil { initialInventoryOwner = userID; inventoryByOwner[userID] = mockPantryItemsByID; return mockPantryItemsByID }
        inventoryByOwner[userID] = [:]; return [:]
    }

    public func fetchInventory(userID: String) async throws -> [PantryItem] {
        if let inventoryAccountID, inventoryAccountID != userID { throw InventoryError.accountChanged }
        if let pantryItemError { throw pantryItemError }
        return Array(inventoryItems(for: userID).values)
    }
    public func fetchInventoryHistory(userID: String) async throws -> [InventoryReceipt] {
        inventoryReceipts.values.filter { $0.userID == userID }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public func applyInventoryMutation(userID: String, mutation: InventoryMutation) async throws {
        guard mutation.userID == userID, inventoryAccountID == nil || inventoryAccountID == userID else { throw InventoryError.accountChanged }
        if pantrySaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: pantrySaveDelayNanoseconds) }
        if let pantryItemError { throw pantryItemError }
        for item in mutation.after { if let error = pantryItemErrors[item.id] { throw error } }
        if let inventoryFailureBeforeCommit { throw inventoryFailureBeforeCommit }
        let effects: ([PantryItem]?, DailyLog?, Bool, Error?) = try lock.withLock {
            guard inventoryAccountID == nil || inventoryAccountID == userID else { throw InventoryError.accountChanged }
            try mutation.validate()
            let key = "\(userID)|\(mutation.id.uuidString)"
            if let receipt = inventoryReceipts[key] {
                try receipt.validate(mutation)
                guard receipt.status == .accepted else { throw InventoryError.cancelled }
                return (nil, nil, false, nil)
            }
            let receipt = try InventoryReceipt(mutation, status: .accepted)
            if let source = mutation.uniqueSourceKey, inventorySourceLocks["\(userID)|\(source)"] != nil { throw InventoryError.alreadyApplied }
            if let undo = mutation.undoing {
                guard inventoryReceipts["\(userID)|\(undo.uuidString)"]?.status == .accepted else { throw InventoryError.changed }
            }
            if mutation.reason == .cook { try mockCheckReviewedCookingSource(userID: userID, mutation: mutation) }
            let current = Array(inventoryItems(for: userID).values)
            let updated = try mutation.applying(to: current)
            if let undo = mutation.undoing, let receipt = inventoryReceipts["\(userID)|\(undo.uuidString)"] {
                try InventoryPlanningRules.validateUndo(mutation, original: receipt.mutation(), current: current)
            }
            let grocery = try mutation.grocery.map { try $0.applying(to: mockGroceryRows(userID: userID)) }
            var log: DailyLog?
            if let patch = mutation.diary {
                let original = diaryLog(userID: userID, day: patch.day)
                log = try patch.applying(to: original)
            }
            let intakeLink = try mockIntakeIndexForStockMutation(userID: userID, mutation: mutation, receipt: receipt)
            mockPantryItemsByID = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
            inventoryByOwner[userID] = mockPantryItemsByID
            for item in mutation.after {
                savedPantryItems.append(item); savedPantryUserIDs.append(userID)
            }
            if let grocery { updateMockGroceryRows(userID: userID, rows: grocery); savedGroceryLists = grocery }
            if let patch = mutation.diary, let log {
                inventoryDiaryLogs["\(userID)|\(patch.day.dayKey)"] = log
                persistedDailyLogsByKey[userID, default: [:]][patch.day.dayKey] = log
                persistedDailyLogs[userID, default: [:]][Calendar.current.startOfDay(for: log.date)] = log
            }
            inventoryReceipts[key] = receipt; appliedInventoryIDs.append(mutation.id)
            if let undo = mutation.undoing, let original = inventoryReceipts["\(userID)|\(undo.uuidString)"],
               let originalKey = try original.mutation().uniqueSourceKey {
                inventorySourceLocks.removeValue(forKey: "\(userID)|\(originalKey)")
            }
            if let source = mutation.uniqueSourceKey { inventorySourceLocks["\(userID)|\(source)"] = mutation.id }
            if let intakeLink {
                inventoryIntakeLinks["\(userID)|\(intakeLink.foodID)"] = intakeLink
                try updateMockIntakeSourceLock(intakeLink)
            }
            let failure: Error? = inventoryFailureAfterCommit ?? (mutation.after.contains(where: { pantryErrorAfterCommitIDs.contains($0.id) }) ? URLError(.timedOut) : nil)
            inventoryFailureAfterCommit = nil
            return (updated, log, mutation.diary.map { inventoryObservedDay[userID] == $0.day.dayKey } ?? false, failure)
        }
        if effects.2, let log = effects.1 { emitLogSnapshot(.success(log), for: userID) }
        if let items = effects.0 { emitPantrySnapshot(.success(items), for: userID) }
        if let error = effects.3 { throw error }
    }
    public func resolveInventoryMutation(userID: String, mutation: InventoryMutation, cancelPending: Bool) async throws -> InventoryResolution {
        guard mutation.userID == userID, inventoryAccountID == nil || inventoryAccountID == userID else { throw InventoryError.accountChanged }
        if let inventoryResolutionError { throw inventoryResolutionError }
        return try lock.withLock {
        let key = "\(userID)|\(mutation.id.uuidString)"
        if let receipt = inventoryReceipts[key] {
            try receipt.validate(mutation)
            return receipt.status == .accepted ? .accepted : .cancelled
        }
        guard cancelPending else { return .pending }
        inventoryReceipts[key] = try InventoryReceipt(mutation, status: .cancelled)
        return .cancelled
        }
    }

    public func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any {
        pantryListenerUserIDs.append(userID)
        pantrySnapshotCallbacks[userID] = onChange
        if shouldDeferPantrySnapshotCallbacks {
            return UUID()
        } else if let mockPantrySnapshotResult {
            onChange(mockPantrySnapshotResult)
        } else {
            onChange(.success([]))
        }
        return UUID()
    }

    public func emitPantrySnapshot(_ result: Result<[PantryItem], Error>, for userID: String) {
        pantrySnapshotCallbacks[userID]?(result)
    }

    public func removePantrySnapshotListener(_ handle: Any) {
        removedPantryListenerHandles.append(handle)
    }

    public func savePantryItem(userID: String, item: PantryItem) async throws {
        if pantrySaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: pantrySaveDelayNanoseconds) }
        if let pantryItemError { throw pantryItemError }
        if let error = pantryItemErrors[item.id] { throw error }
        savedPantryUserIDs.append(userID)
        savedPantryItems.append(item)
        mockPantryItemsByID[item.id] = item
        if pantryErrorAfterCommitIDs.contains(item.id) { throw URLError(.timedOut) }
    }

    public func createPantryReceiptItem(userID: String, receiptID: UUID, item: PantryItem) async throws {
        if pantrySaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: pantrySaveDelayNanoseconds) }
        if let pantryItemError { throw pantryItemError }
        if let error = pantryItemErrors[item.id] { throw error }
        let created = try lock.withLock { () throws -> Bool in
            let key = "\(userID)|\(receiptID.uuidString)|\(item.id.uuidString)"
            if pantryReceiptKeys.contains(key) { return false }
            guard mockPantryItemsByID[item.id] == nil else { throw GroceryChecklistError.changed }
            savedPantryUserIDs.append(userID)
            savedPantryItems.append(item)
            mockPantryItemsByID[item.id] = item
            pantryReceiptKeys.insert(key)
            return true
        }
        if created, pantryErrorAfterCommitIDs.contains(item.id) { throw URLError(.timedOut) }
    }

    public func deletePantryItem(userID: String, itemID: String) async throws {
        if let pantryItemError { throw pantryItemError }
        lock.withLock {
            deletedPantryUserIDs.append(userID)
            deletedPantryItemIDs.append(itemID)
        }
    }
    public var mockRecipes: [Recipe] = []
    public var savedRecipes: [Recipe] = []
    public var deletedRecipeIDs: [String] = []
    public var recipeRevisionError: Error?
    public var recipeRevisionFailureAfterCommit: Error?
    public var recipeRevisionDelayNanoseconds: UInt64 = 0
    public var fetchRecipesHandler: ((String) async throws -> [Recipe])?
    public var recipeRevisionReturnHandler: ((Recipe) async throws -> Recipe)?
    public var savedRecipeRevisionUserIDs: [String] = []
    private var recipeRevisionReceipts: [String: String] = [:]
    private var recipeRevisionCancellations = Set<String>()
    private var recipeVersionRecords: [String: [RecipeVersionRecord]] = [:]
    private var recipeVersionRestoreReceipts: [String: (fingerprint: String, accepted: Bool)] = [:]
    public var recipeVersionAccountID: String?
    
    public func fetchRecipes(userID: String) async throws -> [Recipe] {
        if let fetchRecipesHandler { return try await fetchRecipesHandler(userID) }
        return lock.withLock { mockRecipeRecords(userID: userID) }
    }
    public func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe {
        lock.withLock {
            savedRecipes.append(recipe)
            if recipeSeedOwnerID != nil || recipeLibrariesByUserID[userID] != nil {
                var records = mockRecipeRecords(userID: userID); records.removeAll { $0.id == recipe.id }; records.append(recipe)
                updateMockRecipeRecords(userID: userID, records: records)
            }
        }
        return recipe
    }
    public func saveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID) async throws -> Recipe {
        try RecipeRevisionRules.validate(expected: expected, updated: updated)
        let fingerprint = try RecipeRevisionRules.commandFingerprint(userID: userID, expected: expected, updated: updated, operationID: operationID)
        if recipeRevisionDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: recipeRevisionDelayNanoseconds) }
        if let recipeRevisionError { throw recipeRevisionError }
        let result = try lock.withLock { () throws -> (Recipe, Bool) in
            guard let id = updated.id else { throw RecipeRevisionError.invalid }
            let key = "\(userID)|\(operationID.uuidString)"
            let latest = mockRecipeRecords(userID: userID).first { $0.id == id }
            if let accepted = recipeRevisionReceipts[key] {
                guard accepted == fingerprint else { throw RecipeRevisionError.changed }
                guard !recipeRevisionCancellations.contains(key) else { throw RecipeRevisionError.cancelled }
                guard let latest else { throw RecipeRevisionError.changed }
                return (latest, false)
            }
            switch (expected, latest) {
            case (nil, nil): break
            case let (.some(original), .some(current)):
                guard try RecipeRevisionRules.sameOpeningSnapshot(original, current) else { throw RecipeRevisionError.changed }
            default: throw RecipeRevisionError.changed
            }
            let versions = try makeMockRecipeVersions(recipeID: id, before: latest, after: updated, operationID: operationID, restored: false)
            recipeRevisionReceipts[key] = fingerprint
            recipeVersionRecords["\(userID)|\(id)", default: []].append(contentsOf: versions)
            var records = mockRecipeRecords(userID: userID)
            if let index = records.firstIndex(where: { $0.id == id }) { records[index] = updated } else { records.append(updated) }
            updateMockRecipeRecords(userID: userID, records: records)
            savedRecipes.append(updated); savedRecipeRevisionUserIDs.append(userID)
            return (updated, true)
        }
        if result.1, let recipeRevisionFailureAfterCommit { throw recipeRevisionFailureAfterCommit }
        if let recipeRevisionReturnHandler { return try await recipeRevisionReturnHandler(result.0) }
        return result.0
    }
    private func makeMockRecipeVersions(recipeID: String, before: Recipe?, after: Recipe, operationID: UUID, restored: Bool) throws -> [RecipeVersionRecord] {
        let now = Date()
        let versionPrefix = (restored ? "restore-" : "edit-") + operationID.uuidString
        var result: [RecipeVersionRecord] = []
        if let before { result.append(try .init(id: versionPrefix + "-before", recipeID: recipeID, operationID: operationID, phase: .before, recordedAt: now, snapshot: before)) }
        result.append(try .init(id: versionPrefix + "-after", recipeID: recipeID, operationID: operationID, phase: restored ? .restored : .saved, recordedAt: now, snapshot: after))
        return result
    }
    public func fetchRecipeVersionHistory(userID: String, recipeID: String, limit: Int) async throws -> [RecipeVersionRecord] {
        try checkRecipeVersionOwner(userID)
        guard PlanningDocumentRules.validID(recipeID), (1...200).contains(limit) else { throw RecipeRevisionError.invalid }
        return lock.withLock { Array((recipeVersionRecords["\(userID)|\(recipeID)"] ?? []).sorted { $0.recordedAt > $1.recordedAt }.prefix(limit)) }
    }
    public func restoreRecipeVersion(userID: String, proposal: RecipeVersionRestoreProposal) async throws -> Recipe {
        try checkRecipeVersionOwner(userID); try proposal.validate()
        guard proposal.userID == userID else { throw RecipeRevisionError.accountChanged }
        if let recipeRevisionError { throw recipeRevisionError }
        let fingerprint = try proposal.fingerprint
        let result = try lock.withLock { () throws -> (Recipe, Bool) in
            let key = "\(userID)|\(proposal.id)"
            let actual = mockRecipeRecords(userID: userID).first { $0.id == proposal.version.recipeID }
            if let receipt = recipeVersionRestoreReceipts[key] {
                guard receipt.fingerprint == fingerprint else { throw RecipeRevisionError.changed }
                guard receipt.accepted else { throw RecipeRevisionError.cancelled }
                guard let actual else { throw RecipeRevisionError.changed }; return (actual, false)
            }
            guard let actual, try RecipeRevisionRules.sameOpeningSnapshot(actual, proposal.expected),
                  let selected = recipeVersionRecords["\(userID)|\(proposal.version.recipeID)"]?.first(where: { $0.id == proposal.version.id }),
                  try PlanFingerprint.make(selected) == PlanFingerprint.make(proposal.version) else { throw RecipeRevisionError.changed }
            let updated = try proposal.updated
            let versions = try makeMockRecipeVersions(recipeID: selected.recipeID, before: actual, after: updated, operationID: proposal.id, restored: true)
            var values = mockRecipeRecords(userID: userID); values.removeAll { $0.id == updated.id }; values.append(updated)
            recipeVersionRestoreReceipts[key] = (fingerprint, true)
            recipeVersionRecords["\(userID)|\(selected.recipeID)", default: []].append(contentsOf: versions)
            updateMockRecipeRecords(userID: userID, records: values); savedRecipes.append(updated)
            return (updated, true)
        }
        if result.1, let recipeRevisionFailureAfterCommit { throw recipeRevisionFailureAfterCommit }
        return result.0
    }
    public func resolveRecipeVersionRestore(userID: String, proposal: RecipeVersionRestoreProposal, cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution {
        try checkRecipeVersionOwner(userID); try proposal.validate()
        guard proposal.userID == userID else { throw RecipeRevisionError.accountChanged }
        if let recipeRevisionError { throw recipeRevisionError }
        let fingerprint = try proposal.fingerprint
        return try lock.withLock {
            let key = "\(userID)|\(proposal.id)"
            if let receipt = recipeVersionRestoreReceipts[key] {
                guard receipt.fingerprint == fingerprint else { throw RecipeRevisionError.changed }
                return receipt.accepted ? .accepted(mockRecipeRecords(userID: userID).first { $0.id == proposal.version.recipeID }) : .cancelled
            }
            guard cancelIfUnaccepted else { return .pending }
            recipeVersionRestoreReceipts[key] = (fingerprint, false); return .cancelled
        }
    }
    private func checkRecipeVersionOwner(_ userID: String) throws {
        guard !userID.isEmpty, recipeVersionAccountID == nil || recipeVersionAccountID == userID else { throw RecipeRevisionError.accountChanged }
    }
    public func resolveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID,
                                      cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution {
        try RecipeRevisionRules.validate(expected: expected, updated: updated)
        let fingerprint = try RecipeRevisionRules.commandFingerprint(userID: userID, expected: expected, updated: updated, operationID: operationID)
        if let recipeRevisionError { throw recipeRevisionError }
        return try lock.withLock {
            let key = "\(userID)|\(operationID.uuidString)"
            if let saved = recipeRevisionReceipts[key] {
                guard saved == fingerprint else { throw RecipeRevisionError.changed }
                if recipeRevisionCancellations.contains(key) { return .cancelled }
                return .accepted(mockRecipeRecords(userID: userID).first { $0.id == updated.id })
            }
            guard cancelIfUnaccepted else { return .pending }
            recipeRevisionReceipts[key] = fingerprint; recipeRevisionCancellations.insert(key)
            return .cancelled
        }
    }
    public func deleteRecipe(userID: String, recipeID: String) async throws {
        lock.withLock {
            deletedRecipeIDs.append(recipeID)
            var records = mockRecipeRecords(userID: userID); records.removeAll { $0.id == recipeID }
            updateMockRecipeRecords(userID: userID, records: records)
        }
    }
    public var savedCustomFoods: [FoodItem] = []
    public var replacedCustomFoodOperations: [(foodItem: FoodItem, removing: [String])] = []
    public var deletedCustomFoodIDs: [String] = []
    public var barcodeRemovedCustomFoodIDs: [String] = []
    public var mergedCustomFoodOperations: [(keeping: String, removing: [String])] = []
    public var customFoodsToReturn: [FoodItem] = []
    public var customFoodError: Error?
    public var customFoodDelayNanoseconds: UInt64 = 0
    public func saveCustomFood(userID: String, foodItem: FoodItem) async throws {
        if customFoodDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: customFoodDelayNanoseconds)
        }
        if let customFoodError { throw customFoodError }
        lock.withLock {
            savedCustomFoods.append(foodItem)
            if foodSeedOwnerID != nil || foodLibrariesByUserID[userID] != nil {
                var records = mockFoodRecords(userID: userID); records.removeAll { $0.id == foodItem.id }; records.append(foodItem)
                foodLibrariesByUserID[userID] = records
                if foodSeedOwnerID == userID { customFoodsToReturn = records }
            }
        }
    }
    public func saveCustomFoodReplacingDuplicates(
        userID: String,
        foodItem: FoodItem,
        removingFoodIDs: [String]
    ) async throws {
        if let customFoodError { throw customFoodError }
        lock.withLock {
            savedCustomFoods.append(foodItem)
            replacedCustomFoodOperations.append((foodItem, removingFoodIDs))
        }
    }
    public func deleteCustomFood(userID: String, foodItemID: String) async throws {
        if let customFoodError { throw customFoodError }
        deletedCustomFoodIDs.append(foodItemID)
    }
    public func removeCustomFoodBarcode(userID: String, foodItemID: String) async throws {
        if let customFoodError { throw customFoodError }
        barcodeRemovedCustomFoodIDs.append(foodItemID)
    }
    public func mergeCustomFoods(userID: String, keepingFoodID: String, removingFoodIDs: [String]) async throws {
        if let customFoodError { throw customFoodError }
        mergedCustomFoodOperations.append((keepingFoodID, removingFoodIDs))
    }
    public func fetchCustomFoods(userID: String) async throws -> [FoodItem] {
        if customFoodDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: customFoodDelayNanoseconds)
        }
        if let customFoodError { throw customFoodError }
        return lock.withLock { mockFoodRecords(userID: userID) }
    }
    private var storedSavedRecentFoods: [(userID: String, foodItem: FoodItem, source: String, stableID: String)] = []
    private var storedRecentFoodsToReturn: [FoodItem] = []
    private var storedRecentFoodError: Error?
    private var storedFetchRecentFoodLimits: [Int] = []

    public var savedRecentFoods: [(userID: String, foodItem: FoodItem, source: String, stableID: String)] {
        get { lock.withLock { storedSavedRecentFoods } }
        set { lock.withLock { storedSavedRecentFoods = newValue } }
    }

    public var recentFoodsToReturn: [FoodItem] {
        get { lock.withLock { storedRecentFoodsToReturn } }
        set { lock.withLock { storedRecentFoodsToReturn = newValue } }
    }

    public var recentFoodError: Error? {
        get { lock.withLock { storedRecentFoodError } }
        set { lock.withLock { storedRecentFoodError = newValue } }
    }

    public var fetchRecentFoodLimits: [Int] {
        get { lock.withLock { storedFetchRecentFoodLimits } }
        set { lock.withLock { storedFetchRecentFoodLimits = newValue } }
    }

    public func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws {
        try lock.withLock {
            if let storedRecentFoodError { throw storedRecentFoodError }
            storedSavedRecentFoods.append((userID, foodItem, source, stableID))
        }
    }

    public func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem] {
        try lock.withLock {
            if let storedRecentFoodError { throw storedRecentFoodError }
            storedFetchRecentFoodLimits.append(limit)
            return Array(storedRecentFoodsToReturn.prefix(limit))
        }
    }
}
#endif
#if DEBUG
extension MockNutritionRepository {
    public func fetchSavedMealCompositions(userID: String) async throws -> [SavedMealComposition] {
        try checkPlanningOwner(userID)
        return try lock.withLock {
            let values = savedMealCompositionsByUserID[userID] ?? []
            for value in values { try value.validateStoredSnapshot() }
            return values
        }
    }
    public func fetchSavedMealWeekTemplates(userID: String) async throws -> [SavedMealWeekTemplate] {
        try checkPlanningOwner(userID)
        return try lock.withLock {
            let values = savedMealWeekTemplatesByUserID[userID] ?? []
            for value in values { try value.validateStoredSnapshot() }
            return values
        }
    }
    public func saveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal) async throws -> SavedMealComposition {
        try checkPlanningOwner(userID)
        let result = try lock.withLock {
            try mockPlanningSave(userID: userID, scope: "compositions", proposal: proposal,
                actual: savedMealCompositionsByUserID[userID]?.first { $0.id == proposal.updated.id }) { saved in
                var values = savedMealCompositionsByUserID[userID] ?? []; values.removeAll { $0.id == saved.id }; values.append(saved)
                savedMealCompositionsByUserID[userID] = values
            }
        }
        if result.1, let planningWorkspaceFailureAfterCommit { throw planningWorkspaceFailureAfterCommit }
        return result.0
    }
    public func saveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal) async throws -> SavedMealWeekTemplate {
        try checkPlanningOwner(userID)
        let result = try lock.withLock {
            try mockPlanningSave(userID: userID, scope: "weekTemplates", proposal: proposal,
                actual: savedMealWeekTemplatesByUserID[userID]?.first { $0.id == proposal.updated.id }) { saved in
                var values = savedMealWeekTemplatesByUserID[userID] ?? []; values.removeAll { $0.id == saved.id }; values.append(saved)
                savedMealWeekTemplatesByUserID[userID] = values
            }
        }
        if result.1, let planningWorkspaceFailureAfterCommit { throw planningWorkspaceFailureAfterCommit }
        return result.0
    }
    public func resolveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution {
        try checkPlanningOwner(userID)
        return try lock.withLock { try mockPlanningResolution(userID: userID, scope: "compositions", proposal: proposal, cancelPending: cancelPending) }
    }
    public func resolveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution {
        try checkPlanningOwner(userID)
        return try lock.withLock { try mockPlanningResolution(userID: userID, scope: "weekTemplates", proposal: proposal, cancelPending: cancelPending) }
    }
    private func checkPlanningOwner(_ userID: String) throws {
        guard !userID.isEmpty, planningWorkspaceAccountID == nil || planningWorkspaceAccountID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        if let planningWorkspaceError { throw planningWorkspaceError }
    }
    private func mockPlanningSave<Value: PlanningWorkspaceDocument>(userID: String, scope: String,
                                                                    proposal: PlanningDocumentProposal<Value>, actual: Value?, write: (Value) -> Void) throws -> (Value, Bool) {
        guard proposal.userID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        let key = "\(userID)|\(scope)|\(proposal.operationID)"
        if let data = planningWorkspaceReceipts[key] {
            let receipt = try JSONDecoder().decode(PlanningWorkspaceReceipt<Value>.self, from: data)
            try receipt.validate(proposal: proposal)
            guard let accepted = receipt.accepted else { throw MealPlanChangeReceiptError.cancelled }
            return (accepted, false)
        }
        let updated = try PlanningDocumentRules.canonicalized(proposal.applying(to: actual))
        let receipt = try PlanningWorkspaceReceipt(proposal: proposal, resolution: .accepted)
        planningWorkspaceReceipts[key] = try JSONEncoder().encode(receipt)
        write(updated)
        return (updated, true)
    }
    private func mockPlanningResolution<Value: PlanningWorkspaceDocument>(userID: String, scope: String,
                                                                          proposal: PlanningDocumentProposal<Value>, cancelPending: Bool) throws -> PlanningDocumentSaveResolution {
        guard proposal.userID == userID else { throw MealPlanChangeReceiptError.accountChanged }
        try proposal.validateEnvelope()
        let key = "\(userID)|\(scope)|\(proposal.operationID)"
        if let data = planningWorkspaceReceipts[key] {
            let receipt = try JSONDecoder().decode(PlanningWorkspaceReceipt<Value>.self, from: data)
            try receipt.validate(proposal: proposal); return receipt.resolution
        }
        guard cancelPending else { return .pending }
        planningWorkspaceReceipts[key] = try JSONEncoder().encode(PlanningWorkspaceReceipt(proposal: proposal, resolution: .cancelled))
        return .cancelled
    }
    public func fetchMealPlanChangeHistory(userID: String, limit: Int) async throws -> [MealPlanChange] {
        guard !userID.isEmpty, (1...500).contains(limit), mealPlanChangeAccountID == nil || mealPlanChangeAccountID == userID else {
            throw MealPlanChangeReceiptError.invalid
        }
        return lock.withLock {
            Array(mealPlanChangeReceipts.values.filter { $0.userID == userID && $0.status == .accepted }
                .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }.compactMap(\.change).prefix(limit))
        }
    }
    public func applyRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation) async throws {
        try checkLibraryOwner(userID)
        let accepted = try lock.withLock { () throws -> Bool in
            let operation = LibraryOperation.recipes(mutation)
            if try mockExistingLibraryResolution(userID: userID, operation: operation) == "accepted" { return false }
            try mockCheckLibraryInverse(userID: userID, operation: operation)
            let current = mockRecipeRecords(userID: userID)
            let changed = try mutation.applying(to: current)
            if recipeSeedOwnerID == nil { recipeSeedOwnerID = userID }
            updateMockRecipeRecords(userID: userID, records: changed)
            try mockAcceptLibrary(userID: userID, operation: operation)
            return true
        }
        if accepted, let libraryMutationFailureAfterCommit { throw libraryMutationFailureAfterCommit }
    }
    public func applySavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation) async throws {
        try checkLibraryOwner(userID)
        let accepted = try lock.withLock { () throws -> Bool in
            let operation = LibraryOperation.foods(mutation)
            if try mockExistingLibraryResolution(userID: userID, operation: operation) == "accepted" { return false }
            try mockCheckLibraryInverse(userID: userID, operation: operation)
            let current = mockFoodRecords(userID: userID)
            let changed = try mutation.applying(to: current)
            if foodSeedOwnerID == nil { foodSeedOwnerID = userID }
            foodLibrariesByUserID[userID] = changed
            if foodSeedOwnerID == userID { customFoodsToReturn = changed }
            try mockAcceptLibrary(userID: userID, operation: operation)
            return true
        }
        if accepted, let libraryMutationFailureAfterCommit { throw libraryMutationFailureAfterCommit }
    }
    public func resolveRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation, cancelPending: Bool) async throws -> RecipeLibraryMutationResolution {
        let raw = try mockResolveLibrary(userID: userID, operation: .recipes(mutation), cancelPending: cancelPending)
        guard let resolution = RecipeLibraryMutationResolution(rawValue: raw) else { throw LibraryMutationError.unavailable }
        return resolution
    }
    public func resolveSavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation, cancelPending: Bool) async throws -> SavedFoodLibraryMutationResolution {
        let raw = try mockResolveLibrary(userID: userID, operation: .foods(mutation), cancelPending: cancelPending)
        guard let resolution = SavedFoodLibraryMutationResolution(rawValue: raw) else { throw LibraryMutationError.unavailable }
        return resolution
    }
    private func mockRecipeRecords(userID: String) -> [Recipe] {
        if recipeSeedOwnerID == userID { return mockRecipes }
        if let scoped = recipeLibrariesByUserID[userID] { return scoped }
        return recipeSeedOwnerID == nil ? mockRecipes : []
    }
    private func updateMockRecipeRecords(userID: String, records: [Recipe]) {
        if recipeSeedOwnerID == nil {
            if recipeLibrariesByUserID[userID] != nil { recipeLibrariesByUserID[userID] = records } else { mockRecipes = records }
        } else {
            recipeLibrariesByUserID[userID] = records
            if recipeSeedOwnerID == userID { mockRecipes = records }
        }
    }
    private func mockFoodRecords(userID: String) -> [FoodItem] {
        if foodSeedOwnerID == userID { return customFoodsToReturn }
        if let scoped = foodLibrariesByUserID[userID] { return scoped }
        return foodSeedOwnerID == nil ? customFoodsToReturn : []
    }
    private func checkLibraryOwner(_ userID: String) throws {
        guard !userID.isEmpty, libraryMutationAccountID == nil || libraryMutationAccountID == userID else { throw LibraryMutationError.accountChanged }
        if let libraryMutationError { throw libraryMutationError }
    }
    private func libraryKey(userID: String, operation: LibraryOperation, id: UUID? = nil) -> String {
        "\(userID)|\(LibraryMutationReceipt.kind(of: operation))|\((id ?? operation.id).uuidString)"
    }
    private func mockExistingLibraryResolution(userID: String, operation: LibraryOperation) throws -> String? {
        try operation.validate()
        guard let receipt = libraryMutationReceipts[libraryKey(userID: userID, operation: operation)] else { return nil }
        try receipt.validate(userID: userID, operation: operation)
        guard receipt.status == "accepted" else { throw LibraryMutationError.cancelled }
        return receipt.status
    }
    private func mockCheckLibraryInverse(userID: String, operation: LibraryOperation) throws {
        guard let originalID = operation.undoingID else { return }
        let key = libraryKey(userID: userID, operation: operation, id: originalID)
        guard let receipt = libraryMutationReceipts[key], receipt.status == "accepted", let original = receipt.operation,
              libraryUndoLocks[key] == nil else { throw LibraryMutationError.changed }
        try LibraryMutationReceipt.validateInverse(operation, original: original)
    }
    private func mockAcceptLibrary(userID: String, operation: LibraryOperation) throws {
        let receipt = try LibraryMutationReceipt(userID: userID, operation: operation, accepted: true)
        libraryMutationReceipts[libraryKey(userID: userID, operation: operation)] = receipt
        if let originalID = operation.undoingID { libraryUndoLocks[libraryKey(userID: userID, operation: operation, id: originalID)] = operation.id }
    }
    private func mockResolveLibrary(userID: String, operation: LibraryOperation, cancelPending: Bool) throws -> String {
        try checkLibraryOwner(userID); try operation.validate()
        return try lock.withLock {
            let key = libraryKey(userID: userID, operation: operation)
            if let receipt = libraryMutationReceipts[key] { try receipt.validate(userID: userID, operation: operation); return receipt.status }
            guard cancelPending else { return "pending" }
            libraryMutationReceipts[key] = try LibraryMutationReceipt(userID: userID, operation: operation, accepted: false)
            return "cancelled"
        }
    }
    public func fetchRecipeLibraryHistory(userID: String, limit: Int) async throws -> [RecipeLibraryMutation] {
        try mockLibraryHistory(userID: userID, limit: limit, kind: "recipes").compactMap { if case .recipes(let value) = $0 { value } else { nil } }
    }
    public func fetchSavedFoodLibraryHistory(userID: String, limit: Int) async throws -> [SavedFoodLibraryMutation] {
        try mockLibraryHistory(userID: userID, limit: limit, kind: "foods").compactMap { if case .foods(let value) = $0 { value } else { nil } }
    }
    private func mockLibraryHistory(userID: String, limit: Int, kind: String) throws -> [LibraryOperation] {
        try checkLibraryOwner(userID)
        guard (1...500).contains(limit) else { throw LibraryMutationError.invalid }
        return try lock.withLock {
            try libraryMutationReceipts.values.filter { $0.userID == userID && $0.kind == kind && $0.status == "accepted" }
                .sorted { $0.recordedAt > $1.recordedAt }.prefix(limit).map {
                    guard let operation = $0.operation else { throw LibraryMutationError.invalid }; return operation
                }
        }
    }
}
#endif
#if DEBUG
extension MockNutritionRepository {
    private func mockCheckCookedBatchChanges(userID: String, change: MealPlanChange) throws {
        let before = Dictionary(grouping: change.before.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        let after = Dictionary(grouping: change.after.flatMap(\.meals).compactMap(\.cookingBatch), by: \.id)
        guard Set(before.keys).union(after.keys).count <= 80 else { throw MealPlanChangeReceiptError.invalid }
        for (id, values) in after {
            guard let proposed = values.first else { continue }
            if activeCookingDefinitionsByUserID[userID]?.contains(id) == true, let expected = before[id]?.first,
               let actual = cookingDefinitionsByUserID[userID]?[id], !MealPlanCookingRules.sameCookingDefinition(expected, actual) {
                throw MealCookingError.changed
            }
            if let operationID = inventorySourceLocks["\(userID)|cook-\(id)"],
               let receipt = inventoryReceipts["\(userID)|\(operationID.uuidString)"] {
                guard let cooked = try receipt.mutation().after.compactMap(\.cookedBatch).first(where: { $0.id == id }),
                      MealPlanCookingRules.sameCookingDefinition(cooked, proposed) else { throw MealCookingError.alreadyCooked }
            }
        }
        for (id, values) in after {
            if let batch = values.first { cookingDefinitionsByUserID[userID, default: [:]][id] = batch }
            activeCookingDefinitionsByUserID[userID, default: []].insert(id)
        }
        for id in Set(before.keys).subtracting(after.keys) { activeCookingDefinitionsByUserID[userID, default: []].remove(id) }
    }
    private func mockCheckReviewedCookingSource(userID: String, mutation: InventoryMutation) throws {
        let batches = mutation.after.compactMap(\.cookedBatch).filter { batch in !mutation.before.contains { $0.cookedBatch?.id == batch.id } }
        guard batches.count == 1, let reviewed = batches.first, mutation.uniqueSourceKey == "cook-" + reviewed.id else { throw InventoryError.invalid }
        if activeCookingDefinitionsByUserID[userID]?.contains(reviewed.id) == true,
           let actual = cookingDefinitionsByUserID[userID]?[reviewed.id], !MealPlanCookingRules.sameCookingDefinition(actual, reviewed) {
            throw MealCookingError.changed
        }
        for batch in mockMealPlansByDateString.values.flatMap(\.meals).compactMap(\.cookingBatch) where batch.id == reviewed.id {
            guard MealPlanCookingRules.sameCookingDefinition(reviewed, batch) else { throw MealCookingError.changed }
        }
    }
}
#endif

#if DEBUG
extension MockNutritionRepository {
    public func fetchInventoryIntakeLink(userID: String, foodID: String) async throws -> InventoryIntakeLink? {
        try lock.withLock {
            guard inventoryAccountID == nil || inventoryAccountID == userID else { throw InventoryError.accountChanged }
            return try mockIntakeLink(userID: userID, foodID: foodID)
        }
    }
    private func mockIntakeLink(userID: String, foodID: String) throws -> InventoryIntakeLink? {
        if let link = inventoryIntakeLinks["\(userID)|\(foodID)"] { try link.validate(); return link }
        var recorded: [(receipt: InventoryReceipt, mutation: InventoryMutation)] = []
        for receipt in inventoryReceipts.values where receipt.userID == userID && receipt.status == .accepted {
            let mutation = try receipt.mutation()
            if mutation.diary?.foodID == foodID { recorded.append((receipt: receipt, mutation: mutation)) }
        }
        recorded.sort { first, second in
            if first.mutation.createdAt != second.mutation.createdAt { return first.mutation.createdAt < second.mutation.createdAt }
            return first.receipt.id.uuidString < second.receipt.id.uuidString
        }
        guard let position = recorded.lastIndex(where: { event in
            event.mutation.reason == .consume && event.mutation.diary?.expected == nil && event.mutation.diary?.desired != nil
        }) else { return nil }
        var link = try InventoryIntakeLink(source: recorded[position].receipt)
        let stockIDs = Set(link.stockIDs)
        let last = recorded[position...].last(where: { Set($0.mutation.before.map(\.id)) == stockIDs }) ?? recorded[position]
        link.currentScale = try InventoryIntakeRules.scale(food: last.mutation.diary?.desired, link: link)
        link.revisionID = last.receipt.id.uuidString
        return link
    }
    private func mockIntakeIndexForStockMutation(userID: String, mutation: InventoryMutation, receipt: InventoryReceipt) throws -> InventoryIntakeLink? {
        guard let patch = mutation.diary else { return nil }
        let existing = try mockIntakeLink(userID: userID, foodID: patch.foodID)
        if mutation.reason == .consume, patch.expected == nil, patch.desired != nil {
            guard existing?.currentScale ?? 0 == 0 else { throw InventoryError.alreadyApplied }
            return try InventoryIntakeLink(source: receipt)
        }
        guard var link = existing else { return nil }
        let beforeScale = try InventoryIntakeRules.scale(food: patch.expected, link: link)
        let afterScale = try InventoryIntakeRules.scale(food: patch.desired, link: link)
        guard abs(link.currentScale - beforeScale) <= 0.000001 else { throw InventoryIntakeError.changed }
        let source = try link.source.mutation()
        if let sourceKey = source.uniqueSourceKey {
            guard inventorySourceLocks["\(userID)|\(sourceKey)"] == nil || inventorySourceLocks["\(userID)|\(sourceKey)"] == source.id else { throw InventoryIntakeError.changed }
        }
        guard mutation.itemIDs == Set(link.stockIDs) else { throw InventoryIntakeError.invalid }
        for original in source.before {
            guard let consumed = source.after.first(where: { $0.id == original.id }),
                  let before = mutation.before.first(where: { $0.id == original.id }), let after = mutation.after.first(where: { $0.id == original.id }),
                  let delta = InventoryQuantityRules.convert((original.quantity - consumed.quantity) * (beforeScale - afterScale), from: original.unit, to: before.unit),
                  abs(after.quantity - before.quantity - delta) <= 0.000001 else { throw InventoryIntakeError.changed }
        }
        link.currentScale = afterScale; link.revisionID = mutation.id.uuidString
        return link
    }
    private func updateMockIntakeSourceLock(_ link: InventoryIntakeLink) throws {
        let source = try link.source.mutation()
        guard let sourceKey = source.uniqueSourceKey else { return }
        let key = "\(link.userID)|\(sourceKey)"
        guard inventorySourceLocks[key] == nil || inventorySourceLocks[key] == source.id else { throw InventoryIntakeError.changed }
        if link.currentScale == 0 { inventorySourceLocks.removeValue(forKey: key) } else { inventorySourceLocks[key] = source.id }
    }
    private func commitMockDiaryAndIntake(userID: String, log: DailyLog) throws -> [PantryItem]? {
        let stock: [PantryItem]? = try lock.withLock {
            guard inventoryAccountID == nil || inventoryAccountID == userID else { throw InventoryError.accountChanged }
            let mutation = try DailyLogMutation(userID: userID, log: log)
            let receiptKey = "\(userID)|\(mutation.id)"
            let fingerprint = try InventoryIntakeRules.intentFingerprint(mutation)
            if let receipt = inventoryIntakeRevisionReceipts[receiptKey] {
                guard receipt.userID == userID, receipt.intentFingerprint == fingerprint else { throw InventoryIntakeError.changed }
                return nil
            }
            if let inventoryFailureBeforeCommit { throw inventoryFailureBeforeCommit }
            let date = Calendar.current.startOfDay(for: log.date)
            let latest = log.id.flatMap { persistedDailyLogsByKey[userID]?[$0] } ?? persistedDailyLogs[userID]?[date] ?? DailyLog(id: log.id, date: log.date, meals: [])
            let merged = try mutation.applying(to: latest, checkingFoodEdits: true)
            let changes = try InventoryIntakeRules.changes(before: latest, after: merged)
            var lots: [UUID: PantryItem] = [:], links: [String: InventoryIntakeLink] = [:], events: [InventoryReceipt] = []
            var loadedStock = false
            var locks = inventorySourceLocks
            for change in changes {
                guard let link = try mockIntakeLink(userID: userID, foodID: change.id) else { continue }
                if !loadedStock { lots = inventoryItems(for: userID); loadedStock = true }
                let source = try link.source.mutation()
                if let sourceKey = source.uniqueSourceKey {
                    guard locks["\(userID)|\(sourceKey)"] == nil || locks["\(userID)|\(sourceKey)"] == source.id else { throw InventoryIntakeError.changed }
                }
                guard let day = DiaryDayContext(userID: userID, date: log.date, dayKey: log.id) else { throw InventoryIntakeError.invalid }
                let name = merged.meals.first { $0.foodItems.contains { $0.id == change.id } }?.name
                    ?? latest.meals.first { $0.foodItems.contains { $0.id == change.id } }?.name ?? "Lunch"
                let projection = try InventoryIntakeRules.projecting(link: link, before: change.before, after: change.after,
                    current: Array(lots.values), day: day, mealName: name, operationID: mutation.id)
                let event = try InventoryReceipt(projection.event, status: .accepted)
                guard inventoryReceipts["\(userID)|\(event.id.uuidString)"] == nil else { throw InventoryIntakeError.changed }
                for item in projection.after { lots[item.id] = item }
                links["\(userID)|\(change.id)"] = projection.link; events.append(event)
                if let sourceKey = source.uniqueSourceKey {
                    if projection.link.currentScale == 0 { locks.removeValue(forKey: "\(userID)|\(sourceKey)") } else { locks["\(userID)|\(sourceKey)"] = source.id }
                }
            }
            persistedDailyLogs[userID, default: [:]][date] = merged.rememberingMutationBase()
            if let key = log.id {
                persistedDailyLogsByKey[userID, default: [:]][key] = merged.rememberingMutationBase()
                inventoryDiaryLogs["\(userID)|\(key)"] = merged.rememberingMutationBase()
            }
            guard !links.isEmpty else { return nil }
            inventoryByOwner[userID] = lots; mockPantryItemsByID = lots
            inventorySourceLocks = locks
            for (key, link) in links { inventoryIntakeLinks[key] = link }
            for event in events { inventoryReceipts["\(userID)|\(event.id.uuidString)"] = event; appliedInventoryIDs.append(event.id) }
            inventoryIntakeRevisionReceipts[receiptKey] = InventoryIntakeRevisionReceipt(id: mutation.id, userID: userID, intentFingerprint: fingerprint, inventoryEventIDs: events.map(\.id))
            return Array(lots.values)
        }
        if stock != nil, let error = inventoryFailureAfterCommit { inventoryFailureAfterCommit = nil; throw error }
        return stock
    }
}
#endif
