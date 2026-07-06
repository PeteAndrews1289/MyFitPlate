import XCTest
import HealthKit
@testable import MyFitPlateCore

@MainActor
final class RunImportServiceTests: XCTestCase {
    private var mockStore: MockHealthStore!
    private var service: RunImportService!

    override func setUp() {
        super.setUp()
        mockStore = MockHealthStore()
        service = RunImportService(healthStore: mockStore)
    }

    override func tearDown() {
        service = nil
        mockStore = nil
        super.tearDown()
    }

    func testInitWithDefaultStore() {
        let defaultService = RunImportService()
        XCTAssertNotNil(defaultService)
    }

    func testFetchRunsSuccess() {
        let now = Date()
        let start1 = now.addingTimeInterval(-3600)
        let end1 = now.addingTimeInterval(-1800) // 30 min run
        
        let w1 = HKWorkout(
            activityType: .running,
            start: start1,
            end: end1,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 400),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: [HKMetadataKeyIndoorWorkout: false]
        )
        
        // Non-running workout (should be filtered out by RunImportRules.isImportableRun)
        let w2 = HKWorkout(
            activityType: .cycling,
            start: start1,
            end: end1,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 300),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 10000),
            metadata: nil
        )

        // False start running workout (< 100m and < 2 minutes)
        let w3 = HKWorkout(
            activityType: .running,
            start: now.addingTimeInterval(-60),
            end: now,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 5),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 50),
            metadata: nil
        )

        mockStore.workoutQueryResult = [w1, w2, w3]
        
        let exp = expectation(description: "Fetch runs")
        var resultRuns: [Run]?
        service.fetchRuns(since: now.addingTimeInterval(-86400)) { runs in
            resultRuns = runs
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(resultRuns?.count, 1)
        XCTAssertEqual(resultRuns?.first?.id, w1.uuid.uuidString)
        XCTAssertEqual(resultRuns?.first?.distanceMeters, 5000)
        XCTAssertEqual(resultRuns?.first?.activeCalories, 400)
        XCTAssertFalse(resultRuns?.first?.isIndoor ?? true)
    }

    func testFetchRunsError() {
        mockStore.workoutQueryError = NSError(domain: "test", code: 1, userInfo: nil)
        mockStore.workoutQueryResult = nil
        
        let exp = expectation(description: "Fetch runs error")
        var resultRuns: [Run]?
        service.fetchRuns(since: Date().addingTimeInterval(-86400)) { runs in
            resultRuns = runs
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(resultRuns?.count, 0)
    }

    func testFetchRouteWithInvalidUUID() {
        let exp = expectation(description: "Fetch route invalid UUID")
        var fixes: [RunLocationFix]?
        service.fetchRoute(forRunID: "invalid-uuid-string") { result in
            fixes = result
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fixes?.count, 0)
    }

    func testFetchRouteWithNoWorkoutFound() {
        mockStore.workoutQueryResult = []
        let exp = expectation(description: "Fetch route no workout")
        var fixes: [RunLocationFix]?
        service.fetchRoute(forRunID: UUID().uuidString) { result in
            fixes = result
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fixes?.count, 0)
    }

    func testFetchRouteWithWorkoutButNoRouteSample() {
        let w = HKWorkout(activityType: .running, start: Date().addingTimeInterval(-1800), end: Date())
        mockStore.workoutQueryResult = [w]
        
        let exp = expectation(description: "Fetch route no route sample")
        var fixes: [RunLocationFix]?
        service.fetchRoute(forRunID: w.uuid.uuidString) { result in
            fixes = result
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(fixes?.count, 0)
    }

    func testFetchAverageHeartRate() {
        let exp = expectation(description: "Fetch HR")
        var fetchedHR: Double? = -1.0
        service.fetchAverageHeartRate(start: Date().addingTimeInterval(-1800), end: Date()) { hr in
            fetchedHR = hr
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        // Since MockHealthStore invokes HKStatisticsQuery handler with nil statistics, expected is nil
        XCTAssertNil(fetchedHR)
    }

    func testActivityMapping() {
        XCTAssertEqual(RunImportService.activity(from: .running), .running)
        XCTAssertEqual(RunImportService.activity(from: .walking), .walking)
        XCTAssertEqual(RunImportService.activity(from: .hiking), .hiking)
        XCTAssertEqual(RunImportService.activity(from: .cycling), .cycling)
        XCTAssertEqual(RunImportService.activity(from: .swimming), .other)
        XCTAssertEqual(RunImportService.activity(from: .yoga), .other)
    }

    func testSummaryMapping() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let w = HKWorkout(
            activityType: .hiking,
            start: start,
            end: now,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 250),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 3000),
            metadata: [HKMetadataKeyIndoorWorkout: true]
        )
        let summary = RunImportService.summary(from: w)
        XCTAssertEqual(summary.uuid, w.uuid.uuidString)
        XCTAssertEqual(summary.activity, .hiking)
        XCTAssertEqual(summary.distanceMeters, 3000)
        XCTAssertEqual(summary.activeCalories, 250)
        XCTAssertTrue(summary.isIndoor)
    }
}
