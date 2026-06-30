import HealthKit
import XCTest
@testable import MyFitPlateCore

final class GoalSettingsBehaviorTests: XCTestCase {
    @MainActor
    func testMifflinCalculationForMaleMaintenanceGoal() async {
        let settings = makeSettings()
        settings.gender = "Male"
        settings.age = 25
        settings.weight = 180
        settings.height = 180
        settings.activityLevel = 1.2
        settings.goal = "Maintain"
        settings.calorieGoalMethod = .mifflinWithActivity

        settings.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(settings.calories ?? 0, 2_185.76, accuracy: 1.0)
    }

    @MainActor
    func testMifflinCalculationForFemaleWeightLossGoal() async {
        let settings = makeSettings()
        settings.gender = "Female"
        settings.age = 30
        settings.weight = 140
        settings.height = 165
        settings.activityLevel = 1.55
        settings.goal = "Lose"
        settings.calorieGoalMethod = .mifflinWithActivity

        settings.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(settings.calories ?? 0, 1_850.68, accuracy: 1.0)
    }

    @MainActor
    func testCustomCalorieGoalIsPreservedAndFloored() async {
        let male = makeSettings()
        male.gender = "Male"
        male.calorieGoalMethod = .custom
        male.calories = 2_500

        male.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(male.calories ?? 0, 2_500, accuracy: 0.001)

        let female = makeSettings()
        female.gender = "Female"
        female.calorieGoalMethod = .custom
        female.calories = 800

        female.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(female.calories ?? 0, 1_200, accuracy: 0.001)
    }

    @MainActor
    func testMacroTargetsFollowConfiguredPercentages() async {
        let settings = makeSettings()
        settings.calorieGoalMethod = .custom
        settings.calories = 2_000
        settings.proteinPercentage = 25
        settings.carbsPercentage = 45
        settings.fatsPercentage = 30

        settings.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(settings.protein, 125, accuracy: 0.001)
        XCTAssertEqual(settings.carbs, 225, accuracy: 0.001)
        XCTAssertEqual(settings.fats, 66.67, accuracy: 0.01)
    }

    @MainActor
    func testInvalidMacroPercentagesResetToDefaults() async {
        let settings = makeSettings()
        settings.calorieGoalMethod = .custom
        settings.calories = 2_000
        settings.proteinPercentage = 40
        settings.carbsPercentage = 40
        settings.fatsPercentage = 40

        settings.recalculateAllGoals()
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(settings.proteinPercentage, 30, accuracy: 0.001)
        XCTAssertEqual(settings.carbsPercentage, 50, accuracy: 0.001)
        XCTAssertEqual(settings.fatsPercentage, 20, accuracy: 0.001)
        XCTAssertEqual(settings.protein, 150, accuracy: 0.001)
        XCTAssertEqual(settings.carbs, 250, accuracy: 0.001)
        XCTAssertEqual(settings.fats, 44.44, accuracy: 0.01)
    }

