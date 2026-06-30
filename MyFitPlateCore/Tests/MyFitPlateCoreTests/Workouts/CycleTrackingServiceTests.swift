import XCTest
@testable import MyFitPlateCore

@MainActor
final class CycleTrackingServiceTests: XCTestCase {
    private var originalCycleSettingsData: Data?
    private var originalLastPeriodStartDate: Date?

    override func setUpWithError() throws {
        originalCycleSettingsData = UserDefaults.standard.data(forKey: "cycleSettings")
        originalLastPeriodStartDate = UserDefaults.standard.object(forKey: "lastPeriodStartDate") as? Date
        UserDefaults.standard.removeObject(forKey: "cycleSettings")
        UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
    }

    override func tearDownWithError() throws {
        if let originalCycleSettingsData {
            UserDefaults.standard.set(originalCycleSettingsData, forKey: "cycleSettings")
        } else {
            UserDefaults.standard.removeObject(forKey: "cycleSettings")
        }

        if let originalLastPeriodStartDate {
            UserDefaults.standard.set(originalLastPeriodStartDate, forKey: "lastPeriodStartDate")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
        }
    }

    func testInitializesWithoutCycleDayWhenNoPeriodStartExists() {
        let service = CycleTrackingService()

        XCTAssertNil(service.cycleDay)
    }

    func testLogPeriodStartCreatesMenstrualDayOne() {
        let service = CycleTrackingService()

        service.logPeriodStart()

        XCTAssertEqual(service.cycleDay?.cycleDayNumber, 1)
        XCTAssertEqual(service.cycleDay?.phase, .menstrual)
    }

    func testClearLastPeriodStartRemovesCycleDay() {
        let service = serviceWithLastPeriodStart(daysAgo: 3)
        XCTAssertNotNil(service.cycleDay)

        service.clearLastPeriodStart()

        XCTAssertNil(service.cycleDay)
    }

    func testDefaultPhaseBoundaries() {
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 0).cycleDay?.phase, .menstrual)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 5).cycleDay?.phase, .follicular)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 13).cycleDay?.phase, .ovulatory)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 17).cycleDay?.phase, .luteal)
    }

    func testCustomCycleSettingsAffectPhaseCalculation() throws {
        let customSettings = CycleSettings(typicalCycleLength: 32, typicalPeriodLength: 4)
        let data = try JSONEncoder().encode(customSettings)
        UserDefaults.standard.set(data, forKey: "cycleSettings")

        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 4).cycleDay?.phase, .follicular)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 15).cycleDay?.phase, .ovulatory)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 19).cycleDay?.phase, .luteal)
    }

    func testCycleSettingsPersistWhenChanged() throws {
        let service = CycleTrackingService()

        service.cycleSettings = CycleSettings(typicalCycleLength: 31, typicalPeriodLength: 6)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "cycleSettings"))
        let decoded = try JSONDecoder().decode(CycleSettings.self, from: data)
        XCTAssertEqual(decoded.typicalCycleLength, 31)
        XCTAssertEqual(decoded.typicalPeriodLength, 6)
    }

    func testFetchAIInsightBuildsPromptFromRecentLogsAndStoresDecodedInsight() async {
        let mockRepo = MockNutritionRepository()
        mockRepo.mockFetchDailyHistoryResult = .success([
            DailyLog(
                id: "log-1",
                date: Date(timeIntervalSince1970: 1_725_235_200),
                meals: [
                    Meal(name: "Breakfast", foodItems: [
                        FoodItem(id: "food-1", name: "Oats", calories: 300, protein: 20, carbs: 45, fats: 6)
                    ])
                ]
            )
        ])
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = MockAuthService()
        let aiService = MockAIService()
        aiService.mockResult = .success("""
        {
          "phaseTitle": "Power Phase",
          "phaseDescription": "Energy is trending up.",
          "trainingFocus": {
            "title": "Strength",
            "description": "Lean into progressive overload."
          },
          "hormonalState": "Rising estrogen",
          "energyLevel": "High",
          "nutritionTip": "Keep protein steady.",
          "symptomTip": "Hydrate well."
        }
        """)
        DIContainer.shared.aiService = aiService
        let service = serviceWithLastPeriodStart(daysAgo: 13)
        let goals = GoalSettings()
        goals.goal = "Lose"
        service.setupDependencies(goalSettings: goals, dailyLogService: DailyLogService())

        service.fetchAIInsight()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(service.isLoadingInsight)
        XCTAssertEqual(service.aiInsight?.phaseTitle, "Power Phase")
        XCTAssertEqual(service.aiInsight?.trainingFocus.title, "Strength")
        XCTAssertEqual(mockRepo.fetchRecentFoodLimits, [])
    }

    func testFetchAIInsightClearsLoadingWhenAIRequestFails() async {
        DIContainer.shared.nutritionRepository = MockNutritionRepository()
        DIContainer.shared.authService = MockAuthService()
        let aiService = MockAIService()
        aiService.mockResult = .failure(.networkError(URLError(.timedOut)))
        DIContainer.shared.aiService = aiService
        let service = serviceWithLastPeriodStart(daysAgo: 13)
        service.setupDependencies(goalSettings: GoalSettings(), dailyLogService: DailyLogService())

        service.fetchAIInsight()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(service.isLoadingInsight)
        XCTAssertNil(service.aiInsight)
    }

    func testFetchAIInsightReturnsEarlyWithoutCycleDayOrGoals() async {
        let service = CycleTrackingService()

        service.fetchAIInsight()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(service.isLoadingInsight)
        XCTAssertNil(service.aiInsight)
    }

    private func serviceWithLastPeriodStart(daysAgo: Int) -> CycleTrackingService {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        UserDefaults.standard.set(Calendar.current.startOfDay(for: startDate), forKey: "lastPeriodStartDate")
        return CycleTrackingService()
    }
}
