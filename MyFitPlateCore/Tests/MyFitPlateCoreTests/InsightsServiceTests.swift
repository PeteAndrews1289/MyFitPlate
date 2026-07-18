import XCTest
@testable import MyFitPlateCore

@MainActor
final class InsightsServiceTests: XCTestCase {
    var service: InsightsService!
    var mockRepo: MockNutritionRepository!
    var mockAI: MockAIService!
    var mockAnalytics: MockAnalyticsManager!
    var mockGoalSettings: GoalSettings!
    var mockHealthKit: HealthKitViewModel!
    var dailyLogService: DailyLogService!
    
    var mockAuth: MockAuthService!
    
    override func setUp() {
        super.setUp()
        
        mockRepo = MockNutritionRepository()
        mockAI = MockAIService()
        mockAnalytics = MockAnalyticsManager()
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "testUser123"
        AIDataConsentStore.shared.grant(for: "testUser123", includesHealthData: false)
        
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.aiService = mockAI
        DIContainer.shared.analyticsManager = mockAnalytics
        DIContainer.shared.authService = mockAuth
        
        mockGoalSettings = GoalSettings()
        mockHealthKit = HealthKitViewModel()
        dailyLogService = DailyLogService()
        dailyLogService.setupDependencies(
            goalSettings: mockGoalSettings,
            bannerService: BannerService(),
            achievementService: AchievementService()
        )
        dailyLogService.activateAccount("testUser123")
        
        service = InsightsService(
            dailyLogService: dailyLogService,
            goalSettings: mockGoalSettings,
            healthKitViewModel: mockHealthKit
        )
        service.activateAccount("testUser123")
    }
    
    override func tearDown() {
        AIDataConsentStore.shared.revoke(for: "testUser123")
        service = nil
        mockRepo = nil
        mockAI = nil
        mockAnalytics = nil
        mockAuth = nil
        mockGoalSettings = nil
        mockHealthKit = nil
        dailyLogService = nil
        super.tearDown()
    }
    
    // MARK: - Daily Smart Insight
    func testGenerateDailySmartInsight() {
        // Setup state
        mockGoalSettings.protein = 150
        dailyLogService.currentDailyLog = DailyLog(id: "1", date: Date(), meals: [])
        
        service.generateDailySmartInsight()
        
        XCTAssertNotNil(service.smartSuggestion)
    }
    
    // MARK: - Generate And Fetch Insights
    func testGenerateAndFetchInsights() async {
        // Setup at least 3 logs to bypass the < 3 check
        mockRepo.mockFetchDailyHistoryResult = .success([
            DailyLog(id: "1", date: Date(), meals: []),
            DailyLog(id: "2", date: Date().addingTimeInterval(-86400), meals: []),
            DailyLog(id: "3", date: Date().addingTimeInterval(-172800), meals: [])
        ])
        
        let json = """
        {
            "insights": [
                {
                    "title": "Protein Check",
                    "message": "You are doing great.",
                    "category": "nutritionGeneral"
                }
            ]
        }
        """
        mockAI.mockResult = .success(json)
        
        service.generateAndFetchInsights(forLastDays: 7)
        
        // Wait for task
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertFalse(service.currentInsights.isEmpty)
        XCTAssertEqual(service.currentInsights.first?.title, "Protein Check")
    }

