import XCTest

final class DietTrackingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"]
        app.launch()
    }

    func testQuickLogMenuOpens() throws {
        let quickLogButton = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        let quickLogHittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickLogButton)
        XCTAssertEqual(XCTWaiter.wait(for: [quickLogHittable], timeout: 5), .completed)
        XCTAssertTrue(app.frame.contains(quickLogButton.frame))
        XCTAssertLessThanOrEqual(app.buttons["tab_reports"].frame.maxX, quickLogButton.frame.minX)

        quickLogButton.tap()
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["food_search_action_barcode"].isHittable)
        XCTAssertTrue(app.buttons["food_search_action_camera"].isHittable)
        app.buttons["food_search_more_actions"].tap()
        XCTAssertTrue(app.buttons["Running"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Log exercise"].isHittable)
    }
}
