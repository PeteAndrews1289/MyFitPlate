import XCTest

final class WorkoutDashboardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "train"
        ]
        app.launch()
    }

    func testWorkoutDashboardNavigationAndButtons() throws {
        let trainHeader = app.staticTexts["train_screen_header"].firstMatch
        XCTAssertTrue(trainHeader.waitForExistence(timeout: 10), "Train should open directly for deterministic dashboard coverage")

        XCTAssertTrue(app.descendants(matching: .any)["train_next_step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["train_program_week"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["train_readiness"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["muscle_recovery_map"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["running_history_button"].exists)
    }
}
