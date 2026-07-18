//
//  MyFitPlateUITestsLaunchTests.swift
//  MyFitPlateUITests
//
//  Created by Peter Andrews on 6/27/26.
//

import XCTest

final class MyFitPlateUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "MyFitPlate should reach the foreground after launch"
        )

        XCTAssertTrue(
            app.buttons["quick_log_button"].waitForExistence(timeout: 10),
            "MyFitPlate should finish loading its deterministic Home state"
        )

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 10),
            "MyFitPlate should close its automation session cleanly"
        )
    }
}
