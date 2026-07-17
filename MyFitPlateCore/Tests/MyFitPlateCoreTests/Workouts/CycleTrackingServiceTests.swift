import XCTest
@testable import MyFitPlateCore

@MainActor
final class CycleTrackingServiceTests: XCTestCase {
    private let testUserID = "cycle-test-user"
    private let otherUserID = "cycle-other-user"
    private var originalCycleSettingsData: Data?
    private var originalLastPeriodStartDate: Date?
    private var originalScopedSettingsData: Data?
    private var originalScopedPeriodStartDate: Date?
    private var originalOtherSettingsData: Data?
    private var originalOtherPeriodStartDate: Date?

    override func setUpWithError() throws {
        originalCycleSettingsData = UserDefaults.standard.data(forKey: "cycleSettings")
        originalLastPeriodStartDate = UserDefaults.standard.object(forKey: "lastPeriodStartDate") as? Date
        originalScopedSettingsData = UserDefaults.standard.data(forKey: CycleTrackingService.settingsStorageKey(for: testUserID))
        originalScopedPeriodStartDate = UserDefaults.standard.object(forKey: CycleTrackingService.periodStartStorageKey(for: testUserID)) as? Date
        originalOtherSettingsData = UserDefaults.standard.data(forKey: CycleTrackingService.settingsStorageKey(for: otherUserID))
        originalOtherPeriodStartDate = UserDefaults.standard.object(forKey: CycleTrackingService.periodStartStorageKey(for: otherUserID)) as? Date
        UserDefaults.standard.removeObject(forKey: "cycleSettings")
        UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
        UserDefaults.standard.removeObject(forKey: CycleTrackingService.settingsStorageKey(for: testUserID))
        UserDefaults.standard.removeObject(forKey: CycleTrackingService.periodStartStorageKey(for: testUserID))
        UserDefaults.standard.removeObject(forKey: CycleTrackingService.settingsStorageKey(for: otherUserID))
        UserDefaults.standard.removeObject(forKey: CycleTrackingService.periodStartStorageKey(for: otherUserID))
        AIDataConsentStore.shared.grant(for: testUserID, includesHealthData: false)
    }

    override func tearDownWithError() throws {
        AIDataConsentStore.shared.revoke(for: testUserID)
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
        restore(originalScopedSettingsData, key: CycleTrackingService.settingsStorageKey(for: testUserID))
        restore(originalScopedPeriodStartDate, key: CycleTrackingService.periodStartStorageKey(for: testUserID))
        restore(originalOtherSettingsData, key: CycleTrackingService.settingsStorageKey(for: otherUserID))
        restore(originalOtherPeriodStartDate, key: CycleTrackingService.periodStartStorageKey(for: otherUserID))
    }

    func testInitializesWithoutCycleDayWhenNoPeriodStartExists() {
        let service = CycleTrackingService(userID: testUserID)

        XCTAssertNil(service.cycleDay)
    }

    func testLogPeriodStartCreatesMenstrualDayOne() {
        let service = CycleTrackingService(userID: testUserID)

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
        UserDefaults.standard.set(data, forKey: CycleTrackingService.settingsStorageKey(for: testUserID))

        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 4).cycleDay?.phase, .follicular)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 15).cycleDay?.phase, .ovulatory)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 19).cycleDay?.phase, .luteal)
    }

    func testCycleSettingsPersistWhenChanged() throws {
        let service = CycleTrackingService(userID: testUserID)

        service.cycleSettings = CycleSettings(typicalCycleLength: 31, typicalPeriodLength: 6)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: CycleTrackingService.settingsStorageKey(for: testUserID)))
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
        let authService = MockAuthService()
        authService.currentUserID = testUserID
        DIContainer.shared.authService = authService
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
        let authService = MockAuthService()
        authService.currentUserID = testUserID
        DIContainer.shared.authService = authService
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
        let service = CycleTrackingService(userID: testUserID)

        service.fetchAIInsight()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(service.isLoadingInsight)
        XCTAssertNil(service.aiInsight)
    }

    func testAccountSwitchDoesNotExposePreviousCycleState() {
        let service = CycleTrackingService(userID: testUserID)
        service.cycleSettings = CycleSettings(typicalCycleLength: 31, typicalPeriodLength: 6)
        service.logPeriodStart()
        XCTAssertNotNil(service.cycleDay)

        service.activateAccount(otherUserID)

        XCTAssertNil(service.cycleDay)
        XCTAssertEqual(service.cycleSettings.typicalCycleLength, CycleSettings().typicalCycleLength)

        service.activateAccount(testUserID)
        XCTAssertNotNil(service.cycleDay)
        XCTAssertEqual(service.cycleSettings.typicalCycleLength, 31)
    }

    func testLegacyCycleDataMigratesOnlyIntoActiveAccount() throws {
        let settings = CycleSettings(typicalCycleLength: 30, typicalPeriodLength: 4)
        UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "cycleSettings")
        UserDefaults.standard.set(Date(), forKey: "lastPeriodStartDate")

        let service = CycleTrackingService(userID: testUserID)

        XCTAssertEqual(service.cycleSettings.typicalCycleLength, 30)
        XCTAssertNotNil(service.cycleDay)
        XCTAssertNil(UserDefaults.standard.object(forKey: "cycleSettings"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "lastPeriodStartDate"))
        XCTAssertNil(UserDefaults.standard.data(forKey: CycleTrackingService.settingsStorageKey(for: otherUserID)))
    }

    private func serviceWithLastPeriodStart(daysAgo: Int) -> CycleTrackingService {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        UserDefaults.standard.set(
            Calendar.current.startOfDay(for: startDate),
            forKey: CycleTrackingService.periodStartStorageKey(for: testUserID)
        )
        return CycleTrackingService(userID: testUserID)
    }

    private func restore(_ value: Any?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
