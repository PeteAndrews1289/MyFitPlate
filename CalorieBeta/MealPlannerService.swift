import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

@MainActor
class MealPlannerService: ObservableObject {
    private let db = Firestore.firestore()
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
        let otherMeals = day.meals.filter { $0.id != mealToReplace.id }
        let otherMealsSummary = otherMeals.compactMap { $0.foodItem?.name }.joined(separator: ", ")

        let prompt = """
        You are regenerating a single meal for a user's meal plan.

        **Details:**
        - Replace: **\(mealToReplace.mealType)**
        - Do NOT suggest: **'\(mealToReplace.foodItem?.name ?? "")'**
        - Current other meals: **\(otherMealsSummary)**
        - Daily Goals: \(Int(goals.calories ?? 2000)) cal, \(Int(goals.protein))g P, \(Int(goals.carbs))g C, \(Int(goals.fats))g F.
        - Prefs: \(preferredFoods.joined(separator: ", ")).
        - Cuisines: \(preferredCuisines.joined(separator: ", ")).

        **Format:** Valid JSON object: "mealType", "mealName", "calories", "protein", "carbs", "fats", "ingredients", "instructions".
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await AIService.shared.performRequest(messages: messages, responseFormat: ["type": "json_object"])

        switch result {
        case .success(let jsonString):
            do {
                return try parseSingleMealFromAIResponse(jsonString)
            } catch {
                if retryCount > 0 {
                    return await regenerateSingleMeal(for: day, mealToReplace: mealToReplace, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, userID: userID, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure:
            return nil
        }
    }

    public func generateAndSaveFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String) async -> Bool {
        let generatedPlans: [MealPlanDay]

        if let fullWeekPlan = await generateFullWeekPlan(
            goals: goals,
            preferredFoods: preferredFoods,
            preferredCuisines: preferredCuisines,
            preferredSnacks: preferredSnacks
        ) {
            generatedPlans = fullWeekPlan
        } else if let legacyPlan = await generateLegacyFullWeekPlan(
            goals: goals,
            preferredFoods: preferredFoods,
            preferredCuisines: preferredCuisines,
            preferredSnacks: preferredSnacks
        ) {
            generatedPlans = legacyPlan
        } else {
            generatedPlans = generateLocalFullWeekPlan(
                goals: goals,
                preferredFoods: preferredFoods,
                preferredCuisines: preferredCuisines,
                preferredSnacks: preferredSnacks
            )
        }

        guard generatedPlans.count == 7 else { return false }

        Analytics.logEvent("meal_plan_generated", parameters: ["cuisine_preference": preferredCuisines.joined(separator: ",")])

        generateAndSaveGroceryList(from: generatedPlans, userID: userID)
        await saveFullMealPlan(days: generatedPlans, for: userID)

        return true
    }

    private func generateFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], retryCount: Int = 1) async -> [MealPlanDay]? {
        let startDate = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d"
        let dateList = (0..<7).compactMap { offset -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            return "dayOffset \(offset): \(dateFormatter.string(from: date))"
        }.joined(separator: "\n")

        let prompt = """
        Generate a complete 7-day meal plan.

        Dates:
        \(dateList)

        Daily targets:
        - Calories: about \(Int(goals.calories ?? 2000))
        - Protein: about \(Int(goals.protein))g
        - Carbs: about \(Int(goals.carbs))g
        - Fats: about \(Int(goals.fats))g

        Preferences:
        - Cooking Style: \(goals.cookingStyle)
        - Preferred foods: \(preferredFoods.isEmpty ? "Flexible" : preferredFoods.joined(separator: ", "))
        - Preferred cuisines: \(preferredCuisines.isEmpty ? "Flexible" : preferredCuisines.joined(separator: ", "))
        - Preferred snacks: \(preferredSnacks.isEmpty ? "Flexible" : preferredSnacks.joined(separator: ", "))

