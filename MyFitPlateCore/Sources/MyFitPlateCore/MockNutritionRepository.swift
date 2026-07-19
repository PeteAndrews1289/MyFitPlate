#if DEBUG
import Foundation
import Combine

public final class MockNutritionRepository: NutritionRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public init() {}
    
    // Properties for testing
    public var lastUpdatedLog: DailyLog?
    public var savedDailyLogs: [DailyLog] = []
    public var savedDailyLogUserIDs: [String] = []
    public var saveDailyLogError: Error?
    public var updateLogSuccess: Bool = true
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
        if shouldDeferDailyLogUpdateCompletions {
            deferredDailyLogUpdateCompletions.append(completion)
        } else {
            completion(updateLogSuccess)
        }
    }
    public func saveDailyLog(userID: String, log: DailyLog) async throws {
        if let saveDailyLogError { throw saveDailyLogError }
        lastUpdatedLog = log
        savedDailyLogs.append(log)
        savedDailyLogUserIDs.append(userID)
    }
    public func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        if let result = mockFetchLogResult {
            completion(result)
        } else if let log = mockLogsByDay.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            completion(.success(log))
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            completion(.success(emptyLog))
        }
    }
    public func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any { 
        logSnapshotListenerUserIDs.append(userID)
        logSnapshotCallbacks[userID] = onChange
        if shouldDeferLogSnapshotCallbacks {
            return UUID()
        } else if let result = mockFetchLogResult {
            onChange(result)
        } else if let log = mockLogsByDay.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            onChange(.success(log))
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            onChange(.success(emptyLog))
        }
        return UUID() 
    }
    public func removeLogSnapshotListener(_ handle: Any) {}
    public func emitLogSnapshot(_ result: Result<DailyLog, Error>, for userID: String) {
        logSnapshotCallbacks[userID]?(result)
    }
    public func completeDeferredDailyLogUpdates(success: Bool? = nil) {
        let completions = deferredDailyLogUpdateCompletions
        deferredDailyLogUpdateCompletions = []
        completions.forEach { $0(success ?? updateLogSuccess) }
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
            let logs = try mock.get()
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
    public var batchSavedMealPlans: [MealPlanDay] = []
    public var discardedMealPlanDateStrings: [String] = []
    public var discardedMealPlanUserIDs: [String] = []
    public var mealPlanError: Error?
    
    public func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? { 
        if let mealPlanError { throw mealPlanError }
        return mockMealPlansByDateString[dateString] ?? mockFetchMealPlanResult
    }
    public func saveMealPlan(userID: String, plan: MealPlanDay) async throws {
        if let mealPlanError { throw mealPlanError }
        savedMealPlans.append(plan)
    }
    public func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        if let mealPlanError { throw mealPlanError }
        batchSavedMealPlans.append(contentsOf: plans)
    }
    public func discardMealPlans(
        userID: String,
        dateStrings: [String],
        retainingGroceryItems: [GroceryListItem]
    ) async throws {
        if let mealPlanError { throw mealPlanError }
        discardedMealPlanUserIDs.append(userID)
        discardedMealPlanDateStrings = dateStrings
        dateStrings.forEach { mockMealPlansByDateString.removeValue(forKey: $0) }
        savedGroceryLists = retainingGroceryItems
        mockFetchGroceryListResult = retainingGroceryItems
    }
    public func fetchGroceryList(userID: String) async throws -> [GroceryListItem] { 
        if let groceryListError { throw groceryListError }
        return mockFetchGroceryListResult 
    }
    public func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {
        if grocerySaveDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: grocerySaveDelayNanoseconds)
        }
        grocerySaveSnapshots.append(items)
        savedGroceryLists = items
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
        if let pantryItemError { throw pantryItemError }
        savedPantryUserIDs.append(userID)
        savedPantryItems.append(item)
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
    
    public func fetchRecipes(userID: String) async throws -> [Recipe] { return mockRecipes }
    public func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe { 
        savedRecipes.append(recipe)
        return recipe 
    }
    public func deleteRecipe(userID: String, recipeID: String) async throws {
        deletedRecipeIDs.append(recipeID)
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
        savedCustomFoods.append(foodItem)
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
        return customFoodsToReturn
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
