import XCTest
@testable import MyFitPlateCore

final class RunRecoveryRulesTests: XCTestCase {

    func testShortRunDoesNotTriggerRecoveryPrompt() {
        let shortRun = Run(
            source: .recorded,
            startDate: Date().addingTimeInterval(-600),
            endDate: Date(),
            distanceMeters: 1500,
            movingSeconds: 600,
            activeCalories: 90
        )

        let target = RunRecoveryRules.calculateTarget(for: shortRun, weightLbs: 165.0)
        XCTAssertNil(target, "Short run under threshold should not require formal glycogen refuel alert")
    }

    func testModerateRunTriggersRecoveryTarget() {
        let run = Run(
            source: .recorded,
            startDate: Date().addingTimeInterval(-1800),
            endDate: Date(),
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: 350
        )

        guard let target = RunRecoveryRules.calculateTarget(for: run, weightLbs: 165.0) else {
            XCTFail("5k run should trigger recovery target")
            return
        }

        XCTAssertEqual(target.runID, run.id)
        XCTAssertGreaterThanOrEqual(target.targetCarbGrams, 30)
        XCTAssertLessThanOrEqual(target.targetCarbGrams, 60)
        XCTAssertGreaterThanOrEqual(target.targetProteinGrams, 20)
        XCTAssertLessThanOrEqual(target.targetProteinGrams, 40)
        XCTAssertEqual(target.rehydrateMilliLiters, Int((350.0 * 1.3).rounded()))
        XCTAssertEqual(target.windowMinutes, 45)
        XCTAssertFalse(target.isExpired)
    }

    func testLongRunCapAtMaxCarbsAndProtein() {
        let longRun = Run(
            source: .recorded,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date(),
            distanceMeters: 25000,
            movingSeconds: 7200,
            activeCalories: 1800
        )

        guard let target = RunRecoveryRules.calculateTarget(for: longRun, weightLbs: 165.0) else {
            XCTFail("25k run should trigger recovery target")
            return
        }

        // 165 lbs is ~74.8 kg. Max carb ratio is 1.2g/kg ≈ 90g carbs.
        XCTAssertEqual(target.targetCarbGrams, 90, accuracy: 1)
        // Max protein cap is 45g.
        XCTAssertEqual(target.targetProteinGrams, 45)
    }

    func testWindowExpiry() {
        let pastRun = Run(
            source: .recorded,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-3600), // Ended 60 mins ago
            distanceMeters: 10000,
            movingSeconds: 3600,
            activeCalories: 700
        )

        guard let target = RunRecoveryRules.calculateTarget(for: pastRun, weightLbs: 165.0) else {
            XCTFail("10k run should trigger recovery target")
            return
        }

        XCTAssertTrue(target.isExpired, "Window of 45 minutes should be expired after 60 minutes")
        XCTAssertEqual(target.remainingMinutes, 0)
    }
}
