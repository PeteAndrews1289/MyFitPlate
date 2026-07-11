import XCTest
@testable import MyFitPlate

@MainActor
final class ScreenshotDemoDataTests: XCTestCase {
    func testCustomProductPageAliasesResolveToStableScreens() {
        let aliases = [
            "cpp-trust": "trust",
            "cpp-logging": "food-search",
            "cpp-dining": "builder",
            "cpp-strength": "train",
            "cpp-running": "runs",
            "cpp-weight": "reports",
            "cpp-meal-plan": "meal-plan"
        ]

        for (alias, expected) in aliases {
            XCTAssertEqual(ScreenshotDemoData.canonicalScreenName(alias), expected)
        }
    }

    func testRunningFixtureIsUsefulWithoutHealthKit() {
        let runs = ScreenshotDemoData.runningDemoRuns

        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(Set(runs.map(\.id)).count, runs.count)
        XCTAssertTrue(runs.allSatisfy { $0.distanceMeters >= 5_000 })
        XCTAssertTrue(runs.allSatisfy { !$0.splits.isEmpty })
        XCTAssertTrue(runs.allSatisfy(\.hasRoute))
    }
}
