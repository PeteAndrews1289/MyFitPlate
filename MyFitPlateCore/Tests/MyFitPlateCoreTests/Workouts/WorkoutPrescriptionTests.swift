import XCTest
@testable import MyFitPlateCore

final class WorkoutPrescriptionTests: XCTestCase {
    func testLegacyRepetitionRangeIsRecognizedWithoutChangingOriginalText() throws {
        let target = try XCTUnwrap(WorkoutPrescription.legacy(" 8-12 reps ", type: .strength))
        XCTAssertEqual(target.kind, .repetitions)
        XCTAssertEqual(target.lowerBound, 8)
        XCTAssertEqual(target.upperBound, 12)
        XCTAssertEqual(target.originalText, " 8-12 reps ")
        XCTAssertNil(target.validationMessage)
    }

    func testAmbiguousLegacyTargetsRemainWritten() {
        for text in ["5+", "3 × 8", "75% @ RPE 8", "8 reps / side", "light", "1:30"] {
            let target = WorkoutPrescription.legacy(text, type: .strength)
            XCTAssertEqual(target?.kind, .manual, text)
            XCTAssertEqual(target?.originalText, text)
            XCTAssertEqual(target?.targetText, text)
        }
        XCTAssertEqual(WorkoutPrescription.legacy("20", type: .cardio)?.kind, .manual)
    }

    func testKnownTimeAndDistanceUnitsHaveOneCanonicalBasis() {
        XCTAssertEqual(WorkoutPrescription.legacy("2-3 min", type: .cardio)?.lowerBound, 120)
        XCTAssertEqual(WorkoutPrescription.legacy("2-3 min", type: .cardio)?.upperBound, 180)
        XCTAssertEqual(WorkoutPrescription.legacy("5 km", type: .cardio)?.lowerBound, 5_000)
        XCTAssertEqual(WorkoutPrescription.legacy("30 sec", type: .flexibility)?.lowerBound, 30)
    }