    @MainActor
    func testMicronutrientGoalsReflectAgeAndGender() async {
        let adultFemale = makeSettings()
        adultFemale.gender = "Female"
        adultFemale.age = 30

        adultFemale.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(adultFemale.calciumGoal ?? 0, 1_000, accuracy: 0.001)
        XCTAssertEqual(adultFemale.ironGoal ?? 0, 18, accuracy: 0.001)
        XCTAssertEqual(adultFemale.potassiumGoal ?? 0, 2_600, accuracy: 0.001)
        XCTAssertEqual(adultFemale.vitaminAGoal ?? 0, 700, accuracy: 0.001)
        XCTAssertEqual(adultFemale.vitaminCGoal ?? 0, 75, accuracy: 0.001)

        let olderMale = makeSettings()
        olderMale.gender = "Male"
        olderMale.age = 72

        olderMale.recalculateAllGoals()
        await drainMainQueue()

        XCTAssertEqual(olderMale.calciumGoal ?? 0, 1_200, accuracy: 0.001)
        XCTAssertEqual(olderMale.ironGoal ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(olderMale.vitaminDGoal ?? 0, 20, accuracy: 0.001)
    }

    @MainActor
    func testHeightHelpersRoundTripFeetAndInches() async {
        let settings = makeSettings()
        settings.height = 177.8

        XCTAssertEqual(settings.getHeightInFeetAndInches().feet, 5)
        XCTAssertEqual(settings.getHeightInFeetAndInches().inches, 10)

        settings.setHeight(feet: 6, inches: 1)
        await drainMainQueue()

        XCTAssertEqual(settings.height, 185.42, accuracy: 0.001)
    }

    @MainActor
    func testWeightProgressHandlesLossGainAndCompletedTargets() {
        let loss = makeSettings()
        loss.weightHistory = [weightEntry(daysAgo: 30, weight: 180)]
        loss.weight = 170
        loss.targetWeight = 160
        XCTAssertEqual(loss.calculateWeightProgress() ?? 0, 50, accuracy: 0.001)

        let gain = makeSettings()
        gain.weightHistory = [weightEntry(daysAgo: 30, weight: 160)]
        gain.weight = 170
        gain.targetWeight = 180
        XCTAssertEqual(gain.calculateWeightProgress() ?? 0, 50, accuracy: 0.001)

        let completed = makeSettings()
        completed.weightHistory = [weightEntry(daysAgo: 30, weight: 180)]
        completed.weight = 155
        completed.targetWeight = 160
        XCTAssertEqual(completed.calculateWeightProgress() ?? 0, 100, accuracy: 0.001)

        let noTarget = makeSettings()
        XCTAssertNil(noTarget.calculateWeightProgress())
    }

    @MainActor
    func testWeightProgressWhenInitialAndTargetMatch() {
        let onTarget = makeSettings()
        onTarget.weightHistory = [weightEntry(daysAgo: 10, weight: 170)]
        onTarget.weight = 170
        onTarget.targetWeight = 170
        XCTAssertEqual(onTarget.calculateWeightProgress() ?? 0, 100, accuracy: 0.001)

        let offTarget = makeSettings()
        offTarget.weightHistory = [weightEntry(daysAgo: 10, weight: 170)]
        offTarget.weight = 172
        offTarget.targetWeight = 170
        XCTAssertEqual(offTarget.calculateWeightProgress() ?? 0, 0, accuracy: 0.001)
    }

    @MainActor
    func testWeightStatsAndWeeklyChangeUseRecentChronologicalData() {
        let settings = makeSettings()
        let period = [
            weightEntry(daysAgo: 10, weight: 160),
            weightEntry(daysAgo: 5, weight: 158),
            weightEntry(daysAgo: 0, weight: 156)
        ]

        let stats = settings.getWeightStats(for: period)
        XCTAssertEqual(stats.highest ?? 0, 160, accuracy: 0.001)
        XCTAssertEqual(stats.lowest ?? 0, 156, accuracy: 0.001)
        XCTAssertEqual(stats.trend ?? 0, -4, accuracy: 0.001)
        XCTAssertEqual(stats.dailyRate ?? 0, -0.4, accuracy: 0.001)

        settings.weightHistory = [
            weightEntry(daysAgo: 50, weight: 190),
            weightEntry(daysAgo: 21, weight: 180),
            weightEntry(daysAgo: 0, weight: 174)
        ]
        XCTAssertEqual(settings.calculateWeeklyWeightChange() ?? 0, -2, accuracy: 0.05)
    }

    @MainActor
    func testCheckInReadinessRequiresAdaptiveGoalConfidenceAndSevenDays() {
        let settings = makeSettings()
        let adaptiveGoalService = AdaptiveGoalService()
        settings.adaptiveGoalService = adaptiveGoalService
        adaptiveGoalService.dataConfidence = .high

        settings.calorieGoalMethod = .mifflinWithActivity
        XCTAssertFalse(settings.isCheckInReady)

        settings.calorieGoalMethod = .dynamicTDEE
        settings.lastCheckInDate = nil
        XCTAssertTrue(settings.isCheckInReady)

        settings.lastCheckInDate = date(daysAgo: 3)
        XCTAssertFalse(settings.isCheckInReady)

        settings.lastCheckInDate = date(daysAgo: 8)
        XCTAssertTrue(settings.isCheckInReady)

        adaptiveGoalService.dataConfidence = .low
        XCTAssertFalse(settings.isCheckInReady)
    }

    @MainActor
    func testDynamicTDEECalorieCalculation() async {
        let settings = makeSettings()
        let adaptiveService = AdaptiveGoalService()
        settings.adaptiveGoalService = adaptiveService
        adaptiveService.calculatedTDEE = 2_500
        
        settings.goal = "Lose"
        settings.calorieGoalMethod = .dynamicTDEE
        
        settings.recalculateAllGoals()
        await drainMainQueue()
        
        // 2500 - 250 = 2250
        XCTAssertEqual(settings.calories ?? 0, 2_250, accuracy: 1.0)
    }

    @MainActor
    func testLoadUserGoalsSuccess() async {
        let settings = makeSettings()
        let mockRepo = MockSettingsRepository()
        DIContainer.shared.settingsRepository = mockRepo
        
        mockRepo.mockFetchUserGoalsResult = [
            "weight": 190.0,
            "height": 182.0,
            "age": 35,
            "gender": "Male",
            "calorieGoalMethod": CalorieGoalMethod.dynamicTDEE.rawValue,
            "goals": [
                "proteinPercentage": 35.0,
                "carbsPercentage": 45.0,
                "fatsPercentage": 20.0,
                "goal": "Build Muscle",
                "targetWeight": 200.0,
                "suggestionProteins": ["Chicken"],
                "lastCheckInDate": Date()
            ]
        ]
        
        let expectation = XCTestExpectation(description: "load")
        settings.loadUserGoals(userID: "user_123") {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(settings.weight, 190.0)
        XCTAssertEqual(settings.height, 182.0)
        XCTAssertEqual(settings.age, 35)
        XCTAssertEqual(settings.gender, "Male")
        XCTAssertEqual(settings.calorieGoalMethod, .dynamicTDEE)
        XCTAssertEqual(settings.proteinPercentage, 35.0)
        XCTAssertEqual(settings.goal, "Build Muscle")
        XCTAssertEqual(settings.targetWeight, 200.0)
        XCTAssertEqual(settings.suggestionProteins, ["Chicken"])
    }

    @MainActor
    func testLoadUserGoalsBackwardCompatibility() async {
        let settings = makeSettings()
        let mockRepo = MockSettingsRepository()
        DIContainer.shared.settingsRepository = mockRepo
        
        // Tests the top-level "targetWeight" moving into "goals" map
        mockRepo.mockFetchUserGoalsResult = [
            "targetWeight": 150.0,
            "goals": [:]
        ]
        
        let expectation = XCTestExpectation(description: "load_compat")
        settings.loadUserGoals(userID: "user_123") {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(settings.targetWeight, 150.0)
    }

    @MainActor
    func testSaveUserGoals() async throws {
        let settings = makeSettings()
        let mockRepo = MockSettingsRepository()
        DIContainer.shared.settingsRepository = mockRepo
        
        settings.weight = 160
        settings.goal = "Lose"
        
        let exp = expectation(description: "saveUserGoals")
        mockRepo.onSave = {
            exp.fulfill()
        }
        
        settings.saveUserGoals(userID: "user_456")
        await drainMainQueue()
        
        await fulfillment(of: [exp], timeout: 2.0)
        
        let savedData = mockRepo.savedUserGoals
        XCTAssertNotNil(savedData)
        XCTAssertEqual(savedData?["weight"] as? Double, 160.0)
        
        let goalsMap = savedData?["goals"] as? [String: Any]
        XCTAssertEqual(goalsMap?["goal"] as? String, "Lose")
    }

    @MainActor
    func testSetupDependencies() {
        let settings = makeSettings()
        let service = DailyLogService()
        settings.setupDependencies(dailyLogService: service)
        XCTAssertNotNil(settings.dailyLogService)
    }

    @MainActor
    private func makeSettings() -> GoalSettings {
        GoalSettings(healthKitManager: MockCoreHealthKitManager())
    }

    private func weightEntry(daysAgo: Int, weight: Double) -> (id: String, date: Date, weight: Double) {
        ("weight-\(daysAgo)", date(daysAgo: daysAgo), weight)
    }

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class MockCoreHealthKitManager: HealthKitManaging {
    private(set) var savedWeightSamples: [(weight: Double, date: Date)] = []

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        completion(true, nil)
    }

    func fetchWorkouts(for date: Date, completion: @escaping ([HKWorkout]?, Error?) -> Void) {
        completion([], nil)
    }

    func fetchSleepAnalysis(startDate: Date, endDate: Date, completion: @escaping ([HKCategorySample]?, Error?) -> Void) {
        completion([], nil)
    }

    func fetchLatestRestingHeartRate(completion: @escaping (HKQuantitySample?) -> Void) {
        completion(nil)
    }

    func fetchLatestHRV(completion: @escaping (HKQuantitySample?) -> Void) {
        completion(nil)
    }

    func fetchTodaySteps(completion: @escaping (Double) -> Void) {
        completion(5_000)
    }

    func fetchTodayActiveEnergy(completion: @escaping (Double) -> Void) {
        completion(300)
    }

    func fetchBiologicalSex() -> HKBiologicalSexObject? {
        nil
    }

    func fetchTodayDistance(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func fetchTodayFlights(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func fetchTodayExerciseTime(completion: @escaping (Double) -> Void) {
        completion(0)
    }

    func saveNutrition(for foodItem: FoodItem) {}

    func appFoodMetadataPredicate(for foodItem: FoodItem) -> NSPredicate {
        NSPredicate(value: true)
    }

    func deleteNutrition(for foodItem: FoodItem, completion: ((Bool) -> Void)?) {
        completion?(true)
    }

    func replaceNutrition(oldItem: FoodItem, newItem: FoodItem) {}

    func saveWeightSample(weightLbs: Double, date: Date) {
        savedWeightSamples.append((weightLbs, date))
    }
}

final class GoalSettingsAdditionalTests: XCTestCase {
    var settings: GoalSettings!
    var mockRepo: MockSettingsRepository!
    
    @MainActor
    override func setUp() {
        super.setUp()
        settings = GoalSettings(healthKitManager: MockCoreHealthKitManager())
        mockRepo = MockSettingsRepository()
        DIContainer.shared.settingsRepository = mockRepo
        let mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        DIContainer.shared.authService = mockAuth
    }
    
    @MainActor
    func testApplyWeeklyCheckIn() {
        settings.gender = "Male"
        settings.weight = 100
        settings.height = 150.0
        settings.age = 30
        settings.activityLevel = 1.2
        
        let exp = expectation(description: "Wait for async")
        mockRepo.onSave = {
            exp.fulfill()
        }
        
        settings.applyWeeklyCheckIn(userID: "user_123", newCalories: 1000)
        
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertEqual(settings.calories ?? 0, 1500) // Minimum for male
        XCTAssertNotNil(settings.lastCheckInDate)
    }
    
    @MainActor
    func testUpdateUserWeight() {
        settings.weightHistory = []
        settings.updateUserWeight(185.0)
        
        let dispatchExp = expectation(description: "dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dispatchExp.fulfill()
        }
        wait(for: [dispatchExp], timeout: 1.0)
        
        XCTAssertEqual(settings.weight, 185.0)
    }
    
    @MainActor
    func testDeleteWeightEntry() {
        let exp = expectation(description: "Completion called")
        settings.deleteWeightEntry(entryID: "entry1") { error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        
        wait(for: [exp], timeout: 1.0)
    }
}
