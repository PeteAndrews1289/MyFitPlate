import Foundation
import FirebaseAnalytics

@MainActor
class MealPlannerService: ObservableObject {
    private let recipeService: RecipeService
    private var planCache: [String: MealPlanDay] = [:]

    init(recipeService: RecipeService) {
        self.recipeService = recipeService
        loadCacheFromDisk()
    }

    private func loadCacheFromDisk() {
        if let data = UserDefaults.standard.data(forKey: "mealPlanCache"),
           let cached = try? JSONDecoder().decode([String: MealPlanDay].self, from: data) {
            self.planCache = cached
        }
    }

    private func saveCacheToDisk() {
        if let data = try? JSONEncoder().encode(planCache) {
            UserDefaults.standard.set(data, forKey: "mealPlanCache")
        }
    }

    // MARK: - Single Meal Regeneration
    public func regenerateSingleMeal(for day: MealPlanDay, mealToReplace: PlannedMeal, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String, retryCount: Int = 1) async -> PlannedMeal? {
        let generator = MealPlanAIGenerator()
        return await generator.regenerateSingleMeal(for: day, mealToReplace: mealToReplace, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, retryCount: retryCount)
    }

    public func generateAndSaveFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String) async -> Bool {
        let generator = MealPlanAIGenerator()
        let generatedPlans = await generator.generateWeekPlan(
            goals: goals,
            preferredFoods: preferredFoods,
            preferredCuisines: preferredCuisines,
            preferredSnacks: preferredSnacks
        )

        guard generatedPlans.count == 7 else { return false }

        Analytics.logEvent("meal_plan_generated", parameters: ["cuisine_count": preferredCuisines.count])

        generateAndSaveGroceryList(from: generatedPlans, userID: userID)
        await saveFullMealPlan(days: generatedPlans, for: userID)

        return true
    }



    // MARK: - Grocery List
    public func saveGroceryList(_ list: [GroceryListItem], for userID: String) {
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.saveGroceryList(userID: userID, items: list)
            } catch {
                AppLog.mealPlanner.error("Failed to encode grocery list: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func fetchGroceryList(for userID: String) async -> [GroceryListItem] {
        do {
            return try await DIContainer.shared.nutritionRepository.fetchGroceryList(userID: userID)
        } catch {
            AppLog.mealPlanner.error("Failed to fetch grocery list: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func refreshGroceryList(for userID: String, starting startDate: Date = Date()) async {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        var days: [MealPlanDay] = []

        for offset in 0..<7 {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfDay),
                  let plan = await fetchPlan(for: date, userID: userID),
                  !plan.meals.isEmpty else {
                continue
            }
            days.append(plan)
        }

        let existingItems = await fetchGroceryList(for: userID)
        let generatedItems = makeGroceryList(from: days)
        let generatedKeys = Set(generatedItems.map { GroceryListBuilder.mergeKey(for: $0.name) })
        let manualItems = existingItems.filter { item in
            isManualGroceryItem(item) && !generatedKeys.contains(GroceryListBuilder.mergeKey(for: item.name))
        }

        let mergedGeneratedItems = generatedItems.map { generatedItem -> GroceryListItem in
            var item = generatedItem
            if let existing = existingItems.first(where: { GroceryListBuilder.mergeKey(for: $0.name) == GroceryListBuilder.mergeKey(for: generatedItem.name) }) {
                item.isCompleted = existing.isCompleted
            }
            return item
        }

        saveGroceryList(mergedGeneratedItems + manualItems, for: userID)
    }

    private func generateAndSaveGroceryList(from days: [MealPlanDay], userID: String) {
        saveGroceryList(makeGroceryList(from: days), for: userID)
    }

    private func makeGroceryList(from days: [MealPlanDay]) -> [GroceryListItem] {
        GroceryListBuilder.makeGroceryList(from: days)
    }

    private func generateAndSaveGroceryListFromAI(for mealNames: [String], userID: String) async {
        let prompt = "Create a categorized grocery list for: \(mealNames.joined(separator: ", ")). Format: Category:\n- Item (Qty)".trimmingCharacters(in: .whitespaces)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await AIService.shared.performRequest(messages: messages)

        if case .success(let content) = result {
            let items = parseGroceryList(from: content)
            if !items.isEmpty { saveGroceryList(items, for: userID) }
        } else if case .failure(let error) = result {
            AppLog.mealPlanner.error("Failed to generate grocery list: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseGroceryList(from text: String) -> [GroceryListItem] {
        // (Keep existing parsing logic unchanged)
        var items: [GroceryListItem] = []
        var currentCategory = "Misc"
        let categories = ["Produce", "Protein", "Pantry", "Dairy & Misc", "Carbohydrates"]

        text.split(whereSeparator: \.isNewline).forEach { line in
            let trimmedLine = String(line).trimmingCharacters(in: .whitespaces)
            if let category = categories.first(where: { trimmedLine.hasPrefix($0 + ":") }) {
                currentCategory = category
                return
            }
            if trimmedLine.hasPrefix("-") {
                let itemString = trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces)
                var name = String(itemString); let quantity: Double = 1; let unit = "item"
                // Simple regex parsing placeholder (Reuse your existing regex logic here if needed)
                if let parenIndex = itemString.lastIndex(of: "(") {
                    name = String(itemString[..<parenIndex]).trimmingCharacters(in: .whitespaces)
                }
                items.append(GroceryListItem(name: name.capitalized, quantity: quantity, unit: unit, category: currentCategory, source: "mealPlan"))
            }
        }
        return items
    }

    private func isManualGroceryItem(_ item: GroceryListItem) -> Bool {
        if item.source == "manual" || item.source == "barcode" { return true }
        if item.source == nil {
            return item.unit.lowercased() == "item" && item.category == "Misc"
        }
        return false
    }

    public func cachedPlan(for date: Date, userID: String) -> MealPlanDay? {
        return planCache[cacheKey(for: date, userID: userID)]
    }

    /// Clears the in-memory + disk plan cache so the next fetch reads fresh from Firestore.
    /// Call after generating or editing a plan, otherwise the view can show a stale (e.g. empty) week.
    public func invalidateCache() {
        planCache.removeAll()
        saveCacheToDisk()
    }

    public func prefetchPlans(starting date: Date, userID: String) async {
        for i in 0..<7 {
            guard let fetchDate = Calendar.current.date(byAdding: .day, value: i, to: date) else { continue }
            _ = await fetchPlan(for: fetchDate, userID: userID)
        }
    }

    public func fetchPlan(for date: Date, userID: String) async -> MealPlanDay? {
        let key = cacheKey(for: date, userID: userID)
        if let cachedPlan = planCache[key] {
            return cachedPlan
        }

        let dateString = dateString(for: date)
        do {
            if let plan = try await DIContainer.shared.nutritionRepository.fetchMealPlan(userID: userID, dateString: dateString) {
                planCache[key] = plan
                saveCacheToDisk()
                return plan
            }
            return nil
        } catch {
            return nil
        }
    }

    public func savePlan(_ plan: MealPlanDay, for userID: String) async {
        guard let planID = plan.id else { return }
        do {
            try await DIContainer.shared.nutritionRepository.saveMealPlan(userID: userID, plan: plan)
            planCache[cacheKey(for: plan.date.dateValue(), userID: userID)] = plan
            saveCacheToDisk()
        } catch {
            AppLog.mealPlanner.error("Failed to save meal plan \(planID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func saveFullMealPlan(days: [MealPlanDay], for userID: String) async {
        do {
            try await DIContainer.shared.nutritionRepository.saveFullMealPlanBatch(userID: userID, plans: days)
            days.forEach { day in
                planCache[cacheKey(for: day.date.dateValue(), userID: userID)] = day
            }
            saveCacheToDisk()
        } catch {
            AppLog.mealPlanner.error("Failed to save full meal plan batch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cacheKey(for date: Date, userID: String) -> String {
        "\(userID)::\(dateString(for: date))"
    }

    private func dateString(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
}
