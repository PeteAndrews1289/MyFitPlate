import XCTest
import HealthKit
import CoreLocation
@testable import MyFitPlateCore

@MainActor
final class RunRecorderStoreTests: XCTestCase {
    private var mockStore: MockHealthStore!
    private var store: RunRecorderStore!

    override func setUp() {
        super.setUp()
        mockStore = MockHealthStore()
        store = RunRecorderStore(healthStore: mockStore)
    }

    override func tearDown() {
        store = nil
        mockStore = nil
        super.tearDown()
    }

    func testInitWithDefaultStore() {
        let defaultStore = RunRecorderStore()
        XCTAssertNotNil(defaultStore)
    }

    func testSaveWithoutExternalOverlapAndEstimatedCalories() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: nil, // Should estimate
            averageHeartRate: 145,
            isIndoor: false,
            hasRoute: true
        )
        
        let locs = [CLLocation(latitude: 40.0, longitude: -74.0)]
        mockStore.workoutQueryResult = [] // No overlapping external workouts
        
        let exp = expectation(description: "Save run")
        var savedUUID: String?
        store.save(run: run, locations: locs, weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(savedUUID, mockStore.saveWorkoutUUID)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.configuration.activityType, .running)
        XCTAssertEqual(saved.configuration.locationType, .outdoor)
        XCTAssertEqual(saved.samples.count, 2, "Should include distance and energy samples when no external overlap")
        XCTAssertEqual(saved.locations.count, 1)
    }

    func testSaveWithExternalOverlap() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: 350,
            averageHeartRate: 150,
            isIndoor: false,
            hasRoute: true
        )
        
        // External watch workout overlapping by > 60 seconds
        let watchWorkout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 360),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5050),
            metadata: nil
        )
        mockStore.workoutQueryResult = [watchWorkout]
        
        let exp = expectation(description: "Save run with overlap")
        var savedUUID: String?
        store.save(run: run, locations: [], weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(savedUUID, mockStore.saveWorkoutUUID)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.samples.count, 0, "Should NOT include quantity samples when external recording overlaps")
    }

    func testSaveWithIndoorRunAndProvidedCalories() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 4000,
            movingSeconds: 1800,
            activeCalories: 300,
            averageHeartRate: 140,
            isIndoor: true,
            hasRoute: false
        )
        
        mockStore.workoutQueryResult = []
        let exp = expectation(description: "Save indoor run")
        store.save(run: run, locations: [], weightLbs: 165) { _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.configuration.locationType, .indoor)
        XCTAssertEqual(saved.samples.count, 2)
    }

    func testSaveWithError() {
        let now = Date()
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: now.addingTimeInterval(-1800),
            endDate: now,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: 350,
            averageHeartRate: nil,
            isIndoor: false,
            hasRoute: false
        )
        
        mockStore.workoutQueryResult = []
        mockStore.saveWorkoutError = NSError(domain: "test", code: 1, userInfo: nil)
        mockStore.saveWorkoutUUID = nil
        
        let exp = expectation(description: "Save run error")
        var savedUUID: String? = "initial"
        store.save(run: run, locations: [], weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertNil(savedUUID)
    }
}
