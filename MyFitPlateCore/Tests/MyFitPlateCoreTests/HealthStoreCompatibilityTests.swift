import XCTest
import HealthKit
import CoreLocation
@testable import MyFitPlateCore

/// Intentionally implements only the original workout method. The protocol's default
/// event-aware bridge must preserve this conformer without silently omitting events.
private final class LegacyWorkoutWriter: HealthStoreScheduling, @unchecked Sendable {
    let base = MockHealthStore()
    func isHealthDataAvailable() -> Bool { base.isHealthDataAvailable() }
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>?, read typesToRead: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, Error?) -> Void) {
        base.requestAuthorization(toShare: typesToShare, read: typesToRead, completion: completion)
    }
    func getRequestStatusForAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void) {
        base.getRequestStatusForAuthorization(toShare: typesToShare, read: typesToRead, completion: completion)
    }
    func execute(_ query: HKQuery) { base.execute(query) }
    func biologicalSex() throws -> HKBiologicalSexObject { try base.biologicalSex() }
    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        base.save(object, withCompletion: completion)
    }
    func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void) {
        base.save(objects, withCompletion: completion)
    }
    func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate, withCompletion completion: @escaping @Sendable (Bool, Int, Error?) -> Void) {
        base.deleteObjects(of: objectType, predicate: predicate, withCompletion: completion)
    }
    func saveWorkout(configuration: HKWorkoutConfiguration, start: Date, end: Date, samples: [HKSample], locations: [CLLocation], completion: @escaping @Sendable (String?, Error?) -> Void) {
        base.saveWorkout(configuration: configuration, start: start, end: end, samples: samples, locations: locations, completion: completion)
    }
}

@MainActor
final class HealthStoreCompatibilityTests: XCTestCase {
    func testOldConformerAcceptsEventAwareUnpausedWriteThroughExistingMethod() {
        let writer = LegacyWorkoutWriter()
        let done = expectation(description: "Original conformer supports empty events")
        let start = Date()
        writer.saveWorkout(configuration: HKWorkoutConfiguration(), start: start, end: start.addingTimeInterval(60),
                           samples: [], locations: [], events: []) { id, error in
            XCTAssertEqual(id, writer.base.saveWorkoutUUID)
            XCTAssertNil(error)
            done.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(writer.base.savedWorkouts.count, 1)
    }

    func testOldConformerCannotPretendItSavedUnsupportedPauseEvents() {
        let writer = LegacyWorkoutWriter()
        let done = expectation(description: "Unsupported pause events fail explicitly")
        let start = Date()
        let events = [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(20), duration: 0), metadata: nil),
                      HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: start.addingTimeInterval(40), duration: 0), metadata: nil)]
        writer.saveWorkout(configuration: HKWorkoutConfiguration(), start: start, end: start.addingTimeInterval(60),
                           samples: [], locations: [], events: events) { id, error in
            XCTAssertNil(id)
            XCTAssertNotNil(error)
            done.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(writer.base.savedWorkouts.isEmpty)
        XCTAssertTrue(writer.base.savedWorkoutEvents.isEmpty)
    }

    func testOldConformerCannotSilentlyDropRecordingIdentityMetadata() {
        let writer = LegacyWorkoutWriter()
        let done = expectation(description: "Unsupported identity metadata fails explicitly")
        let start = Date()
        writer.saveWorkout(configuration: HKWorkoutConfiguration(), start: start, end: start.addingTimeInterval(60),
                           samples: [], locations: [], events: [], metadata: [RunRecorderRules.recordingIDMetadataKey: "recording"]) { id, error in
            XCTAssertNil(id)
            XCTAssertNotNil(error)
            done.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(writer.base.savedWorkouts.isEmpty)
    }
}
