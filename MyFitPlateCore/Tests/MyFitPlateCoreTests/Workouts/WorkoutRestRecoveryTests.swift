import XCTest
import MyFitPlateShared
@testable import MyFitPlateCore

final class WorkoutRestRecoveryTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func draft() -> WorkoutSessionDraft {
        let routine = WorkoutRoutine(id: "phul-upper", userID: "owner", name: "Upper power", dateCreated: startedAt,
                                     exercises: [RoutineExercise(id: "bench", name: "Bench Press", sets: [
                                        ExerciseSet(id: "first", isCompleted: true, reps: 5, weight: 135),
                                        ExerciseSet(id: "second", reps: 5, weight: 135)
                                     ])])
        return WorkoutSessionDraft(routine: routine, now: startedAt)
    }

    func testLegacyDraftWithoutRestStillRestoresEveryCompletedSet() throws {
        var original = draft()
        original.elapsed = 360
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "rest")
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.rest)
        XCTAssertEqual(restored.sessionID, original.sessionID)
        XCTAssertEqual(restored.elapsed, 360)
        XCTAssertEqual(restored.routine.id, "phul-upper")
        XCTAssertEqual(restored.routine.exercises.first?.sets.filter(\.isCompleted).map(\.id), ["first"])
    }

    func testRelaunchRestUsesOriginalDeadlineAndStaysAccountScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var original = draft()
        original.rest = try XCTUnwrap(WorkoutRestState(duration: 120, routineName: "Upper power",
                                                     exerciseID: "bench", setID: "first", now: startedAt))
        try WorkoutDraftStore(directory: directory).save(original, userID: "owner")
        let reopened = WorkoutDraftStore(directory: directory)
        let restored = try XCTUnwrap(reopened.load(userID: "owner"))
        XCTAssertNil(try reopened.load(userID: "other"))
        let rest = try XCTUnwrap(restored.rest)
        XCTAssertEqual(rest.id, original.rest?.id)
        XCTAssertEqual(rest.exerciseID, "bench")
        XCTAssertEqual(rest.setID, "first")
        XCTAssertEqual(rest.remaining(at: startedAt.addingTimeInterval(37)), 83)
        XCTAssertEqual(rest.deadline, startedAt.addingTimeInterval(120))
        XCTAssertEqual(restored.routine.exercises.first?.sets.map(\.isCompleted), [true, false])
        XCTAssertEqual(restored.routine.exercises.first?.sets.map(\.weight), [135, 135])
    }

    func testExpiredRestCannotBecomeAnotherFullDurationOnReopen() throws {
        let rest = try XCTUnwrap(WorkoutRestState(duration: 90, routineName: "Upper power", now: startedAt))
        let decoded = try JSONDecoder().decode(WorkoutRestState.self, from: JSONEncoder().encode(rest))
        XCTAssertEqual(decoded.remaining(at: startedAt.addingTimeInterval(89)), 1)
        XCTAssertEqual(decoded.remaining(at: startedAt.addingTimeInterval(90)), 0)
        XCTAssertEqual(decoded.remaining(at: startedAt.addingTimeInterval(600)), 0)
    }

    func testInvalidOrCorruptDeadlineCannotCreateAnUnboundedRest() throws {
        for duration in [0, -1, Double.infinity, Double.nan, WorkoutRestState.maximumDuration + 1] {
            XCTAssertNil(WorkoutRestState(duration: duration, routineName: "Upper power", now: startedAt))
        }
        let rest = try XCTUnwrap(WorkoutRestState(duration: 120, routineName: "Upper power", now: startedAt))
        XCTAssertEqual(rest.remaining(at: startedAt.addingTimeInterval(-1)), 0, "A reversed wall clock must not extend rest")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rest)) as? [String: Any])
        json["deadline"] = startedAt.addingTimeInterval(24 * 60 * 60).timeIntervalSinceReferenceDate
        let corrupt = try JSONDecoder().decode(WorkoutRestState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(corrupt.remaining(at: startedAt), 0)
    }

    func testCorruptOptionalRestMetadataDoesNotHideCompletedWork() throws {
        let original = draft()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["rest"] = ["deadline": "not a date"]
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.rest)
        XCTAssertEqual(restored.sessionID, original.sessionID)
        XCTAssertEqual(restored.routine.exercises.first?.sets.filter(\.isCompleted).map(\.id), ["first"])
    }

    func testExplicitStopSurvivesAnotherDraftSaveAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutDraftStore(directory: directory)
        var original = draft()
        original.rest = WorkoutRestState(duration: 120, routineName: "Upper power", now: startedAt)
        try store.save(original, userID: "owner")
        original.rest = nil
        try store.save(original, userID: "owner")
        let restored = try XCTUnwrap(WorkoutDraftStore(directory: directory).load(userID: "owner"))
        XCTAssertNil(restored.rest)
        XCTAssertEqual(restored.sessionID, original.sessionID)
        XCTAssertEqual(restored.routine.exercises.first?.sets.filter(\.isCompleted).count, 1)
    }

    func testFinishingClearsRestAndKeepsFrozenCompletionStableOnRetry() throws {
        var original = draft()
        original.rest = WorkoutRestState(duration: 120, routineName: "Upper power", now: startedAt)
        original.elapsed = 360
        XCTAssertTrue(original.prepareCompletion(weightPounds: 180, now: startedAt.addingTimeInterval(360)))
        XCTAssertNil(original.rest)
        let frozenLog = try JSONEncoder().encode(try XCTUnwrap(original.completion))
        let frozenDiary = try JSONEncoder().encode(try XCTUnwrap(original.diaryExercise))
        var restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(restored.prepareCompletion(weightPounds: 210, now: startedAt.addingTimeInterval(86_400)))
        XCTAssertNil(restored.rest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(restored.completion), try encoder.encode(JSONDecoder().decode(WorkoutSessionLog.self, from: frozenLog)))
        XCTAssertEqual(try encoder.encode(restored.diaryExercise), try encoder.encode(JSONDecoder().decode(LoggedExercise.self, from: frozenDiary)))
        XCTAssertEqual(restored.routine.exercises.first?.sets.map(\.isCompleted), [true, false])
    }

    func testRestAdjustmentsRetainIdentityAndShiftTheExistingDeadline() throws {
        let original = try XCTUnwrap(WorkoutRestState(duration: 120, routineName: "Upper power",
                                                     exerciseID: "bench", setID: "first", now: startedAt))
        let now = startedAt.addingTimeInterval(37)
        let extended = try XCTUnwrap(original.adjusted(by: 30, at: now))
        let shortened = try XCTUnwrap(extended.adjusted(by: -15, at: now))
        XCTAssertEqual(extended.deadline, startedAt.addingTimeInterval(150))
        XCTAssertEqual(extended.remaining(at: now), 113)
        XCTAssertEqual(shortened.deadline, startedAt.addingTimeInterval(135))
        XCTAssertEqual(shortened.id, original.id)
        XCTAssertEqual(shortened.startedAt, original.startedAt)
        XCTAssertEqual(shortened.routineName, original.routineName)
        XCTAssertEqual(shortened.exerciseID, "bench")
        XCTAssertEqual(shortened.setID, "first")
    }

    func testShorteningToZeroEndsRestAndFinishedRestCannotBeExtended() throws {
        let rest = try XCTUnwrap(WorkoutRestState(duration: 90, routineName: "Upper power", now: startedAt))
        XCTAssertNil(rest.adjusted(by: -15, at: startedAt.addingTimeInterval(80)))
        XCTAssertNil(rest.adjusted(by: 30, at: startedAt.addingTimeInterval(90)))
        XCTAssertNil(rest.adjusted(by: 30, at: startedAt.addingTimeInterval(600)))
        XCTAssertNil(rest.adjusted(by: 30, at: startedAt.addingTimeInterval(-1)))
    }

    func testRestAdjustmentCapIsMeasuredFromItsOriginalStart() throws {
        let rest = try XCTUnwrap(WorkoutRestState(duration: WorkoutRestState.maximumDuration - 15,
                                                 routineName: "Upper power", now: startedAt))
        let extended = try XCTUnwrap(rest.adjusted(by: Double.greatestFiniteMagnitude,
                                                  at: startedAt.addingTimeInterval(100)))
        XCTAssertEqual(extended.deadline, startedAt.addingTimeInterval(WorkoutRestState.maximumDuration))
        XCTAssertEqual(extended.id, rest.id)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(rest.adjusted(by: invalid, at: startedAt))
        }
    }

    func testAdjustedRestPersistsWithoutChangingWorkAndKeepsSkipReceiptsScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var original = draft()
        let rest = try XCTUnwrap(WorkoutRestState(duration: 120, routineName: "Upper power",
                                                 exerciseID: "bench", setID: "first", now: startedAt))
        original.rest = try XCTUnwrap(rest.adjusted(by: 30, at: startedAt.addingTimeInterval(37)))
        try WorkoutDraftStore(directory: directory).save(original, userID: "owner")
        let restored = try XCTUnwrap(WorkoutDraftStore(directory: directory).load(userID: "owner"))
        let recoveredRest = try XCTUnwrap(restored.rest)
        XCTAssertEqual(recoveredRest.id, rest.id)
        XCTAssertEqual(recoveredRest.deadline, startedAt.addingTimeInterval(150))
        XCTAssertEqual(recoveredRest.remaining(at: startedAt.addingTimeInterval(50)), 100)
        XCTAssertEqual(restored.sessionID, original.sessionID)
        XCTAssertEqual(restored.routine.exercises.first?.sets.map(\.isCompleted), [true, false])
        XCTAssertEqual(restored.routine.exercises.first?.sets.map(\.weight), [135, 135])

        let skipStore = WorkoutRestSkipStore(directory: directory.appendingPathComponent("skips"))
        XCTAssertTrue(skipStore.request(restID: rest.id, now: startedAt))
        XCTAssertTrue(skipStore.wasRequested(restID: recoveredRest.id, now: startedAt))
        let nextRest = try XCTUnwrap(WorkoutRestState(duration: 60, routineName: "Upper power", now: startedAt))
        XCTAssertFalse(skipStore.wasRequested(restID: nextRest.id, now: startedAt))
    }
}
