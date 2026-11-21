import XCTest

final class WaveOneFoodLoggingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPortionReviewKeepsSearchAndDoesNotSelectOnCancel() {
        let app = launch()
        app.buttons["food_search_mode"].tap()
        let search = app.textFields["food_search_field"]
        search.tap(); search.typeText("apple\n")
        let row = app.buttons["food_picker_row_ui-test-apple"]
        reveal(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let cancel = app.buttons["food_detail_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertEqual((search.value as? String)?.lowercased(), "apple")
        XCTAssertTrue(search.isHittable)
        XCTAssertFalse(app.buttons["food_search_review_meal"].exists, "Cancel must not add the reviewed food")
        app.buttons["food_picker_add_ui-test-apple"].tap()
        XCTAssertTrue(app.buttons["food_search_review_meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["food_search_review_meal"].label.contains("1 food"))
        XCTAssertEqual((search.value as? String)?.lowercased(), "apple")
        attach(app, "Food search - query and destination retained after portion review")
    }

    @MainActor
    func testThreeSelectionsStayInSearchAndKeepOneReviewTray() {
        let app = launch()
        app.buttons["food_search_mode"].tap()
        for index in 0..<3 {
            let select = app.buttons["repeat_food_add_\(index)"]
            reveal(select, in: app)
            XCTAssertTrue(select.exists)
            XCTAssertFalse((select.value as? String ?? "").isEmpty, "The selected amount must be available to VoiceOver")
            select.tap()
            XCTAssertTrue(app.textFields["food_search_field"].isHittable)
            XCTAssertFalse(app.buttons["meal_draft_log"].exists)
        }
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.label.contains("3 foods"))
        XCTAssertTrue(review.isHittable)
        app.buttons["food_search_mode"].tap()
        XCTAssertTrue(review.exists, "Changing to quick add must retain the pending meal")
        review.tap()
        let total = app.staticTexts["meal_draft_total"]
        reveal(total, in: app)
        XCTAssertTrue(total.label.hasPrefix("3 foods"))
        XCTAssertTrue(app.buttons["meal_draft_keep_building"].isHittable)
        attach(app, "Food selection - three foods, one review tray")
    }

    @MainActor
    func testMealFailureRetainsFrozenSelectionAndRetriesAfterRelaunch() {
        let app = launch(flags: ["-ui-testing-food-save-failure"])
        app.buttons["food_search_mode"].tap()
        for index in 0..<2 {
            let select = app.buttons["repeat_food_add_\(index)"]
            reveal(select, in: app); select.tap()
        }
        let review = app.buttons["food_search_review_meal"]
        let destination = review.label
        review.tap()
        let total = app.staticTexts["meal_draft_total"]
        reveal(total, in: app)
        let originalTotal = total.label
        app.buttons["meal_draft_log"].tap()
        let status = app.staticTexts["meal_draft_status"]
        reveal(status, in: app)
        XCTAssertTrue(status.label.contains("Couldn't save"))
        app.terminate()
        app.launchArguments = arguments()
        app.launch()
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        XCTAssertTrue(review.label.contains("Dinner"))
        XCTAssertTrue(destination.contains("Dinner"))
        review.tap()
        reveal(total, in: app)
        XCTAssertEqual(total.label, originalTotal)
        app.buttons["meal_draft_log"].tap()
        XCTAssertTrue(app.buttons["food_search_undo"].waitForExistence(timeout: 8))
        XCTAssertFalse(review.exists)
        attach(app, "Food selection - rejected save recovered and accepted once")
    }

    @MainActor
    func testLiveSearchKeyboardPreservesPendingTrayAtLargestText() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["food_search_mode"].tap()
        let select = app.buttons["repeat_food_add_0"]
        reveal(select, in: app); select.tap()
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let pendingSummary = review.label
        let destination = app.buttons["food_search_meal_menu"]
        let capturedDestination = destination.label
        let search = app.textFields["food_search_field"]
        search.tap(); search.typeText("apple")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), app.debugDescription)
        let addApple = app.buttons["food_picker_add_ui-test-apple"]
        XCTAssertTrue(addApple.waitForExistence(timeout: 8))
        attach(app, "Food selection - live keyboard and pending tray at largest text")
        let observations = XCTAttachment(string: "Search: \(search.frame), hittable \(search.isHittable)\nDestination: \(destination.frame), enabled \(destination.isEnabled)\nReview: \(review.frame), hittable \(review.isHittable)\nApple Add: \(addApple.frame), hittable \(addApple.isHittable)\nKeyboard: \(keyboard.frame)")
        observations.name = "Live food search keyboard reachability"
        observations.lifetime = .keepAlways; add(observations)
        XCTAssertTrue(search.isHittable)
        XCTAssertEqual(destination.label, capturedDestination)
        XCTAssertGreaterThanOrEqual(destination.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(destination.frame.maxY, keyboard.frame.minY + 1,
                                 "The captured destination must remain readable above the keyboard")
        XCTAssertTrue(review.isHittable, "The pending meal review must remain reachable")
        let submit = keyboard.buttons["Search"].firstMatch
        XCTAssertTrue(submit.isHittable, "Search explicitly closes the keyboard without leaving this flow")
        submit.tap()
        let keyboardClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardClosed], timeout: 5), .completed)
        XCTAssertEqual((search.value as? String)?.lowercased(), "apple")
        XCTAssertEqual(review.label, pendingSummary)
        XCTAssertEqual(destination.label, capturedDestination)
        reveal(addApple, in: app); addApple.tap()
        XCTAssertTrue(review.label.contains("2 foods"))
        attach(app, "Food selection - query and tray retained after explicit keyboard close")
    }

    @MainActor
    func testSearchDestinationAndTrayFitLargestTextInDarkAppearance() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let destination = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(destination.label.contains("Dinner"))
        XCTAssertTrue(destination.label.contains(String(Calendar.current.component(.year, from: Date()))))
        app.buttons["food_search_mode"].tap()
        let select = app.buttons["repeat_food_add_0"]
        reveal(select, in: app); select.tap()
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.isHittable)
        XCTAssertGreaterThanOrEqual(review.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(review.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.textFields["food_search_field"].isHittable)
        attach(app, "Food selection - large text destination and review action")
    }

    @MainActor
    func testQuickAddUndoAndPendingMealRemainReachableDuringLargestTextSearch() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let quickAdd = app.buttons["repeat_food_add_0"]
        reveal(quickAdd, in: app); quickAdd.tap()
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        XCTAssertTrue(undo.isHittable)
        let quickAddAcceptedAt = Date()
        app.buttons["food_search_mode"].tap()
        let select = app.buttons["repeat_food_add_1"]
        reveal(select, in: app); select.tap()
        if Date().timeIntervalSince(quickAddAcceptedAt) < 25 {
            XCTAssertTrue(undo.isHittable, "Selecting a pending food must retain the live quick-add Undo")
        }
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let pendingSummary = review.label
        let destination = app.buttons["food_search_meal_menu"]
        let capturedDestination = destination.label
        let search = app.textFields["food_search_field"]
        search.tap(); search.typeText("apple")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let addApple = app.buttons["food_picker_add_ui-test-apple"]
        XCTAssertTrue(addApple.waitForExistence(timeout: 8))
        let undoAge = Date().timeIntervalSince(quickAddAcceptedAt)
        attach(app, "Food selection - live keyboard with pending meal and quick-add Undo")
        let undoVisible = undo.exists && undo.isHittable
        let observations = XCTAttachment(string: "Search: \(search.frame), hittable \(search.isHittable)\nDestination: \(destination.frame), enabled \(destination.isEnabled)\nReview: \(review.frame), hittable \(review.isHittable)\nUndo visible: \(undoVisible), quick-add age \(undoAge) seconds (Undo expires after 30)\nApple Add: \(addApple.frame), hittable \(addApple.isHittable)\nKeyboard: \(keyboard.frame)")
        observations.name = "Mixed food search keyboard reachability"
        observations.lifetime = .keepAlways; add(observations)
        XCTAssertTrue(search.isHittable)
        XCTAssertEqual((search.value as? String)?.lowercased(), "apple")
        XCTAssertEqual(destination.label, capturedDestination)
        XCTAssertGreaterThanOrEqual(destination.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(destination.frame.maxY, keyboard.frame.minY + 1,
                                 "The captured destination must remain readable above the keyboard")
        XCTAssertTrue(review.isHittable, "The pending meal must remain reachable alongside Undo")
        if undoAge < 25 {
            XCTAssertTrue(undo.isHittable, "Search must not hide an unexpired quick-add Undo")
        }
        // Inspect the current result viewport before deliberately closing the keyboard.
        // Scrolling here would interactively dismiss it and conceal a crowded layout.
        let submit = keyboard.buttons["Search"].firstMatch
        XCTAssertTrue(submit.isHittable)
        submit.tap()
        let keyboardClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardClosed], timeout: 5), .completed)
        XCTAssertEqual((search.value as? String)?.lowercased(), "apple")
        XCTAssertEqual(review.label, pendingSummary)
        XCTAssertEqual(destination.label, capturedDestination)
        reveal(addApple, in: app)
        XCTAssertTrue(addApple.isHittable, "The searched food must be reachable after explicitly closing the keyboard")
        attach(app, "Food selection - mixed state retained after keyboard close")
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(flags: ["-ui-testing-reset-editor-drafts"] + flags)
        app.launch()
        let search = app.textFields["food_search_field"]
        // Retry only a confirmed cold launch that missed the test route.
        if !search.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        return app
    }

    private func arguments(flags: [String] = []) -> [String] {
        ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search"] + flags
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let reviewIsOpen = app.buttons["meal_draft_log"].exists
            let scroll = app.scrollViews["food_search_results_scroll"].firstMatch
            if !reviewIsOpen, scroll.exists {
                let destination = app.descendants(matching: .any)["food_search_destination"].firstMatch
                let search = app.textFields["food_search_field"]
                let top = max(search.frame.maxY, destination.exists ? destination.frame.maxY : search.frame.maxY) + 8
                var bottom = app.frame.maxY - 16
                for (id, inset) in [("food_search_review_meal", 8.0), ("food_search_undo", 16.0)] {
                    let control = app.buttons[id]
                    if control.exists { bottom = min(bottom, control.frame.minY - inset) }
                }
                let height = max(60, bottom - top)
                if element.exists, element.isHittable, element.frame.minY >= top,
                   element.frame.maxY <= bottom { return }
                let above = element.exists && element.frame.midY < top
                let startY = top + height * (above ? 0.35 : 0.75)
                let endY = top + height * (above ? 0.75 : 0.35)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: app.frame.width - 10, dy: startY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width - 10, dy: endY)))
            } else {
                if element.exists, element.isHittable { return }
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
