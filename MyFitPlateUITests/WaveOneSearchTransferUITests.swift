import XCTest

final class WaveOneSearchTransferUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMealShortcutUsesCheckedTransferReviewAndTargetedUndo() {
        let app = launch()
        let copy = app.buttons["food_search_repeat_meal"]
        XCTAssertTrue(copy.waitForExistence(timeout: 15)); reveal(copy, app: app); copy.tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["diary_transfer_total"].label.contains("1 food"), app.debugDescription)
        let portion = app.steppers["diary_transfer_portion_yesterday-salmon"]
        reveal(portion, app: app); portion.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", "-Increment", "Increment")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1.25 × saved portion"].exists)
        let meal = app.buttons["diary_transfer_meal_yesterday-salmon"]
        reveal(meal, app: app); meal.tap(); app.buttons["Lunch"].tap()
        submit.tap()
        XCTAssertTrue(app.staticTexts["diary_transfer_accepted"].waitForExistence(timeout: 8))
        let undo = app.buttons["diary_transfer_undo"]
        reveal(undo, app: app); undo.tap()
        let accepted = app.staticTexts["diary_transfer_accepted"]
        reveal(accepted, app: app)
        let undone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Undone"), object: accepted)
        XCTAssertEqual(XCTWaiter.wait(for: [undone], timeout: 5), .completed, app.debugDescription)
        record(app, "Food search - checked copy and targeted Undo")
        app.buttons["diary_transfer_done"].tap()
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAllMealsShortcutReviewsExclusionsAndCanDiscardWithoutWriting() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let more = app.buttons["food_search_more_repeat_options"]
        XCTAssertTrue(more.waitForExistence(timeout: 15)); reveal(more, app: app); more.tap()
        app.buttons["food_search_copy_all_meals"].tap()
        let submit = app.buttons["diary_transfer_submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        let total = app.staticTexts["diary_transfer_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(total.isHittable, app.debugDescription)
        XCTAssertTrue(total.label.contains("4 foods"), app.debugDescription)
        let exclude = app.buttons["diary_transfer_select_yesterday-oats"]
        reveal(exclude, app: app); exclude.tap()
        XCTAssertTrue(total.isHittable, app.debugDescription)
        XCTAssertTrue(total.label.contains("3 foods"), app.debugDescription)
        XCTAssertTrue(submit.isEnabled)
        record(app, "Food search - all meals review with excluded food")
        let discard = app.buttons["diary_transfer_discard"]
        XCTAssertTrue(discard.isHittable); discard.tap()
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 5))
        let copy = app.buttons["food_search_repeat_meal"]
        reveal(copy, app: app); copy.tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(total.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(total.isHittable, app.debugDescription)
        XCTAssertTrue(total.label.contains("1 food"), "Discard must clear only the unsubmitted proposal. \(app.debugDescription)")
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search", "-ui-testing-reset-editor-drafts"] + flags
        app.launch()
        let search = app.textFields["food_search_field"]
        if !search.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        var searchAbove = false
        var unknownSteps = 0
        for _ in 0..<24 {
            let submit = app.buttons["diary_transfer_submit"]
            let done = app.buttons["diary_transfer_done"]
            let total = app.staticTexts["diary_transfer_total"]
            let transferIsOpen = submit.exists || done.exists
            let destination = app.descendants(matching: .any)["food_search_destination"].firstMatch
            let copyBar = app.navigationBars["Copy food"]
            let moveBar = app.navigationBars["Move food"]
            let bar = transferIsOpen && copyBar.exists ? copyBar : transferIsOpen && moveBar.exists ? moveBar : app.navigationBars.firstMatch
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
            let height = bottom - top
            let distance: CGFloat
            if element.exists, element.frame.height > 0 {
                let overflow = searchAbove ? top - element.frame.minY : element.frame.maxY - bottom
                distance = min(160, max(24, overflow + 12))
            } else { distance = min(160, height * 0.35) }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Use the empty Form gutter and hold at the end so inertia cannot
            // bounce a tall accessibility label between both viewport edges.
            let startY = top + height * 0.5
            let endY = min(bottom - 8, max(top + 8, startY + (searchAbove ? distance : -distance)))
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: startY))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTFail("Couldn't reveal \(element.identifier) inside its unobscured scroll viewport. \(app.debugDescription)")
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
