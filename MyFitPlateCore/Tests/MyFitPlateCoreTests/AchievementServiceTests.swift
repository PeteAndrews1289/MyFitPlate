import XCTest
import Combine
@testable import MyFitPlateCore

@MainActor
final class AchievementServiceTests: XCTestCase {
    var service: AchievementService!
    var mockRepo: MockAchievementRepository!
    var dailyLogService: DailyLogService!
    var goalSettings: GoalSettings!
    var bannerService: BannerService!
    var mockAuth: MockAuthService!
    private var directory: URL!
    private var awardStore: AchievementAwardStore!
    private var settings: MockSettingsRepository!
    private var nutrition: MockNutritionRepository!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepo: AchievementRepositoryProtocol?
    private var previousSettings: SettingsRepositoryProtocol?
    private var previousNutrition: NutritionRepositoryProtocol?

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepo = DIContainer.shared.achievementRepository
        previousSettings = DIContainer.shared.settingsRepository; previousNutrition = DIContainer.shared.nutritionRepository
        mockRepo = MockAchievementRepository()
        settings = MockSettingsRepository(); nutrition = MockNutritionRepository()
        DIContainer.shared.settingsRepository = settings; DIContainer.shared.nutritionRepository = nutrition
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        awardStore = AchievementAwardStore(store: EditorDraftStore(directory: directory))
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        
        DIContainer.shared.achievementRepository = mockRepo
        DIContainer.shared.authService = mockAuth
        
