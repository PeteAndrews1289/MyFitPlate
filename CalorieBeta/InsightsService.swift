import Foundation
import Combine
import FirebaseAuth
import HealthKit

struct UserInsight: Identifiable, Decodable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var category: InsightCategory
    var priority: Int = 0
    
    
    private enum CodingKeys: String, CodingKey {
        case title, message, category, priority
    }
    
  
    enum InsightCategory: String, Codable, Equatable, CaseIterable {
        case nutritionGeneral, hydration, macroBalance, microNutrient, mealTiming, consistency, postWorkout, foodVariety, positiveReinforcement, sugarAwareness, fiberIntake, saturatedFat, smartSuggestion, sleep
    }
    
   
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        category = (try? container.decode(InsightCategory.self, forKey: .category)) ?? .nutritionGeneral
        priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
    }

  
    init(title: String, message: String, category: InsightCategory, priority: Int = 0) {
        self.title = title
        self.message = message
        self.category = category
        self.priority = priority
    }
}

@MainActor
class InsightsService: ObservableObject {
    @Published var currentInsights: [UserInsight] = []
    @Published var smartSuggestion: UserInsight? = nil
    @Published var isLoadingInsights: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()

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
                    await handleInsightsError(message: nil, insights: noDataInsight, isLoading: false)
                    return
                }
                
                let aiInsights = await generateAIInsights(for: logs, sleepSamples: sleepData, goals: goalSettings)
                
                if aiInsights.isEmpty {
                    await handleInsightsError(message: "Could not generate AI insights at this time. Please try again later.")
                } else {
                    await handleInsightsError(message: nil, insights: aiInsights, isLoading: false)
                }

            case .failure(let error):
                await handleInsightsError(message: "Could not analyze data: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateAIInsights(for logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) async -> [UserInsight] {
        let prompt = createAIPrompt(logs: logs, sleepSamples: sleepSamples, goals: goals)
        
        guard let responseString = await fetchAIResponse(prompt: prompt) else {
            return []
        }
        
        guard let jsonData = responseString.data(using: .utf8) else { return [] }
        
        do {
            let insightsResponse = try JSONDecoder().decode([String: [UserInsight]].self, from: jsonData)
            if let insights = insightsResponse["insights"] {
                 return insights.sorted { $0.priority > $1.priority }
            }
           return []
        } catch {
            print("AI Insight Decoding Error: \(error)")
            let fallbackInsight = UserInsight(title: "Today's Tip", message: responseString, category: .smartSuggestion)
            return [fallbackInsight]
        }
    }

    private func createAIPrompt(logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> String {
        let avgCalories = logs.map { $0.totalCalories() }.reduce(0, +) / Double(logs.count)
        let avgProtein = logs.map { $0.totalMacros().protein }.reduce(0, +) / Double(logs.count)
        let avgCarbs = logs.map { $0.totalMacros().carbs }.reduce(0, +) / Double(logs.count)
        let avgFats = logs.map { $0.totalMacros().fats }.reduce(0, +) / Double(logs.count)
        let daysWithExercise = logs.filter { !($0.exercises?.isEmpty ?? true) }.count

        var sleepSummary = "No sleep data available."
        if !sleepSamples.isEmpty {
            let asleepStates: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM, .asleep]
            let asleepRawValues = Set(asleepStates.map { $0.rawValue })
            let totalAsleep = sleepSamples.filter { asleepRawValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let numberOfNights = Set(sleepSamples.map { Calendar.current.startOfDay(for: $0.startDate) }).count
            if numberOfNights > 0 {
                let averageSleepHours = (totalAsleep / Double(numberOfNights)) / 3600
                sleepSummary = String(format: "Average sleep: %.1f hours per night.", averageSleepHours)
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
        
        let weeklySummary = """
        Weekly Data Summary:
        - Logged Days: \(logs.count)
        - Average daily calories consumed: \(Int(avgCalories)) kcal
        - Average daily protein: \(Int(avgProtein))g
        - Average daily carbs: \(Int(avgCarbs))g
        - Average daily fats: \(Int(avgFats))g
        - Days with logged exercise: \(daysWithExercise) out of \(logs.count)
        - \(sleepSummary)
        """

        return """
        You are an expert fitness and nutrition coach for an app called MyFitPlate.
        Your tone is encouraging, insightful, and positive.
        Analyze the following user data summary and generate 3 to 5 personalized insights.
        
        RULES:
        1.  Your response MUST be a valid JSON object.
        2.  The root object must have a single key called "insights" which is a JSON array of objects.
        3.  Each object in the "insights" array must have four keys: "title" (string), "message" (string), "category" (string), and "priority" (number from 1-100).
        4.  The "category" must be one of the following exact strings: \(UserInsight.InsightCategory.allCases.map { $0.rawValue }.joined(separator: ", ")).
        5.  Find interesting connections between the data. For example, if protein is low and exercise is high, suggest post-workout nutrition. If calories are high on days after poor sleep, point that out.
        6.  Do not be generic. Use the numbers from the data to make the insights specific and personal. Give actionable advice.
        
        DATA TO ANALYZE:
        \(userGoals)
        \(weeklySummary)

        JSON-ONLY RESPONSE:
        """
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        let apiKey = getAPIKey()
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
            print("API Key is missing or invalid.")
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
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("AI API Error: Invalid response from server. Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
        } catch {
            print("AI API Fetch Error: \(error)")
        }
        return nil
    }

    private func handleInsightsError(message: String?, insights: [UserInsight]? = nil, isLoading: Bool? = nil) async {
        if let isLoading = isLoading { self.isLoadingInsights = isLoading }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        if let insights = insights { self.currentInsights = insights }
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await withCheckedContinuation { continuation in
            dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
