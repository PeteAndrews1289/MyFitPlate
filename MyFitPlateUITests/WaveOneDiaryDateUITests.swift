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
    func testYesterdayDinnerJumpEditAndSearchKeepMealAndDay() {
        let app = launch(flags: ["-ui-testing-day-review-persistence"])
        let todayEnergy = app.staticTexts["home_calories_remaining"]
        let originalToday = todayEnergy.label
        app.buttons["home_diary_previous"].tap()
        let calendar = app.buttons["home_diary_calendar"]
        let yesterday = calendar.label
        let index = app.buttons["home_diary_index"]
        index.tap()
        app.buttons["Dinner"].tap()
        let food = app.buttons["diary_food_yesterday-salmon"]
        XCTAssertTrue(food.waitForExistence(timeout: 8))
        XCTAssertTrue(food.isHittable)
        XCTAssertTrue(food.label.contains("690"))
        let dinner = app.buttons["diary_toggle_Dinner"]
        dinner.tap()
        index.tap()
        app.buttons["Dinner"].tap()
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        let destination = app.staticTexts["food_detail_destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.label.contains("Dinner"), destination.label)
        app.buttons["food_portion_half"].tap()
        app.buttons["food_detail_log_action"].tap()
        XCTAssertTrue(food.waitForExistence(timeout: 8))
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "345 cal"), object: food)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, food.label)
        food.tap()
        let editedTotal = app.descendants(matching: .any)["food_detail_portion_total"].firstMatch
        XCTAssertTrue(editedTotal.waitForExistence(timeout: 5))
        XCTAssertTrue(editedTotal.label.contains("345 cal"), editedTotal.label)
        app.buttons["food_detail_cancel"].tap()
        app.buttons["diary_add_Dinner"].tap()
        let meal = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(meal.waitForExistence(timeout: 8))
        XCTAssertTrue(meal.label.contains("Dinner"))
        app.navigationBars["Log food"].buttons["Done"].tap()
        XCTAssertTrue(index.waitForExistence(timeout: 8))
        XCTAssertEqual(calendar.label, yesterday)
        attach(app, "Yesterday - edited dinner")
        app.buttons["home_diary_today"].tap()
        XCTAssertEqual(todayEnergy.label, originalToday)
        app.buttons["home_diary_previous"].tap()
        index.tap()
        app.buttons["Dinner"].tap()
        XCTAssertTrue(food.label.contains("345"), food.label)
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
        let index = app.buttons["home_diary_index"]
        index.tap()
        let addFood = app.buttons["Log dinner"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 6))
        addFood.tap()
        let destination = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        XCTAssertTrue(destination.label.contains("Dinner"))
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
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44, id)
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
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
