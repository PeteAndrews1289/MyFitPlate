import XCTest
import HealthKit
@testable import MyFitPlateCore

final class HealthKitManagerTests: XCTestCase {
    var mockStore: MockHealthStore!
    var manager: HealthKitManager!

    override func setUp() {
        super.setUp()
        mockStore = MockHealthStore()
        manager = HealthKitManager(store: mockStore)
    }

    override func tearDown() {
        manager = nil
        mockStore = nil
        super.tearDown()
    }

    func testRequestAuthorizationWhenHealthDataNotAvailable() {
        mockStore.isHealthDataAvailableResult = false
        let exp = expectation(description: "Auth completes")
        var authSuccess: Bool?
        var authError: NSError?
        manager.requestAuthorization { success, error in
            authSuccess = success
            authError = error as NSError?
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(authSuccess, false)
        XCTAssertEqual(authError?.domain, "com.MyFitPlate.HealthKit")
        XCTAssertEqual(authError?.code, 1)
    }

    func testRequestAuthorizationSuccess() {
        mockStore.isHealthDataAvailableResult = true
        mockStore.requestAuthorizationSuccess = true
        let exp = expectation(description: "Auth completes")
        var authSuccess: Bool?
        manager.requestAuthorization { success, _ in
            authSuccess = success
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(authSuccess, true)
    }

    func testGetRequestStatusForAuthorization() {
        mockStore.authorizationStatusResult = .shouldRequest
        let exp = expectation(description: "Status completes")
        var reqStatus: HKAuthorizationRequestStatus?
        manager.getRequestStatusForAuthorization(toShare: [], read: []) { status, _ in
            reqStatus = status
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(reqStatus, .shouldRequest)
    }

    func testFetchWorkouts() {
        let dummyWorkout = HKWorkout(activityType: .running, start: Date().addingTimeInterval(-3600), end: Date())
        mockStore.workoutQueryResult = [dummyWorkout]
        let exp = expectation(description: "Fetch workouts")
        var fetched: [HKWorkout]?
        manager.fetchWorkouts(for: Date()) { workouts, _ in
            fetched = workouts
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fetched?.count, 1)
        XCTAssertEqual(fetched?.first?.uuid, dummyWorkout.uuid)
    }

    func testFetchSleepAnalysis() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            XCTFail("Missing sleepAnalysis type")
            return
        }
        let dummySleep = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: Date().addingTimeInterval(-28800), end: Date())
        mockStore.sleepQueryResult = [dummySleep]
        let exp = expectation(description: "Fetch sleep")
        var fetched: [HKCategorySample]?
        manager.fetchSleepAnalysis(startDate: Date().addingTimeInterval(-86400), endDate: Date()) { samples, _ in
            fetched = samples
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fetched?.count, 1)
        XCTAssertEqual(fetched?.first?.uuid, dummySleep.uuid)
    }

    func testFetchLatestRestingHeartRate() {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            XCTFail("Missing restingHeartRate type")
            return
        }
        let dummyHR = HKQuantitySample(type: hrType, quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 60), start: Date(), end: Date())
        mockStore.restingHeartRateQueryResult = [dummyHR]
        let exp = expectation(description: "Fetch HR")
        var fetched: HKQuantitySample?
        manager.fetchLatestRestingHeartRate { sample in
            fetched = sample
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fetched?.uuid, dummyHR.uuid)
    }

    func testFetchLatestHRV() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            XCTFail("Missing hrv type")
            return
        }
        let dummyHRV = HKQuantitySample(type: hrvType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 45), start: Date(), end: Date())
        mockStore.hrvQueryResult = [dummyHRV]
        let exp = expectation(description: "Fetch HRV")
        var fetched: HKQuantitySample?
        manager.fetchLatestHRV { sample in
            fetched = sample
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fetched?.uuid, dummyHRV.uuid)
    }

    func testFetchTodayStatisticsQueries() {
        let exp1 = expectation(description: "steps")
        manager.fetchTodaySteps { val in XCTAssertEqual(val, 0); exp1.fulfill() }
        let exp2 = expectation(description: "energy")
        manager.fetchTodayActiveEnergy { val in XCTAssertEqual(val, 0); exp2.fulfill() }
        let exp3 = expectation(description: "dist")
        manager.fetchTodayDistance { val in XCTAssertEqual(val, 0); exp3.fulfill() }
        let exp4 = expectation(description: "flights")
        manager.fetchTodayFlights { val in XCTAssertEqual(val, 0); exp4.fulfill() }
        let exp5 = expectation(description: "time")
        manager.fetchTodayExerciseTime { val in XCTAssertEqual(val, 0); exp5.fulfill() }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockStore.executedQueries.count, 5)
    }

    func testFetch7DayTrendQuery() {
        let exp = expectation(description: "trend")
        manager.fetch7DayTrend(for: .stepCount, options: .cumulativeSum, unit: .count()) { vals in
            XCTAssertEqual(vals, Array(repeating: 0.0, count: 7))
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockStore.executedQueries.count, 1)
    }

    func testFetchBiologicalSex() {
        mockStore.biologicalSexResult = MockBiologicalSexObject(sex: .female)
        XCTAssertEqual(manager.fetchBiologicalSex()?.biologicalSex, .female)

        mockStore.biologicalSexError = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertNil(manager.fetchBiologicalSex())
    }

    func testSaveNutrition() {
        let item = FoodItem(name: "Oatmeal", calories: 300, protein: 10, carbs: 50, fats: 5, timestamp: Date())
        manager.saveNutrition(for: item)
        // Dietary energy, protein, carbs, fat = 4 samples
        XCTAssertEqual(mockStore.savedObjects.count, 4)
    }

    func testSaveNutritionWithZeroCalories() {
        let item = FoodItem(name: "Water", calories: 0, protein: 0, carbs: 0, fats: 0, timestamp: Date())
        manager.saveNutrition(for: item)
        XCTAssertEqual(mockStore.savedObjects.count, 0)
    }

    func testSaveWater() {
        manager.saveWater(ounces: 8, date: Date())
        XCTAssertEqual(mockStore.savedObjects.count, 1)
    }

    func testAppFoodMetadataPredicate() {
        let item = FoodItem(name: "Apple", calories: 80, protein: 0, carbs: 20, fats: 0, timestamp: Date())
        let predicate = manager.appFoodMetadataPredicate(for: item)
        XCTAssertNotNil(predicate)
    }

    func testDeleteNutrition() {
        let item = FoodItem(name: "Banana", calories: 100, protein: 1, carbs: 25, fats: 0, timestamp: Date())
        let exp = expectation(description: "Delete nutrition")
        var deleteResult: Bool?
        manager.deleteNutrition(for: item) { success in
            deleteResult = success
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(deleteResult, true)
        XCTAssertEqual(mockStore.deletedObjectTypes.count, 4) // energy, protein, carbs, fat
    }

    func testReplaceNutrition() {
        let oldItem = FoodItem(name: "Apple", calories: 80, protein: 0, carbs: 20, fats: 0, timestamp: Date())
        let newItem = FoodItem(name: "Apple Large", calories: 120, protein: 0, carbs: 30, fats: 0, timestamp: Date())
        
        let exp = expectation(description: "Replace nutrition completes")
        manager.replaceNutrition(oldItem: oldItem, newItem: newItem)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(mockStore.deletedObjectTypes.count, 4)
        XCTAssertEqual(mockStore.savedObjects.count, 2) // calories and carbs for new item
    }

    func testSaveWeightSample() {
        manager.saveWeightSample(weightLbs: 175.5, date: Date())
        XCTAssertEqual(mockStore.savedObjects.count, 1)
    }
}
