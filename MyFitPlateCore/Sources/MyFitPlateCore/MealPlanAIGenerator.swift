import Foundation
@MainActor
public struct MealPlanAIGenerator {
    
    // MARK: - Single Meal Regeneration
    public func regenerateSingleMeal(for day: MealPlanDay, mealToReplace: PlannedMeal, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], retryCount: Int = 1) async -> PlannedMeal? {
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
        
        **Medical Disclaimer**: Note that generated nutritional values and meal plans are AI estimates and should not be considered medical advice.
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        let result = await DIContainer.shared.aiService.performRequest(messages: messages, responseFormat: ["type": "json_object"])

        switch result {
        case .success(let jsonString):
            do {
                return try parseSingleMealFromAIResponse(jsonString)
            } catch {
                if retryCount > 0 {
                    return await regenerateSingleMeal(for: day, mealToReplace: mealToReplace, goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure:
            return nil
        }
    }

    // MARK: - Week Generation Orchestrator
    public func generateWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String]) async -> [MealPlanDay] {
        if let fullWeekPlan = await generateFullWeekPlanAI(goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks) {
            return fullWeekPlan
        } else if let legacyPlan = await generateLegacyFullWeekPlanAI(goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks) {
            return legacyPlan
        } else {
            return generateLocalFullWeekPlan(goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks)
        }
    }

    // MARK: - Private Generators
    private func generateFullWeekPlanAI(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], retryCount: Int = 1) async -> [MealPlanDay]? {
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
        - **Medical Disclaimer**: Note that generated nutritional values and meal plans are AI estimates and should not be considered medical advice.

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

        let result = await DIContainer.shared.aiService.performRequest(
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
                return await generateFullWeekPlanAI(goals: goals, preferredFoods: preferredFoods, preferredCuisines: preferredCuisines, preferredSnacks: preferredSnacks, retryCount: retryCount - 1)
            }
            return nil

        case .failure(let error):
            AppLog.mealPlanner.error("Failed to generate full-week meal plan: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func generateLegacyFullWeekPlanAI(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String]) async -> [MealPlanDay]? {
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

    private func generatePlanForSingleDay(date: Date, goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String], mealHistory: [String], retryCount: Int) async -> MealPlanDay? {
        let formatter = DateFormatter(); formatter.dateFormat = "EEEE, MMMM d"
        let dateStringForPrompt = formatter.string(from: date)

        let prompt = """
        Generate a one-day meal plan for \(dateStringForPrompt).
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
        let result = await DIContainer.shared.aiService.performRequest(messages: messages, responseFormat: ["type": "json_object"])

        switch result {
        case .success(let jsonString):
            do {
                let meals = try parsePlanFromAIResponse(jsonString)
                if meals.count >= 3 {
                    return MealPlanDay(id: dateString(for: date), date: date, meals: meals)
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

    func generateLocalFullWeekPlan(goals: GoalSettings, preferredFoods: [String], preferredCuisines: [String], preferredSnacks: [String]) -> [MealPlanDay] {
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

            return MealPlanDay(id: dateString(for: date), date: date, meals: meals)
        }
    }

    private func localMeal(type: String, name: String, calories: Double, protein: Double, carbs: Double, fats: Double, ingredients: [String], instructions: String) -> PlannedMeal {
        let foodItem = FoodItem(id: UUID().uuidString, name: name, calories: calories, protein: protein, carbs: carbs, fats: fats, servingSize: "1 serving", servingWeight: 0)
        return PlannedMeal(id: UUID().uuidString, mealType: type, foodItem: foodItem, ingredients: ingredients, instructions: instructions)
    }

    // MARK: - Parsing Helpers
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

    func parseFullWeekPlanFromAIResponse(_ jsonString: String, startDate: Date) throws -> [MealPlanDay] {
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

                return MealPlanDay(id: dateString(for: date), date: date, meals: meals)
            }
    }

    func parsePlanFromAIResponse(_ jsonString: String) throws -> [PlannedMeal] {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let response = try JSONDecoder().decode(AIPlanResponse.self, from: jsonData)
        return response.meals.map(mapAIMealToPlannedMeal)
    }

    func parseSingleMealFromAIResponse(_ jsonString: String) throws -> PlannedMeal {
        guard let jsonData = jsonString.data(using: .utf8) else { throw NSError(domain: "MealPlanner", code: 1) }
        let aiMeal = try JSONDecoder().decode(AIMeal.self, from: jsonData)
        return mapAIMealToPlannedMeal(aiMeal)
    }

    private func mapAIMealToPlannedMeal(_ aiMeal: AIMeal) -> PlannedMeal {
        let foodItem = FoodItem(id: UUID().uuidString, name: aiMeal.mealName, calories: aiMeal.calories, protein: aiMeal.protein, carbs: aiMeal.carbs, fats: aiMeal.fats, servingSize: "1 serving", servingWeight: 0)
        return PlannedMeal(id: UUID().uuidString, mealType: aiMeal.mealType, foodItem: foodItem, ingredients: aiMeal.ingredients, instructions: aiMeal.instructions.joined(separator: "\n"))
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}
