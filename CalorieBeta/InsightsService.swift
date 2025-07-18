import Foundation
import Combine
import FirebaseAuth
import HealthKit

@MainActor
class InsightsService: ObservableObject {
    @Published var currentInsights: [UserInsight] = []
    @Published var smartSuggestion: UserInsight? = nil
    @Published var isLoadingInsights: Bool = false
    @Published var isGeneratingSuggestion: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()
    
    private var lastWeeklyInsightFetch: Date?

    init(dailyLogService: DailyLogService, goalSettings: GoalSettings, healthKitViewModel: HealthKitViewModel) {
        self.dailyLogService = dailyLogService
        self.goalSettings = goalSettings
        self.healthKitViewModel = healthKitViewModel
        
        healthKitViewModel.$sleepSamples
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.generateAndFetchInsights()
            }
            .store(in: &cancellables)
    }

    func generateSingleMealSuggestion() async -> MealSuggestion? {
        self.isGeneratingSuggestion = true
        
        let prompt = createMealSuggestionPrompt()
        
        guard let responseString = await fetchAIResponse(prompt: prompt) else {
            self.isGeneratingSuggestion = false
            return nil
        }
        
        guard let jsonData = responseString.data(using: .utf8) else {
            self.isGeneratingSuggestion = false
            return nil
        }
        
        let suggestion = try? JSONDecoder().decode(MealSuggestion.self, from: jsonData)
        
        self.isGeneratingSuggestion = false
        return suggestion
    }
    
    private func createMealSuggestionPrompt() -> String {
        let remainingCalories = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingProtein = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        let remainingCarbs = max(0, goalSettings.carbs - (dailyLogService.currentDailyLog?.totalMacros().carbs ?? 0))
        let remainingFats = max(0, goalSettings.fats - (dailyLogService.currentDailyLog?.totalMacros().fats ?? 0))
        
        let hour = Calendar.current.component(.hour, from: Date())
        let mealType: String
        switch hour {
            case 4..<11: mealType = "breakfast"
            case 11..<16: mealType = "lunch"
            case 16..<21: mealType = "dinner"
            default: mealType = "snack"
        }

        let proteinPrefs = goalSettings.suggestionProteins.isEmpty ? "any" : goalSettings.suggestionProteins.joined(separator: ", ")
        let carbPrefs = goalSettings.suggestionCarbs.isEmpty ? "any" : goalSettings.suggestionCarbs.joined(separator: ", ")
        let veggiePrefs = goalSettings.suggestionVeggies.isEmpty ? "any" : goalSettings.suggestionVeggies.joined(separator: ", ")
        let cuisinePrefs = (goalSettings.suggestionCuisines.isEmpty || goalSettings.suggestionCuisines.contains("Any")) ? "any" : goalSettings.suggestionCuisines.joined(separator: ", ")

        return """
        You are Maia, a helpful nutrition coach. The user needs a suggestion for their next meal, which is likely \(mealType).
        
        Their remaining goals for today are:
        - Calories: \(Int(remainingCalories))
        - Protein: \(Int(remainingProtein))g
        - Carbs: \(Int(remainingCarbs))g
        - Fats: \(Int(remainingFats))g

        User Preferences:
        - Proteins: \(proteinPrefs)
        - Carbs: \(carbPrefs)
        - Veggies: \(veggiePrefs)
        - Cuisines: \(cuisinePrefs)

        RULES:
        1. Generate a single, simple, healthy meal idea that fits the user's remaining nutritional targets AND their preferences.
        2. **Prioritize Variety**: Do NOT suggest common items like 'quinoa' or 'chicken breast' unless they are explicitly listed in the user's preferences. Use a diverse range of ingredients.
        3. Your response MUST be a valid JSON object. Do not include any other text.
        4. The JSON object must have these exact keys: "mealName" (string), "calories" (number), "protein" (number), "carbs" (number), "fats" (number), "ingredients" (an array of strings), "instructions" (a single string with newlines).
        
        Example Response (if user likes Fish and Potatoes):
        {
            "mealName": "Sheet Pan Cod with Roasted Potatoes and Green Beans",
            "calories": 480,
            "protein": 35,
            "carbs": 40,
            "fats": 20,
            "ingredients": [
                "1 cod fillet (6 oz)",
                "1 medium potato, cubed",
                "1 cup green beans",
                "1 tbsp olive oil",
                "1 tsp paprika",
                "Salt and pepper to taste"
            ],
            "instructions": "1. Preheat oven to 400°F (200°C).\\n2. Toss potatoes and green beans with olive oil, paprika, salt, and pepper on a baking sheet. Roast for 10 minutes.\\n3. Add the cod fillet to the pan, season, and bake for another 12-15 minutes until the fish is flaky and potatoes are tender."
        }

        JSON-ONLY RESPONSE:
        """
    }

    func generateDailySmartInsight() {
        guard let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date) else {
            self.smartSuggestion = UserInsight(
                title: "Welcome!",
                message: "Start logging your meals and workouts to receive personalized tips here.",
                category: .smartSuggestion, priority: 1)
            return
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let loggedFoods = log.meals.flatMap { $0.foodItems }

        if let lastWorkout = log.exercises?.last(where: { $0.caloriesBurned > 150 }) {
            let workoutEndTime = lastWorkout.date.addingTimeInterval(Double(lastWorkout.durationMinutes ?? 30) * 60)
            if Date().timeIntervalSince(workoutEndTime) < (2 * 60 * 60) {
                self.smartSuggestion = UserInsight(title: "Post-Workout Refuel", message: "Great work on your recent \(lastWorkout.name.lowercased())! A snack with protein and carbs can help with recovery.", category: .smartSuggestion, priority: 100)
                return
            }
        }

        if hour >= 19 {
            let proteinRemaining = (goalSettings.protein) - log.totalMacros().protein
            if proteinRemaining > 15 && proteinRemaining < 50 {
                self.smartSuggestion = UserInsight(title: "Hit Your Protein Goal", message: String(format: "You're just %.0fg of protein away from your goal. A Greek yogurt or protein shake could be a great choice!", proteinRemaining), category: .smartSuggestion, priority: 90)
                return
            }
        }
        
        if hour >= 12 && hour < 15 && !log.meals.contains(where: { $0.name == "Lunch" }) {
            self.smartSuggestion = UserInsight(title: "Lunch Time!", message: "Don't forget to log your lunch to stay on track with your goals for the day.", category: .smartSuggestion, priority: 80)
            return
        }
        
        if hour >= 18 && hour < 21 && !log.meals.contains(where: { $0.name == "Dinner" }) {
            self.smartSuggestion = UserInsight(title: "Time for Dinner?", message: "Remember to log your dinner to get a complete picture of your day's nutrition.", category: .smartSuggestion, priority: 80)
            return
        }

        if !loggedFoods.isEmpty {
            self.smartSuggestion = UserInsight(title: "Keep Up the Great Work!", message: "Consistency is the key to reaching your goals. You're doing great today!", category: .smartSuggestion, priority: 5)
            return
        }
        
        self.smartSuggestion = UserInsight(title: "Have a Great Day!", message: "Log your first meal or workout to get personalized tips and insights.", category: .smartSuggestion, priority: 1)
    }

    func generateAndFetchInsights(forLastDays days: Int = 7) {
        guard !isLoadingInsights else { return }

        if let lastFetch = lastWeeklyInsightFetch, !currentInsights.isEmpty, Calendar.current.isDateInToday(lastFetch) {
            return
        }
        
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        let sleepData = self.healthKitViewModel?.sleepSamples ?? []

        isLoadingInsights = true
        analysisTask?.cancel()

        analysisTask = Task {
            let endDate = Calendar.current.startOfDay(for: Date())
            guard let startDate = Calendar.current.date(byAdding: .day, value: -(days), to: endDate) else {
                await handleInsightsError(message: "Could not calculate date range for insights.")
                return
            }

            let result = await fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)
            
            if Task.isCancelled {
                await handleInsightsError(message: nil, isLoading: false)
                return
            }
            
            switch result {
            case .success(let logs):
                if logs.count < 3 {
                    let noDataInsight = [UserInsight(title: "More Data Needed", message: "Log consistently for a few more days to unlock your personalized weekly insights!", category: .nutritionGeneral, priority: 100)]
                    await handleInsightsResult(insights: noDataInsight, error: nil)
                    return
                }
                
                let aiInsights = await generateAIInsights(for: logs, sleepSamples: sleepData, goals: goalSettings)
                await handleInsightsResult(insights: aiInsights, error: aiInsights.isEmpty ? "Could not generate AI insights at this time." : nil)

            case .failure(let error):
                await handleInsightsError(message: "Could not analyze data: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleInsightsResult(insights: [UserInsight], error: String?) {
        self.isLoadingInsights = false
        if let errorMessage = error {
            self.currentInsights = [UserInsight(title: "Insight Error", message: errorMessage, category: .nutritionGeneral)]
        } else {
            self.currentInsights = insights
            self.lastWeeklyInsightFetch = Date()
        }
    }
    
    private func generateAIInsights(for logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) async -> [UserInsight] {
        let prompt = createAIPrompt(logs: logs, sleepSamples: sleepSamples, goals: goals)
        
        guard let responseString = await fetchAIResponse(prompt: prompt) else { return [] }
        guard let jsonData = responseString.data(using: .utf8) else { return [] }
        
        do {
            let insightsResponse = try JSONDecoder().decode([String: [UserInsight]].self, from: jsonData)
            return insightsResponse["insights"] ?? []
        } catch {
            let fallbackInsight = UserInsight(title: "Today's Tip", message: responseString, category: .smartSuggestion)
            return [fallbackInsight]
        }
    }

    private func createAIPrompt(logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"
        
        var dailyDataStrings: [String] = []
        for log in logs {
            let day = dateFormatter.string(from: log.date)
            let macros = log.totalMacros()
            let fiber = log.totalFiber()
            let exerciseCal = (log.totalCaloriesBurnedFromHealthKitWorkouts() + log.totalCaloriesBurnedFromManualExercises())
            let exerciseString = exerciseCal > 0 ? ", Exercise Burn: \(Int(exerciseCal))" : ""
            
            dailyDataStrings.append(
                "- \(day): Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g, Fiber: \(Int(fiber))g\(exerciseString)"
            )
        }
        let dailySummary = dailyDataStrings.joined(separator: "\n")
        
        var sleepSummary = "No sleep data available."
        if !sleepSamples.isEmpty {
            let asleepStates: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM, .asleep]
            let asleepRawValues = Set(asleepStates.map { $0.rawValue })
            let totalAsleep = sleepSamples.filter { asleepRawValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let numberOfNights = Set(sleepSamples.map { Calendar.current.startOfDay(for: $0.startDate) }).count
            if numberOfNights > 0 {
                let averageSleepHours = (totalAsleep / Double(numberOfNights)) / 3600
                sleepSummary = String(format: "Average sleep over \(numberOfNights) night(s): %.1f hours per night.", averageSleepHours)
            }
        }

        let userGoals = """
        User's Goals:
        - Calorie Target: \(Int(goals.calories ?? 0)) kcal
        - Protein Target: \(Int(goals.protein))g
        - Carbs Target: \(Int(goals.carbs))g
        - Fats Target: \(Int(goals.fats))g
        - Weight Goal: \(goals.goal)
        """

        return """
        You are Maia, an expert fitness and nutrition coach for the app MyFitPlate.
        Your tone is encouraging, insightful, actionable, and positive.
        Analyze the following user data and generate 3 to 5 personalized insights.
        
        RULES:
        1.  Your response MUST be a valid JSON object.
        2.  The root object must have a single key "insights" which is a JSON array of objects.
        3.  Each object in the "insights" array must have keys: "title" (string), "message" (string), "category" (string), "priority" (number from 1-100).
        4.  The "category" must be one of the following exact strings: \(UserInsight.InsightCategory.allCases.map { $0.rawValue }.joined(separator: ", ")).
        5.  **Be Specific & Actionable:** Instead of "Eat more protein," say "Your protein intake on Wednesday was 30g below your goal. Adding a serving of Greek yogurt to your breakfast can help close that gap."
        6.  **Find Connections:** Look for patterns. Did poor sleep on Tuesday lead to higher calorie intake on Wednesday? Do they eat fewer carbs on days they exercise? Mention these connections.
        7.  **Positive Reinforcement:** ALWAYS start with at least one positive insight highlighting something the user did well.
        8.  **Identify Opportunities:** Find 1-2 key areas for improvement and provide concrete, easy-to-follow advice.
        
        DATA TO ANALYZE:
        \(userGoals)
        
        Daily Log Summary for the past week:
        \(dailySummary)
        
        Sleep Summary:
        \(sleepSummary)

        JSON-ONLY RESPONSE:
        """
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        let apiKey = getAPIKey()
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
            return nil
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "response_format": ["type": "json_object"]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
        } catch { }
        return nil
    }

    private func handleInsightsError(message: String?, isLoading: Bool? = nil) async {
        if let isLoading = isLoading { self.isLoadingInsights = isLoading }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        self.isLoadingInsights = false
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await withCheckedContinuation { continuation in
            dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
