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
        
        service = InsightsService(
            dailyLogService: dailyLogService,
            goalSettings: mockGoalSettings,
            healthKitViewModel: mockHealthKit
        )
    }
    
    override func tearDown() {
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
        
        await service.executeOperatorActions(actions, userID: "user1")
        
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
        
        let briefing = await service.generateDailyBriefing(for: "user1")
        
        XCTAssertNotNil(briefing)
        XCTAssertEqual(briefing?.title, "Morning Briefing")
        XCTAssertEqual(briefing?.body, "Good morning! Here is your plan.")
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
}
