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
                await self.handleInsightsError(message: "Could not calculate date range for insights.")
                return
            }

            let result = await self.fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)
            
            if Task.isCancelled {
                await self.handleInsightsError(message: nil, isLoading: false)
                return
            }
            
            switch result {
            case .success(let logs):
                if logs.count < 3 {
                    let noDataInsight = [UserInsight(title: "More Data Needed", message: "Log consistently for a few more days to unlock your personalized weekly insights!", category: .nutritionGeneral, priority: 100)]
                    await self.handleInsightsResult(insights: noDataInsight, error: nil)
                    return
                }
                
                let aiInsights = await self.generateAIInsights(for: logs, sleepSamples: sleepData, goals: self.goalSettings)
                await self.handleInsightsResult(insights: aiInsights, error: aiInsights.isEmpty ? "Could not generate AI insights at this time." : nil)

            case .failure(let error):
                await self.handleInsightsError(message: "Could not analyze data: \(error.localizedDescription)")
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
        
        let dailyNutritionSummary = logs.map { log -> String in
            let day = dateFormatter.string(from: log.date)
            let macros = log.totalMacros()
            let micros = log.totalMicronutrients()
            return "- \(day): Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g, Fiber: \(Int(micros.fiber))g, Sodium: \(Int(micros.sodium))mg"
        }.joined(separator: "\n")
        
        let dailyWorkoutSummary = logs.compactMap { log -> String? in
            guard let exercises = log.exercises, !exercises.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let totalBurn = exercises.reduce(0) { $0 + $1.caloriesBurned }
            let exerciseNames = exercises.map { $0.name }.joined(separator: ", ")
            return "- \(day): Burned \(Int(totalBurn)) calories from \(exerciseNames)."
        }.joined(separator: "\n")
        
        let sleepSummaryByDay = Dictionary(grouping: sleepSamples) {
            Calendar.current.startOfDay(for: $0.startDate)
        }.mapValues { samples -> TimeInterval in
            samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        }

        let sleepSummaryString = sleepSummaryByDay.keys.sorted().map { date -> String in
            let day = dateFormatter.string(from: date)
            let hours = (sleepSummaryByDay[date] ?? 0) / 3600
            return "- \(day): \(String(format: "%.1f", hours)) hours"
        }.joined(separator: "\n")

        let journalSummary = logs.compactMap { log -> String? in
            guard let entries = log.journalEntries, !entries.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let entrySummaries = entries.map { "\($0.category): \($0.text)" }.joined(separator: "; ")
            return "- \(day): \(entrySummaries)"
        }.joined(separator: "\n")
        
        let userGoals = """
        User's Goals:
        - Calorie Target: \(Int(goals.calories ?? 0)) kcal
        - Protein Target: \(Int(goals.protein))g
        - Fiber Target: 25g
        - Sodium Limit: 2300mg
        - Weight Goal: \(goals.goal)
        """

        return """
        You are Maia, an expert fitness and nutrition coach. Your tone is encouraging, insightful, and actionable. Analyze the following user data and generate 7 personalized insights.

        RULES:
        1.  Your response MUST be a valid JSON object with a single root key "insights".
        2.  Each insight object must have keys: "title", "message", "category", "priority", and "sourceData".
        3.  **Source Data (CRITICAL):** For each insight, the "sourceData" key must contain a concise, human-readable string of the specific data points you used. For example, "Wednesday Sleep: 6.1 hours, Thursday Calories: 1950 kcal".
        4.  **Holistic Insight (CRITICAL):** Generate at least two insights that connect workout data to nutrition OR sleep data. Example: "On Wednesday you had a tough leg day, and followed it up with 8 hours of sleep. This is fantastic for muscle recovery."
        5.  **Be Specific & Actionable:** Instead of "Eat more protein," say "Your protein intake on Wednesday was 30g below your goal. Adding a serving of Greek yogurt to your breakfast can help close that gap."
        6.  **Positive Reinforcement:** ALWAYS start with at least one positive insight highlighting something the user did well.
        7.  **Fitness Insight Requirement:** If the user has logged exercise, you MUST include at least one fitness-related insight.
        8.  **CATEGORIZE CORRECTLY:** For each insight, you MUST assign a 'category' from this exact list: [\(UserInsight.InsightCategory.allCases.map { $0.rawValue }.joined(separator: ", "))].
        
        DATA TO ANALYZE:
        \(userGoals)
        
        Daily Nutrition Summary (with Food Quality metrics):
        \(dailyNutritionSummary)
        
        Daily Workout Summary:
        \(dailyWorkoutSummary.isEmpty ? "No workouts logged this period." : dailyWorkoutSummary)
        
        Daily Sleep Summary:
        \(sleepSummaryString.isEmpty ? "No sleep data available." : sleepSummaryString)
        
        Daily Journal Summary:
        \(journalSummary.isEmpty ? "No journal entries logged this period." : journalSummary)

        JSON-ONLY RESPONSE:
        """
    }
    
    func generateDailyBriefing(for userID: String) async -> (title: String, body: String)? {
        let wellnessScoreSummary = "Good Recovery"
        let todaysWorkout = "Leg Day"
        
        let prompt = """
        You are Maia, an encouraging fitness coach. Create a short, motivational "Daily Briefing" push notification.

        Yesterday's Wellness Score resulted in a summary of: "\(wellnessScoreSummary)".
        Today's planned workout is: "\(todaysWorkout)".

        RULES:
        1.  The title should be 4-5 words.
        2.  The body should be 1-2 short, encouraging sentences.
        3.  Combine the user's recovery status with their plan for the day.
        4.  Provide ONLY the title and body, separated by a newline. Do not add any other text.
        """
        
        guard let response = await fetchAIResponse(prompt: prompt) else { return nil }
        let lines = response.split(separator: "\n").map(String.init)
        guard lines.count >= 2 else { return nil }
        
        return (title: lines[0], body: lines[1])
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
        return await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate)
    }
}
