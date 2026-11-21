import XCTest
@testable import MyFitPlateCore

final class WorkoutDurationEntryRulesTests: XCTestCase {
    func testPluralMinutesAndRangesDoNotTurnIntoSeconds() {
        XCTAssertEqual(WorkoutDurationEntryRules.targetSeconds("20 minutes"), 1200)
        XCTAssertEqual(WorkoutDurationEntryRules.targetSeconds("10–15 min"), 600)
        XCTAssertEqual(WorkoutDurationEntryRules.targetSeconds("45s per side"), 45)
        XCTAssertEqual(WorkoutDurationEntryRules.targetSeconds("1.5 hours"), 5400)
        XCTAssertEqual(WorkoutDurationEntryRules.targetSeconds("45", bareNumberIsSeconds: true), 45)
        XCTAssertNil(WorkoutDurationEntryRules.targetSeconds("5 km"))
        XCTAssertNil(WorkoutDurationEntryRules.targetSeconds("1000 meters"))
        XCTAssertNil(WorkoutDurationEntryRules.targetSeconds("0 min"))
        XCTAssertEqual(WorkoutDurationEntryRules.seconds(fromMinutes: "0.5"), 30)
        XCTAssertNil(WorkoutDurationEntryRules.seconds(fromMinutes: "-3"))
    }

    func testMeasuredClockUsesValidatedTypedDurationAndKeepsLegacyUnits() {
        let prescribed = WorkoutPrescription(kind: .duration, lowerBound: 45, upperBound: 60)
        XCTAssertEqual(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: prescribed, legacyTarget: "2 min"), 45)
        XCTAssertEqual(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: nil, legacyTarget: "1.5 min"), 90)
        XCTAssertEqual(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: nil, legacyTarget: "45", bareNumberIsSeconds: true), 45)
        XCTAssertEqual(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: WorkoutPrescription(kind: .duration, lowerBound: 86_400), legacyTarget: nil), 86_400)
        XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: nil, legacyTarget: "25 hours"))
        XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: nil, legacyTarget: "0.1 seconds"))
        XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: nil, legacyTarget: nil))
    }

    func testMalformedDurationCannotTrapOrFallThroughToStaleLegacyTarget() {
        for value in [Double.nan, .infinity, -.infinity, -1, 0, 0.5, 86_401, Double(Int.max), Double.greatestFiniteMagnitude] {
            let prescribed = WorkoutPrescription(kind: .duration, lowerBound: value)
            XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: prescribed, legacyTarget: "30 seconds"))
        }
        var future = WorkoutPrescription(kind: .duration, lowerBound: 30)
        future.schemaVersion = 2
        XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: future, legacyTarget: "30 seconds"))
        let reversedRange = WorkoutPrescription(kind: .duration, lowerBound: 60, upperBound: 30)
        XCTAssertNil(WorkoutDurationEntryRules.intervalTargetSeconds(prescription: reversedRange, legacyTarget: "30 seconds"))
        let unknown = WorkoutDurationEntryRules.intervalTargetSeconds(prescription: reversedRange, legacyTarget: "30 seconds")
        var timer = WorkoutIntervalTimerState(setID: "hold", targetSeconds: unknown)
        XCTAssertNoThrow(try timer.start(at: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertTrue(timer.isValid, "An invalid target cannot prevent a free measured hold")
    }
}
