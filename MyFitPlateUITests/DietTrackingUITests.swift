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
        
        let quickLogButton = app.buttons["Quick log"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        
        quickLogButton.tap()
        
        let logCameraBtn = app.buttons["Log with Camera"]
        XCTAssertTrue(logCameraBtn.waitForExistence(timeout: 2), "Quick Log options should appear")
        
        let scanBarcodeBtn = app.buttons["Scan Barcode"]
        XCTAssertTrue(scanBarcodeBtn.exists, "Scan Barcode should appear")
    }
}
