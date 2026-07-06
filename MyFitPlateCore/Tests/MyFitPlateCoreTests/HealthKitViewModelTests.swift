import XCTest
import HealthKit
import Combine
@testable import MyFitPlateCore

@MainActor
final class HealthKitViewModelTests: XCTestCase {
    var mockManager: MockHealthKitManager!
    var viewModel: HealthKitViewModel!
    var dailyLogService: DailyLogService!

    override func setUp() {
        super.setUp()
        let mockAuth = MockAuthService()
        mockAuth.currentUserID = "testUser123"
        DIContainer.shared.authService = mockAuth
        DIContainer.shared.nutritionRepository = MockNutritionRepository()
        mockManager = MockHealthKitManager()
        viewModel = HealthKitViewModel(manager: mockManager)
        dailyLogService = DailyLogService()
    }

    override func tearDown() {
        viewModel = nil
        mockManager = nil
        dailyLogService = nil
        super.tearDown()
    }

    func testCheckAuthorizationStatusUnnecessary() {
        mockManager.authorizationStatusResult = .unnecessary
        let exp = expectation(description: "Auth check")
        viewModel.setup(dailyLogService: dailyLogService)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.isAuthorized)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testCheckAuthorizationStatusShouldRequest() {
        mockManager.authorizationStatusResult = .shouldRequest
        let exp = expectation(description: "Auth check")
        viewModel.setup(dailyLogService: dailyLogService)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isAuthorized)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testCheckAuthorizationStatusUnknown() {
        mockManager.authorizationStatusResult = .unknown
        let exp = expectation(description: "Auth check")
        viewModel.setup(dailyLogService: dailyLogService)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isAuthorized)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testCheckAuthorizationStatusError() {
        mockManager.authorizationStatusError = NSError(domain: "test", code: 1, userInfo: nil)
        let exp = expectation(description: "Auth check")
        viewModel.setup(dailyLogService: dailyLogService)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isAuthorized)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testRequestAuthorizationSuccess() {
        mockManager.requestAuthorizationSuccess = true
        let exp = expectation(description: "Req auth")
        viewModel.requestAuthorization()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.viewModel.isAuthorized)
            XCTAssertNil(self.viewModel.authError)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testRequestAuthorizationFailure() {
        mockManager.requestAuthorizationSuccess = false
        mockManager.requestAuthorizationError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let exp = expectation(description: "Req auth fail")
        viewModel.requestAuthorization()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isAuthorized)
            XCTAssertEqual(self.viewModel.authError, "Permission denied")
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSyncAllHealthDataWhenNotAuthorized() {
        viewModel.isAuthorized = false
        viewModel.syncAllHealthData()
        XCTAssertEqual(viewModel.workouts.count, 0)
    }

    func testFetchTodayWorkoutsSuccess() {
        viewModel.setup(dailyLogService: dailyLogService)
        viewModel.isAuthorized = true
        
        // Setup mock workouts
        let w1 = HKWorkout(activityType: .running, start: Date().addingTimeInterval(-3600), end: Date(), workoutEvents: nil, totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 450), totalDistance: nil, metadata: nil)
        mockManager.workoutsResult = [w1]
        
