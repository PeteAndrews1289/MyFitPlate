import XCTest
@testable import MyFitPlateCore

/// Set-quality foundation: RPE/RIR effort, richer set types, and the guarantee that
/// warmup sets never inflate volume / 1RM / PRs. Also pins Codable back-compat so
/// documents written before these fields existed still decode.
final class WorkoutSetQualityTests: XCTestCase {

    // MARK: - SetEffort normalization

    func testRPEEffortNormalizesToItself() {
        XCTAssertEqual(SetEffort(scale: .rpe, value: 8).normalizedRPE, 8, accuracy: 0.001)
        XCTAssertEqual(SetEffort(scale: .rpe, value: 7.5).normalizedRPE, 7.5, accuracy: 0.001)
    }

    func testRIREffortMapsToRPE() {
        // 0 reps in reserve == RPE 10; 2 RIR == RPE 8.
        XCTAssertEqual(SetEffort(scale: .rir, value: 0).normalizedRPE, 10, accuracy: 0.001)
        XCTAssertEqual(SetEffort(scale: .rir, value: 2).normalizedRPE, 8, accuracy: 0.001)
    }

    func testEffortClampsToSaneBand() {
        XCTAssertEqual(SetEffort(scale: .rpe, value: 99).normalizedRPE, 10, accuracy: 0.001)
        XCTAssertEqual(SetEffort(scale: .rir, value: 99).normalizedRPE, 1, accuracy: 0.001)
    }

    // MARK: - Set-type resolution

    func testLegacyWarmupFlagResolvesToWarmupType() {
        let warmup = ExerciseSet(isWarmup: true, reps: 5, weight: 45)
        XCTAssertEqual(warmup.resolvedSetType, .warmup)
        XCTAssertFalse(warmup.isWorkingSet)

        let working = ExerciseSet(isWarmup: false, reps: 8, weight: 100)
        XCTAssertEqual(working.resolvedSetType, .normal)
        XCTAssertTrue(working.isWorkingSet)
    }

    func testExplicitSetTypeWinsAndSetKindSyncsWarmupFlag() {
        var set = ExerciseSet(reps: 8, weight: 100)
        set.setKind(.drop)
        XCTAssertEqual(set.resolvedSetType, .drop)
        XCTAssertTrue(set.isWorkingSet)       // drop sets still count
        XCTAssertFalse(set.isWarmup)

        set.setKind(.warmup)
        XCTAssertEqual(set.resolvedSetType, .warmup)
        XCTAssertFalse(set.isWorkingSet)
        XCTAssertTrue(set.isWarmup, "setKind(.warmup) keeps the legacy flag in sync")
    }

    func testCompletedSetDefaultsToNormalWorkingSet() {
        let set = CompletedSet(reps: 10, weight: 135)
        XCTAssertEqual(set.resolvedSetType, .normal)
        XCTAssertTrue(set.isWorkingSet)

        let warmup = CompletedSet(reps: 10, weight: 45, setType: .warmup)
        XCTAssertFalse(warmup.isWorkingSet)
    }

    // MARK: - Codable back-compat (documents written before these fields existed)

    func testLegacyCompletedSetJSONDecodes() throws {
        let json = #"{"id":"s1","reps":8,"weight":100}"#
        let set = try JSONDecoder().decode(CompletedSet.self, from: Data(json.utf8))
        XCTAssertNil(set.setType)
        XCTAssertNil(set.effort)
        XCTAssertEqual(set.resolvedSetType, .normal)
        XCTAssertTrue(set.isWorkingSet, "Old history had no warmup flag — those sets stay counted, as before")
    }

    func testLegacyExerciseSetJSONBridgesWarmup() throws {
        let json = #"{"id":"e1","isCompleted":true,"isWarmup":true,"reps":5,"weight":45,"distance":0,"durationInSeconds":0}"#
        let set = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        XCTAssertNil(set.setType)
        XCTAssertEqual(set.resolvedSetType, .warmup)
        XCTAssertFalse(set.isWorkingSet)
    }

    func testEffortSurvivesRoundTrip() throws {
        let original = CompletedSet(reps: 6, weight: 185, setType: .normal, effort: SetEffort(scale: .rir, value: 2))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompletedSet.self, from: data)
        let effort = try XCTUnwrap(decoded.effort)
        XCTAssertEqual(effort.scale, .rir)
        XCTAssertEqual(effort.value, 2, accuracy: 0.001)
        XCTAssertEqual(effort.normalizedRPE, 8, accuracy: 0.001)
    }

    // MARK: - Analytics regression: warmups excluded from volume & 1RM

    func testWeeklyRecapVolumeExcludesWarmupSets() {
        let calendar = Calendar.current
        let weekEnding = Date()
        let inWindow = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: weekEnding))!
            .addingTimeInterval(12 * 60 * 60)

        let warmup = CompletedSet(reps: 5, weight: 500, setType: .warmup)   // absurd heavy warmup: 2500 if counted
        let working = CompletedSet(reps: 10, weight: 100, setType: .normal) // the only real 1000 of volume
        let exercise = CompletedExercise(
            exerciseName: "Back Squat",
            exercise: RoutineExercise(name: "Back Squat", type: .strength, sets: []),
            sets: [warmup, working]
        )
        let session = WorkoutSessionLog(date: inWindow, routineID: "r1", completedExercises: [exercise])

        let recap = WeeklyRecapBuilder.build(
            weekEnding: weekEnding,
            calendar: calendar,
            dailyLogs: [],
            sessionLogs: [session],
            priorSessionLogs: [],
            weightHistory: [],
            runs: [],
            calorieGoal: 2200
        )

        XCTAssertEqual(recap.totalVolume, 1000, accuracy: 0.01,
                       "Warmup sets must not inflate weekly training volume")
    }
}
