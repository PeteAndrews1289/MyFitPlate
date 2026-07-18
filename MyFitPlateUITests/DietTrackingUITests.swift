import XCTest

final class DietTrackingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testQuickLogMenuOpens() throws {
        let quickLogButton = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        let quickLogHittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickLogButton)
        XCTAssertEqual(XCTWaiter.wait(for: [quickLogHittable], timeout: 5), .completed)
        XCTAssertEqual(
            quickLogButton.frame.midX,
            app.frame.midX,
            accuracy: 4,
            "Quick log should remain centered when navigation tabs change"
        )

        let scanBarcodeBtn = app.buttons["quick_log_scan_barcode"]
        quickLogButton.press(forDuration: 0.1)
        if !scanBarcodeBtn.waitForExistence(timeout: 5) {
            XCTContext.runActivity(named: "Recover from a simulator-dropped input event") { _ in
                XCTAssertTrue(quickLogButton.isHittable, "Quick log should remain tappable after a dropped simulator event")
                quickLogButton.press(forDuration: 0.1)
            }
        }
        XCTAssertTrue(scanBarcodeBtn.waitForExistence(timeout: 5), "Primary Quick Log options should appear")

        let moreOptionsButton = app.buttons["quick_log_more_options"]
        XCTAssertTrue(moreOptionsButton.exists, "Specialty logging tools should be collapsible")
        moreOptionsButton.tap()

        let logCameraBtn = app.buttons["quick_log_log_with_camera"]
        if !logCameraBtn.waitForExistence(timeout: 5), moreOptionsButton.label == "More options" {
            XCTContext.runActivity(named: "Recover from a simulator-dropped expansion event") { _ in
                XCTAssertTrue(moreOptionsButton.isHittable, "More options should remain tappable after a dropped simulator event")
                moreOptionsButton.tap()
            }
        }
        XCTAssertTrue(logCameraBtn.waitForExistence(timeout: 5), "Expanded Quick Log options should appear")

        let runningButton = app.buttons["quick_log_running"]
        XCTAssertTrue(runningButton.waitForExistence(timeout: 5), "The final specialty action should be present")
        for _ in 0..<3 where !runningButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(runningButton.isHittable, "Every expanded Quick Log action should be reachable on compact screens")
    }
}
