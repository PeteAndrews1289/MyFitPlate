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

    @MainActor
    func testHomeTrustHubHasNavigationAndInteractiveRows() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "home"
        ]
        app.launch()

        let trustButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Review Food Trust"))
            .firstMatch
        XCTAssertTrue(trustButton.waitForExistence(timeout: 8), "Home should expose the food trust review")
        XCTAssertTrue(
            app.staticTexts["Daily log"].waitForExistence(timeout: 8),
            "Home should finish loading the deterministic diary before interaction"
        )
        let trustHittable = expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: trustButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [trustHittable], timeout: 5), .completed)
        trustButton.tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Trust Hub should always provide a visible dismissal")
        XCTAssertTrue(doneButton.isHittable, "Trust Hub dismissal should be tappable")

        let verifiedFood = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Greek Yogurt Parfait"))
            .firstMatch
        XCTAssertTrue(verifiedFood.waitForExistence(timeout: 5), "Verified foods should appear in Trust Hub")
        XCTAssertTrue(verifiedFood.isEnabled, "Trust Hub food rows should remain interactive")

        doneButton.tap()
        XCTAssertTrue(
            app.buttons["quick_log_button"].waitForExistence(timeout: 5),
            "Done should return to Home"
        )
    }

    @MainActor
    func testWeeklyTrainingFuelReportRendersPopulatedAndScrollable() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "weekly-report"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Training & Fuel"].waitForExistence(timeout: 10),
            "The unified weekly report should open directly in screenshot mode"
        )
        XCTAssertTrue(
            app.staticTexts["weekly_report_headline"].waitForExistence(timeout: 10),
            "The report should finish its deterministic data load"
        )
        XCTAssertTrue(app.otherElements["weekly_report_strength"].exists)

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "Unified Training and Fuel report - top"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        let fueling = app.otherElements["weekly_report_fueling"]
        for _ in 0..<6 where !fueling.exists || !fueling.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(fueling.waitForExistence(timeout: 5), "Fueling denominators should be reachable")

        let middleScreenshot = XCTAttachment(screenshot: app.screenshot())
        middleScreenshot.name = "Unified Training and Fuel report - running and fueling"
        middleScreenshot.lifetime = .keepAlways
        add(middleScreenshot)

        let share = app.descendants(matching: .any)["weekly_report_share"]
        for _ in 0..<8 where !share.exists || !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.otherElements["weekly_report_context"].exists, "Outcome context should be reachable")
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The privacy-reviewed share menu should be reachable")

        let bottomScreenshot = XCTAttachment(screenshot: app.screenshot())
        bottomScreenshot.name = "Unified Training and Fuel report - context and share"
        bottomScreenshot.lifetime = .keepAlways
        add(bottomScreenshot)
    }

    @MainActor
    func testWeeklyTrainingFuelReportSupportsLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "weekly-report",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let headline = app.staticTexts["weekly_report_headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertLessThanOrEqual(headline.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(headline.frame.minX, app.frame.minX - 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unified Training and Fuel report - accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCustomProductPageDeepLinksOpenExactDestinations() throws {
        let app = XCUIApplication()
        let destinations = [
            ("myfitplate://food-search", "Log food"),
            ("myfitplate://trust", "Trust Hub"),
            ("myfitplate://builder", "Fast Food"),
            ("myfitplate://runs", "Running"),
            ("myfitplate://meal-plan", "Meal plan")
        ]

        for (url, title) in destinations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-deep-link-url",
                url
            ]
            app.launch()

            let navigationTitle = app.navigationBars[title]
            let visibleTitle = app.staticTexts[title]
            XCTAssertTrue(
                navigationTitle.waitForExistence(timeout: 8) || visibleTitle.waitForExistence(timeout: 3),
                "\(url) should open \(title), not a neighboring tab"
            )
        }
    }
}
