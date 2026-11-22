import XCTest

@MainActor
final class WeeklyRecapHistoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSelectedWeekIntentionFollowsItsOwnNextWeekAndSurvivesRelaunch() {
        let ending = Calendar.current.startOfDay(for: Date())
        let app = launch(reset: true, ending: ending)
        let comparison = app.otherElements["weekly_report_comparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 20))
        let currentWeek = comparison.value as? String
        XCTAssertFalse(app.buttons["weekly_report_next"].isEnabled)
        app.buttons["weekly_report_previous"].tap()
        let changed = NSPredicate { _, _ in comparison.exists && comparison.value as? String != currentWeek }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 15), .completed)
        let field = app.textFields["weekly_report_intention"]
        reveal(field, in: app); field.tap(); field.typeText("Record effort after each set")
        app.buttons["weekly_report_finish_typing"].tap()
        let pin = app.buttons["weekly_report_pin"]
        reveal(pin, in: app); pin.tap()
        XCTAssertTrue(app.staticTexts["weekly_report_journal_status"].label.contains("Pinned"))
        let next = app.buttons["weekly_report_next"]
        reveal(next, in: app); next.tap()
        let reflect = app.buttons["weekly_report_reflect"]
        reveal(reflect, in: app)
        XCTAssertEqual(comparison.value as? String, currentWeek)
        XCTAssertTrue(app.staticTexts["Record effort after each set"].exists)
        reflect.tap(); app.buttons["Partly followed through"].tap()
        XCTAssertTrue(reflect.label.contains("Partly followed through"))
        app.terminate()
        let reopened = launch(reset: false, ending: ending)
        XCTAssertTrue(reopened.otherElements["weekly_report_comparison"].waitForExistence(timeout: 20))
        let restored = reopened.buttons["weekly_report_reflect"]
        reveal(restored, in: reopened)
        XCTAssertTrue(restored.label.contains("Partly followed through"))
        let evidence = reopened.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "evidence & saved versions")).firstMatch
        reveal(evidence, in: reopened); evidence.tap()
        let refresh = reopened.buttons["weekly_report_refresh"]
        reveal(refresh, in: reopened); XCTAssertTrue(refresh.isEnabled)
        let capture = XCTAttachment(screenshot: reopened.screenshot())
        capture.name = "Selected week intention and scoped evidence"; capture.lifetime = .keepAlways; add(capture)
    }

    private func launch(reset: Bool, ending: Date) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-report"]
        app.launchEnvironment["MFP_TEST_REPORT_WEEK_ENDING"] = String(ending.timeIntervalSince1970)
        if reset { app.launchArguments.append("-ui-testing-reset-editor-drafts") }
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists && element.isHittable && element.frame.minY >= 90 && element.frame.maxY < app.frame.maxY - 50 { return }
            let scroll = app.scrollViews.firstMatch
            if element.exists && element.frame.minY < 90 { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable)
    }
}
