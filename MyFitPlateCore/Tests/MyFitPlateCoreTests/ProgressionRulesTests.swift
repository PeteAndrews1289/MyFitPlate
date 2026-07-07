import XCTest
@testable import MyFitPlateCore

final class ProgressionRulesTests: XCTestCase {

    private func exercise(_ sets: [CompletedSet]) -> CompletedExercise {
        CompletedExercise(
            exerciseName: "Bench",
            exercise: RoutineExercise(name: "Bench", sets: []),
            sets: sets
        )
    }

    func testNoPreviousGivesNoSuggestion() {
        XCTAssertNil(ProgressionRules.suggest(previous: nil, targetReps: 8))
    }

    func testRepsInReserveAddsWeight() throws {
        let prev = exercise([CompletedSet(reps: 8, weight: 135, effort: SetEffort(scale: .rpe, value: 7))])
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8, weightIncrement: 5))
        XCTAssertEqual(s.move, .addWeight)
        XCTAssertEqual(s.suggestedWeight, 140, accuracy: 0.001)
        XCTAssertEqual(s.suggestedReps, 8)
    }

    func testHardButCompleteAddsARep() throws {
        let prev = exercise([CompletedSet(reps: 8, weight: 135, effort: SetEffort(scale: .rpe, value: 8))])
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8))
        XCTAssertEqual(s.move, .addRep)
        XCTAssertEqual(s.suggestedWeight, 135, accuracy: 0.001)
        XCTAssertEqual(s.suggestedReps, 9)
    }

    func testNearMaxEffortHolds() throws {
        let prev = exercise([CompletedSet(reps: 8, weight: 135, effort: SetEffort(scale: .rir, value: 0))]) // RIR 0 == RPE 10
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8))
        XCTAssertEqual(s.move, .hold)
        XCTAssertEqual(s.suggestedWeight, 135, accuracy: 0.001)
    }

    func testMissedRepsHoldsAndTargetsTheRepGoal() throws {
        let prev = exercise([CompletedSet(reps: 5, weight: 135, effort: SetEffort(scale: .rpe, value: 7))])
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8))
        XCTAssertEqual(s.move, .hold)
        XCTAssertEqual(s.suggestedReps, 8, "Aim for the rep goal before adding load")
    }

    func testNoEffortLoggedButHitRepsAddsWeight() throws {
        let prev = exercise([CompletedSet(reps: 8, weight: 100)])
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8, weightIncrement: 5))
        XCTAssertEqual(s.move, .addWeight)
        XCTAssertEqual(s.suggestedWeight, 105, accuracy: 0.001)
    }

    func testWarmupSetsAreIgnoredForTheReference() throws {
        let prev = exercise([
            CompletedSet(reps: 5, weight: 300, setType: .warmup),       // heavy "warmup" must not anchor
            CompletedSet(reps: 8, weight: 135, setType: .normal, effort: SetEffort(scale: .rpe, value: 7))
        ])
        let s = try XCTUnwrap(ProgressionRules.suggest(previous: prev, targetReps: 8, weightIncrement: 5))
        XCTAssertEqual(s.referenceWeight, 135, accuracy: 0.001)
        XCTAssertEqual(s.suggestedWeight, 140, accuracy: 0.001)
    }

    func testTargetRepsLowEndParsing() {
        XCTAssertEqual(ProgressionRules.targetRepsLowEnd("8-12"), 8)
        XCTAssertEqual(ProgressionRules.targetRepsLowEnd("5"), 5)
        XCTAssertEqual(ProgressionRules.targetRepsLowEnd("AMRAP"), 0)
    }
}
