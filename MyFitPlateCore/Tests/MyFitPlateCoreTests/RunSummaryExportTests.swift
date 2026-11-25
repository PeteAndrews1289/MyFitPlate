import XCTest
@testable import MyFitPlateCore

final class RunSummaryExportTests: XCTestCase {
    func testSummaryRetainsCanonicalDistanceActiveElapsedAndHonestUnknownPauseEvidence() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(id: "private-health-id", source: .imported(appName: "Watch, \"Example\""), startDate: start,
                      endDate: start.addingTimeInterval(1800), distanceMeters: 5000, movingSeconds: 1500, activeCalories: 350)
        let csv = RunSummaryExport.csv(run: run)
        XCTAssertTrue(csv.contains("\"Distance\",\"5000.0\",\"meters\""))
        XCTAssertTrue(csv.contains("\"Active time\",\"1500.0\",\"seconds\""))
        XCTAssertTrue(csv.contains("\"Elapsed time\",\"1800.0\",\"seconds\""))
        XCTAssertTrue(csv.contains("\"Pause evidence\",\"Unknown\""))
        XCTAssertTrue(csv.contains("\"Watch, \"\"Example\"\"\""))
        XCTAssertFalse(csv.contains(run.id))
        XCTAssertFalse(csv.contains("latitude"))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testKnownPauseAndRecoveryRemainSeparateAndSourceTextCannotBecomeFormula() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let timeline = RunPauseTimeline(completeness: .complete, intervals: [
            RunPauseInterval(startDate: start.addingTimeInterval(10), endDate: start.addingTimeInterval(20), origin: .explicitPause),
            RunPauseInterval(startDate: start.addingTimeInterval(30), endDate: start.addingTimeInterval(50), origin: .recoveryGap)
        ])
        let run = Run(source: .imported(appName: "=UNTRUSTED()"), startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 0, movingSeconds: 70, pauseTimeline: timeline)
        let csv = RunSummaryExport.csv(run: run)
        XCTAssertTrue(csv.contains("\"Explicit pause time\",\"10.0\""))
        XCTAssertTrue(csv.contains("\"Recovery gap time\",\"20.0\""))
        XCTAssertTrue(csv.contains("\"Average pace\",\"\""))
        XCTAssertTrue(csv.contains("\"'=UNTRUSTED()\""))
    }
}

extension RunSummaryExportTests {
    func testManualCorrectionExportsProvenanceWithoutPrivateReasonOrInventedElapsedTime() throws {
        var run = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: 6_000, movingSeconds: 1_900, metric: true))
        run.reviewAnnotation = RunReviewAnnotation(receiptID: "private-receipt", changedAt: run.endDate,
            reason: "Private correction explanation", originalDistanceMeters: 5_000, originalMovingSeconds: 1_800)
        let csv = RunSummaryExport.csv(run: run)
        XCTAssertTrue(csv.contains("\"Elapsed time\",\"\""))
        XCTAssertTrue(csv.contains("\"Original distance\",\"5000.0\""))
        XCTAssertTrue(csv.contains("\"Original active time\",\"1800.0\""))
        XCTAssertTrue(csv.contains("Reviewed manual correction"))
        XCTAssertFalse(csv.contains("private-receipt"))
        XCTAssertFalse(csv.contains("Private correction explanation"))
    }
}
