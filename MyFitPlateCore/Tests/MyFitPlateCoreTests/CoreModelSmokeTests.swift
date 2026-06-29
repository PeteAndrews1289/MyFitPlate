import XCTest
@testable import MyFitPlateCore

final class CoreModelSmokeTests: XCTestCase {
    func testAIAndAPIErrorDescriptionsAreHumanReadable() {
        let decoding = NSError(domain: "decode", code: 10, userInfo: [NSLocalizedDescriptionKey: "Bad payload"])
        let network = NSError(domain: "network", code: 11, userInfo: [NSLocalizedDescriptionKey: "Offline"])

        XCTAssertEqual(AIError.invalidURL.errorDescription, "Invalid API URL.")
        XCTAssertEqual(AIError.noData.errorDescription, "The AI returned no data.")
        XCTAssertEqual(AIError.apiError("Quota exceeded").errorDescription, "AI Error: Quota exceeded")
        XCTAssertEqual(AIError.decodingError(decoding).errorDescription, "Failed to process AI response: Bad payload")
        XCTAssertEqual(AIError.networkError(network).errorDescription, "Network connection failed: Offline")
        XCTAssertEqual(AIError.maxRetriesExceeded.errorDescription, "Unable to generate a valid response after multiple attempts.")

        XCTAssertEqual(APIError.invalidURL.errorDescription, "The provided URL was invalid.")
        XCTAssertEqual(APIError.noData.errorDescription, "No data was received from the server.")
        XCTAssertEqual(APIError.decodingError(decoding).errorDescription, "There was an error decoding the data: Bad payload")
        XCTAssertEqual(APIError.networkError(network).errorDescription, "There was a network error: Offline")
        XCTAssertEqual(APIError.apiError("Server rejected request").errorDescription, "Server rejected request")
        XCTAssertEqual(APIError.unknown.errorDescription, "An unknown error occurred.")
    }

    func testAIServiceProtocolDefaultArgumentsDelegateToFullSignature() async {
        let service = RecordingAIService()
        let result = await service.performRequest(messages: [["role": "user", "content": "hello"]])

        XCTAssertEqual(try? result.get(), "ok")
        XCTAssertEqual(service.recordedModel, "gpt-4o-mini")
        XCTAssertEqual(service.recordedMaxTokens, 2048)
        XCTAssertEqual(service.recordedTemperature, 0.7)
        XCTAssertNil(service.recordedResponseFormat)
        XCTAssertEqual(service.recordedRetryCount, 1)
    }

    func testChatModelsCodableAndCapitalizationHelper() throws {
        XCTAssertEqual(capitalizedFirstLetter(of: "maia"), "Maia")
        XCTAssertEqual(capitalizedFirstLetter(of: ""), "")

        let message = ChatMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            text: "Log my lunch",
            isUser: true
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded, message)
    }

    func testRecipeAndReportValueModelsPreserveInputs() {
        let nutrition = Nutrition(calories: 500, protein: 40, carbs: 55, fats: 12, fiber: 8)
        let recipe = Recipe(
            id: "recipe",
            name: "Chicken Bowl",
            ingredients: ["Chicken", "Rice"],
            instructions: ["Cook", "Serve"],
            nutrition: nutrition,
            servings: 2,
            imageURL: "https://example.com/image.jpg"
        )
        XCTAssertEqual(recipe.nutrition, nutrition)
        XCTAssertEqual(Nutrition.zero, Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0))

        let noScore = MealScore.noScore
        XCTAssertEqual(noScore.grade, "N/A")
        XCTAssertEqual(noScore.goalCalories, 2000)
        XCTAssertTrue(noScore.improvementTips.isEmpty)

        let micro = MicroAverageDataPoint(name: "Fiber", unit: "g", averageValue: 15, goalValue: 30)
        XCTAssertEqual(micro.percentageMet, 50, accuracy: 0.001)
        XCTAssertEqual(micro.progressViewValue, 0.5, accuracy: 0.001)

        let capped = MicroAverageDataPoint(name: "Sodium", unit: "mg", averageValue: 4_000, goalValue: 2_000)
        XCTAssertEqual(capped.progressViewValue, 1, accuracy: 0.001)

        let zeroGoal = MicroAverageDataPoint(name: "Unknown", unit: "", averageValue: 10, goalValue: 0)
        XCTAssertEqual(zeroGoal.percentageMet, 0, accuracy: 0.001)
        XCTAssertEqual(zeroGoal.progressViewValue, 0, accuracy: 0.001)
    }

    func testCycleAndInsightModelsInitializePredictably() throws {
        XCTAssertEqual(MenstrualPhase.allCases.map(\.id), MenstrualPhase.allCases)

        let settings = CycleSettings()
        XCTAssertEqual(settings.typicalCycleLength, 28)
        XCTAssertEqual(settings.typicalPeriodLength, 5)

        let encoded = try JSONEncoder().encode(AIInsight(
            phaseTitle: "Follicular",
            phaseDescription: "Energy rising",
            trainingFocus: AIInsight.TrainingFocus(title: "Strength", description: "Push progression"),
            hormonalState: "Balanced",
            energyLevel: "High",
            nutritionTip: "Prioritize protein",
            symptomTip: "Track symptoms"
        ))
        let decoded = try JSONDecoder().decode(AIInsight.self, from: encoded)
        XCTAssertEqual(decoded.phaseTitle, "Follicular")
        XCTAssertEqual(decoded.trainingFocus.title, "Strength")
    }
}

private final class RecordingAIService: AIServiceProtocol {
    private(set) var recordedModel: String?
    private(set) var recordedMaxTokens: Int?
    private(set) var recordedTemperature: Double?
    private(set) var recordedResponseFormat: [String: Any]?
    private(set) var recordedRetryCount: Int?

    func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        retryCount: Int
    ) async -> Result<String, AIError> {
        recordedModel = model
        recordedMaxTokens = maxTokens
        recordedTemperature = temperature
        recordedResponseFormat = responseFormat
        recordedRetryCount = retryCount
        return .success("ok")
    }
}
