import XCTest
@testable import MyFitPlateCore

final class RecoveryEvidenceRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_798_000_000)
    private func session(_ id: String = "session", hours: Double = 2, sets: Int = 4, warmups: Int = 0, name: String = "Bench Press") -> WorkoutSessionLog {
        let exercise = RoutineExercise(id: "movement", name: name)
        let recorded = (0..<sets).map { CompletedSet(id: "working-\($0)", reps: 8, weight: 100) }
            + (0..<warmups).map { CompletedSet(id: "warm-\($0)", reps: 20, weight: 400, setType: .warmup) }
        return .init(id: id, date: now.addingTimeInterval(-hours * 3_600), routineID: "routine",
                     completedExercises: [.init(exerciseName: name, exercise: exercise, sets: recorded)])
    }
    private func evidence(_ sessions: [WorkoutSessionLog] = [], runs: [Run] = [], checkIns: [RecoveryCheckIn] = [],
                          sleepScore: Int? = nil, sleepDate: Date? = nil, group: RecoveryMuscleGroup = .chest) throws -> RecoveryRegionEvidence {
        try XCTUnwrap(MuscleRecoveryRules.regionEvidence(sessions: sessions, runs: runs, checkIns: checkIns,
            sleepScore: sleepScore, sleepDate: sleepDate, asOf: now).first { $0.group == group })
    }
    func testMissingEvidenceStaysUnknownRatherThanReady() throws {
        let value = try evidence()
        XCTAssertEqual(value.state, .unknown)
        XCTAssertEqual(value.sleepFreshness, .unknown)
        XCTAssertNil(value.checkIn)
        XCTAssertEqual(value.modelVersion, "exposure-v2")
    }
    func testWarmupsInvalidAndCardioCannotInflateWorkingEvidence() throws {
        let plain = try evidence([session()])
        let withWarmups = try evidence([session(warmups: 20)])
        XCTAssertEqual(plain.training, withWarmups.training)
        XCTAssertEqual(plain.state, withWarmups.state)
        var invalid = session(); invalid.completedExercises[0].sets = [.init(reps: 8, weight: .nan), .init(reps: 0, weight: 100)]
        var cardio = session("cardio"); cardio.completedExercises[0].exercise.type = .cardio
        XCTAssertEqual(try evidence([invalid, cardio, session(sets: 0, warmups: 5)]).state, .unknown)
    }
    func testDetailedHistoryDuplicatesAndEmptyDiaryMirrorCountOnce() throws {
        let detailed = session(sets: 6)
        var mirror = detailed; mirror.id = "diary-summary"; mirror.completedExercises = []
        let value = try evidence([detailed, detailed, mirror])
        XCTAssertEqual(value.training.count, 1)
        XCTAssertEqual(value.sevenDayWorkingSets, 6)
        XCTAssertEqual(value.training[0].date, detailed.date)
        XCTAssertEqual(value.training[0].exerciseNames, ["Bench Press"])
    }
    func testAccumulationUsesDatedMultipleSessionsNotOnlyLatest() throws {
        let value = try evidence([session("today", sets: 6), session("earlier", hours: 48, sets: 8)])
        XCTAssertEqual(value.sevenDayWorkingSets, 14)
        XCTAssertEqual(value.training.count, 2)
        XCTAssertEqual(value.state, .accumulatedExposure)
        XCTAssertEqual(try evidence([session("old", hours: 8 * 24, sets: 20)]).sevenDayWorkingSets, 0)
    }
    func testFutureAndOutsideHistoryWindowDoNotCreateSignal() throws {
        XCTAssertEqual(try evidence([session(hours: -1), session("old", hours: 15 * 24)]).state, .unknown)
    }
    func testStaleInvalidAndFutureSleepCannotBecomeCurrentEvidence() throws {
        let source = [session()]
        XCTAssertEqual(try evidence(source, sleepScore: 20, sleepDate: now.addingTimeInterval(-40 * 3_600)).state, .recentExposure)
        XCTAssertEqual(try evidence(source, sleepScore: 20, sleepDate: now.addingTimeInterval(-40 * 3_600)).sleepFreshness, .stale)
        XCTAssertEqual(try evidence(source, sleepScore: 20, sleepDate: now.addingTimeInterval(-3_600)).state, .reviewCheckIn)
        XCTAssertEqual(try evidence(source, sleepScore: 500, sleepDate: now).sleepFreshness, .unknown)
        XCTAssertEqual(try evidence(source, sleepScore: 20, sleepDate: now.addingTimeInterval(100)).sleepFreshness, .unknown)
    }
    func testFreshSubjectiveConcernShownWithoutInventingTraining() throws {
        let checkIn = RecoveryCheckIn(group: .chest, observedAt: now.addingTimeInterval(-3_600), soreness: .high)
        let value = try evidence(checkIns: [checkIn])
        XCTAssertEqual(value.state, .reviewCheckIn)
        XCTAssertTrue(value.training.isEmpty)
        XCTAssertEqual(value.checkIn?.soreness, .high)
        XCTAssertNil(value.checkIn?.fatigue)
    }
    func testStaleAndFutureSubjectiveObservationsAreNotCurrent() throws {
        let stale = RecoveryCheckIn(group: .chest, observedAt: now.addingTimeInterval(-100 * 3_600), fatigue: .high)
        let future = RecoveryCheckIn(group: .chest, observedAt: now.addingTimeInterval(100), soreness: .high)
        let value = try evidence(checkIns: [future, stale])
        XCTAssertEqual(value.state, .unknown)
        XCTAssertFalse(value.checkInIsFresh)
        XCTAssertEqual(value.checkIn?.id, stale.id)
    }
    func testPainAndInjuryNotePrioritizesConservativePrompt() throws {
        let pain = RecoveryCheckIn(group: .chest, observedAt: now, note: "Sharp pain when pressing")
        let value = try evidence([session(hours: 100)], checkIns: [pain])
        XCTAssertEqual(value.state, .stopAndChange)
        XCTAssertTrue(value.explanation.contains("Stop or change"))
        XCTAssertFalse(value.explanation.contains("diagnosed"))
        let unrelated = RecoveryCheckIn(group: .legs, observedAt: now, painOrInjury: true)
        XCTAssertEqual(try evidence(checkIns: [unrelated]).state, .unknown)
    }
    func testLowerRecentLoadIsNotClaimedMeasuredReadiness() throws {
        let value = try evidence([session(hours: 100)])
        XCTAssertEqual(value.state, .lowerRecentLoad)
        XCTAssertTrue(value.explanation.contains("not measured"))
    }
    func testMeaningfulRunsDeduplicateRecordingAndStaySeparateFromStrengthSets() throws {
        let run = Run(id: "health", source: .recorded, startDate: now.addingTimeInterval(-7_200),
            endDate: now.addingTimeInterval(-3_600), distanceMeters: 5_000, movingSeconds: 3_600, recordingID: "recording")
        var mirror = run; mirror = mirror.reidentified(as: "local")
        let value = try evidence(runs: [run, mirror], group: .legs)
        XCTAssertEqual(value.runs.count, 1)
        XCTAssertEqual(value.runs[0].movingMinutes, 60)
        XCTAssertEqual(value.sevenDayWorkingSets, 0)
        XCTAssertEqual(value.state, .recentExposure)
        XCTAssertTrue(try evidence(runs: [run], group: .chest).runs.isEmpty)
    }
    func testStationaryShortFutureAndImpossibleRunsAreExcluded() throws {
        let stationary = Run(source: .recorded, startDate: now.addingTimeInterval(-600), endDate: now,
                             distanceMeters: 0, movingSeconds: 600)
        let short = Run(source: .recorded, startDate: now.addingTimeInterval(-300), endDate: now,
                       distanceMeters: 1_000, movingSeconds: 300)
        let impossible = Run(source: .recorded, startDate: now.addingTimeInterval(-600), endDate: now,
                            distanceMeters: 1_000, movingSeconds: 3_000)
        XCTAssertEqual(try evidence(runs: [stationary, short, impossible], group: .legs).state, .unknown)
    }
}

