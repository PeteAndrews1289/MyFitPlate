import XCTest

final class BuffetUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ route: String, extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route] + extras
        app.launch()
        return app
    }

    @MainActor
    private func settle(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 12), XCUIApplication().debugDescription)
        var previous = CGRect.null
        var since = ProcessInfo.processInfo.systemUptime
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            let now = ProcessInfo.processInfo.systemUptime
            if previous != frame { previous = frame; since = now; return false }
            return now - since >= 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, XCUIApplication().debugDescription)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // SwiftUI can report an offscreen row as hittable; keep the whole target
        // between the pinned search field and footer before sending a touch.
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<16 {
            let search = app.textFields["ayce_catalog_search"]
            let top = search.exists ? search.frame.maxY + 12 : scroll.frame.minY + 8
            let footer = app.buttons["ayce_end_button"]
            let bottom = footer.exists ? footer.frame.minY - 12 : app.frame.maxY - 110
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                let start = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.width * 0.9, dy: (top + bottom) / 2))
                let offset = frame.minY < top ? top - frame.minY : bottom - frame.maxY
                // A tiny remaining offset may not cross UIScrollView's drag threshold.
                let distance = (offset < 0 ? -1.0 : 1.0) * min(max(abs(offset), 40), 120)
                start.press(forDuration: 0.05,
                            thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            } else {
                scroll.swipeUp()
            }
        }
        XCTFail("Couldn't reveal \(element.identifier) inside the scrollable viewport")
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, isPortion: Bool = false) {
        let app = XCUIApplication()
        if isPortion { revealPortionField(field, in: app) }
        settle(field)
        if isPortion {
            app.buttons["ayce_clear_portion"].press(forDuration: 0.1)
        } else {
            app.buttons["Clear buffet search"].press(forDuration: 0.1)
        }
        settle(field)
        field.press(forDuration: 0.1)
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor
    private func revealPortionField(_ field: XCUIElement, in app: XCUIApplication) {
        // Form rows can report hittable underneath a safe-area footer. A tap there
        // would hit Save, so verify that the entire input is above the preview.
        for _ in 0..<16 {
            let top = app.navigationBars["Adjust portion"].frame.maxY + 12
            let bottom = app.buttons["ayce_save_portion"].frame.minY - 100
            if field.exists, field.isHittable, field.frame.minY >= top, field.frame.maxY <= bottom { return }
            let distance = field.exists && field.frame.minY < top ? 100.0 : -100.0
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.9, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("Couldn't reveal the portion input: \(app.debugDescription)")
    }

    @MainActor
    private func start(_ cuisine: String, extra: [String] = [], restaurant: String? = nil) -> XCUIApplication {
        let app = launch("ayce-start", extras: ["-ui-testing-reset-ayce"] + extra)
        if !app.buttons[cuisine].waitForExistence(timeout: 12), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        settle(app.buttons[cuisine])
        app.buttons[cuisine].press(forDuration: 0.1)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.buttons[cuisine])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let price = app.textFields["ayce_price_field"]
        reveal(price, in: app)
        price.press(forDuration: 0.1)
        price.typeText("35")
        settle(app.toolbars.buttons["Done"])
        app.toolbars.buttons["Done"].press(forDuration: 0.1)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(price.value as? String, "35")
        if let restaurant {
            let name = app.textFields["ayce_restaurant"]
            reveal(name, in: app); name.tap(); name.typeText(restaurant)
            app.toolbars.buttons["Done"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertEqual(name.value as? String, restaurant)
        }
        settle(app.buttons["ayce_start_button"])
        app.buttons["ayce_start_button"].press(forDuration: 0.1)
        settle(app.textFields["ayce_catalog_search"])
        return app
    }

    @MainActor
    func testFavoriteSushiRoundReviewRepeatAndUndo() {
        let app = start("Sushi", restaurant: "QA Sushi")
        let search = app.textFields["ayce_catalog_search"]
        search.tap(); search.typeText("rainbow\n")
        let portion = app.buttons["ayce_portion_sushi_rainbow_roll"]
        reveal(portion, in: app); settle(portion); portion.tap()
        settle(app.textFields["ayce_portion_amount"])
        let favorite = app.buttons["ayce_toggle_favorite"]
        if favorite.label == "Add to favorites" { favorite.tap() }
        app.buttons["Roll cut · 8 pieces"].tap()
        let cut = app.steppers["ayce_roll_cut"]
        XCTAssertTrue(cut.exists)
        cut.buttons["ayce_roll_cut-Decrement"].tap(); cut.buttons["ayce_roll_cut-Decrement"].tap()
        XCTAssertTrue(app.staticTexts["6 pieces per roll"].exists)
        app.buttons["Roll cut · 6 pieces"].tap()
        replace(app.textFields["ayce_portion_amount"], with: "3", isPortion: true)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.buttons["ayce_save_portion"].tap()
        settle(app.buttons["ayce_end_button"])
        app.buttons["Clear buffet search"].tap()
        let finish = app.buttons["ayce_finish_round"]
        settle(finish); finish.tap()
        let options = app.buttons["ayce_session_options"]
        reveal(options, in: app); options.tap()
        let repeatRound = app.buttons["ayce_repeat_round"]
        settle(repeatRound); repeatRound.tap()
        let confirm = app.buttons["ayce_confirm_repeat"]
        settle(confirm)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.frame.maxY)
        let total = app.staticTexts["ayce_repeat_calories"]
        XCTAssertTrue(total.exists)
        XCTAssertLessThanOrEqual(total.frame.maxY, confirm.frame.minY)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3 pieces'")).firstMatch.exists)
        capture(app, "Buffet - repeat round review")
        confirm.tap()
        settle(app.buttons["ayce_undo_change"])
        app.buttons["ayce_undo_change"].tap()
        app.buttons["ayce_category_filter"].tap()
        app.buttons["Favorites"].tap()
        reveal(portion, in: app); portion.tap()
        settle(app.textFields["ayce_portion_amount"])
        XCTAssertEqual(app.textFields["ayce_portion_amount"].value as? String, "3")
        XCTAssertEqual(app.buttons["ayce_toggle_favorite"].label, "Remove from favorites")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testSharedKBBQLogsOnlyMyCookedShare() {
        let app = start("Korean BBQ")
        let search = app.textFields["ayce_catalog_search"]
        search.tap(); search.typeText("chadol\n")
        let portion = app.buttons["ayce_portion_kbbq_brisket"]
        reveal(portion, in: app); settle(portion); portion.tap()
        let shared = app.switches["ayce_shared_portion"]
        XCTAssertTrue(shared.waitForExistence(timeout: 8))
        settle(shared)
        shared.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let splitting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: shared)
        XCTAssertEqual(XCTWaiter.wait(for: [splitting], timeout: 5), .completed, app.debugDescription)
        let amount = app.textFields["ayce_portion_amount"]
        replace(amount, with: "300", isPortion: true)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let share = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Your portion: 150 g cooked'")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5), app.debugDescription)
        capture(app, "Buffet - personal share of cooked KBBQ")
        app.buttons["ayce_save_portion"].tap()
        settle(app.buttons["ayce_end_button"])
        reveal(portion, in: app); portion.tap()
        settle(app.textFields["ayce_portion_amount"])
        XCTAssertEqual(app.textFields["ayce_portion_amount"].value as? String, "150")
        XCTAssertEqual(app.switches["ayce_shared_portion"].value as? String, "0")
    }

    @MainActor
    func testSushiSharedRollRecoversThroughSummaryAndLogs() {
        var app = start("Sushi")
        let search = app.textFields["ayce_catalog_search"]
        search.press(forDuration: 0.1)
        search.typeText("rainbow\n")
        let portion = app.buttons["ayce_portion_sushi_rainbow_roll"]
        reveal(portion, in: app)
        settle(portion)
        portion.press(forDuration: 0.1)
        settle(app.textFields["ayce_portion_amount"])
        app.buttons["ayce_portion_unit"].press(forDuration: 0.1)
        app.buttons["Pieces"].press(forDuration: 0.1)
        replace(app.textFields["ayce_portion_amount"], with: "3", isPortion: true)
        if app.buttons["Done"].exists { app.buttons["Done"].press(forDuration: 0.1) }
        XCTAssertTrue(app.staticTexts["ayce_portion_preview"].label.contains("131 cal"))
        settle(app.buttons["ayce_save_portion"])
        app.buttons["ayce_save_portion"].press(forDuration: 0.1)
        settle(app.buttons["ayce_end_button"])
        reveal(portion, in: app)
        settle(portion)
        portion.press(forDuration: 0.1)
        settle(app.textFields["ayce_portion_amount"])
        XCTAssertEqual(app.textFields["ayce_portion_amount"].value as? String, "3")
        XCTAssertTrue(app.staticTexts["ayce_portion_preview"].label.contains("131 cal"))
        app.buttons["ayce_save_portion"].press(forDuration: 0.1)
        settle(app.buttons["ayce_end_button"])
        app.buttons["ayce_end_button"].press(forDuration: 0.1)
        settle(app.buttons["ayce_log_diary_button"])
        capture(app, "Buffet - partial sushi roll review")
        app.terminate()
        app = launch("ayce-resume")
        settle(app.buttons["ayce_log_diary_button"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3 pieces'")).firstMatch.exists)
        app.buttons["ayce_log_diary_button"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["ayce_log_diary_button"].waitForNonExistence(timeout: 8))
    }

    @MainActor
    func testKBBQAliasesCookedWeightUndoAndEmptySearch() {
        let app = start("Korean BBQ")
        app.textFields["ayce_catalog_search"].press(forDuration: 0.1)
        app.textFields["ayce_catalog_search"].typeText("chadol\n")
        let portion = app.buttons["ayce_portion_kbbq_brisket"]
        reveal(portion, in: app)
        settle(portion)
        portion.press(forDuration: 0.1)
        settle(app.textFields["ayce_portion_amount"])
        app.buttons["ayce_portion_unit"].press(forDuration: 0.1)
        app.buttons["Cooked grams"].press(forDuration: 0.1)
        replace(app.textFields["ayce_portion_amount"], with: "165", isPortion: true)
        if app.buttons["Done"].exists { app.buttons["Done"].press(forDuration: 0.1) }
        XCTAssertTrue(app.staticTexts["ayce_portion_preview"].label.contains("525 cal"))
        settle(app.buttons["ayce_save_portion"])
        app.buttons["ayce_save_portion"].press(forDuration: 0.1)
        settle(app.buttons["ayce_end_button"])
        let undo = app.buttons["ayce_undo_change"]
        for _ in 0..<5 where !undo.isHittable { app.scrollViews.firstMatch.swipeDown() }
        undo.press(forDuration: 0.1)
        XCTAssertFalse(app.buttons["ayce_end_button"].isEnabled)
        replace(app.textFields["ayce_catalog_search"], with: "nonexistentxyz")
        XCTAssertTrue(app.otherElements["ayce_empty_results"].exists || app.staticTexts["No matching foods"].exists)
        app.buttons["Clear filters"].press(forDuration: 0.1)
        XCTAssertEqual(app.textFields["ayce_catalog_search"].value as? String, "Search foods or menu names")
        app.buttons["ayce_category_filter"].press(forDuration: 0.1)
        app.buttons["Sauces"].press(forDuration: 0.1)
        capture(app, "Buffet - Korean BBQ sauces")
        XCTAssertTrue(app.buttons["ayce_portion_kbbq_ssamjang"].exists)
    }

    @MainActor
    func testRejectedDiarySaveStaysRetryableAfterRelaunch() {
        var app = launch("ayce-summary", extras: ["-ui-testing-reset-ayce", "-ui-testing-food-save-failure"])
        settle(app.buttons["ayce_log_diary_button"])
        app.buttons["ayce_log_diary_button"].press(forDuration: 0.1)
        XCTAssertTrue(app.staticTexts["ayce_save_error"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["ayce_save_error"].label.contains("Couldn't save"))
        XCTAssertTrue(app.buttons["ayce_log_diary_button"].isEnabled)
        XCTAssertFalse(app.buttons["ayce_resume_session"].exists)
        capture(app, "Buffet - failed save retains session")
        app.terminate()
        app = launch("ayce-resume")
        settle(app.buttons["ayce_log_diary_button"])
        app.buttons["ayce_log_diary_button"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["ayce_log_diary_button"].waitForNonExistence(timeout: 8))
    }

    @MainActor
    func testLargeTextCatalogStillAllowsPortionReview() {
        let app = launch("ayce-live", extras: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        settle(app.textFields["ayce_catalog_search"])
        app.textFields["ayce_catalog_search"].press(forDuration: 0.1)
        app.textFields["ayce_catalog_search"].typeText("salmon nigiri\n")
        let portion = app.buttons["ayce_portion_sushi_salmon_nigiri"]
        reveal(portion, in: app)
        settle(portion)
        capture(app, "Buffet - accessible search results")
        portion.press(forDuration: 0.1)
        settle(app.buttons["ayce_save_portion"])
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture(app, "Buffet - accessible portion editor")
        app.buttons["Cancel"].press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["ayce_save_portion"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
