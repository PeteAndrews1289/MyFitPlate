import XCTest
@testable import MyFitPlateCore

final class AppReviewPromptCoordinatorTests: XCTestCase {
    private let suiteName = "app-review-prompt-tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRequiresThreeDistinctSessionsAcrossThreeDays() {
        let start = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(60)))
        XCTAssertTrue(register("three", at: start.addingTimeInterval(3 * 24 * 60 * 60)))
    }

    func testDuplicateSessionDoesNotAdvanceEligibility() {
        let start = Date(timeIntervalSince1970: 20_000)

        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("one", at: start.addingTimeInterval(4 * 24 * 60 * 60)))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(5 * 24 * 60 * 60)))
    }

    func testRequestsOnlyOncePerVersionAndHonorsCooldown() {
        let start = Date(timeIntervalSince1970: 30_000)
        XCTAssertFalse(register("one", at: start))
        XCTAssertFalse(register("two", at: start.addingTimeInterval(60)))
        XCTAssertTrue(register("three", at: start.addingTimeInterval(3 * 24 * 60 * 60)))

        XCTAssertFalse(register("four", version: "2.2", at: start.addingTimeInterval(130 * 24 * 60 * 60)))
        XCTAssertFalse(register("five", version: "2.3", at: start.addingTimeInterval(100 * 24 * 60 * 60)))
        XCTAssertTrue(register("six", version: "2.3", at: start.addingTimeInterval(130 * 24 * 60 * 60)))
    }

    func testRejectsMissingSessionOrVersion() {
        XCTAssertFalse(register("", at: Date()))
        XCTAssertFalse(register("session", version: "", at: Date()))
    }

    private func register(
        _ sessionID: String,
        version: String = "2.2",
        at date: Date
    ) -> Bool {
        AppReviewPromptCoordinator.registerCompletedSession(
            id: sessionID,
            appVersion: version,
            now: date,
            userDefaults: defaults
        )
    }
}
