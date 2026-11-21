import XCTest

final class WaveOneDiaryTransferUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDuplicateUsesReviewedPortionAndUndoCanBeReopenedFromHistory() {
        let app = launch()
        openFoodOptions(in: app)
        app.buttons["Duplicate serving"].tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6))
        let portion = app.steppers["diary_transfer_portion_today-parfait"]
        reveal(portion, in: app)
        portion.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", "-Increment", "Increment")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1.25 × saved portion"].exists)
        submit.tap()
        XCTAssertTrue(app.buttons["diary_transfer_done"].waitForExistence(timeout: 6), app.debugDescription)
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, in: app)
        XCTAssertTrue(accepted.exists)
        app.buttons["diary_transfer_undo"].tap()
        assertUndone(in: app)
        app.buttons["diary_transfer_done"].tap()
        let options = app.buttons["diary_day_options"]
        reveal(options, in: app); options.tap(); app.buttons["Food changes"].tap()
        let undone = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary_transfer_history_")).firstMatch
        XCTAssertTrue(undone.waitForExistence(timeout: 5)); undone.tap()
        assertUndone(in: app)
        app.buttons["diary_transfer_done"].tap()
        XCTAssertTrue(app.navigationBars["Food changes"].waitForExistence(timeout: 4))
        attach(app, "Diary transfer - copied portion, targeted Undo and reopened history")
    }

    @MainActor
    func testFailedTransferRetainsSourceAndReviewedIntentAcrossRelaunch() {
        let app = launch(flags: ["-ui-testing-transfer-failure"])
        openFoodOptions(in: app); app.buttons["Duplicate serving"].tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6)); submit.tap()
        XCTAssertTrue(app.staticTexts["diary_transfer_error"].waitForExistence(timeout: 6))
        XCTAssertEqual(submit.label, "Retry transfer")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["diary_food_options_today-parfait"].exists, "Rejected transfer leaves its source visible")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"]
        app.launch()
        let resume = app.buttons["diary_transfer_resume"]
        reveal(resume, in: app); resume.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 6)); XCTAssertEqual(submit.label, "Retry transfer")
        submit.tap()
        XCTAssertTrue(app.buttons["diary_transfer_done"].waitForExistence(timeout: 6), app.debugDescription)
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, in: app)
        XCTAssertTrue(accepted.exists)
        app.buttons["diary_transfer_done"].tap()
        attach(app, "Diary transfer - failure and restart recovery")
    }

    @MainActor
    func testSameDayMoveRequiresDifferentMealAndSupportsUndoAtLargestText() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openFoodOptions(in: app); app.buttons["Move to day or meal…"].tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6)); XCTAssertFalse(submit.isEnabled)
        let meal = app.buttons["diary_transfer_meal_today-parfait"]
        reveal(meal, in: app); meal.tap(); app.buttons["Dinner"].tap()
        XCTAssertTrue(submit.isEnabled); XCTAssertGreaterThanOrEqual(submit.frame.height, 44)
        XCTAssertGreaterThanOrEqual(submit.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(submit.frame.maxX, app.frame.maxX)
        submit.tap()
        XCTAssertTrue(app.buttons["diary_transfer_done"].waitForExistence(timeout: 6), app.debugDescription)
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, in: app)
        XCTAssertTrue(accepted.exists)
        let undo = app.buttons["diary_transfer_undo"]; reveal(undo, in: app); undo.tap()
        assertUndone(in: app)
        app.buttons["diary_transfer_done"].tap()
        attach(app, "Diary transfer - checked same-day move at largest text")
    }

    @MainActor
    func testCrossDayMoveAppearsOnlyAtDestinationAndHistoryUndoRestoresOriginalDay() {
        let app = launch()
        openFoodOptions(in: app); app.buttons["Move to day or meal…"].tap()
        let yesterday = app.buttons["diary_transfer_yesterday"]
        reveal(yesterday, in: app); yesterday.tap()
        let destinationDay = app.staticTexts["diary_transfer_destination_day"]
        reveal(destinationDay, in: app)
        let destination = destinationDay.label
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(app.buttons["diary_transfer_done"].waitForExistence(timeout: 6), app.debugDescription)
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, in: app)
        XCTAssertTrue(accepted.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", destination)).firstMatch.exists)
        app.buttons["diary_transfer_done"].tap()
        XCTAssertFalse(app.buttons["diary_food_options_today-parfait"].exists)
        app.buttons["home_diary_previous"].tap()
        let moved = app.buttons["diary_food_options_today-parfait"]
        reveal(moved, in: app)
        XCTAssertTrue(moved.isHittable)
        let options = app.buttons["diary_day_options"]; reveal(options, in: app); options.tap()
        app.buttons["Food changes"].tap()
        let receipt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diary_transfer_history_")).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5)); receipt.tap()
        let undo = app.buttons["diary_transfer_undo"]; reveal(undo, in: app); undo.tap(); assertUndone(in: app)
        app.buttons["diary_transfer_done"].tap()
        app.navigationBars["Food changes"].buttons["Done"].tap()
        app.buttons["home_diary_today"].tap()
        reveal(moved, in: app)
        XCTAssertTrue(moved.isHittable)
        attach(app, "Diary transfer - cross-day move and history Undo preserve original identity")
    }

    @MainActor
    func testHomeYesterdayShortcutReviewsAllFoodsForTodayAndDiscardKeepsSource() {
        let app = launch()
        let repeatDay = app.buttons["home_repeat_previous_day"]
        reveal(repeatDay, in: app); repeatDay.tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6))
        XCTAssertTrue(app.navigationBars["Copy food"].exists)
        XCTAssertTrue(app.staticTexts["4 foods available"].exists)
        let today = app.buttons["diary_transfer_today"]
        reveal(today, in: app); today.tap()
        let destination = app.staticTexts["diary_transfer_destination_day"]
        reveal(destination, in: app)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current; formatter.dateStyle = .medium
        XCTAssertEqual(destination.label, formatter.string(from: Date()), "The copy target must be today's diary")
        for id in ["yesterday-oats", "yesterday-wrap", "yesterday-salmon", "yesterday-cottage"] {
            let selected = app.buttons["diary_transfer_select_" + id]
            reveal(selected, in: app)
            XCTAssertEqual(selected.value as? String, "Selected", id)
        }
        let summary = app.staticTexts["diary_transfer_total"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.label.hasPrefix("4 foods"))
        XCTAssertFalse(app.staticTexts["diary_transfer_accepted"].exists)
        app.buttons["diary_transfer_discard"].tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["diary_transfer_resume"].exists)
        let originalToday = app.buttons["diary_food_options_today-parfait"]
        reveal(originalToday, in: app)
        XCTAssertTrue(originalToday.isHittable)
        app.buttons["home_diary_previous"].tap()
        for id in ["yesterday-oats", "yesterday-wrap", "yesterday-salmon", "yesterday-cottage"] {
            let original = app.buttons["diary_food_options_" + id]
            reveal(original, in: app)
            XCTAssertTrue(original.isHittable, "Discard must retain the original " + id)
        }
        attach(app, "Diary transfer - Yesterday shortcut reviews four foods and Discard preserves source")
    }

    @MainActor
    func testFailedTransferCanBeCancelledAfterRelaunchWithoutLosingSourceOrBlockingNewReview() {
        let app = launch(flags: ["-ui-testing-transfer-failure"])
        openFoodOptions(in: app); app.buttons["Duplicate serving"].tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6)); submit.tap()
        XCTAssertTrue(app.staticTexts["diary_transfer_error"].waitForExistence(timeout: 6))
        XCTAssertEqual(submit.label, "Retry transfer")
        XCTAssertFalse(app.buttons["diary_transfer_today"].isEnabled, "The rejected request must retain its frozen destination")
        XCTAssertFalse(app.buttons["diary_transfer_discard"].exists, "A frozen request cannot be discarded as an unsent proposal")
        app.buttons["Close"].tap()
        let source = app.buttons["diary_food_options_today-parfait"]
        reveal(source, in: app); XCTAssertTrue(source.isHittable)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"]
        app.launch()
        let resume = app.buttons["diary_transfer_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 12))
        reveal(resume, in: app); resume.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 6))
        XCTAssertEqual(submit.label, "Retry transfer", "Relaunch must restore the frozen request")
        let cancel = app.buttons["diary_transfer_cancel_pending"]
        reveal(cancel, in: app); cancel.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 6))
        XCTAssertTrue(resume.waitForNonExistence(timeout: 6), "Confirmed cancellation must clear the pending banner")
        reveal(source, in: app); XCTAssertTrue(source.isHittable)
        openFoodOptions(in: app); app.buttons["Duplicate serving"].tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 6))
        XCTAssertNotEqual(submit.label, "Retry transfer")
        XCTAssertFalse(app.buttons["diary_transfer_cancel_pending"].exists)
        let discard = app.buttons["diary_transfer_discard"]
        XCTAssertTrue(discard.isEnabled, "A new proposal must be editable after confirmed cancellation")
        discard.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 5))
        XCTAssertFalse(resume.exists)
        reveal(source, in: app); XCTAssertTrue(source.isHittable)
        attach(app, "Diary transfer - cancelled frozen request preserves source and permits a fresh proposal")
    }

    @MainActor
    private func assertUndone(in app: XCUIApplication) {
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, in: app)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Undone"), object: accepted)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, app.debugDescription)
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home", "-ui-testing-reset-editor-drafts"] + flags
        app.launch()
        if !app.buttons["home_diary_calendar"].waitForExistence(timeout: 12), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(app.buttons["home_diary_calendar"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func openFoodOptions(in app: XCUIApplication) {
        let options = app.buttons["diary_food_options_today-parfait"]
        reveal(options, in: app); options.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for attempt in 0..<28 {
            let actions = [app.staticTexts["diary_transfer_error"], app.staticTexts["diary_transfer_total"], app.buttons["diary_transfer_submit"], app.buttons["diary_transfer_done"], app.buttons["diary_transfer_check_to_finish"]]
            let pinned = actions.filter { $0.exists && $0.frame.height > 0 }
            let transferOpen = !pinned.isEmpty
            let calendar = app.buttons["home_diary_calendar"]
            let bar = app.navigationBars.firstMatch
            let top = !transferOpen && calendar.exists ? calendar.frame.maxY + 5 : (bar.exists ? bar.frame.maxY + 5 : 115)
            let quickLog = app.buttons["quick_log_button"]
            let fallback = !transferOpen && quickLog.exists && quickLog.isHittable ? quickLog.frame.minY - 5 : app.frame.maxY - 8
            let bottom = pinned.map(\.frame.minY).min().map { $0 - 5 } ?? fallback
            if element.exists, element.isHittable {
                if pinned.contains(where: { $0.identifier == element.identifier }), app.frame.contains(element.frame) { return }
                if element.frame.minY >= top, element.frame.maxY <= bottom { return }
            }
            guard bottom - top > 60 else { break }
            let above = element.exists ? element.frame.minY < top : (8..<22).contains(attempt)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: top + (bottom - top) * 0.55))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: top + (bottom - top) * (above ? 0.8 : 0.3)))
            start.press(forDuration: 0.03, thenDragTo: end)
        }
        XCTFail("Couldn't reveal a complete target above the actual pinned controls. \(app.debugDescription)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