    func testRepetitionValidationRejectsFractionalReversedAndUnboundedTargets() {
        XCTAssertNotNil(WorkoutPrescription(kind: .repetitions, lowerBound: 1.5).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .repetitions, lowerBound: 12, upperBound: 8).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .repetitions, lowerBound: .nan).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .repetitions, lowerBound: 1, upperBound: .infinity).validationMessage)
        XCTAssertNil(WorkoutPrescription(kind: .repetitions, lowerBound: 8, upperBound: 12).validationMessage)
    }

    func testEffortUsesPrescribedScaleAndBounds() {
        XCTAssertNil(WorkoutPrescription(kind: .amrap, effort: SetEffort(scale: .rir, value: 0)).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .amrap, effort: SetEffort(scale: .rpe, value: 0)).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .amrap, effort: SetEffort(scale: .rir, value: 11)).validationMessage)
        XCTAssertNotNil(WorkoutPrescription(kind: .amrap, effort: SetEffort(scale: .rpe, value: .nan)).validationMessage)
    }

    func testPercentageNeedsExplicitNamedDatedReference() {
        var target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, loadPercentage: 75)
        XCTAssertNotNil(target.validationMessage)
        XCTAssertNil(target.resolvedWeightPounds)
        target.loadReference = .init(label: "Squat training max", weightPounds: 200, date: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(target.validationMessage)
        XCTAssertEqual(target.resolvedWeightPounds, 150)
        XCTAssertTrue(target.summary.contains("75%"))
        XCTAssertTrue(target.summary.contains("Squat training max"))
        target.loadReference?.label = " "
        XCTAssertNotNil(target.validationMessage)
    }

    func testNewStrengthLoggerSeedsTypedTargetsWithoutConvertingEffortIntoPerformedEffort() {
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rpe, value: 8), loadPercentage: 75,
            loadReference: .init(label: "Squat max", weightPounds: 200, date: Date()))
        let source = ExerciseSet(id: "original-set", target: target.targetText, prescription: target)
        let seeded = target.seedingEmptyValues(in: source, type: .strength)
        XCTAssertEqual(seeded.id, source.id)
        XCTAssertEqual(seeded.reps, 5)
        XCTAssertEqual(seeded.weight, 150)
        XCTAssertNil(seeded.effort)
        XCTAssertEqual(seeded.prescription, target)
        XCTAssertFalse(seeded.isCompleted)
        XCTAssertEqual(source.reps, 0)
        XCTAssertEqual(source.weight, 0)
    }

    func testSavedAndCompletedValuesAreNeverRewrittenByTargetSeeding() {
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5)
        let saved = ExerciseSet(id: "saved", reps: 9, weight: 127.345)
        let seeded = target.seedingEmptyValues(in: saved, type: .strength)
        XCTAssertEqual(seeded.reps, 9)
        XCTAssertEqual(seeded.weight, 127.345)
        let completed = ExerciseSet(id: "finished", isCompleted: true, reps: 0)
        XCTAssertEqual(target.seedingEmptyValues(in: completed, type: .strength).reps, 0)
    }

    func testDistanceTargetSeedsExistingMilesLoggerExplicitly() throws {
        let target = WorkoutPrescription(kind: .distance, lowerBound: 5_000)
        let set = target.seedingEmptyValues(in: ExerciseSet(), type: .cardio)
        XCTAssertEqual(set.distance * 1_609.344, 5_000, accuracy: 0.000_001)
        XCTAssertEqual(set.durationInSeconds, 0, "A distance target cannot invent performed time")
        let duration = WorkoutPrescription(kind: .duration, lowerBound: 90)
        XCTAssertEqual(duration.seedingEmptyValues(in: ExerciseSet(), type: .flexibility).durationInSeconds, 90)
    }

    func testAMRAPAndWrittenTargetsDoNotInventRepetitions() {
        let amrap = WorkoutPrescription(kind: .amrap)
        XCTAssertEqual(amrap.seedingEmptyValues(in: ExerciseSet(), type: .strength).reps, 0)
        let manual = WorkoutPrescription(kind: .manual, originalText: "As instructed")
        XCTAssertEqual(manual.seedingEmptyValues(in: ExerciseSet(), type: .strength).reps, 0)
        XCTAssertEqual(WorkoutPrescription.legacy("AMRAP", type: .strength)?.kind, .amrap)
    }

    func testTypedTargetRoundTripsInsideHistoricalExerciseWithoutChangingActualValues() throws {
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rir, value: 2), notes: "3-second eccentric")
        let actual = ExerciseSet(id: "history-set", isCompleted: true, target: target.targetText,
            effort: SetEffort(scale: .rpe, value: 9), prescription: target, reps: 7, weight: 135)
        let restored = try JSONDecoder().decode(ExerciseSet.self, from: JSONEncoder().encode(actual))
        XCTAssertEqual(restored.prescription, target)
        XCTAssertEqual(restored.effort, SetEffort(scale: .rpe, value: 9))
        XCTAssertEqual(restored.reps, 7)
        XCTAssertEqual(restored.weight, 135)
        XCTAssertTrue(restored.isCompleted)
    }

    func testLegacySetDecodeDoesNotInventPrescription() throws {
        let data = Data(#"{"id":"legacy-set","isCompleted":true,"target":"5+","reps":6,"weight":135}"#.utf8)
        let set = try JSONDecoder().decode(ExerciseSet.self, from: data)
        XCTAssertNil(set.prescription)
        XCTAssertEqual(set.target, "5+")
        XCTAssertEqual(set.reps, 6)
    }

    func testUnsupportedPrescriptionCannotBeSubmittedInBlock() throws {
        var target = WorkoutPrescription(kind: .repetitions, lowerBound: 5)
        target.schemaVersion = 2
        XCTAssertNotNil(target.validationMessage)
        XCTAssertEqual(target.seedingEmptyValues(in: ExerciseSet(), type: .strength).reps, 0)
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutPrescription.self, from: JSONEncoder().encode(target)))
    }
}
