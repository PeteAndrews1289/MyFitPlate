import XCTest
@testable import MyFitPlateCore

@MainActor
final class AchievementServiceTests: XCTestCase {
    var service: AchievementService!
    var mockRepo: MockAchievementRepository!
    var dailyLogService: DailyLogService!
    var goalSettings: GoalSettings!
    var bannerService: BannerService!
    var mockAuth: MockAuthService!

    override func setUp() {
        super.setUp()
        mockRepo = MockAchievementRepository()
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        
        DIContainer.shared.achievementRepository = mockRepo
        DIContainer.shared.authService = mockAuth
        
        service = AchievementService()
        dailyLogService = DailyLogService()
        goalSettings = GoalSettings()
        bannerService = BannerService()
    }

    override func tearDown() {
        service = nil
        mockRepo = nil
        dailyLogService = nil
        goalSettings = nil
        bannerService = nil
        mockAuth = nil
        super.tearDown()
    }

    func testSetupDependenciesInitializesAndFetchesData() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        XCTAssertTrue(service.isLoading)
        // Simulate fetch return
        mockRepo.mockStatusesPublisher.send([])
        
        let expectation = XCTestExpectation(description: "Loading finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.service.isLoading)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testListenToUserProfileUpdatesPointsAndLevel() async {
        service.listenToUserProfile(userID: "user_123")
        mockRepo.mockProfilePublisher.send((points: 150, level: 3))
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        XCTAssertEqual(service.userTotalAchievementPoints, 150)
        XCTAssertEqual(service.userAchievementLevel, 3)
    }

    func testFetchUserStatusesWithEmptyReturnsDefaults() async {
        service.fetchUserStatuses(userID: "user_123")
        mockRepo.mockStatusesPublisher.send([])
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        XCTAssertFalse(service.userStatuses.isEmpty) // Default definitions should be merged
        XCTAssertEqual(service.unlockedAchievementsCount, 0)
    }

    func testFetchUserStatusesWithExistingStatuses() async {
        service.fetchUserStatuses(userID: "user_123")
        
        let status = UserAchievementStatus(achievementID: "first_log", isUnlocked: true, unlockedDate: Date(), currentProgress: 1.0)
        mockRepo.mockStatusesPublisher.send([status])
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        XCTAssertEqual(service.unlockedAchievementsCount, 1)
        XCTAssertTrue(service.userStatuses["first_log"]?.isUnlocked == true)
    }

    func testCheckFeatureUsedAchievementUnlocks() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        
        // Let publishers emit
        mockRepo.mockStatusesPublisher.send([])
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        service.checkFeatureUsedAchievement(userID: "user_123", featureType: .featureUsed)
        
        try? await Task.sleep(nanoseconds: 10_000_000) // Wait for Task inside
        
        XCTAssertEqual(mockRepo.savedStatuses.count, 1)
        XCTAssertEqual(mockRepo.awardPointsCalledCount, 1)
    }

    func testCheckRecipeCountAchievements() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        mockRepo.mockRecipeCount = 50 // Enough to unlock early ones
        service.checkRecipeCountAchievements(userID: "user_123")
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertGreaterThan(mockRepo.savedStatuses.count, 0)
    }

    func testCheckWorkoutCountAchievements() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        mockRepo.mockWorkoutCount = 100
        service.checkWorkoutCountAchievements(userID: "user_123")
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertGreaterThan(mockRepo.savedStatuses.count, 0)
    }
    
    func testGenerateWeeklyChallenges() async {
        service.generateWeeklyChallenges(for: "user_123")
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        XCTAssertEqual(mockRepo.generatedChallenges.count, 5) // Always picks 5
    }
    
    func testUpdateChallengeProgressCompletesChallenge() async {
        var challenge = Challenge(
            id: "c1",
            title: "Test Challenge",
            description: "Desc",
            type: .calorieRange,
            goal: 5,
            progress: 4,
            pointsValue: 50,
            expiresAt: Date()
        )
        mockRepo.mockActiveChallenges = [challenge]
        
        service.updateChallengeProgress(for: "user_123", type: .calorieRange, amount: 1)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertEqual(mockRepo.updatedChallenges.count, 1)
        XCTAssertTrue(mockRepo.updatedChallenges.first?.isCompleted == true)
        XCTAssertEqual(mockRepo.awardPointsCalledCount, 1)
    }
    
    func testCheckAchievementsOnGoalSet() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        service.checkAchievementsOnGoalSet(userID: "user_123")
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let saved = mockRepo.savedStatuses.first { $0.achievementID == "goal_setter" }
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved!.isUnlocked)
    }
}
