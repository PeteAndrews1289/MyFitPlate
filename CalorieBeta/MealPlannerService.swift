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

    public func generateAndSaveFullWeekPlan(goals: GoalSettings, preferredFoods: [String], userID: String) async -> Bool {
        var allDayPlans: [MealPlanDay] = []
        var mealHistory: [String] = []

        for i in 0..<7 {
            let targetDate = Calendar.current.date(byAdding: .day, value: i, to: Date())!
            print("MealPlannerService Debug: Generating plan for Day \(i + 1)...")
            
            guard let singleDayPlan = await generatePlanForSingleDay(
                date: targetDate,
                goals: goals,
                preferredFoods: preferredFoods,
                mealHistory: mealHistory
            ) else {
                print("MealPlannerService Debug: Failed to generate or parse plan for Day \(i + 1). Aborting week generation.")
                return false
            }
            
            for meal in singleDayPlan.meals {
                if let mealName = meal.foodItem?.name {
                    mealHistory.append(mealName)
                }
            }
            
            allDayPlans.append(singleDayPlan)
        }
        
        if allDayPlans.count < 7 {
            print("MealPlannerService Debug: Failed to generate all 7 days. Only created \(allDayPlans.count).")
            return false
        }

        print("MealPlannerService Debug: Successfully generated all 7 day plans. Saving to Firestore.")
        await saveFullMealPlan(days: allDayPlans, for: userID)
        await generateAndSaveGroceryListFromAI(for: mealHistory, userID: userID)

        return true
    }

    private func generatePlanForSingleDay(date: Date, goals: GoalSettings, preferredFoods: [String], mealHistory: [String]) async -> MealPlanDay? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        let dateString = formatter.string(from: date)

        var historyPromptSection = ""
        if !mealHistory.isEmpty {
            let mealList = mealHistory.joined(separator: ", ")
            historyPromptSection = """
            **Variety Requirement:** To ensure variety, please create meals that are different from the ones already generated for previous days. It is acceptable for a meal to be repeated once or twice over the entire week, but avoid daily repetition. Here are the meals generated so far: \(mealList)
            """
        }

        let prompt = """
        Generate a one-day meal plan for \(dateString) with a Breakfast, Lunch, and Dinner.
        \(historyPromptSection)
        **Primary Goal:** The total nutrition for the day must add up to approximately \(Int(goals.calories ?? 2000)) calories, \(Int(goals.protein))g Protein, \(Int(goals.carbs))g Carbs, and \(Int(goals.fats))g Fats.
        **Allowed Ingredients:** Create meals primarily using this list: \(preferredFoods.joined(separator: ", ")). Common pantry items are also allowed.
        
        **Response Format:** You MUST follow this format exactly. Do NOT add any conversational text or day numbers.
        **Ingredient Format:** Every ingredient line MUST be in the format: '- [Ingredient Name] - [Quantity] [Unit]'.
        **Instruction Format:** Provide clear, step-by-step cooking instructions. Include details like cooking temperatures, times, and methods (e.g., "bake at 400°F for 20 minutes," "sauté until browned").

        Breakfast: [Meal Name]
        Ingredients:
        - [Ingredient Name] - [Quantity] [Unit]
        Instructions:
        1. Preheat oven to 400°F (200°C).
        2. Season the main protein with salt and pepper.
        3. Bake for 20-25 minutes, or until cooked through.
        4. While the main dish is baking, steam the vegetables until tender-crisp.

        Lunch: [Meal Name]
        Ingredients:
        - [Ingredient Name] - [Quantity] [Unit]
        Instructions:
        1. [Detailed Step-by-Step Instructions]

        Dinner: [Meal Name]
        Ingredients:
        - [Ingredient Name] - [Quantity] [Unit]
        Instructions:
        1. [Detailed Step-by-Step Instructions]
        """
        
        guard let aiResponse = await fetchAIResponse(prompt: prompt) else { return nil }
        print("MealPlannerService Debug: AI Response for \(dateString):\n\(aiResponse)")
        
        let meals = parseSingleDayPlan(from: aiResponse)
        
        if meals.count == 3 {
            return MealPlanDay(id: self.dateString(for: date), date: Timestamp(date: date), meals: meals)
        } else {
            print("MealPlannerService Debug: Parsing failed for \(dateString). Found \(meals.count) meals instead of 3.")
            return nil
        }
    }
    
    private func parseSingleDayPlan(from text: String) -> [PlannedMeal] {
        var parsedMeals: [PlannedMeal] = []
        let mealTypes = ["Breakfast", "Lunch", "Dinner"]
        var lastMealEndIndex = text.startIndex

        for i in 0..<mealTypes.count {
            let currentMealType = mealTypes[i]
            
            guard let mealStartRange = text.range(of: "\(currentMealType):", options: .caseInsensitive, range: lastMealEndIndex..<text.endIndex) else {
                continue
            }
            
            let startOfMealContent = mealStartRange.upperBound
            var endOfMealContent = text.endIndex
            
            if (i + 1) < mealTypes.count {
                let nextMealType = mealTypes[i+1]
                if let nextMealStartRange = text.range(of: "\(nextMealType):", options: .caseInsensitive, range: startOfMealContent..<text.endIndex) {
                    endOfMealContent = nextMealStartRange.lowerBound
                }
            }
            
            lastMealEndIndex = endOfMealContent
            let mealBlock = String(text[startOfMealContent..<endOfMealContent]).trimmingCharacters(in: .whitespacesAndNewlines)
            let mealLines = mealBlock.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            
            let ingredientsIndex = mealLines.firstIndex(where: { $0.lowercased() == "ingredients:" })
            let instructionsIndex = mealLines.firstIndex(where: { $0.lowercased() == "instructions:" })
            
            let nameLines = mealLines[..<(ingredientsIndex ?? mealLines.endIndex)]
            let mealName = nameLines.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            
            var ingredients: [String] = []
            if let ingredientsIndex = ingredientsIndex {
                let ingredientsEndIndex = instructionsIndex ?? mealLines.endIndex
                let ingredientsStart = mealLines.index(after: ingredientsIndex)
                if ingredientsStart < ingredientsEndIndex {
                    ingredients = Array(mealLines[ingredientsStart..<ingredientsEndIndex]).filter { $0.hasPrefix("-") }
                }
            }

            var instructions = ""
            if let instructionsIndex = instructionsIndex {
                let instructionsStart = mealLines.index(after: instructionsIndex)
                if instructionsStart < mealLines.endIndex {
                    instructions = mealLines[instructionsStart...].joined(separator: "\n")
                }
            }

            if mealName.isEmpty { continue }
            
            print("MealPlannerService Debug: Day \(i + 1) - \(currentMealType): \(mealName)")
            
            let foodItem = FoodItem(id: UUID().uuidString, name: mealName, calories: 0, protein: 0, carbs: 0, fats: 0, servingSize: "1 serving", servingWeight: 0)
            let meal = PlannedMeal(id: UUID().uuidString, mealType: currentMealType, foodItem: foodItem, ingredients: ingredients, instructions: instructions)
            parsedMeals.append(meal)
        }
        return parsedMeals
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [ "model": "gpt-3.5-turbo", "messages": [["role": "user", "content": prompt]], "max_tokens": 1500, "temperature": 0.7 ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("MealPlannerService Debug: API call failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                if let data = try? JSONSerialization.jsonObject(with: data) { print("MealPlannerService Debug: API Error Response: \(data)") }
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("MealPlannerService Debug: URLSession error: \(error.localizedDescription)")
        }
        return nil
    }

    public func saveGroceryList(_ list: [GroceryListItem], for userID: String) {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let listData = try list.map { try Firestore.Encoder().encode($0) }
            listRef.setData(["items": listData, "lastUpdated": Timestamp(date: Date())], merge: true)
        } catch { print("Error saving grocery list: \(error)") }
    }

    public func fetchGroceryList(for userID: String) async -> [GroceryListItem] {
        let listRef = db.collection("users").document(userID).collection("userSettings").document("groceryList")
        do {
            let document = try await listRef.getDocument()
            guard let data = document.data(), let itemsData = data["items"] as? [[String: Any]] else { return [] }
            return itemsData.compactMap { try? Firestore.Decoder().decode(GroceryListItem.self, from: $0) }
        } catch {
            print("Error fetching grocery list: \(error)")
            return []
        }
    }

    private func generateAndSaveGroceryListFromAI(for mealNames: [String], userID: String) async {
        print("MealPlannerService Debug: Generating grocery list from AI based on meal names.")
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
            print("MealPlannerService Debug: Failed to get AI response for grocery list.")
            return
        }
        
        let groceryListItems = parseGroceryList(from: aiResponse)
        
        if !groceryListItems.isEmpty {
            print("MealPlannerService Debug: Successfully parsed \(groceryListItems.count) items for grocery list.")
            saveGroceryList(groceryListItems, for: userID)
        } else {
            print("MealPlannerService Debug: Failed to parse any items from AI grocery list response.")
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
                
                // Regex to find patterns like "Item Name (Quantity Unit)"
                let pattern = #"^(.+?)\s*\(([\d\.]+)\s*(.*?)\)$"#
                if let match = itemString.range(of: pattern, options: .regularExpression) {
                    let parts = itemString.capturedGroups(with: pattern)
                    if parts.count == 3 {
                        name = parts[0].trimmingCharacters(in: .whitespaces)
                        quantity = Double(parts[1]) ?? 1.0
                        unit = parts[2].trimmingCharacters(in: .whitespaces)
                    }
                } else if let fallbackMatch = itemString.range(of: #"^(.+?)\s*\((.*?)\)$"#, options: .regularExpression) {
                    // Fallback for patterns like "Item Name (a few)"
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
    
    private func categorizeIngredient(_ name: String) -> String {
        let lowercasedName = name.lowercased()
        if ["chicken", "beef", "fish", "tofu", "eggs", "pork", "lamb", "turkey", "salmon", "shrimp"].contains(where: lowercasedName.contains) { return "Protein" }
        if ["rice", "quinoa", "potato", "pasta", "bread", "oats", "tortilla"].contains(where: lowercasedName.contains) { return "Carbohydrates" }
        if ["broccoli", "spinach", "peppers", "onions", "carrots", "zucchini", "lettuce", "tomato", "avocado", "greens"].contains(where: lowercasedName.contains) { return "Produce" }
        if ["oil", "salt", "pepper", "garlic", "soy sauce", "spices", "herbs", "vinegar"].contains(where: lowercasedName.contains) { return "Pantry" }
        if ["yogurt", "cheese", "milk"].contains(where: lowercasedName.contains) { return "Dairy" }
        return "Misc"
    }
    
    public func fetchPlan(for date: Date, userID: String) async -> MealPlanDay? {
        let dateString = dateString(for: date); let planRef = db.collection("users").document(userID).collection("mealPlans").document(dateString)
        do { return try await planRef.getDocument(as: MealPlanDay.self) } catch { return nil }
    }
    
    public func savePlan(_ plan: MealPlanDay, for userID: String) async {
        guard let planID = plan.id else { return }; let planRef = db.collection("users").document(userID).collection("mealPlans").document(planID)
        do { try planRef.setData(from: plan, merge: true) } catch { print("Error saving single meal plan: \(error)") }
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