        service = AchievementService(awardStore: awardStore)
        service.activateAccount("user_123")
        dailyLogService = DailyLogService()
        goalSettings = GoalSettings()
        bannerService = BannerService()
    }

    override func tearDown() {
        service?.activateAccount(nil)
        service = nil
        DIContainer.shared.authService = previousAuth; DIContainer.shared.achievementRepository = previousRepo
        DIContainer.shared.settingsRepository = previousSettings; DIContainer.shared.nutritionRepository = previousNutrition
        try? FileManager.default.removeItem(at: directory)
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
        
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "accepted-barcode-food", name: "Yogurt", calories: 150), date: Date(), source: "barcode_scan")
        
        await service.awardDrainTask?.value
        
        XCTAssertEqual(Set(mockRepo.savedStatuses.filter(\.isUnlocked).map(\.achievementID)), ["first_log", "scanner_pro"])
        XCTAssertEqual(mockRepo.acceptedAwardCount, 2)
        XCTAssertEqual(mockRepo.awardPointsCalledCount, 0)
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
        let challenge = Challenge(
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
    
    func testCheckAchievementsOnGoalSet() async throws {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        let accepted = expectation(description: "Saved goal achievement published")
        let observation = service.$userStatuses
            .first { $0["goal_setter"]?.isUnlocked == true }
            .sink { _ in accepted.fulfill() }
        defer { observation.cancel() }

        settings.mockFetchUserGoalsResult = ["calories": 2_000.0, "protein": 150.0, "carbs": 200.0, "fats": 60.0]
        service.checkAchievementsOnGoalSet(userID: "user_123")
        await fulfillment(of: [accepted], timeout: 5)
        let saved = try XCTUnwrap(mockRepo.savedStatuses.first { $0.achievementID == "goal_setter" })
        XCTAssertTrue(saved.isUnlocked)
    }
    
    func testCheckAchievementsOnLogUpdate() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        let date = Date()
        let log = DailyLog(id: DiaryDayContext.dayKey(for: date), date: date,
            meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "accepted-food", name: "Rice", calories: 200)])])
        let mockNutRepo = DIContainer.shared.nutritionRepository as? MockNutritionRepository ?? MockNutritionRepository()
        mockNutRepo.mockFetchLogResult = .success(log)
        DIContainer.shared.nutritionRepository = mockNutRepo
        
        goalSettings.calories = 2000
        goalSettings.protein = 150
        
        service.checkAchievementsOnLogUpdate(userID: "user_123", logDate: date)
        
        let exp = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 1.0)
        
        // At least first log should be unlocked
        let firstLogUnlocked = mockRepo.savedStatuses.contains { $0.achievementID == "first_log" && $0.isUnlocked }
        XCTAssertTrue(firstLogUnlocked)
    }
    
    func testCheckAchievementsOnWeightUpdate() async throws {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        mockRepo.mockStatusesPublisher.send([])
        mockRepo.awardDelayNanoseconds = 30_000_000
        settings.mockWeightHistory = [(id: "saved-measurement", date: Date().addingTimeInterval(-60), weight: 180)]
        let accepted = expectation(description: "Atomic saved-weight milestone accepted and published")
        let observation = service.$userStatuses
            .first { $0["on_the_weigh"]?.isUnlocked == true }
            .sink { _ in accepted.fulfill() }
        service.checkAchievementsOnWeightUpdate(userID: "user_123")
        await fulfillment(of: [accepted], timeout: 5)
        withExtendedLifetime(observation) {}
        let status = try XCTUnwrap(mockRepo.savedStatuses.first { $0.achievementID == "on_the_weigh" && $0.isUnlocked })
        XCTAssertEqual(status.awardEvidence?.sourceID, "saved-measurement")
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
        XCTAssertEqual(service.pendingAwardCount, 0)
    }

    func testAcceptedPhotoBulkPreservesExplicitFeatureSourceThroughNutritionNormalization() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        dailyLogService.activateAccount("user_123")
        let date = Date()
        nutrition.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: date), date: date, meals: []).rememberingMutationBase())
        let food = FoodItem(id: "reviewed-photo-food", name: "Photo rice", calories: 200, protein: 5, carbs: 40, fats: 2,
            sourceMetadata: FoodSourceMetadata(sourceType: .aiImage, confidence: .estimated, reviewStatus: .userConfirmed))
        let published = expectation(description: "Reviewed photo achievement published")
        let observation = service.$userStatuses
            .first { $0["picture_perfect"]?.isUnlocked == true }
            .sink { _ in published.fulfill() }
        defer { observation.cancel() }
        let accepted = await withCheckedContinuation { continuation in
            dailyLogService.addMealGroupsToLog(for: "user_123", date: date, mealGroups: [("Lunch", [food])], source: "ai_image") {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(accepted)
        await fulfillment(of: [published], timeout: 5)
        let award = mockRepo.savedStatuses.first { $0.achievementID == "picture_perfect" && $0.isUnlocked }
        XCTAssertEqual(award?.awardEvidence?.facts?["foodID"], "reviewed-photo-food")
        XCTAssertEqual(award?.awardEvidence?.facts?["source"], "ai_image")
        XCTAssertFalse(mockRepo.savedStatuses.contains { $0.achievementID == "ai_chef" && $0.isUnlocked })
    }

    func testEmptyDiaryDefaultWeightAndUnprovenFeatureCannotUnlockMilestones() async {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        let date = Date()
        nutrition.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: date), date: date, meals: []))
        service.checkAchievementsOnLogUpdate(userID: "user_123", logDate: date)
        service.checkAchievementsOnWeightUpdate(userID: "user_123")
        service.checkFeatureUsedAchievement(userID: "user_123", featureType: .featureUsed)
        service.checkFeatureUsedAchievement(userID: "user_123", featureType: .barcodeScanUsed)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(mockRepo.acceptedAwardCount, 0)
        XCTAssertFalse(mockRepo.savedStatuses.contains(where: \.isUnlocked))
    }

    func testFailedAwardSurvivesServiceRecreationAndRetryAddsPointsExactlyOnce() async throws {
        mockRepo.awardError = AchievementAwardError.unavailable
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "accepted-food", name: "Rice", calories: 200), date: Date(), source: "manual")
        await service.awardDrainTask?.value
        XCTAssertEqual(service.pendingAwardCount, 1)
        XCTAssertFalse(service.userStatuses["first_log"]?.isUnlocked == true)
        let kept = try XCTUnwrap(awardStore.pending(userID: "user_123").first)
        service = AchievementService(awardStore: awardStore)
        service.activateAccount("user_123")
        await service.awardDrainTask?.value
        XCTAssertEqual(try awardStore.pending(userID: "user_123").first, kept)
        mockRepo.awardError = nil; mockRepo.awardFailureAfterCommit = AchievementAwardError.unavailable
        service.retryPendingAwards()
        await service.awardDrainTask?.value
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
        XCTAssertEqual(service.pendingAwardCount, 1)
        mockRepo.awardFailureAfterCommit = nil
        service.retryPendingAwards()
        await service.awardDrainTask?.value
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
        XCTAssertEqual(service.pendingAwardCount, 0)
        XCTAssertEqual(service.userTotalAchievementPoints, 10)
        XCTAssertEqual(service.userStatuses["first_log"]?.awardEvidence?.facts?["foodID"], "accepted-food")
    }

    func testOneUnreadableSourceDoesNotStarveIndependentMilestoneAndRetryRemainsBounded() async throws {
        mockRepo.awardErrorsByID["first_log"] = AchievementAwardError.evidenceUnavailable
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "barcode-food", name: "Yogurt", calories: 150), date: Date(), source: "barcode_scan")
        await service.awardDrainTask?.value
        XCTAssertEqual(service.pendingAwardCount, 1)
        XCTAssertNil(service.userStatuses["first_log"]?.awardEvidence)
        XCTAssertTrue(service.userStatuses["scanner_pro"]?.isUnlocked == true)
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
        XCTAssertEqual(service.userTotalAchievementPoints, 20)
        mockRepo.awardErrorsByID = [:]; service.retryPendingAwards()
        await service.awardDrainTask?.value
        XCTAssertEqual(service.pendingAwardCount, 0)
        XCTAssertEqual(mockRepo.acceptedAwardCount, 2)
        XCTAssertEqual(service.userTotalAchievementPoints, 30)
    }

    func testInvalidAwardLedgerStopsOwnerQueueWithoutDiscardingOtherRequests() async throws {
        mockRepo.awardError = AchievementAwardError.invalid
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "barcode-food", name: "Yogurt", calories: 150), date: Date(), source: "barcode_scan")
        await service.awardDrainTask?.value
        XCTAssertEqual(service.pendingAwardCount, 2)
        XCTAssertEqual(mockRepo.acceptedAwardCount, 0)
        XCTAssertEqual(try awardStore.pending(userID: "user_123").count, 2)
    }

    func testUndoneFoodEvidenceRetiresAndNewFoodArrivingInFlightStillAwardsExactlyOnce() async throws {
        mockRepo.awardErrorsByFoodID["undone-food"] = AchievementAwardError.evidenceNoLongerEligible
        mockRepo.beforeAcceptAward = { [service] command in
            guard command.evidence.facts?["foodID"] == "undone-food" else { return }
            service?.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "kept-food", name: "Kept rice", calories: 200), date: Date(), source: "manual")
        }
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "undone-food", name: "Removed rice", calories: 200), date: Date(), source: "manual")
        await service.awardDrainTask?.value
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
        XCTAssertEqual(service.userTotalAchievementPoints, 10)
        XCTAssertEqual(service.pendingAwardCount, 0)
        XCTAssertEqual(service.userStatuses["first_log"]?.awardEvidence?.facts?["foodID"], "kept-food")
        XCTAssertEqual(try awardStore.retiredEvidence(userID: "user_123").first?.command.evidence.facts?["foodID"], "undone-food")
        service.retryPendingAwards()
        await service.awardDrainTask?.value
        XCTAssertEqual(mockRepo.acceptedAwardCount, 1)
    }

    func testLoggingStreakUsesAcceptedCivilKeysAcrossTravelMidnightOffsets() async throws {
        service.setupDependencies(dailyLogService: dailyLogService, goalSettings: goalSettings, bannerService: bannerService)
        var remote = Calendar(identifier: .gregorian)
        remote.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let today = Calendar.current.startOfDay(for: Date())
        let logs = try (0..<3).map { offset -> DailyLog in
            let localDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -offset, to: today))
            let key = try XCTUnwrap(DiaryDayContext.dayKey(for: localDay))
            var components = Calendar.current.dateComponents([.year, .month, .day], from: localDay)
            components.hour = 0
            let remoteMidnight = try XCTUnwrap(remote.date(from: components))
            return DailyLog(id: key, date: offset == 2 ? localDay : remoteMidnight,
                meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "food-\(offset)", name: "Rice", calories: 200)])])
        }
        nutrition.mockFetchLogResult = .success(logs[0]); nutrition.mockFetchDailyHistoryResult = .success(logs)
        service.checkAchievementsOnLogUpdate(userID: "user_123", logDate: today, dayKey: logs[0].id)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let status = mockRepo.savedStatuses.first { $0.achievementID == "log_streak_3" && $0.isUnlocked }
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.awardEvidence?.facts?["dayKeys"], logs.compactMap(\.id).joined(separator: ","))
    }

    func testAccountChangeDuringAwardCannotPublishOrClearOriginalPendingEvidence() async throws {
        mockRepo.beforeAcceptAward = { [mockAuth, service] _ in
            mockAuth?.currentUserID = "user_456"
            service?.activateAccount("user_456")
        }
        service.checkAcceptedFood(userID: "user_123", food: FoodItem(id: "old-food", name: "Rice", calories: 200), date: Date(), source: "manual")
        await service.awardDrainTask?.value
        XCTAssertEqual(service.pendingAwardCount, 0)
        XCTAssertTrue(service.userStatuses.isEmpty)
        XCTAssertEqual(try awardStore.pending(userID: "user_123").count, 1)
        XCTAssertTrue(try awardStore.pending(userID: "user_456").isEmpty)
    }

    func testAccountSwitchClearsPublishedStateAndDetachesPreviousPublishers() async {
        service.listenToUserProfile(userID: "user_123")
        mockRepo.mockProfilePublisher.send((points: 150, level: 3))
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(service.userTotalAchievementPoints, 150)

        mockAuth.currentUserID = "user_456"
        service.activateAccount("user_456")
        mockRepo.mockProfilePublisher.send((points: 999, level: 9))
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(service.userTotalAchievementPoints, 0)
        XCTAssertEqual(service.userAchievementLevel, 1)
        XCTAssertTrue(service.userStatuses.isEmpty)
        XCTAssertTrue(service.activeChallenges.isEmpty)
    }
}
