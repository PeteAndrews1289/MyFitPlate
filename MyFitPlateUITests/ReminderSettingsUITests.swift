import XCTest

@MainActor final class ReminderSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testDailyOffSwitchRuleAndTimeRemainReachableAndPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home", "-deep-link-url", "myfitplate://settings"]
        app.launch()
        let notifications = app.buttons["settings_open_notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        reveal(notifications, in: app); notifications.tap()
        let daily = app.buttons["reminder_settings_dailyLog"]
        XCTAssertTrue(daily.waitForExistence(timeout: 8), app.debugDescription); reveal(daily, in: app); daily.tap()
        let enabled = app.switches["reminder_enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        set(enabled, to: "1", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["reminder_time_0"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["reminder_diary_rule"].exists)
        app.buttons["reminder_save"].tap()
        daily.tap()
        XCTAssertEqual(enabled.value as? String, "1")
        set(enabled, to: "0", in: app)
        app.buttons["reminder_save"].tap()
        daily.tap(); XCTAssertEqual(enabled.value as? String, "0")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reminders - explicit daily opt-out and schedule review"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func set(_ toggle: XCUIElement, to value: String, in app: XCUIApplication) {
        reveal(toggle, in: app)
        if toggle.value as? String != value { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed, app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY >= 100 && element.frame.maxY <= app.frame.maxY - 70 { return }
            let scroll = app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
                ?? app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable) ?? app
            if element.exists && element.frame.minY < 100 { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

}
