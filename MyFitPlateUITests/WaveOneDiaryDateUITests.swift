import XCTest

final class WaveOneDiaryDateUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCalendarCancelIsInertAndTodayRemainsAvailable() {
        let app = launch()
        let calendar = app.buttons["home_diary_calendar"]
        let original = calendar.label
        XCTAssertFalse(app.buttons["home_diary_next"].isEnabled, "Consumed food cannot navigate into tomorrow")
        app.buttons["home_diary_previous"].tap()
        XCTAssertNotEqual(calendar.label, original)
        let historical = calendar.label
        calendar.tap()
        jumpSixMonths(in: app)
        app.buttons["diary_calendar_cancel"].tap()
        XCTAssertEqual(calendar.label, historical, "Calendar review is inert until Show day")
        XCTAssertTrue(app.buttons["home_diary_today"].isHittable)
        app.buttons["home_diary_today"].tap()
        XCTAssertEqual(calendar.label, original)
        XCTAssertFalse(app.buttons["home_diary_next"].isEnabled)
        attach(app, "Diary date - explicit Today and inert calendar Cancel")
    }

    @MainActor
    func testSixMonthJumpKeepsDestinationAfterSearchAndForegrounding() {
        let app = launch()
        let calendar = app.buttons["home_diary_calendar"]
        calendar.tap()
        jumpSixMonths(in: app)
        app.buttons["diary_calendar_apply"].tap()
        let historical = calendar.label
        XCTAssertEqual(calendar.value as? String, "Historical day")
        XCTAssertTrue(app.staticTexts["home_historical_target_scope"].exists)
        let addFood = app.buttons["diary_add_food"]
        reveal(addFood, in: app); addFood.tap()
        let destination = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let sixMonthsAgo = gregorian.date(byAdding: .month, value: -6, to: Date())!
        let formatter = DateFormatter()
        formatter.calendar = gregorian; formatter.timeZone = gregorian.timeZone; formatter.dateStyle = .full
        XCTAssertTrue(destination.label.contains(formatter.string(from: sixMonthsAgo)))
        app.navigationBars["Log food"].buttons["Done"].tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        XCTAssertEqual(calendar.label, historical)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(calendar.waitForExistence(timeout: 8))
        XCTAssertEqual(calendar.label, historical, "Foregrounding must not silently replace the reviewed day with Today")
        attach(app, "Diary date - six-month destination survives search and foreground")
    }

    @MainActor
    func testDateControlsStayPinnedAndEntirelyVisibleAtLargestText() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["home_diary_previous"].tap()
        app.scrollViews["home_scroll"].swipeUp()
        for id in ["home_diary_previous", "home_diary_next", "home_diary_calendar", "home_diary_today"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, id)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX - 1, id)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX + 1, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
        XCTAssertTrue(app.buttons["home_diary_today"].isEnabled)
        attach(app, "Diary date - pinned calendar and Today at largest text")
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"] + flags
        app.launch()
        let fixture = app.buttons["home_diary_calendar"]
        if !fixture.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func jumpSixMonths(in app: XCUIApplication) {
        let jump = app.buttons["diary_calendar_jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5)); jump.tap()
        let sixMonths = app.buttons["6 months ago"]
        XCTAssertTrue(sixMonths.waitForExistence(timeout: 5)); sixMonths.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists, element.isHittable { return }
            app.scrollViews["home_scroll"].swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
