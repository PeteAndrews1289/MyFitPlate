import XCTest
import HealthKit
@testable import MyFitPlateCore

final class HealthWorkoutBuilderWriterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Result: @unchecked Sendable {
        var workout: HKWorkout?
        var error: Error?
        var count = 0
        func receive(_ workout: HKWorkout?, _ error: Error?) { self.workout = workout; self.error = error; count += 1 }
    }

    private final class Builder: HealthWorkoutBuilding, @unchecked Sendable {
        var trace: [String] = []
        var failAt: String?
        var failure: Error? = NSError(domain: "builder-test", code: 7)
        var returnUnavailableWorkout = false
        var start = Date.distantPast
        var end = Date.distantFuture
        var events: [HKWorkoutEvent] = []
        var metadata: [String: Any] = [:]
        func beginCollection(withStart start: Date, completion: @escaping @Sendable (Bool, Error?) -> Void) {
            self.start = start; complete("begin", completion)
        }
        func add(_ samples: [HKSample], completion: @escaping @Sendable (Bool, Error?) -> Void) { complete("samples", completion) }
        func addMetadata(_ metadata: [String: Any], completion: @escaping @Sendable (Bool, Error?) -> Void) {
            self.metadata = metadata; complete("metadata", completion)
        }
        func addWorkoutEvents(_ events: [HKWorkoutEvent], completion: @escaping @Sendable (Bool, Error?) -> Void) {
            self.events = events; complete("events", completion)
        }
        func endCollection(withEnd end: Date, completion: @escaping @Sendable (Bool, Error?) -> Void) {
            self.end = end; complete("end", completion)
        }
        func finishWorkout(completion: @escaping @Sendable (HKWorkout?, Error?) -> Void) {
            trace.append("finish")
            if returnUnavailableWorkout { completion(nil, nil); return }
            completion(HKWorkout(activityType: .running, start: start, end: end, workoutEvents: events,
                                 totalEnergyBurned: nil, totalDistance: nil, metadata: nil), nil)
        }
        func discardWorkout() { trace.append("discard") }
        private func complete(_ step: String, _ completion: @escaping @Sendable (Bool, Error?) -> Void) {
            trace.append(step)
            completion(failAt != step, failAt == step ? failure : nil)
        }
    }

    private func events() -> [HKWorkoutEvent] {
        [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(20), duration: 0), metadata: nil),
         HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: start.addingTimeInterval(40), duration: 0), metadata: nil)]
    }

    private func sample() -> HKSample {
        HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning), quantity: HKQuantity(unit: .meter(), doubleValue: 1_000),
                         start: start, end: start.addingTimeInterval(100))
    }

    func testRealBuilderPathAddsOrderedEventsBeforeQuantitiesAndFinishesOriginalWindow() {
        let builder = Builder(), result = Result()
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: Array(events().reversed())) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "events", "samples", "end", "finish"])
        XCTAssertEqual(builder.events.map(\.type), [.pause, .resume])
        XCTAssertEqual(result.workout?.startDate, start)
        XCTAssertEqual(result.workout?.endDate, start.addingTimeInterval(100))
        XCTAssertEqual(result.workout?.duration, 80)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.count, 1)
    }

    func testEventFailureDiscardsBeforeQuantitySamplesOrWorkoutAreSaved() {
        let builder = Builder(), result = Result()
        builder.failAt = "events"
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: events()) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "events", "discard"])
        XCTAssertNil(result.workout)
        XCTAssertEqual((result.error as NSError?)?.domain, "builder-test")
        XCTAssertEqual(result.count, 1)
    }

    func testMissingEventErrorStillFailsExplicitlyAndLegacyEmptyEventsSkipThatStage() {
        let builder = Builder(), result = Result()
        builder.failAt = "events"; builder.failure = nil
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [], events: events()) { result.receive($0, $1) }
        XCTAssertNotNil(result.error)
        let empty = Builder(), emptyResult = Result()
        HealthWorkoutBuilderWriter(builder: empty).save(start: start, end: start.addingTimeInterval(100),
                                                       samples: [], events: []) { emptyResult.receive($0, $1) }
        XCTAssertEqual(empty.trace, ["begin", "end", "finish"])
        XCTAssertNotNil(emptyResult.workout)
    }

    func testOutOfWindowEventsFailBeforeCollectionStarts() {
        let builder = Builder(), result = Result()
        let outside = HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(-1), duration: 0), metadata: nil)
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: [outside]) { result.receive($0, $1) }
        XCTAssertTrue(builder.trace.isEmpty)
        XCTAssertNil(result.workout)
        XCTAssertNotNil(result.error)
    }

    func testLockedFinishWithoutReadableWorkoutDoesNotInventUUIDOrDiscardSuccessfulWrite() {
        let builder = Builder(), result = Result()
        builder.returnUnavailableWorkout = true
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [], events: events()) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "events", "end", "finish"])
        XCTAssertNil(result.workout)
        XCTAssertEqual(result.error as? HealthWorkoutWriteError, .savedButUnreadable)
        XCTAssertEqual(result.count, 1)
    }

    func testIdentityMetadataIsCommittedBeforeEventsAndQuantities() {
        let builder = Builder(), result = Result()
        let metadata: [String: Any] = [RunRecorderRules.recordingIDMetadataKey: "original-recording",
                                       HKMetadataKeySyncIdentifier: "stable-workout-id", HKMetadataKeySyncVersion: 1]
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: events(), metadata: metadata) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "metadata", "events", "samples", "end", "finish"])
        XCTAssertEqual(builder.metadata[RunRecorderRules.recordingIDMetadataKey] as? String, "original-recording")
        XCTAssertEqual(builder.metadata[HKMetadataKeySyncVersion] as? Int, 1)
        XCTAssertNotNil(result.workout)
    }

    func testMetadataFailureStopsBeforeEventOrQuantitySamples() {
        let builder = Builder(), result = Result()
        builder.failAt = "metadata"
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: events(),
                                                         metadata: [HKMetadataKeySyncIdentifier: "stable"]) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "metadata", "discard"])
        XCTAssertNil(result.workout)
        XCTAssertNotNil(result.error)
    }

    func testPostSampleFailureNeverReportsSuccessfulWorkout() {
        let builder = Builder(), result = Result()
        builder.failAt = "end"
        HealthWorkoutBuilderWriter(builder: builder).save(start: start, end: start.addingTimeInterval(100),
                                                         samples: [sample()], events: events(),
                                                         metadata: [HKMetadataKeySyncIdentifier: "stable"]) { result.receive($0, $1) }
        XCTAssertEqual(builder.trace, ["begin", "metadata", "events", "samples", "end", "discard"])
        XCTAssertNil(result.workout)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.count, 1)
    }
}