        Rules:
        - Create Breakfast, Lunch, Dinner, and Snack for each day.
        - Adapt recipes to the Cooking Style. If 'Macro-Focused Prep', generate bulk batch-cooking meals using heavy proteins and frozen/bulk vegetables for extreme convenience. If 'Aesthetic Prep', use traditional tupperware-friendly distinct meals. If 'Daily Fresh', vary meals daily.
        - GROCERY FRIENDLY INGREDIENTS (CRITICAL): Never use fractional whole foods or granular amounts (e.g., DO NOT use '0.5 cup pineapple' or '0.25 onion'). Specify ingredients exactly as bought at the store (e.g., '1 bag frozen broccoli', '1 lb chicken breast', '1 medium onion', '1 carton eggs').
        - Avoid repeating the exact same meal name more than twice, though base ingredients can repeat.
        - Instructions should be concise.

        Return valid JSON only:
        {
          "days": [
            {
              "dayOffset": 0,
              "meals": [
                {
                  "mealType": "Breakfast",
                  "mealName": "...",
                  "calories": 500,
                  "protein": 35,
                  "carbs": 50,
                  "fats": 15,
                  "ingredients": ["..."],
                  "instructions": ["..."]
                }
              ]
            }
          ]
        }
        """

        let result = await AIService.shared.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-4o-mini",
            maxTokens: 5000,
            temperature: 0.55,
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let jsonString):
            do {
                let plans = try parseFullWeekPlanFromAIResponse(jsonString, startDate: startDate)
                if plans.count == 7 {
                    return plans
                }
            } catch {
                AppLog.mealPlanner.error("Failed to parse full-week meal plan: \(error.localizedDescription, privacy: .public)")
            }

            if retryCount > 0 {
                return await generateFullWeekPlan(
                    goals: goals,
                    preferredFoods: preferredFoods,
                    preferredCuisines: preferredCuisines,
                    preferredSnacks: preferredSnacks,
                    retryCount: retryCount - 1
                )
            }
            return nil

        case .failure(let error):
            AppLog.mealPlanner.error("Failed to generate full-week meal plan: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func generateLegacyFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String]) async -> [MealPlanDay]? {
        var dailyPlans: [MealPlanDay?] = .init(repeating: nil, count: 7)
        var mealHistory: [String] = []

        for i in 0..<7 {
            guard let targetDate = Calendar.current.date(byAdding: .day, value: i, to: Date()) else {
                return nil
            }

            let singleDayPlan = await generatePlanForSingleDay(
                date: targetDate,
                goals: goals,
                preferredFoods: preferredFoods,
                preferredCuisines: preferredCuisines,
                preferredSnacks: preferredSnacks,
                mealHistory: mealHistory,
                retryCount: 1
            )

            dailyPlans[i] = singleDayPlan
            if let plan = singleDayPlan {
                mealHistory.append(contentsOf: plan.meals.compactMap { $0.foodItem?.name })
            }
        }

        let successfullyGeneratedPlans = dailyPlans.compactMap { $0 }
        return successfullyGeneratedPlans.count == 7 ? successfullyGeneratedPlans : nil
    }

    public func cachedPlan(for date: Date, userID: String) -> MealPlanDay? {
        planCache[cacheKey(for: date, userID: userID)]
    }

    public func prefetchPlans(starting startDate: Date, days: Int = 7, userID: String) async {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            if cachedPlan(for: date, userID: userID) == nil {
                _ = await fetchPlan(for: date, userID: userID)
            }
        }
    }

    // MARK: - Single Day Plan Generation
    private func generatePlanForSingleDay(date: Date, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], mealHistory: [String], retryCount: Int) async -> MealPlanDay? {
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMMM d"
        let dateString = formatter.string(from: date)

        let prompt = """
        Generate a one-day meal plan for \(dateString).
        - Cooking Style: \(goals.cookingStyle)
        - Breakfast, Lunch, Dinner, 1 Snack.
        - Avoid: \(mealHistory.joined(separator: ", ")).
        - Cuisines: \(preferredCuisines.joined(separator: ", ")).
        - Snack Prefs: \(preferredSnacks.joined(separator: ", ")).
        - Target: ~\(Int(goals.calories ?? 2000)) cal, \(Int(goals.protein))g P.

        CRITICAL: Adapt to the Cooking Style (e.g., batch-cooking slop bowls vs daily fresh). Ensure all ingredients are GROCERY FRIENDLY (e.g., '1 bag frozen broccoli', '1 lb beef', NOT '0.5 cup' or '0.25 pepper').