@MainActor final class RecoveryCheckInStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_798_000_000)
    private var directory: URL!
    private var drafts: EditorDraftStore!
    private var active = "owner"
    private var subject: RecoveryCheckInStore!
    override func setUp() {
        super.setUp()
        active = "owner"; directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        drafts = EditorDraftStore(directory: directory)
        subject = RecoveryCheckInStore(store: drafts, currentUserID: { self.active })
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        subject = nil; drafts = nil; directory = nil; super.tearDown()
    }
    func testDatedCheckInPersistsAndEditsWithFullExpectedCAS() throws {
        let value = RecoveryCheckIn(group: .legs, observedAt: now, soreness: .mild)
        let saved = try subject.save(value, expected: nil, userID: "owner", now: now)
        let reopened = RecoveryCheckInStore(store: drafts, currentUserID: { self.active })
        XCTAssertEqual(try reopened.observations(userID: "owner"), [saved])
        var edit = saved; edit.fatigue = .high
        let newer = try reopened.save(edit, expected: saved, userID: "owner", now: now)
        XCTAssertThrowsError(try subject.save(saved, expected: saved, userID: "owner", now: now))
        XCTAssertThrowsError(try subject.remove(saved, userID: "owner"))
        XCTAssertEqual(try reopened.observations(userID: "owner"), [newer])
    }
    func testAccountSwitchCannotReadWriteOrRemoveOtherObservation() throws {
        let saved = try subject.save(.init(group: .arms, observedAt: now, fatigue: .mild), expected: nil, userID: "owner", now: now)
        active = "other"
        XCTAssertThrowsError(try subject.observations(userID: "owner"))
        XCTAssertThrowsError(try subject.remove(saved, userID: "owner"))
        XCTAssertTrue(try subject.observations(userID: "other").isEmpty)
        active = "owner"; XCTAssertEqual(try subject.observations(userID: "owner"), [saved])
    }
    func testDeletingAccountDraftsClearsObservationsForOnlyThatOwner() throws {
        _ = try subject.save(.init(group: .arms, observedAt: now, fatigue: .mild), expected: nil, userID: "owner", now: now)
        active = "other"
        let other = try subject.save(.init(group: .legs, observedAt: now, fatigue: .high), expected: nil, userID: "other", now: now)
        try drafts.removeAll(userID: "owner")
        XCTAssertEqual(try subject.observations(userID: "other"), [other])
        active = "owner"; XCTAssertTrue(try subject.observations(userID: "owner").isEmpty)
    }
    func testInvalidObservationCannotReplaceSavedRecord() throws {
        let saved = try subject.save(.init(group: .core, observedAt: now, soreness: RecoveryRating.none), expected: nil, userID: "owner", now: now)
        var invalid = saved; invalid.note = String(repeating: "x", count: 501)
        XCTAssertThrowsError(try subject.save(invalid, expected: saved, userID: "owner", now: now))
        var future = saved; future.observedAt = now.addingTimeInterval(100)
        XCTAssertThrowsError(try subject.save(future, expected: saved, userID: "owner", now: now))
        XCTAssertEqual(try subject.observations(userID: "owner"), [saved])
    }
    func testUnreadableLibraryIsPreservedWhenSaving() throws {
        struct Other: Codable { let unexpected: String }
        try drafts.save(Other(unexpected: "preserve"), userID: "owner", scope: RecoveryCheckInStore.scope)
        XCTAssertThrowsError(try subject.save(.init(group: .legs, observedAt: now, fatigue: .mild), expected: nil, userID: "owner", now: now))
        XCTAssertEqual(try drafts.load(Other.self, userID: "owner", scope: RecoveryCheckInStore.scope)?.value.unexpected, "preserve")
    }
}
