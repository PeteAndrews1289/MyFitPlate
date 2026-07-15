import XCTest
@testable import MyFitPlateCore

final class MuscleRecoveryRulesTests: XCTestCase {
    func testSpecificLegPatternsDoNotFallThroughToGenericUpperBodyRules() {
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Leg Press"), [.legs])
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Seated Leg Curl"), [.legs])
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Calf Raise"), [.legs])
    }

    func testCompoundMovementsCreditAllBroadRegions() {
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Romanian Deadlift"), [.back, .legs])
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Barbell Bench Press"), [.chest, .arms])
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Pull-up"), [.back, .arms])
        XCTAssertEqual(MuscleRecoveryRules.muscleGroups(for: "Overhead Press"), [.shoulders])
    }

    func testSleepScoreAdjustsRecoveryWindowConservatively() {
        XCTAssertEqual(MuscleRecoveryRules.wellnessMultiplier(90), 0.9)
        XCTAssertEqual(MuscleRecoveryRules.wellnessMultiplier(70), 1)
        XCTAssertEqual(MuscleRecoveryRules.wellnessMultiplier(50), 1.1)
        XCTAssertEqual(MuscleRecoveryRules.wellnessMultiplier(20), 1.2)
        XCTAssertEqual(MuscleRecoveryRules.wellnessMultiplier(nil), 1)
    }

    func testEstimateUsesExplicitReferenceDateAndHonestLinearProgress() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let estimate = MuscleRecoveryEstimate(
            group: .chest,
            lastTrained: now.addingTimeInterval(-28 * 3_600),
            lastSessionSets: 8,
            recoveryHours: 56,
            sleepMultiplier: 1,
            asOf: now
        )

        XCTAssertEqual(estimate.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(estimate.roundedPercentage, 50)
        XCTAssertEqual(estimate.hoursUntilReady, 28, accuracy: 0.0001)
        XCTAssertEqual(estimate.status, .recovering)
        XCTAssertFalse(estimate.isReady)
    }

    func testReadyAndNoSignalStatesRemainDistinct() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let ready = MuscleRecoveryEstimate(
            group: .arms,
            lastTrained: now.addingTimeInterval(-72 * 3_600),
            lastSessionSets: 6,
            recoveryHours: 40,
            sleepMultiplier: 1,
            asOf: now
        )
        let noSignal = MuscleRecoveryEstimate(
            group: .core,
            lastTrained: nil,
            lastSessionSets: 0,
            recoveryHours: 44,
            sleepMultiplier: 1,
            asOf: now
        )

        XCTAssertEqual(ready.status, .ready)
        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(noSignal.status, .noRecentSignal)
        XCTAssertFalse(noSignal.isReady)
    }

    func testHigherRecentVolumeExtendsWindowWithinBounds() {
        let light = MuscleRecoveryRules.recoveryWindowHours(
            group: .arms,
            sets: 2,
            wellnessMultiplier: 1
        )
        let heavy = MuscleRecoveryRules.recoveryWindowHours(
            group: .arms,
            sets: 20,
            wellnessMultiplier: 1
        )

        XCTAssertEqual(light, 32, accuracy: 0.0001)
        XCTAssertEqual(heavy, 60, accuracy: 0.0001)
        XCTAssertGreaterThan(heavy, light)
    }
}
