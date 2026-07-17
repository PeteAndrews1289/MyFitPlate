import Foundation

public enum MealPlannerServiceError: LocalizedError {
    case groceryListSaveFailed

    public var errorDescription: String? {
        switch self {
        case .groceryListSaveFailed:
            "The grocery list could not be saved."
        }
    }
}

@MainActor
public class MealPlannerService: ObservableObject {
    private let recipeService: RecipeService
    private let userDefaults: UserDefaults
    private var planCache: [String: MealPlanDay] = [:]
    private var loadedCacheUserIDs: Set<String> = []
    private var grocerySaveTasks: [String: Task<Bool, Never>] = [:]
    private let legacyCacheKey = "mealPlanCache"
    private let cacheKeyPrefix = "mealPlanCache"

    public init(
        recipeService: RecipeService,
        userDefaults: UserDefaults = .standard
    ) {
        self.recipeService = recipeService
        self.userDefaults = userDefaults
    }

    private func prepareCache(for userID: String) {
        guard !userID.isEmpty, !loadedCacheUserIDs.contains(userID) else { return }
        migrateLegacyCacheIfNeeded()
        loadedCacheUserIDs.insert(userID)

        guard let storageKey = AccountScopedStorageKey.make(prefix: cacheKeyPrefix, userID: userID),
              let data = userDefaults.data(forKey: storageKey),
              let cached = try? JSONDecoder().decode([String: MealPlanDay].self, from: data) else {
            return
        }
        for (dateKey, plan) in cached {
            planCache[cacheKey(forDateString: dateKey, userID: userID)] = plan
        }
    }

    private func saveCacheToDisk(for userID: String) {
        guard let storageKey = AccountScopedStorageKey.make(prefix: cacheKeyPrefix, userID: userID) else {
            return
        }
        let prefix = "\(userID)::"
        let accountPlans = planCache.reduce(into: [String: MealPlanDay]()) { result, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            result[String(entry.key.dropFirst(prefix.count))] = entry.value
        }

        guard !accountPlans.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(accountPlans) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private func migrateLegacyCacheIfNeeded() {
        guard let data = userDefaults.data(forKey: legacyCacheKey) else { return }
        defer { userDefaults.removeObject(forKey: legacyCacheKey) }
        guard let legacyPlans = try? JSONDecoder().decode([String: MealPlanDay].self, from: data) else {
            return
        }

        var plansByUser: [String: [String: MealPlanDay]] = [:]
        for (key, plan) in legacyPlans {
            guard let separator = key.range(of: "::") else { continue }
            let userID = String(key[..<separator.lowerBound])
            let dateKey = String(key[separator.upperBound...])
            guard !userID.isEmpty, !dateKey.isEmpty else { continue }
            plansByUser[userID, default: [:]][dateKey] = plan
        }

        for (userID, legacyAccountPlans) in plansByUser {
            guard let storageKey = AccountScopedStorageKey.make(prefix: cacheKeyPrefix, userID: userID) else {
                continue
            }
            var mergedPlans = legacyAccountPlans
            if let existingData = userDefaults.data(forKey: storageKey),
               let existingPlans = try? JSONDecoder().decode([String: MealPlanDay].self, from: existingData) {
                mergedPlans.merge(existingPlans) { _, existing in existing }
            }
            if let encoded = try? JSONEncoder().encode(mergedPlans) {
                userDefaults.set(encoded, forKey: storageKey)
            }
        }
    }

    // MARK: - Single Meal Regeneration
    public func regenerateSingleMeal(for day: MealPlanDay, mealToReplace: PlannedMeal, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String, retryCount: Int = 1) async -> PlannedMeal? {
        guard DIContainer.shared.authService.currentUserID == userID else { return nil }
        let generator = MealPlanAIGenerator()
        let regeneratedMeal = await generator.regenerateSingleMeal(for: day, mealToReplace: mealToReplace, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, retryCount: retryCount)
        guard DIContainer.shared.authService.currentUserID == userID else { return nil }
        return regeneratedMeal
    }

    public func generateAndSaveFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String) async -> Bool {
        guard DIContainer.shared.authService.currentUserID == userID else { return false }
        let generator = MealPlanAIGenerator()
        let generatedPlans = await generator.generateWeekPlan(
            goals: goals,
            preferredFoods: preferredFoods,
            preferredCuisines: preferredCuisines,
            preferredSnacks: preferredSnacks
        )

        guard !Task.isCancelled else { return false }
        guard DIContainer.shared.authService.currentUserID == userID else { return false }
        guard generatedPlans.count == 7 else { return false }

        guard await saveFullMealPlan(days: generatedPlans, for: userID) else {
            DIContainer.shared.analyticsManager?.logEvent(
                "meal_plan_generation_failed",
                parameters: ["stage": "save"]
            )
            return false
        }

        guard !Task.isCancelled else { return true }
        guard DIContainer.shared.authService.currentUserID == userID else { return true }
        let planStart = generatedPlans.map(\.date).min() ?? Date()
        _ = await refreshGroceryList(for: userID, starting: planStart)
        DIContainer.shared.analyticsManager?.logEvent(
            "meal_plan_generated",
            parameters: ["cuisine_count": preferredCuisines.count]
        )

        return true
    }