    func testGenerateAndFetchInsightsUsesLocalAnalysisWithoutAIConsent() async {
        AIDataConsentStore.shared.revoke(for: "testUser123")
        mockRepo.mockFetchDailyHistoryResult = .success([
            DailyLog(id: "1", date: Date(), meals: []),
            DailyLog(id: "2", date: Date().addingTimeInterval(-86_400), meals: []),
            DailyLog(id: "3", date: Date().addingTimeInterval(-172_800), meals: [])
        ])
        mockAI.mockResult = .success(#"{"insights":[{"title":"Remote","message":"Called","category":"nutritionGeneral"}]}"#)

        service.generateAndFetchInsights(forLastDays: 7)
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(service.currentInsights.isEmpty)
        XCTAssertTrue(mockAI.lastMessages.isEmpty, "Passive insights must not contact AI before consent.")
    }

    func testAccountSwitchCancelsPreviousAccountsDelayedInsights() async {
        mockRepo.mockFetchDailyHistoryResult = .success([
            DailyLog(id: "old-1", date: Date(), meals: []),
            DailyLog(id: "old-2", date: Date().addingTimeInterval(-86_400), meals: []),
            DailyLog(id: "old-3", date: Date().addingTimeInterval(-172_800), meals: [])
        ])
        mockRepo.fetchDailyHistoryDelayNanoseconds = 100_000_000
        mockAI.mockResult = .success(#"{"insights":[{"title":"Old account","message":"Private","category":"nutritionGeneral"}]}"#)

        service.generateAndFetchInsights()
        mockAuth.currentUserID = "new-user"
        dailyLogService.activateAccount("new-user")
        service.activateAccount("new-user")

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(service.currentInsights.isEmpty)
        XCTAssertNil(service.currentCoachingPlan)
        XCTAssertFalse(service.isLoadingInsights)
    }

    func testDelayedOperatorResponseIsDiscardedAfterAccountSwitch() async {
        mockAI.responseDelayNanoseconds = 100_000_000
        mockAI.mockResult = .success(#"{"reply":"Old account","actions":[]}"#)

        let task = Task {
            await service.processOperatorMessage(message: "Help", context: "Private old context")
        }
        await Task.yield()
        mockAuth.currentUserID = "new-user"
        service.activateAccount("new-user")

        let response = await task.value
        XCTAssertNil(response)
    }

    func testOperatorActionsCannotApplyToDifferentActiveAccount() async {
        mockGoalSettings.calories = 2_000
        mockAuth.currentUserID = "new-user"
        service.activateAccount("new-user")

        await service.executeOperatorActions([
            MaiaOperatorAction(
                actionType: "adjust_goal",
                foodName: nil,
                calories: nil,
                protein: nil,
                carbs: nil,
                fats: nil,
                target: "calories",
                value: 3_000
            )
        ], userID: "testUser123")

        XCTAssertEqual(mockGoalSettings.calories, 2_000)
    }
    
    // MARK: - Operator Actions
    func testProcessOperatorMessageSuccess() async {
        let json = """
        {
            "reply": "I adjusted your goals",
            "actions": [
                {
                    "actionType": "adjust_goal",
                    "target": "calories",
                    "value": 2500
                }
            ]
        }
        """
        mockAI.mockResult = .success(json)
        
        let response = await service.processOperatorMessage(message: "Increase my calories to 2500", context: "")
        
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.reply, "I adjusted your goals")
        XCTAssertEqual(response?.actions.first?.actionType, "adjust_goal")
        XCTAssertEqual(response?.actions.first?.value, 2500)
    }
    
    func testProcessOperatorMessageFailure() async {
        mockAI.mockResult = .failure(.apiError("test"))
        let response = await service.processOperatorMessage(message: "Increase calories", context: "")
        XCTAssertNil(response)
    }
    
    func testExecuteOperatorActions() async {
        mockGoalSettings.calories = 2000
        
        let actions = [
            MaiaOperatorAction(
                actionType: "adjust_goal",
                foodName: nil,
                calories: nil,
                protein: nil,
                carbs: nil,
                fats: nil,
                target: "calories",
                value: 2500
            ),
            MaiaOperatorAction(
                actionType: "log_food",
                foodName: "Apple",
                calories: 95,
                protein: 0,
                carbs: 25,
                fats: 0,
                target: nil,
                value: nil
            )
        ]
        
        await service.executeOperatorActions(actions, userID: "testUser123")
        
        XCTAssertEqual(mockGoalSettings.calories, 2500)
    }
    
    // MARK: - Single Meal Suggestion
    func testGenerateSingleMealSuggestion() async {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "title": "High Protein Dinner",
            "mealName": "Chicken Salad",
            "calories": 400,
            "protein": 30,
            "carbs": 20,
            "fats": 10,
            "ingredients": ["Chicken", "Lettuce"],
            "instructions": "Mix it"
        }
        """
        mockAI.mockResult = .success(json)
        
        let suggestion = await service.generateSingleMealSuggestion()
        
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.mealName, "Chicken Salad")
        XCTAssertEqual(suggestion?.calories, 400)
    }
    
    // MARK: - Daily Briefing
    func testGenerateDailyBriefing() async {
        let json = """
        {
            "title": "Morning Briefing",
            "body": "Good morning! Here is your plan."
        }
        """
        mockAI.mockResult = .success(json)
        
        let briefing = await service.generateDailyBriefing(for: "testUser123", wellnessScoreSummary: "Fair recovery", todaysWorkout: "Push day")

        XCTAssertNotNil(briefing)
        XCTAssertEqual(briefing?.title, "Morning Briefing")
        XCTAssertEqual(briefing?.body, "Good morning! Here is your plan.")
    }

    func testGenerateDailyBriefingLogsAndReturnsNilOnMalformedResponse() async {
        mockAI.mockResult = .success("not json at all")
        let briefing = await service.generateDailyBriefing(for: "testUser123", wellnessScoreSummary: "Fair", todaysWorkout: "Rest")
        XCTAssertNil(briefing, "A malformed AI response yields nil, not a crash")
    }
    
    // MARK: - Smart Notification
    func testGenerateSmartNotification() async {
        let json = """
        {
            "title": "Drink Water",
            "body": "Stay hydrated today."
        }
        """
        mockAI.mockResult = .success(json)
        
        let context = InsightsService.NotificationContext(
            gender: "Male",
            phase: nil,
            wellnessScore: 80,
            sleepScore: 85,
            caloriesRemaining: 1500,
            proteinRemaining: 80,
            daysSinceLastWorkout: 1,
            lastWorkoutName: "Legs",
            stepsToday: 5000,
            activeEnergyToday: 400
        )
        
        let notification = await service.generateSmartNotification(context: context)
        
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.title, "Drink Water")
        XCTAssertEqual(notification?.body, "Stay hydrated today.")
    }

    func testSmartNotificationOmitsHealthSignalsWithoutHealthSharingConsent() async throws {
        AIDataConsentStore.shared.grant(for: "testUser123", includesHealthData: false)
        mockAI.mockResult = .success(#"{"title":"Plan","body":"Keep going."}"#)
        let context = InsightsService.NotificationContext(
            gender: "Unspecified",
            phase: nil,
            wellnessScore: 13,
            sleepScore: 17,
            caloriesRemaining: 0,
            proteinRemaining: 0,
            daysSinceLastWorkout: 0,
            lastWorkoutName: nil,
            stepsToday: 12_345,
            activeEnergyToday: 678
        )

        _ = await service.generateSmartNotification(context: context)

        let prompt = try XCTUnwrap(mockAI.lastMessages.first?["content"] as? String)
        XCTAssertFalse(prompt.contains("Wellness Score is low (13)"))
        XCTAssertFalse(prompt.contains("sleep score is low (17)"))
        XCTAssertFalse(prompt.contains("12345 steps"))
    }

    func testSmartNotificationDoesNotContactAIWithoutConsent() async {
        AIDataConsentStore.shared.revoke(for: "testUser123")
        let context = InsightsService.NotificationContext(
            gender: "Unspecified",
            phase: nil,
            wellnessScore: nil,
            sleepScore: nil,
            caloriesRemaining: 500,
            proteinRemaining: 30,
            daysSinceLastWorkout: 2,
            lastWorkoutName: nil,
            stepsToday: 0,
            activeEnergyToday: 0
        )

        let notification = await service.generateSmartNotification(context: context)

        XCTAssertNil(notification)
        XCTAssertTrue(mockAI.lastMessages.isEmpty)
    }

    func testSmartNotificationIncludesHealthSignalsWhenHealthSharingIsAllowed() async throws {
        AIDataConsentStore.shared.grant(for: "testUser123", includesHealthData: true)
        mockAI.mockResult = .success(#"{"title":"Plan","body":"Take it easy."}"#)
        let context = InsightsService.NotificationContext(
            gender: "Unspecified",
            phase: nil,
            wellnessScore: 13,
            sleepScore: 17,
            caloriesRemaining: 0,
            proteinRemaining: 0,
            daysSinceLastWorkout: 0,
            lastWorkoutName: nil,
            stepsToday: 12_345,
            activeEnergyToday: 678
        )

        _ = await service.generateSmartNotification(context: context)

        let prompt = try XCTUnwrap(mockAI.lastMessages.first?["content"] as? String)
        XCTAssertTrue(prompt.contains("Wellness Score is low (13)"))
    }

    func testEvaluateRunRecoveryPrompt() async {
        let run = Run(source: .recorded, startDate: Date().addingTimeInterval(-1800), endDate: Date(), distanceMeters: 5000, movingSeconds: 1800, activeCalories: 350)
        await MainActor.run {
            service.evaluateRunRecoveryPrompt(recentRun: run)
            XCTAssertNotNil(service.currentRunRecoveryPrompt)
            XCTAssertEqual(service.currentRunRecoveryPrompt?.runID, run.id)

            service.evaluateRunRecoveryPrompt(recentRun: nil)
            XCTAssertNil(service.currentRunRecoveryPrompt)
        }
    }
}
