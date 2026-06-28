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

        let quickLogButton = app.buttons["Quick log"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        quickLogButton.tap()

        let searchFoodButton = app.buttons["Search Food"]
        XCTAssertTrue(searchFoodButton.waitForExistence(timeout: 2), "Search Food option should be visible")
        searchFoodButton.tap()

        let searchField = app.searchFields["Search foods, meals, brands..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Food search field should appear")

        searchField.tap()
        searchField.typeText("Apple")

        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "Search results should populate")
    }
}