    // MARK: - Grocery List
    public func saveGroceryList(_ list: [GroceryListItem], for userID: String) {
        _ = enqueueGroceryListSave(list, for: userID)
    }

    @discardableResult
    func waitForPendingGrocerySave(for userID: String) async -> Bool {
        guard let task = grocerySaveTasks[userID] else { return true }
        return await task.value
    }

    public func fetchGroceryList(for userID: String) async -> [GroceryListItem] {
        switch await fetchGroceryListResult(for: userID) {
        case .success(let items): return items
        case .failure: return []
        }
    }

    public func fetchGroceryListResult(for userID: String) async -> Result<[GroceryListItem], Error> {
        _ = await waitForPendingGrocerySave(for: userID)
        do {
            return .success(try await DIContainer.shared.nutritionRepository.fetchGroceryList(userID: userID))
        } catch {
            AppLog.mealPlanner.error("Failed to fetch grocery list: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    public func fetchSynchronizedGroceryList(
        for userID: String,
        starting startDate: Date = Date()
    ) async -> [GroceryListItem] {
        switch await fetchSynchronizedGroceryListResult(for: userID, starting: startDate) {
        case .success(let items): return items
        case .failure: return []
        }
    }

    public func fetchSynchronizedGroceryListResult(
        for userID: String,
        starting startDate: Date = Date()
    ) async -> Result<[GroceryListItem], Error> {
        let existingItems: [GroceryListItem]
        switch await fetchGroceryListResult(for: userID) {
        case .success(let items): existingItems = items
        case .failure(let error): return .failure(error)
        }
        guard !existingItems.isEmpty else { return .success([]) }

        let planItems = existingItems.filter { $0.source == "mealPlan" }
        guard !planItems.isEmpty else { return .success(existingItems) }

        let currentStart = Calendar.current.startOfDay(for: startDate)
        let isCurrentWindow = planItems.allSatisfy { item in
            guard let sourcePlanStart = item.sourcePlanStart else { return false }
            return Calendar.current.isDate(sourcePlanStart, inSameDayAs: currentStart)
        }

        if isCurrentWindow {
            return .success(existingItems)
        }
        return await refreshGroceryListResult(
            for: userID,
            starting: currentStart,
            existingItems: existingItems
        )
    }

    @discardableResult
    public func refreshGroceryList(for userID: String, starting startDate: Date = Date()) async -> [GroceryListItem] {
        switch await refreshGroceryListResult(for: userID, starting: startDate) {
        case .success(let items): return items
        case .failure: return []
        }
    }

    public func refreshGroceryListResult(
        for userID: String,
        starting startDate: Date = Date(),
        existingItems suppliedExistingItems: [GroceryListItem]? = nil
    ) async -> Result<[GroceryListItem], Error> {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        var days: [MealPlanDay] = []

        for offset in 0..<7 {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfDay) else {
                continue
            }
            switch await fetchPlanResult(for: date, userID: userID) {
            case .success(let plan):
                if let plan, !plan.meals.isEmpty { days.append(plan) }
            case .failure(let error):
                return .failure(error)
            }
        }

        let existingItems: [GroceryListItem]
        if let suppliedExistingItems {
            existingItems = suppliedExistingItems
        } else {
            switch await fetchGroceryListResult(for: userID) {
            case .success(let items): existingItems = items
            case .failure(let error): return .failure(error)
            }
        }
        let generatedItems = GroceryListBuilder.makeGroceryList(from: days, starting: startOfDay)
        let mergedItems = GroceryListBuilder.mergeGroceryItems(generatedItems: generatedItems, existingItems: existingItems)

        guard await enqueueGroceryListSave(mergedItems, for: userID).value else {
            return .failure(MealPlannerServiceError.groceryListSaveFailed)
        }
        return .success(mergedItems)
    }

    private func generateAndSaveGroceryListFromAI(for mealNames: [String], userID: String) async {
        let prompt = "Create a categorized grocery list for: \(mealNames.joined(separator: ", ")). Format: Category:\n- Item (Qty)".trimmingCharacters(in: .whitespaces)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await DIContainer.shared.aiService.performRequest(messages: messages)

        if case .success(let content) = result {
            let items = GroceryListBuilder.parseGroceryList(from: content)
            if !items.isEmpty { saveGroceryList(items, for: userID) }
        } else if case .failure(let error) = result {
            AppLog.mealPlanner.error("Failed to generate grocery list: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cachedPlan(for date: Date, userID: String) -> MealPlanDay? {
        prepareCache(for: userID)
        return planCache[cacheKey(for: date, userID: userID)]
    }

    /// Clears the in-memory + disk plan cache so the next fetch reads fresh from Firestore.
    /// Call after generating or editing a plan, otherwise the view can show a stale (e.g. empty) week.
    public func invalidateCache(for userID: String) {
        prepareCache(for: userID)
        let prefix = "\(userID)::"
        planCache = planCache.filter { !$0.key.hasPrefix(prefix) }
        saveCacheToDisk(for: userID)
    }

    public func prefetchPlans(starting date: Date, userID: String) async {
        for i in 0..<7 {
            guard let fetchDate = Calendar.current.date(byAdding: .day, value: i, to: date) else { continue }
            _ = await fetchPlan(for: fetchDate, userID: userID)
        }
    }

    public func fetchPlan(for date: Date, userID: String) async -> MealPlanDay? {
        switch await fetchPlanResult(for: date, userID: userID) {
        case .success(let plan): return plan
        case .failure: return nil
        }
    }

    private func fetchPlanResult(for date: Date, userID: String) async -> Result<MealPlanDay?, Error> {
        prepareCache(for: userID)
        let key = cacheKey(for: date, userID: userID)
        if let cachedPlan = planCache[key] {
            return .success(cachedPlan)
        }

        let dateString = dateString(for: date)
        do {
            if let plan = try await DIContainer.shared.nutritionRepository.fetchMealPlan(userID: userID, dateString: dateString) {
                planCache[key] = plan
                saveCacheToDisk(for: userID)
                return .success(plan)
            }
            return .success(nil)
        } catch {
            AppLog.mealPlanner.error("Failed to fetch meal plan: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    @discardableResult
    public func savePlan(_ plan: MealPlanDay, for userID: String) async -> Bool {
        prepareCache(for: userID)
        let planID = plan.id
        do {
            try await DIContainer.shared.nutritionRepository.saveMealPlan(userID: userID, plan: plan)
            planCache[cacheKey(for: plan.date, userID: userID)] = plan
            saveCacheToDisk(for: userID)
            notifyMealPlanChanged(for: userID)
            return true
        } catch {
            AppLog.mealPlanner.error("Failed to save meal plan \(planID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func saveFullMealPlan(days: [MealPlanDay], for userID: String) async -> Bool {
        prepareCache(for: userID)
        do {
            try await DIContainer.shared.nutritionRepository.saveFullMealPlanBatch(userID: userID, plans: days)
            days.forEach { day in
                planCache[cacheKey(for: day.date, userID: userID)] = day
            }
            saveCacheToDisk(for: userID)
            notifyMealPlanChanged(for: userID)
            return true
        } catch {
            AppLog.mealPlanner.error("Failed to save full meal plan batch: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func discardMealPlan(starting startDate: Date = Date(), for userID: String) async -> Bool {
        guard !userID.isEmpty else { return false }
        prepareCache(for: userID)

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let dates = (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: startOfDay)
        }
        let dateStrings = dates.map(dateString(for:))

        do {
            let groceryItems = try await DIContainer.shared.nutritionRepository.fetchGroceryList(userID: userID)
            let retainedItems = groceryItems.filter { $0.source != "mealPlan" }

            try await DIContainer.shared.nutritionRepository.discardMealPlans(
                userID: userID,
                dateStrings: dateStrings,
                retainingGroceryItems: retainedItems
            )

            dates.forEach { date in
                planCache.removeValue(forKey: cacheKey(for: date, userID: userID))
            }
            saveCacheToDisk(for: userID)
            notifyMealPlanChanged(for: userID)
            DIContainer.shared.analyticsManager?.logEvent(
                "meal_plan_discarded",
                parameters: ["day_count": dateStrings.count]
            )
            return true
        } catch {
            AppLog.mealPlanner.error("Failed to discard meal plan: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func cacheKey(for date: Date, userID: String) -> String {
        cacheKey(forDateString: dateString(for: date), userID: userID)
    }

    private func cacheKey(forDateString dateString: String, userID: String) -> String {
        "\(userID)::\(dateString)"
    }

    private func notifyMealPlanChanged(for userID: String) {
        NotificationCenter.default.post(name: .mealPlanChanged, object: userID)
    }

    private func enqueueGroceryListSave(
        _ list: [GroceryListItem],
        for userID: String
    ) -> Task<Bool, Never> {
        guard let repository = DIContainer.shared.nutritionRepository else {
            return Task { false }
        }
        let previousTask = grocerySaveTasks[userID]
        let task = Task {
            if let previousTask {
                _ = await previousTask.value
            }
            do {
                try await repository.saveGroceryList(userID: userID, items: list)
                return true
            } catch {
                AppLog.mealPlanner.error(
                    "Failed to save grocery list: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
        grocerySaveTasks[userID] = task
        return task
    }

    private func dateString(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
}
