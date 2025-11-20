import Foundation
import FirebaseFirestore
import FirebaseAuth

// This struct holds the final calculated analytics data, including AI insights.
struct WorkoutAnalytics {
    let totalVolume: Double
    let personalRecords: [String: String]
    let aiInsights: [WorkoutAnalysisInsight]
}

// This struct defines the structure for a single AI-generated workout insight.
struct WorkoutAnalysisInsight: Decodable, Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
    let category: String

    private enum CodingKeys: String, CodingKey {
        case title, message, category
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WorkoutAnalysisInsight, rhs: WorkoutAnalysisInsight) -> Bool {
        lhs.id == rhs.id
    }
}

// Helper struct to decode the root JSON object from the AI response.
private struct AIWorkoutInsightResponse: Decodable {
    let insights: [WorkoutAnalysisInsight]
}

// This service is responsible for calculating statistics and generating AI insights for workouts.
@MainActor
class WorkoutAnalyticsService {
    private let workoutService = WorkoutService()
    private let apiKey = getAPIKey() // Assumes getAPIKey() is available globally

    // Calculates workout analytics based on provided daily logs and optional program info
    func calculateAnalytics(for logs: [DailyLog], program: WorkoutProgram?) async -> WorkoutAnalytics {
        var totalVolume: Double = 0
        var personalRecords: [String: (weight: Double, reps: Int)] = [:]

        let allLoggedExercises = logs.flatMap { $0.exercises ?? [] }

        // Fetch detailed session data for each logged routine exercise
        for loggedExercise in allLoggedExercises {
            guard let workoutID = loggedExercise.workoutID, let sessionID = loggedExercise.sessionID else { continue }

            let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)

            if case .success(let sessionLog) = sessionResult {
                for completedExercise in sessionLog.completedExercises {
                    for set in completedExercise.sets {
                        let volume = set.weight * Double(set.reps)
                        totalVolume += volume

                        let exerciseName = completedExercise.exerciseName // Use exerciseName from CompletedExercise
                        if let currentPR = personalRecords[exerciseName] {
                            // Simple PR logic: highest weight lifted for any reps
                            if set.weight > currentPR.weight {
                                personalRecords[exerciseName] = (weight: set.weight, reps: set.reps)
                            }
                            // Could add logic for highest weight at specific rep ranges too
                        } else {
                            personalRecords[exerciseName] = (weight: set.weight, reps: set.reps)
                        }
                    }
                }
            }
        }

        let prStrings = personalRecords.mapValues { String(format: "%.1f lbs x %d reps", $0.weight, $0.reps) }

        // Generate AI insights based on the calculated stats and logs
        let aiInsights = await generateAIWorkoutInsights(for: logs, program: program, analytics: (totalVolume, prStrings))

        return WorkoutAnalytics(totalVolume: totalVolume, personalRecords: prStrings, aiInsights: aiInsights)
    }

    // Generates personalized workout insights using an AI model
    private func generateAIWorkoutInsights(for logs: [DailyLog], program: WorkoutProgram?, analytics: (totalVolume: Double, prs: [String: String])) async -> [WorkoutAnalysisInsight] {
        // Prepare summaries of workout and nutrition data for the AI prompt
        let workoutSummary = logs.flatMap { $0.exercises ?? [] }
            .map { "On \(($0.date).formatted(date: .abbreviated, time: .omitted)), user did \($0.name) for \($0.durationMinutes ?? 0) mins, burning \(Int($0.caloriesBurned)) calories." }
            .joined(separator: "\n")

        let nutritionSummary = logs.map {
            "On \(($0.date).formatted(date: .abbreviated, time: .omitted)), user ate \(Int($0.totalCalories())) calories, with \(Int($0.totalMacros().protein))g protein."
        }.joined(separator: "\n")

        // *** HIGH-LEVEL COMMENT: ***
        // The prompt below has been modified to request 8 focused insights
        // instead of 10 generic ones, and to prioritize actionable, holistic advice.
        
        // Construct the prompt for the AI
        let prompt = """
        You are Maia, an expert fitness and nutrition coach for the MyFitPlate app. Your tone is encouraging, insightful, and actionable. Analyze the following user data and generate **exactly 8 high-quality, focused, and actionable** insights in a JSON format.

        **User Data:**
        - **Workout Program:** \(program?.name ?? "No active program")
        - **Total Volume This Period:** \(Int(analytics.totalVolume)) lbs
        - **New Personal Records:** \(analytics.prs.isEmpty ? "None" : analytics.prs.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
        - **Workout Logs:**
        \(workoutSummary.isEmpty ? "No workouts logged." : workoutSummary)
        - **Nutrition Logs:**
        \(nutritionSummary.isEmpty ? "No nutrition logged." : nutritionSummary)

        **Your Task:**
        Provide a JSON object with a single root key "insights". The value should be an array of **8** insight objects. Each insight object must have three keys: "title" (string), "message" (string), and "category" (string).

        **Insight Categories:**
        Use one of the following for the "category" key: "Performance", "Consistency", "Recovery", "Nutrition", "Mindset".

        **CRITICAL Rules:**
        1. **Holistic & Actionable Insights:** Prioritize insights that are genuinely actionable. You MUST generate at least 3-4 insights that connect multiple data areas (e.g., how sleep impacted a workout, or how nutrition supported recovery).
        2. **Data-Driven & Specific:** Insights MUST be data-driven. Instead of "Eat more protein," say "Your protein intake on Wednesday was 30g below your goal. Adding a serving of Greek yogurt to your breakfast can help close that gap."
        3. **Positive Reinforcement:** ALWAYS start with at least one positive insight highlighting something the user did well.
        4. **Fitness Insight Requirement:** If the user has logged exercise, you MUST include at least one fitness-related insight.
        5. **JSON Structure:** Ensure the JSON response is valid and contains exactly the requested structure ("insights" array with 8 objects).
        """


        // Fetch the AI response
        let aiResponse = await fetchAIResponse(prompt: prompt)

        guard let responseData = aiResponse?.data(using: .utf8) else {
            print("AI Insight Generation: Failed to get data from AI response.")
            return []
        }

        // Decode the AI response
        do {
            let decodedResponse = try JSONDecoder().decode(AIWorkoutInsightResponse.self, from: responseData)
            return decodedResponse.insights
        } catch {
            print("Error decoding AI workout insights: \(error)")
            // Optionally try to return a fallback error insight
            return [WorkoutAnalysisInsight(title: "Analysis Error", message: "Could not generate insights at this time. AI response might be invalid.", category: "Mindset")]
        }
    }

    // Fetches a response from the OpenAI API
    private func fetchAIResponse(prompt: String) async -> String? {
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
             print("AI fetch error: API Key not configured.")
             return nil
        }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 1500 // 1500 is fine for 8 insights
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

             guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                 let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                 print("AI fetch error: Invalid server response (\(statusCode)).")
                 return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            } else if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errorDict = errorJson["error"] as? [String: Any],
                      let errorMessage = errorDict["message"] as? String {
                 print("AI fetch error: API returned error - \(errorMessage)")
                 return nil // API returned a specific error message
             } else {
                 print("AI fetch error: Invalid JSON structure in response.")
                 return nil // Unexpected JSON format
             }
        } catch {
            print("AI fetch error: Network request failed - \(error.localizedDescription)")
            return nil
        }
    }
}