        let exp = expectation(description: "Fetch workouts")
        viewModel.fetchTodayWorkouts()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(self.viewModel.workouts.count, 1)
            XCTAssertEqual(self.viewModel.workouts.first?.name, "Running")
            XCTAssertEqual(self.viewModel.workouts.first?.caloriesBurned, 450)
            XCTAssertEqual(self.viewModel.workouts.first?.durationMinutes, 60)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchTodayWorkoutsError() {
        viewModel.isAuthorized = true
        mockManager.workoutsError = NSError(domain: "test", code: 1, userInfo: nil)
        let exp = expectation(description: "Fetch workouts error")
        viewModel.fetchTodayWorkouts()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isSyncing)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchLastSevenDaysSleepWithValidSamples() {
        viewModel.isAuthorized = true
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            XCTFail("Missing sleep type")
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        
        // 3 nights of sleep samples (7 hours asleep, 0.5 hours awake per night)
        func makeSamples(for nightDate: Date) -> [HKCategorySample] {
            let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: nightDate)!
            let mid = start.addingTimeInterval(7 * 3600) // 7 hours asleep
            let end = mid.addingTimeInterval(1800) // 30 min awake
            
            let s1 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start, end: mid)
            let s2 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: mid, end: end)
            return [s1, s2]
        }
        
        var samples: [HKCategorySample] = []
        samples.append(contentsOf: makeSamples(for: twoDaysAgo))
        samples.append(contentsOf: makeSamples(for: yesterday))
        samples.append(contentsOf: makeSamples(for: now))
        
        mockManager.sleepResult = samples
        let exp = expectation(description: "Fetch sleep")
        viewModel.fetchLastSevenDaysSleep()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.sleepSamples.count, 6)
            XCTAssertEqual(self.viewModel.sleepSummary.nightCount, 3)
            XCTAssertEqual(self.viewModel.sleepSummary.averageHours, 7.0, accuracy: 0.1)
            XCTAssertNotNil(self.viewModel.sleepSummary.lastNightScore)
            XCTAssertNotNil(self.viewModel.sleepSummary.averageScore)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchLastSevenDaysSleepWithNoSamples() {
        viewModel.isAuthorized = true
        mockManager.sleepResult = []
        let exp = expectation(description: "Fetch sleep empty")
        viewModel.fetchLastSevenDaysSleep()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.sleepSummary, .empty)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchTodayPassiveData() {
        viewModel.isAuthorized = true
        mockManager.todayStepsResult = 8_500
        mockManager.todayActiveEnergyResult = 450.5
        let exp = expectation(description: "Passive data")
        viewModel.fetchTodayPassiveData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.todaySteps, 8_500)
            XCTAssertEqual(self.viewModel.todayActiveEnergy, 450.5)
            XCTAssertNotNil(self.viewModel.lastSyncedAt)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchComprehensiveWeeklyData() {
        viewModel.isAuthorized = true
        let dummyTrends = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0]
        mockManager.trendResult = dummyTrends
        let exp = expectation(description: "Weekly data")
        viewModel.fetchComprehensiveWeeklyData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.weeklySteps, dummyTrends)
            XCTAssertEqual(self.viewModel.weeklyActiveEnergy, dummyTrends)
            XCTAssertEqual(self.viewModel.weeklyRestingHeartRate, dummyTrends)
            XCTAssertEqual(self.viewModel.weeklyHRV, dummyTrends)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testWorkoutActivityTypeNames() {
        let types: [HKWorkoutActivityType: String] = [
            .americanFootball: "American Football",
            .archery: "Archery",
            .australianFootball: "Australian Football",
            .badminton: "Badminton",
            .baseball: "Baseball",
            .basketball: "Basketball",
            .bowling: "Bowling",
            .boxing: "Boxing",
            .climbing: "Climbing",
            .cricket: "Cricket",
            .crossTraining: "Cross Training",
            .curling: "Curling",
            .cycling: "Cycling",
            .dance: "Dance",
            .danceInspiredTraining: "Dance Training",
            .elliptical: "Elliptical",
            .equestrianSports: "Equestrian Sports",
            .fencing: "Fencing",
            .fishing: "Fishing",
            .functionalStrengthTraining: "Functional Strength Training",
            .golf: "Golf",
            .gymnastics: "Gymnastics",
            .handball: "Handball",
            .hiking: "Hiking",
            .hockey: "Hockey",
            .hunting: "Hunting",
            .lacrosse: "Lacrosse",
            .martialArts: "Martial Arts",
            .mindAndBody: "Mind and Body",
            .mixedMetabolicCardioTraining: "Cardio Training",
            .paddleSports: "Paddle Sports",
            .play: "Play",
            .preparationAndRecovery: "Preparation and Recovery",
            .racquetball: "Racquetball",
            .rowing: "Rowing",
            .rugby: "Rugby",
            .running: "Running",
            .sailing: "Sailing",
            .skatingSports: "Skating",
            .snowSports: "Snow Sports",
            .soccer: "Soccer",
            .softball: "Softball",
            .squash: "Squash",
            .stairClimbing: "Stair Climbing",
            .surfingSports: "Surfing",
            .swimming: "Swimming",
            .tableTennis: "Table Tennis",
            .tennis: "Tennis",
            .trackAndField: "Track and Field",
            .traditionalStrengthTraining: "Strength Training",
            .volleyball: "Volleyball",
            .walking: "Walking",
            .waterFitness: "Water Fitness",
            .waterPolo: "Water Polo",
            .waterSports: "Water Sports",
            .wrestling: "Wrestling",
            .yoga: "Yoga",
            .barre: "Barre",
            .coreTraining: "Core Training",
            .crossCountrySkiing: "Cross Country Skiing",
            .downhillSkiing: "Downhill Skiing",
            .flexibility: "Flexibility",
            .highIntensityIntervalTraining: "HIIT",
            .jumpRope: "Jump Rope",
            .kickboxing: "Kickboxing",
            .pilates: "Pilates",
            .snowboarding: "Snowboarding",
            .stairs: "Stairs",
            .stepTraining: "Step Training",
            .wheelchairWalkPace: "Wheelchair Walk Pace",
            .wheelchairRunPace: "Wheelchair Run Pace",
            .taiChi: "Tai Chi",
            .mixedCardio: "Mixed Cardio",
            .handCycling: "Hand Cycling"
        ]
        
        for (activityType, expectedName) in types {
            XCTAssertEqual(activityType.name, expectedName)
        }
    }

    func testCheckAuthorizationStatusWhenHealthDataNotAvailable() {
        mockManager.isHealthDataAvailableResult = false
        let exp = expectation(description: "Auth check unavailable")
        viewModel.setup(dailyLogService: dailyLogService)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isAuthorized)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchTodayWorkoutsNilResult() {
        viewModel.isAuthorized = true
        mockManager.workoutsResult = nil
        let exp = expectation(description: "Fetch workouts nil")
        viewModel.fetchTodayWorkouts()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.viewModel.isSyncing)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchLastSevenDaysSleepError() {
        viewModel.isAuthorized = true
        mockManager.sleepError = NSError(domain: "test", code: 1, userInfo: nil)
        let exp = expectation(description: "Fetch sleep error")
        viewModel.fetchLastSevenDaysSleep()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.sleepSamples.count, 0)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testFetchLastSevenDaysSleepNilResult() {
        viewModel.isAuthorized = true
        mockManager.sleepResult = nil
        let exp = expectation(description: "Fetch sleep nil")
        viewModel.fetchLastSevenDaysSleep()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.sleepSamples.count, 0)
            XCTAssertEqual(self.viewModel.sleepSummary, .empty)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSleepScoringVariationsAndOverlappingSamples() {
        viewModel.isAuthorized = true
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        let calendar = Calendar.current
        let base = Date()
        
        // Night 1: Overlapping asleep intervals & short sleep (<6 hrs) & high awake percentage (>20%)
        let n1 = calendar.date(byAdding: .day, value: -1, to: base)!
        let start1 = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: n1)!
        let end1 = start1.addingTimeInterval(3 * 3600) // 3 hrs
        let start1Overlap = start1.addingTimeInterval(1 * 3600)
        let end1Overlap = start1.addingTimeInterval(4 * 3600) // merged total: 4 hrs (<6 hrs)
        let awake1 = end1Overlap.addingTimeInterval(2 * 3600) // 2 hrs awake out of 6 total (~33% awake)
        
        let s1 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start1, end: end1)
        let s2 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: start1Overlap, end: end1Overlap)
        let s3 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: end1Overlap, end: awake1)
        
        // Night 2: Long sleep (>9 hrs) & bedtime 30 min different
        let n2 = calendar.date(byAdding: .day, value: -2, to: base)!
        let start2 = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: n2)!
        let end2 = start2.addingTimeInterval(10 * 3600) // 10 hrs
        let s4 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: start2, end: end2)
        
        // Night 3: Bedtime 60 min different & 15% awake
        let n3 = calendar.date(byAdding: .day, value: -3, to: base)!
        let start3 = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: n3)!
        let end3 = start3.addingTimeInterval(7 * 3600)
        let awake3 = end3.addingTimeInterval(3600) // 1 hr awake out of 8 total (12.5% awake)
        let s5 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start3, end: end3)
        let s6 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: end3, end: awake3)

        // Night 4: Bedtime 90 min different
        let n4 = calendar.date(byAdding: .day, value: -4, to: base)!
        let start4 = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: n4)!
        let end4 = start4.addingTimeInterval(7 * 3600)
        let s7 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start4, end: end4)

        // Night 5: Bedtime 120 min different
        let n5 = calendar.date(byAdding: .day, value: -5, to: base)!
        let start5 = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: n5)!
        let end5 = start5.addingTimeInterval(7 * 3600)
        let s8 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start5, end: end5)

        // Night 6: Bedtime >120 min different
        let n6 = calendar.date(byAdding: .day, value: -6, to: base)!
        let start6 = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: n6)!
        let end6 = start6.addingTimeInterval(7 * 3600)
        let s9 = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start6, end: end6)

        mockManager.sleepResult = [s1, s2, s3, s4, s5, s6, s7, s8, s9]
        let exp = expectation(description: "Fetch sleep variations")
        viewModel.fetchLastSevenDaysSleep()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.sleepSummary.nightCount, 6)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
}
