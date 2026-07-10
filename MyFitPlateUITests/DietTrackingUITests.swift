import XCTest

final class DietTrackingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testQuickLogMenuOpens() throws {
        let app = XCUIApplication()
        
        let quickLogButton = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        let quickLogHittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickLogButton)
        XCTAssertEqual(XCTWaiter.wait(for: [quickLogHittable], timeout: 5), .completed)

        quickLogButton.tap()
        
        let scanBarcodeBtn = app.buttons["Scan barcode"]
        XCTAssertTrue(scanBarcodeBtn.waitForExistence(timeout: 2), "Primary Quick Log options should appear")

        let moreOptionsButton = app.buttons["More options"]
        XCTAssertTrue(moreOptionsButton.exists, "Specialty logging tools should be collapsible")
        moreOptionsButton.tap()

        let logCameraBtn = app.buttons["Log with camera"]
        XCTAssertTrue(logCameraBtn.waitForExistence(timeout: 2), "Expanded Quick Log options should appear")
    }
}
