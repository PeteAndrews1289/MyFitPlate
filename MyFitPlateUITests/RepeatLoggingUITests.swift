import XCTest

final class RepeatLoggingUITests: XCTestCase {
    @MainActor
    func testReviewedDateGroupRetainsFailedDatesAcrossTerminationAndRetriesOnlyRemaining() {
        let app = XCUIApplication()
        func openReview(reset: Bool, failure: Bool) {
            app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin", "-ui-testing-day-review-persistence"]
                + (reset ? ["-ui-testing-reset-editor-drafts"] : [])
                + (failure ? ["-ui-testing-day-review-save-failure"] : [])
            app.launch()
            let review = app.buttons["weekly_review_days"]
            XCTAssertTrue(review.waitForExistence(timeout: 15)); reveal(review, in: app); review.tap()
            XCTAssertTrue(app.buttons["review_day_select_0"].waitForExistence(timeout: 10))
        }
        openReview(reset: true, failure: true)
        for index in 0...1 {
            let select = app.buttons["review_day_select_\(index)"]
            reveal(select, in: app); select.tap()
        }
        let begin = app.buttons["review_days_selected"]
        reveal(begin, in: app); begin.tap()
        XCTAssertTrue(app.navigationBars["Review selected days"].waitForExistence(timeout: 5))
        let confirmation = app.switches["review_batch_confirm"]
        confirm(confirmation, in: app)
        let save = app.buttons["review_batch_save"]
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let attempted = app.staticTexts["Saved dates are kept. Review changed dates or retry the remaining dates."]
        // The completion message is below the List footer on smaller screens.
        reveal(attempted, in: app)
        XCTAssertTrue(attempted.waitForExistence(timeout: 12), app.debugDescription)
        let retry = app.staticTexts["Not confirmed · retry available"].firstMatch
        reveal(retry, in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 12), app.debugDescription)
        reveal(app.staticTexts["review_batch_progress"], in: app)
        XCTAssertEqual(app.staticTexts["review_batch_progress"].label, "0 of 2 dates saved")
        app.terminate()
        openReview(reset: false, failure: false)
        let resume = app.buttons["review_days_resume"]
        reveal(resume, in: app); resume.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirm(confirmation, in: app)
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 of 2 dates saved"), object: app.staticTexts["review_batch_progress"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed, app.debugDescription)
        XCTAssertFalse(save.exists)
        attach(app, name: "Food-day review - two independently confirmed retries")
    }

    @MainActor private func confirm(_ toggle: XCUIElement, in app: XCUIApplication) {
        reveal(toggle, in: app)
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed, app.debugDescription)
    }

    @MainActor
    func testDiaryAddButtonKeepsTheMealDestination() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"]
        app.launch()
        let add = app.buttons["diary_add_Breakfast"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, in: app)
        add.tap()
        let picker = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Breakfast"))
        attach(app, name: "Diary - direct add to breakfast")
    }
    @MainActor
    func testWeeklyTargetAndEvidenceSupportLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin-ready",
                               "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let accept = app.buttons["weekly_checkin_accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        reveal(accept, in: app)
        XCTAssertTrue(accept.isEnabled)
        XCTAssertGreaterThanOrEqual(accept.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(accept.frame.maxX, app.frame.maxX)
        attach(app, name: "Weekly check-in - large text target")
        let evidence = app.buttons["weekly_checkin_evidence"]
        reveal(evidence, in: app)
        evidence.tap()
        let estimate = app.staticTexts["Estimated daily burn"]
        reveal(estimate, in: app)
        XCTAssertGreaterThanOrEqual(estimate.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(estimate.frame.maxX, app.frame.maxX)
        attach(app, name: "Weekly check-in - large text evidence")
    }

    @MainActor
    func testCoachingExplainsMissingRecoveryData() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "coaching"]
        app.launch()
        let evidence = app.buttons["coaching_evidence"]
        XCTAssertTrue(evidence.waitForExistence(timeout: 10))
        reveal(evidence, in: app)
        evidence.tap()
        XCTAssertTrue(app.staticTexts["HRV: no recent readings available"].exists)
        attach(app, name: "Coaching - evidence and missing data")
    }

    @MainActor
    func testWeeklyCheckInCanBeClosedWithoutChangingTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Weekly check-in"].waitForExistence(timeout: 10))
        attach(app, name: "Weekly check-in - target first")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Weekly check-in"].exists)
    }

    @MainActor
    func testFoodDayReviewBrowsesEarlierRangeAndDrillsDownWithoutMovingHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin"]
        app.launch()
        let review = app.buttons["weekly_review_days"]
        XCTAssertTrue(review.waitForExistence(timeout: 15)); reveal(review, in: app); review.tap()
        let first = app.buttons["review_day_detail_0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        let initial = app.staticTexts["review_days_scope"].label
        first.tap()
        XCTAssertTrue(app.navigationBars["Review this day"].waitForExistence(timeout: 5))
        app.navigationBars["Review this day"].buttons.firstMatch.tap()
        let earlier = app.buttons["review_days_earlier"]
        reveal(earlier, in: app); earlier.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", initial), object: app.staticTexts["review_days_scope"])
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let prior = app.staticTexts["review_days_scope"].label
        let older = app.buttons["review_day_detail_0"]
        XCTAssertTrue(older.waitForExistence(timeout: 5)); reveal(older, in: app); older.tap()
        XCTAssertTrue(app.navigationBars["Review this day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No food is recorded for this day. That does not establish zero intake."].exists)
        app.navigationBars["Review this day"].buttons.firstMatch.tap()
        reveal(app.staticTexts["review_days_scope"], in: app)
        XCTAssertEqual(app.staticTexts["review_days_scope"].label, prior)
        attach(app, name: "Food review - earlier range and exact day")
    }

    @MainActor
    func testWeeklyDayReviewChangesEvidenceAndCanBeCorrected() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin", "-screenshot-dark-mode", "-ui-testing-day-review-persistence"]
        app.launch()
        let review = app.buttons["weekly_review_days"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        reveal(review, in: app); review.tap()
        let today = app.buttons["review_day_0"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        for (key, status) in [("partial", "Partly logged"), ("complete", "Fully logged"), ("unknown", "Not reviewed")] {
            today.tap()
            let choice = app.buttons["review_status_\(key)"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND enabled == true", status), object: today)
            XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, app.debugDescription)
            XCTAssertTrue(app.staticTexts["review_days_message"].label.contains("Review saved"))
        }
        attach(app, name: "Weekly check-in - food-day review")
        app.navigationBars["Food-log days"].buttons["Done"].tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        reveal(review, in: app); review.tap()
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.label.contains("Not reviewed"))
    }

    @MainActor
    func testUsualFoodCanBeLoggedAndUndoneWithoutLeavingSearch() {
        let app = launchSearch()
        let add = app.buttons["repeat_food_add_0"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, in: app)
        add.tap()
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        attach(app, name: "Repeat food - saved with undo")
        undo.tap()
        XCTAssertTrue(app.textFields["food_search_field"].exists)
        XCTAssertTrue(add.isEnabled)
    }

    @MainActor
    func testRepeatedMealCanChangeAmountsBeforeLogging() {
        let app = launchSearch()
        let review = app.buttons["food_search_repeat_meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        reveal(review, in: app)
        review.tap()
        let stepper = app.steppers["diary_transfer_portion_yesterday-salmon"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        reveal(stepper, in: app)
        stepper.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", "-Decrement", "Decrement")).firstMatch.tap()
        XCTAssertTrue(stepper.label.contains("0.75") || stepper.descendants(matching: .staticText)["0.75 × saved portion"].exists)
        let confirm = app.buttons["diary_transfer_submit"]
        reveal(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        attach(app, name: "Repeat meal - review portions")
        confirm.tap()
        XCTAssertTrue(app.buttons["diary_transfer_undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(stepper.exists)
        app.buttons["diary_transfer_done"].tap()
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchSearch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search",
                               "-ui-testing-reset-editor-drafts"]
        app.launch()
        let search = app.textFields["food_search_field"]
        // Retry only a confirmed cold launch that missed the test route.
        if !search.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var searchAbove = false
        var unknownSteps = 0
        for _ in 0..<24 {
            let submit = app.buttons["diary_transfer_submit"]
            let done = app.buttons["diary_transfer_done"]
            let total = app.staticTexts["diary_transfer_total"]
            let transferIsOpen = submit.exists || done.exists
            let destination = app.descendants(matching: .any)["food_search_destination"].firstMatch
            let bar = app.navigationBars.firstMatch
            var top = bar.exists ? bar.frame.maxY + 5 : app.frame.minY + 115
            if !transferIsOpen, destination.exists { top = max(top, destination.frame.maxY + 5) }
            let actions = transferIsOpen ? [total, submit, done] : [app.buttons["food_search_review_meal"]]
            let pinned = actions.filter { $0.exists && $0.frame.height > 0 }
            let searchIsOpen = app.textFields["food_search_field"].exists
            let homeTab = app.buttons["tab_home"]
            let nativeTabs = app.tabBars.firstMatch
            let visibleTabsTop: CGFloat? = !searchIsOpen && homeTab.exists && homeTab.isHittable
                ? homeTab.frame.minY - 5
                : !searchIsOpen && nativeTabs.exists && nativeTabs.isHittable ? nativeTabs.frame.minY - 5 : nil
            let bottom = pinned.map(\.frame.minY).min().map { $0 - 5 } ?? visibleTabsTop ?? app.frame.maxY - 8
            if element.exists, element.isHittable {
                if pinned.contains(where: { $0.identifier == element.identifier }), app.frame.contains(element.frame) { return }
                if element.frame.minY >= top, element.frame.maxY <= bottom { return }
            }
            guard bottom - top > 60 else { break }
            if element.exists, element.frame.height > 0 {
                searchAbove = element.frame.minY < top
                unknownSteps = 0
            } else {
                unknownSteps += 1
                if unknownSteps == 8 { searchAbove.toggle(); unknownSteps = 0 }
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: top + (bottom - top) * 0.55))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: top + (bottom - top) * (searchAbove ? 0.8 : 0.3)))
            start.press(forDuration: 0.03, thenDragTo: end)
        }
        XCTFail("Couldn't reveal \(element.identifier) inside its unobscured scroll viewport. \(app.debugDescription)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
