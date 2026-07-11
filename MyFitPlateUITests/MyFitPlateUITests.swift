//
//  MyFitPlateUITests.swift
//  MyFitPlateUITests
//
//  Created by Peter Andrews on 6/27/26.
//

import XCTest

final class MyFitPlateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testHomeDashboardLoads() throws {
        let app = XCUIApplication()

        // Wait for the home dashboard to load
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10), "Home dashboard should be visible")

        // Check for key elements like the weekly check-in or progress circles
        let progressElement = app.otherElements["MetabolismProgress"]
        if progressElement.exists {
            XCTAssertTrue(progressElement.isHittable)
        }
    }

    @MainActor
    func testFoodSearchNavigation() throws {
        let app = XCUIApplication()

        let quickLogButton = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        let quickLogHittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickLogButton)
        XCTAssertEqual(XCTWaiter.wait(for: [quickLogHittable], timeout: 5), .completed)
        quickLogButton.tap()

        let searchFoodButton = app.buttons["Search food"]
        XCTAssertTrue(searchFoodButton.waitForExistence(timeout: 5), "Search Food option should be visible")
        searchFoodButton.tap()

        let searchField = app.textFields["Search foods, meals, brands"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Food search field should appear")

        searchField.tap()
        searchField.typeText("Apple")

        let firstResult = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Test Kitchen Apple"))
            .firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "Search results should populate")
    }

    @MainActor
    func testSettingsFeedbackAndShareRowsAreReachable() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "settings"
        ]
        app.launch()

        let feedbackRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Feedback & support"))
            .firstMatch
        let shareRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Share MyFitPlate"))
            .firstMatch

        for _ in 0..<8 where !feedbackRow.isHittable || !shareRow.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 5), "Feedback row should be reachable in Settings")
        XCTAssertTrue(shareRow.waitForExistence(timeout: 5), "App Store sharing row should be reachable in Settings")
        XCTAssertTrue(feedbackRow.isHittable, "Feedback row should be visible and tappable")
        XCTAssertTrue(shareRow.isHittable, "App Store sharing row should be visible and tappable")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings feedback and sharing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