        **Format:** JSON object with root "meals" (array). Each meal: "mealType", "mealName", "calories", "protein", "carbs", "fats", "ingredients" (array), "instructions" (array).
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await AIService.shared.performRequest(messages: messages, responseFormat: ["type": "json_object"])

        switch result {
        case .success(let jsonString):
            do {
                let meals = try parsePlanFromAIResponse(jsonString)
                if meals.count >= 3 {
                    return MealPlanDay(id: self.dateString(for: date), date: Timestamp(date: date), meals: meals)
                } else if retryCount > 0 {
                    return await generatePlanForSingleDay(date: date, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, mealHistory: mealHistory, retryCount: retryCount - 1)
                }
                return nil
            } catch {
                if retryCount > 0 {
                    return await generatePlanForSingleDay(date: date, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, mealHistory: mealHistory, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure:
            return nil
        }
    }

    // MARK: - Parsing Helpers (Keep existing implementations)
    private struct AIWeekPlanResponse: Codable {
        let days: [AIWeekDay]
    }

    private struct AIWeekDay: Codable {
        let dayOffset: Int
        let meals: [AIMeal]
    }

    private struct AIPlanResponse: Codable { let meals: [AIMeal] }
    private struct AIMeal: Codable {
        let mealType: String; let mealName: String; let calories: Double; let protein: Double; let carbs: Double; let fats: Double; let ingredients: [String]; let instructions: [String]
    }

    private func parseFullWeekPlanFromAIResponse(_ jsonString: String, startDate: Date) throws -> [MealPlanDay] {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let response = try JSONDecoder().decode(AIWeekPlanResponse.self, from: jsonData)

        return response.days
            .sorted { $0.dayOffset < $1.dayOffset }
            .compactMap { day in
                guard (0..<7).contains(day.dayOffset),
                      let date = Calendar.current.date(byAdding: .day, value: day.dayOffset, to: startDate) else {
                    return nil
                }

                let meals = day.meals.map(mapAIMealToPlannedMeal)
                guard meals.count >= 3 else { return nil }

                return MealPlanDay(
                    id: dateString(for: date),
                    date: Timestamp(date: date),
                    meals: meals
                )
            }
    }

    private func parsePlanFromAIResponse(_ jsonString: String) throws -> [PlannedMeal] {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let response = try JSONDecoder().decode(AIPlanResponse.self, from: jsonData)
        return response.meals.map(mapAIMealToPlannedMeal)
    }

    private func parseSingleMealFromAIResponse(_ jsonString: String) throws -> PlannedMeal {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let aiMeal = try JSONDecoder().decode(AIMeal.self, from: jsonData)
        return mapAIMealToPlannedMeal(aiMeal)
    }

    private func mapAIMealToPlannedMeal(_ aiMeal: AIMeal) -> PlannedMeal {
        let foodItem = FoodItem(id: UUID().uuidString, name: aiMeal.mealName, calories: aiMeal.calories, protein: aiMeal.protein, carbs: aiMeal.carbs, fats: aiMeal.fats, servingSize: "1 serving", servingWeight: 0)
        return PlannedMeal(id: UUID().uuidString, mealType: aiMeal.mealType, foodItem: foodItem, ingredients: aiMeal.ingredients, instructions: aiMeal.instructions.joined(separator: "\n"))
    }

    private func generateLocalFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String]) -> [MealPlanDay] {
        let startDate = Calendar.current.startOfDay(for: Date())
        let foods = preferredFoods.filter { !$0.localizedCaseInsensitiveContains("Any") }
        let snacks = preferredSnacks.filter { !$0.localizedCaseInsensitiveContains("Any") }
        let cuisines = preferredCuisines.filter { !$0.localizedCaseInsensitiveContains("Any") }

        let proteins = foods.isEmpty ? ["Chicken", "Turkey", "Eggs", "Greek Yogurt"] : foods
        let carbs = foods.isEmpty ? ["Rice", "Potatoes", "Oats", "Wrap"] : foods
        let veggies = foods.isEmpty ? ["Broccoli", "Bell Peppers", "Spinach", "Onions"] : foods
        let snackOptions = snacks.isEmpty ? ["Greek Yogurt", "Fruit", "Protein Shake", "Cottage Cheese"] : snacks

        return (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate) else { return nil }

            let protein = proteins[offset % proteins.count]
            let carb = carbs[(offset + 1) % carbs.count]
            let veggie = veggies[(offset + 2) % veggies.count]
            let snack = snackOptions[offset % snackOptions.count]
            let cuisine = cuisines.isEmpty ? "balanced" : cuisines[offset % cuisines.count].lowercased()
            let calories = goals.calories ?? 2000

            let meals = [
                localMeal(
                    type: "Breakfast",
                    name: "\(snack) Protein Bowl",
                    calories: calories * 0.24,
                    protein: max(goals.protein * 0.25, 25),
                    carbs: goals.carbs * 0.22,
                    fats: goals.fats * 0.20,
                    ingredients: [snack, "Oats or fruit", "Chia seeds"],
                    instructions: "Combine the base, protein, and fruit. Adjust portions to fit the day."
                ),
                localMeal(
                    type: "Lunch",
                    name: "\(protein) \(carb) Bowl",
                    calories: calories * 0.30,
                    protein: max(goals.protein * 0.30, 30),
                    carbs: goals.carbs * 0.32,
                    fats: goals.fats * 0.25,
                    ingredients: [protein, carb, veggie, "\(cuisine.capitalized) seasoning"],
                    instructions: "Cook the protein and carb, add vegetables, and season to taste."
                ),
                localMeal(
                    type: "Dinner",
                    name: "\(protein) and \(veggie) Plate",
                    calories: calories * 0.34,
                    protein: max(goals.protein * 0.32, 32),
                    carbs: goals.carbs * 0.30,
                    fats: goals.fats * 0.38,
                    ingredients: [protein, veggie, carb, "Olive oil or sauce"],
                    instructions: "Build a simple plate around protein, vegetables, and a moderate carb portion."
                ),
                localMeal(
                    type: "Snack",
                    name: "\(snack) Snack",
                    calories: calories * 0.12,
                    protein: max(goals.protein * 0.13, 12),
                    carbs: goals.carbs * 0.16,
                    fats: goals.fats * 0.17,
                    ingredients: [snack],
                    instructions: "Use this as the flexible slot to close protein or calorie gaps."
                )
            ]

            return MealPlanDay(id: dateString(for: date), date: Timestamp(date: date), meals: meals)
        }
    }

    private func localMeal(type: String, name: String, calories: Double, protein: Double, carbs: Double, fats: Double, ingredients: [String], instructions: String) -> PlannedMeal {
        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            servingSize: "1 serving",
            servingWeight: 0
        )
        return PlannedMeal(
            id: UUID().uuidString,
            mealType: type,
            foodItem: foodItem,
            ingredients: ingredients,
            instructions: instructions
        )
    }

    // MARK: - Grocery List
    public func saveGroceryList(_ list: [GroceryListItem], for userID: String) {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let listData = try list.map { try Firestore.Encoder().encode($0) }
            listRef.setData(["items": listData, "lastUpdated": Timestamp(date: Date())], merge: true)
        } catch {
            AppLog.mealPlanner.error("Failed to encode grocery list: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func fetchGroceryList(for userID: String) async -> [GroceryListItem] {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let document = try await listRef.getDocument()
            guard let data = document.data(), let itemsData = data["items"] as? [[String: Any]] else { return [] }
            return itemsData.compactMap { itemData in
                do {
                    return try Firestore.Decoder().decode(GroceryListItem.self, from: itemData)
                } catch {
                    AppLog.mealPlanner.error("Failed to decode grocery list item: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
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
        let generatedKeys = Set(generatedItems.map { groceryMergeKey(for: $0.name) })
        let manualItems = existingItems.filter { item in
            isManualGroceryItem(item) && !generatedKeys.contains(groceryMergeKey(for: item.name))
        }

        let mergedGeneratedItems = generatedItems.map { generatedItem -> GroceryListItem in
            var item = generatedItem
            if let existing = existingItems.first(where: { groceryMergeKey(for: $0.name) == groceryMergeKey(for: generatedItem.name) }) {
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
        let ingredients = days
            .flatMap(\.meals)
            .flatMap { $0.ingredients ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !ingredients.isEmpty else { return [] }

        var grouped: [String: GroceryListItem] = [:]

        for ingredient in ingredients {
            let parsed = parseIngredient(ingredient)
            let key = "\(parsed.name.lowercased())_\(parsed.unit)"
            let category = groceryCategory(for: parsed.name)

            if var existing = grouped[key] {
                existing.quantity += parsed.quantity
                grouped[key] = existing
            } else {
                grouped[key] = GroceryListItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: category,
                    source: "mealPlan"
                )
            }
        }
        
        let rawPreference = UserDefaults.standard.string(forKey: "groceryUnitSystem") ?? "imperial"
        let system = GroceryUnitSystem(rawValue: rawPreference) ?? .imperial
        
        var results = Array(grouped.values)
        for i in 0..<results.count {
            results[i] = applyUnitSystem(results[i], system: system)
        }

        return results.sorted { first, second in
            if first.category == second.category {
                return first.name < second.name
            }
            return first.category < second.category
        }
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
                items.append(GroceryListItem(name: name, quantity: quantity, unit: unit, category: currentCategory, source: "mealPlan"))
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

    private func groceryMergeKey(for name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private struct ParsedIngredient {
        let name: String
        let quantity: Double
        let unit: String
    }
    
    private func parseIngredient(_ raw: String) -> ParsedIngredient {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        let pattern = #"^[\-•\s]*(\d+(?:\.\d+)?(?:/\d+)?)\s*([a-zA-Z]+)?\s*(?:of\s+)?(.*)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return ParsedIngredient(name: text, quantity: 1, unit: "item")
        }
        
        let nsString = text as NSString
        let qtyString = nsString.substring(with: match.range(at: 1))
        
        var unitString = ""
        if match.range(at: 2).location != NSNotFound {
            unitString = nsString.substring(with: match.range(at: 2)).lowercased()
        }
        
        var nameString = ""
        if match.range(at: 3).location != NSNotFound {
            nameString = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        }
        
        var quantity: Double = 1.0
        if qtyString.contains("/") {
            let parts = qtyString.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
                quantity = num / den
            }
        } else if let val = Double(qtyString) {
            quantity = val
        }
        
        switch unitString {
        case "g", "gram", "grams": unitString = "g"
        case "kg", "kilogram", "kilograms": unitString = "kg"
        case "oz", "ounce", "ounces": unitString = "oz"
        case "lb", "lbs", "pound", "pounds": unitString = "lb"
        case "ml", "milliliter", "milliliters": unitString = "ml"
        case "l", "liter", "liters": unitString = "L"
        case "cup", "cups": unitString = "cup"
        case "tbsp", "tablespoon", "tablespoons": unitString = "tbsp"
        case "tsp", "teaspoon", "teaspoons": unitString = "tsp"
        case "slice", "slices": unitString = "slice"
        case "clove", "cloves": unitString = "clove"
        case "can", "cans": unitString = "can"
        case "piece", "pieces": unitString = "piece"
        default:
            if !unitString.isEmpty {
                nameString = "\(unitString) \(nameString)".trimmingCharacters(in: .whitespaces)
            }
            unitString = "item"
        }
        
        if nameString.isEmpty {
            nameString = text
        }
        
        return ParsedIngredient(name: nameString, quantity: quantity, unit: unitString)
    }

    private func applyUnitSystem(_ item: GroceryListItem, system: GroceryUnitSystem) -> GroceryListItem {
        var newItem = item
        
        if system == .imperial {
            if item.unit == "g" {
                let lbs = item.quantity / 453.592
                if lbs >= 1.0 {
                    newItem.quantity = lbs
                    newItem.unit = "lbs"
                } else {
                    newItem.quantity = item.quantity / 28.3495
                    newItem.unit = "oz"
                }
            } else if item.unit == "kg" {
                newItem.quantity = item.quantity * 2.20462
                newItem.unit = "lbs"
            } else if item.unit == "ml" {
                let flOz = item.quantity / 29.5735
                newItem.quantity = flOz
                newItem.unit = "fl oz"
            } else if item.unit == "L" {
                newItem.quantity = item.quantity * 33.814
                newItem.unit = "fl oz"
            }
        } else {
            if item.unit == "oz" {
                newItem.quantity = item.quantity * 28.3495
                newItem.unit = "g"
            } else if item.unit == "lb" || item.unit == "lbs" {
                newItem.quantity = item.quantity * 453.592
                newItem.unit = "g"
            } else if item.unit == "fl oz" {
                newItem.quantity = item.quantity * 29.5735
                newItem.unit = "ml"
            }
            
            if newItem.unit == "g" && newItem.quantity >= 1000 {
                newItem.quantity = newItem.quantity / 1000
                newItem.unit = "kg"
            }
            if newItem.unit == "ml" && newItem.quantity >= 1000 {
                newItem.quantity = newItem.quantity / 1000
                newItem.unit = "L"
            }
        }
        
        return newItem
    }

    private func groceryCategory(for ingredient: String) -> String {
        let lower = ingredient.lowercased()

        if ["chicken", "turkey", "beef", "salmon", "tuna", "fish", "shrimp", "steak", "pork", "lamb", "meat"].contains(where: lower.contains) {
            return "Meat & Seafood"
        }
        
        if ["eggs", "yogurt", "cheese", "milk", "butter", "cream", "sour cream", "cottage"].contains(where: lower.contains) {
            return "Dairy & Eggs"
        }

        if ["broccoli", "pepper", "onion", "spinach", "lettuce", "carrot", "tomato", "fruit", "berries", "banana", "apple", "vegetable", "garlic", "avocado", "lemon", "lime", "potato"].contains(where: lower.contains) {
            return "Produce"
        }

        if ["rice", "oats", "pasta", "bread", "wrap", "tortilla", "quinoa", "beans", "lentils", "bagel", "bun", "flour"].contains(where: lower.contains) {
            return "Carbohydrates"
        }
        
        if ["oil", "sauce", "chia", "nuts", "seeds", "peanut", "almond", "honey", "jam", "sugar", "broth"].contains(where: lower.contains) {
            return "Pantry & Oils"
        }
        
        if ["seasoning", "spice", "cumin", "paprika", "salt", "pepper", "cinnamon", "oregano", "basil", "thyme", "rosemary", "parsley", "cilantro", "ginger"].contains(where: lower.contains) {
            return "Spices & Seasonings"
        }

        return "Misc"
    }

    public func fetchPlan(for date: Date, userID: String) async -> MealPlanDay? {
        let key = cacheKey(for: date, userID: userID)
        if let cachedPlan = planCache[key] {
            return cachedPlan
        }

        let dateString = dateString(for: date)
        let planRef = db.collection("users").document(userID).collection("mealPlans").document(dateString)
        do {
            let plan = try await planRef.getDocument(as: MealPlanDay.self)
            planCache[key] = plan
            saveCacheToDisk()
            return plan
        } catch {
            return nil
        }
    }

    public func savePlan(_ plan: MealPlanDay, for userID: String) async {
        guard let planID = plan.id else { return }; let planRef = db.collection("users").document(userID).collection("mealPlans").document(planID)
        do {
            let data = try Firestore.Encoder().encode(MealPlanPayload(date: plan.date, meals: plan.meals))
            try await planRef.setData(data, merge: true)
            planCache[cacheKey(for: plan.date.dateValue(), userID: userID)] = plan
            saveCacheToDisk()
        } catch {
            AppLog.mealPlanner.error("Failed to save meal plan \(planID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public func saveFullMealPlan(days: [MealPlanDay], for userID: String) async {
        let batch = db.batch(); let collectionRef = db.collection("users").document(userID).collection("mealPlans")
        for day in days {
            if let dayId = day.id {
                do {
                    let data = try Firestore.Encoder().encode(MealPlanPayload(date: day.date, meals: day.meals))
                    batch.setData(data, forDocument: collectionRef.document(dayId), merge: true)
                } catch {
                    AppLog.mealPlanner.error("Failed to encode meal plan day \(dayId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        do {
            try await batch.commit()
            days.forEach { day in
                planCache[cacheKey(for: day.date.dateValue(), userID: userID)] = day
            }
            saveCacheToDisk()
        } catch {
            AppLog.mealPlanner.error("Failed to save full meal plan batch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct MealPlanPayload: Codable {
        let date: Timestamp
        let meals: [PlannedMeal]
    }

    private func cacheKey(for date: Date, userID: String) -> String {
        "\(userID)::\(dateString(for: date))"
    }

    private func dateString(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
}
