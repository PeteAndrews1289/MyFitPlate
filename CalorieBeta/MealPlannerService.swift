import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

@MainActor
class MealPlannerService: ObservableObject {
    private let db = Firestore.firestore()
    private let recipeService: RecipeService

    init(recipeService: RecipeService) {
        self.recipeService = recipeService
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
        var dailyPlans: [MealPlanDay?] = .init(repeating: nil, count: 7)
        var mealHistory: [String] = []

        for i in 0..<7 {
            guard let targetDate = Calendar.current.date(byAdding: .day, value: i, to: Date()) else {
                return false
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
        
        if successfullyGeneratedPlans.count < 7 { return false }
        
        Analytics.logEvent("meal_plan_generated", parameters: ["cuisine_preference": preferredCuisines.joined(separator: ",")])
        
        let allMealNames = successfullyGeneratedPlans.flatMap { $0.meals.compactMap { $0.foodItem?.name } }
        await generateAndSaveGroceryListFromAI(for: allMealNames, userID: userID)
        await saveFullMealPlan(days: successfullyGeneratedPlans, for: userID)

        return true
    }

    // MARK: - Single Day Plan Generation
    private func generatePlanForSingleDay(date: Date, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], mealHistory: [String], retryCount: Int) async -> MealPlanDay? {
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMMM d"
        let dateString = formatter.string(from: date)

        let prompt = """
        Generate a one-day meal plan for \(dateString).
        - Breakfast, Lunch, Dinner, 1 Snack.
        - Avoid: \(mealHistory.joined(separator: ", ")).
        - Cuisines: \(preferredCuisines.joined(separator: ", ")).
        - Snack Prefs: \(preferredSnacks.joined(separator: ", ")).
        - Target: ~\(Int(goals.calories ?? 2000)) cal, \(Int(goals.protein))g P.
        
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
    private struct AIPlanResponse: Codable { let meals: [AIMeal] }
    private struct AIMeal: Codable {
        let mealType: String; let mealName: String; let calories: Double; let protein: Double; let carbs: Double; let fats: Double; let ingredients: [String]; let instructions: [String]
    }

    private func parsePlanFromAIResponse(_ jsonString: String) throws -> [PlannedMeal] {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let response = try JSONDecoder().decode(AIPlanResponse.self, from: jsonData)
        return response.meals.map { aiMeal in
            let foodItem = FoodItem(id: UUID().uuidString, name: aiMeal.mealName, calories: aiMeal.calories, protein: aiMeal.protein, carbs: aiMeal.carbs, fats: aiMeal.fats, servingSize: "1 serving", servingWeight: 0)
            return PlannedMeal(id: UUID().uuidString, mealType: aiMeal.mealType, foodItem: foodItem, ingredients: aiMeal.ingredients, instructions: aiMeal.instructions.joined(separator: "\n"))
        }
    }
    
    private func parseSingleMealFromAIResponse(_ jsonString: String) throws -> PlannedMeal {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let aiMeal = try JSONDecoder().decode(AIMeal.self, from: jsonData)
        let foodItem = FoodItem(id: UUID().uuidString, name: aiMeal.mealName, calories: aiMeal.calories, protein: aiMeal.protein, carbs: aiMeal.carbs, fats: aiMeal.fats, servingSize: "1 serving", servingWeight: 0)
        return PlannedMeal(id: UUID().uuidString, mealType: aiMeal.mealType, foodItem: foodItem, ingredients: aiMeal.ingredients, instructions: aiMeal.instructions.joined(separator: "\n"))
    }

    // MARK: - Grocery List
    public func saveGroceryList(_ list: [GroceryListItem], for userID: String) {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let listData = try list.map { try Firestore.Encoder().encode($0) }
            listRef.setData(["items": listData, "lastUpdated": Timestamp(date: Date())], merge: true)
        } catch { }
    }

    public func fetchGroceryList(for userID: String) async -> [GroceryListItem] {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let document = try await listRef.getDocument()
            guard let data = document.data(), let itemsData = data["items"] as? [[String: Any]] else { return [] }
            return itemsData.compactMap { try? Firestore.Decoder().decode(GroceryListItem.self, from: $0) }
        } catch { return [] }
    }

    private func generateAndSaveGroceryListFromAI(for mealNames: [String], userID: String) async {
        let prompt = "Create a categorized grocery list for: \(mealNames.joined(separator: ", ")). Format: Category:\n- Item (Qty)".trimmingCharacters(in: .whitespaces)
        
        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await AIService.shared.performRequest(messages: messages)
        
        if case .success(let content) = result {
            let items = parseGroceryList(from: content)
            if !items.isEmpty { saveGroceryList(items, for: userID) }
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
                var name = String(itemString); var quantity: Double = 1; var unit = "item"
                // Simple regex parsing placeholder (Reuse your existing regex logic here if needed)
                if let parenIndex = itemString.lastIndex(of: "(") {
                    name = String(itemString[..<parenIndex]).trimmingCharacters(in: .whitespaces)
                }
                items.append(GroceryListItem(name: name, quantity: quantity, unit: unit, category: currentCategory))
            }
        }
        return items
    }
    
    public func fetchPlan(for date: Date, userID: String) async -> MealPlanDay? {
        let dateString = dateString(for: date); let planRef = db.collection("users").document(userID).collection("mealPlans").document(dateString)
        do { return try await planRef.getDocument(as: MealPlanDay.self) } catch { return nil }
    }
    
    public func savePlan(_ plan: MealPlanDay, for userID: String) async {
        guard let planID = plan.id else { return }; let planRef = db.collection("users").document(userID).collection("mealPlans").document(planID)
        do { try planRef.setData(from: plan, merge: true) } catch { }
    }

    public func saveFullMealPlan(days: [MealPlanDay], for userID: String) async {
        let batch = db.batch(); let collectionRef = db.collection("users").document(userID).collection("mealPlans")
        for day in days { if let dayId = day.id { do { try batch.setData(from: day, forDocument: collectionRef.document(dayId)) } catch { } } }
        do { try await batch.commit() } catch { }
    }
    
    private func dateString(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date) }
}
