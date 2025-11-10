import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class MealPlannerService: ObservableObject {
    private let db = Firestore.firestore()
    private let apiKey = getAPIKey()
    private let recipeService: RecipeService

    init(recipeService: RecipeService) {
        self.recipeService = recipeService
    }


    public func regenerateSingleMeal(for day: MealPlanDay, mealToReplace: PlannedMeal, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String) async -> PlannedMeal? {
        let otherMeals = day.meals.filter { $0.id != mealToReplace.id }
        let otherMealsSummary = otherMeals.compactMap { $0.foodItem?.name }.joined(separator: ", ")

        let prompt = """
        You are regenerating a single meal for a user's meal plan.

        **Meal Type Guidance:**
        - If the meal is **Breakfast**, suggest traditional breakfast items (e.g., oatmeal, eggs, yogurt, smoothies).
        - If the meal is **Lunch**, suggest items like salads, sandwiches, or wraps.
        - If the meal is **Dinner**, suggest a complete, cooked meal.

        **Regeneration Details:**
        - The meal to replace is: **\(mealToReplace.mealType)**
        - Do NOT suggest this meal again: **'\(mealToReplace.foodItem?.name ?? "")'**
        - The user is already eating: **\(otherMealsSummary)** for their other meals today.
        - The user's total daily goals are: \(Int(goals.calories ?? 2000)) calories, \(Int(goals.protein))g Protein, \(Int(goals.carbs))g Carbs, and \(Int(goals.fats))g Fats.
        - The new \(mealToReplace.mealType) should fit nutritionally with the other meals to help the user meet their daily goals.
        - Use these preferred foods: \(preferredFoods.joined(separator: ", ")).
        - Use these preferred cuisines: \(preferredCuisines.joined(separator: ", ")).
        - The response MUST be a valid JSON object for a single meal with keys: "mealType", "mealName", "calories", "protein", "carbs", "fats", "ingredients", "instructions".
        """
        
        guard let aiResponse = await fetchAIResponse(prompt: prompt) else { return nil }
        
        do {
            let meal = try parseSingleMealFromAIResponse(aiResponse)
            return meal
        } catch {
            print("MealPlannerService Debug: JSON Parsing failed for single meal regeneration. Error: \(error)")
            return nil
        }
    }

    public func generateAndSaveFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], userID: String) async -> Bool {
        var dailyPlans: [MealPlanDay?] = .init(repeating: nil, count: 7)
        var mealHistory: [String] = []

        await withTaskGroup(of: (Int, MealPlanDay?).self) { group in
            for i in 0..<7 {
                group.addTask {
                    let targetDate = Calendar.current.date(byAdding: .day, value: i, to: Date())!
                    let singleDayPlan = await self.generatePlanForSingleDay(
                        date: targetDate,
                        goals: goals,
                        preferredFoods: preferredFoods,
                        preferredCuisines: preferredCuisines,
                        preferredSnacks: preferredSnacks,
                        mealHistory: mealHistory
                    )
                    if let plan = singleDayPlan {
                        mealHistory.append(contentsOf: plan.meals.compactMap { $0.foodItem?.name })
                    }
                    return (i, singleDayPlan)
                }
            }
            
            for await (index, plan) in group {
                dailyPlans[index] = plan
            }
        }

        let successfullyGeneratedPlans = dailyPlans.compactMap { $0 }
        
        if successfullyGeneratedPlans.count < 7 {
            return false
        }
        
        let allMealNames = successfullyGeneratedPlans.flatMap { $0.meals.compactMap { $0.foodItem?.name } }
        await generateAndSaveGroceryListFromAI(for: allMealNames, userID: userID)
        
        await saveFullMealPlan(days: successfullyGeneratedPlans, for: userID)

        return true
    }

    private func generatePlanForSingleDay(date: Date, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], mealHistory: [String]) async -> MealPlanDay? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        let dateString = formatter.string(from: date)

        var historyPromptSection = ""
        if !mealHistory.isEmpty {
            let mealList = mealHistory.joined(separator: ", ")
            historyPromptSection = "**Variety Requirement:** To ensure variety, create meals that are different from these: \(mealList)."
        }
        
        var cuisinePromptSection = ""
        if !preferredCuisines.isEmpty && !preferredCuisines.contains("Any / No Preference") {
            cuisinePromptSection = "**Cuisine Influence:** Draw inspiration from: \(preferredCuisines.joined(separator: ", "))."
        }
        
        var snackPromptSection = ""
        if !preferredSnacks.isEmpty {
            snackPromptSection = "**Snack Preference:** Include one snack that aligns with preferences for \(preferredSnacks.joined(separator: ", "))."
        }

        let prompt = """
        Generate a one-day meal plan for \(dateString) with a Breakfast, Lunch, Dinner, and one Snack.
        
        **Meal Type Guidance:**
        - For **Breakfast**, suggest traditional breakfast items (e.g., oatmeal, eggs, yogurt, smoothies, whole-wheat toast). Avoid savory lunch/dinner meals like chicken and rice.
        - For **Lunch**, suggest items like salads, sandwiches, wraps, or light grain bowls.
        - For **Dinner**, suggest a complete, cooked meal that would typically be considered a main evening meal.
        - For the **Snack**, suggest something light like fruit, nuts, or a protein bar, depending on the user's preferences.

        \(historyPromptSection)
        \(cuisinePromptSection)
        \(snackPromptSection)
        **Primary Goal:** Total nutrition must be approximately \(Int(goals.calories ?? 2000)) calories, \(Int(goals.protein))g Protein, \(Int(goals.carbs))g Carbs, and \(Int(goals.fats))g Fats.
        **Allowed Ingredients:** Use primarily: \(preferredFoods.joined(separator: ", ")). Common pantry items are also allowed.
        
        **Response Format:** You MUST respond with a valid JSON object ONLY.
        The root object must have a "meals" key, which is an array of meal objects.
        Each meal object must have these exact keys: "mealType" (string), "mealName" (string), "calories" (number), "protein" (number), "carbs" (number), "fats" (number), "ingredients" (array of strings), "instructions" (array of strings).
        The "mealType" must be one of "Breakfast", "Lunch", "Dinner", or "Snack".
        """
        
        guard let aiResponse = await fetchAIResponse(prompt: prompt) else { return nil }
        
        do {
            let meals = try parsePlanFromAIResponse(aiResponse)
            if meals.count >= 3 {
                return MealPlanDay(id: self.dateString(for: date), date: Timestamp(date: date), meals: meals)
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    private struct AIPlanResponse: Codable {
        let meals: [AIMeal]
    }
    
    private struct AIMeal: Codable {
        let mealType: String
        let mealName: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fats: Double
        let ingredients: [String]
        let instructions: [String]
    }

    private func parsePlanFromAIResponse(_ jsonString: String) throws -> [PlannedMeal] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "MealPlannerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }
        
        let response = try JSONDecoder().decode(AIPlanResponse.self, from: jsonData)
        
        return response.meals.map { aiMeal in
            let foodItem = FoodItem(id: UUID().uuidString, name: aiMeal.mealName, calories: aiMeal.calories, protein: aiMeal.protein, carbs: aiMeal.carbs, fats: aiMeal.fats, servingSize: "1 serving", servingWeight: 0)
            return PlannedMeal(id: UUID().uuidString, mealType: aiMeal.mealType, foodItem: foodItem, ingredients: aiMeal.ingredients, instructions: aiMeal.instructions.joined(separator: "\n"))
        }
    }
    
    private func parseSingleMealFromAIResponse(_ jsonString: String) throws -> PlannedMeal {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "MealPlannerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }

        let aiMeal = try JSONDecoder().decode(AIMeal.self, from: jsonData)

        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: aiMeal.mealName,
            calories: aiMeal.calories,
            protein: aiMeal.protein,
            carbs: aiMeal.carbs,
            fats: aiMeal.fats,
            servingSize: "1 serving",
            servingWeight: 0
        )
        return PlannedMeal(
            id: UUID().uuidString,
            mealType: aiMeal.mealType,
            foodItem: foodItem,
            ingredients: aiMeal.ingredients,
            instructions: aiMeal.instructions.joined(separator: "\n")
        )
    }

    private func fetchAIResponse(prompt: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [ "model": "gpt-4o-mini", "messages": [["role": "user", "content": prompt]], "max_tokens": 2048, "temperature": 0.7, "response_format": ["type": "json_object"] ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch { }
        return nil
    }

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
        } catch {
            return []
        }
    }

    private func generateAndSaveGroceryListFromAI(for mealNames: [String], userID: String) async {
        let mealsString = mealNames.joined(separator: ", ")
        
        let prompt = """
        Based on the following list of meals, create a practical, categorized grocery list for one person for a week. Consolidate all ingredients and use standard purchasing units (e.g., '1 lb chicken breast', '2 bell peppers', '1 head of garlic' instead of '1.5 cups diced peppers').

        The meals are: \(mealsString)

        Respond in this exact format, with no other text:
        Produce:
        - [Item Name] ([Approximate Quantity])
        Protein:
        - [Item Name] ([Approximate Quantity])
        Pantry:
        - [Item Name] ([Approximate Quantity])
        Dairy & Misc:
        - [Item Name] ([Approximate Quantity])
        """
        
        guard let aiResponse = await fetchAIResponse(prompt: prompt) else {
            return
        }
        
        let groceryListItems = parseGroceryList(from: aiResponse)
        
        if !groceryListItems.isEmpty {
            saveGroceryList(groceryListItems, for: userID)
        }
    }

    private func parseGroceryList(from text: String) -> [GroceryListItem] {
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
                
                var name = String(itemString)
                var quantity: Double = 1
                var unit = "item"
                
                let pattern = #"^(.+?)\s*\(([\d\.]+)\s*(.*?)\)$"#
                if let _ = itemString.range(of: pattern, options: .regularExpression) {
                    let parts = itemString.capturedGroups(with: pattern)
                    if parts.count == 3 {
                        name = parts[0].trimmingCharacters(in: .whitespaces)
                        quantity = Double(parts[1]) ?? 1.0
                        unit = parts[2].trimmingCharacters(in: .whitespaces)
                    }
                } else if let _ = itemString.range(of: #"^(.+?)\s*\((.*?)\)$"#, options: .regularExpression) {
                    let parts = itemString.capturedGroups(with: #"^(.+?)\s*\((.*?)\)$"#)
                    if parts.count == 2 {
                        name = parts[0].trimmingCharacters(in: .whitespaces)
                        unit = parts[1].trimmingCharacters(in: .whitespaces)
                        quantity = 1
                    }
                } else {
                    name = String(itemString)
                    quantity = 1
                    unit = "item"
                }
                
                if !name.isEmpty {
                    items.append(GroceryListItem(name: name, quantity: quantity, unit: unit, category: currentCategory))
                }
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

extension String {
    func capturedGroups(with pattern: String) -> [String] {
        var results: [String] = []
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }
        let matches = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
        guard let match = matches.first else { return results }
        for i in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: i), in: self) {
                results.append(String(self[range]))
            }
        }
        return results
    }
}
