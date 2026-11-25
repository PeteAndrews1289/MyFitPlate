import XCTest

@MainActor
final class MealSuggestionContinuityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFailedSuggestionKeepsExactReviewAndRelaunchLogsOneFood() {
        let app = launch(reset: true, failure: true)
        let log = app.buttons["meal_suggestion_log"]
        XCTAssertTrue(log.waitForExistence(timeout: 15), app.debugDescription)
        let title = app.descendants(matching: .any)["meal_suggestion_header"].firstMatch.label
        log.tap()
        XCTAssertTrue(app.staticTexts["meal_suggestion_save_error"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Save awaiting confirmation"].exists)
        app.terminate()
        let restored = launch(reset: false, failure: false)
        XCTAssertTrue(restored.buttons["meal_suggestion_log"].waitForExistence(timeout: 15))
        XCTAssertEqual(restored.descendants(matching: .any)["meal_suggestion_header"].firstMatch.label, title)
        restored.buttons["meal_suggestion_log"].tap()
        XCTAssertTrue(restored.staticTexts["meal_suggestion_accepted"].waitForExistence(timeout: 10), restored.debugDescription)
        XCTAssertEqual(restored.staticTexts["meal_suggestion_saved_count"].label, "Matching food records: 1")
        let capture = XCTAttachment(screenshot: restored.screenshot())
        capture.name = "Meal suggestion - recovered retry accepts exactly one food"
        capture.lifetime = .keepAlways; add(capture)
    }

    func testSavedConstraintReviewPrecedesLoggingAndRetryKeepsOneFood() {
        let app = XCUIApplication()
        let flags = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-suggestion", "-ui-testing-meal-constraints"]
        app.launchArguments = flags + ["-ui-testing-reset-editor-drafts", "-ui-testing-food-save-failure"]
        app.launch()
        let confirm = app.buttons["meal_suggestion_confirm_ingredients"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), app.debugDescription)
        let log = app.buttons["meal_suggestion_log"]
        XCTAssertFalse(log.isEnabled)
        reveal(confirm, in: app); confirm.tap()
        XCTAssertTrue(app.staticTexts["meal_suggestion_ingredients_reviewed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(log.isEnabled); log.tap()
        XCTAssertTrue(app.staticTexts["meal_suggestion_save_error"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(confirm.exists, "An uncertain save is already frozen")
        app.terminate(); app.launchArguments = flags; app.launch()
        XCTAssertTrue(log.waitForExistence(timeout: 15)); XCTAssertTrue(log.isEnabled)
        log.tap()
        XCTAssertTrue(app.staticTexts["meal_suggestion_accepted"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["meal_suggestion_saved_count"].label, "Matching food records: 1")
    }

    func testReasonedAlternativeKeepsOriginalAndRecipeReviewDoesNotLogFood() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-suggestion",
            "-ui-testing-reset-editor-drafts", "-ui-testing-suggestion-alternatives"]
        app.launch()
        openSuggestionOptions(app)
        let menu = app.buttons["meal_suggestion_alternatives"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), app.debugDescription)
        let originalName = "Lemon Herb Chicken Grain Bowl"
        let changedTitle = app.staticTexts["Quick QA bowl"].firstMatch
        menu.tap(); app.buttons["Less prep time"].tap()
        reveal(changedTitle, in: app)
        XCTAssertTrue(changedTitle.exists, app.debugDescription)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-editor-drafts" }; app.launch()
        reveal(changedTitle, in: app)
        XCTAssertTrue(changedTitle.exists, "The replacement itself must survive relaunch. " + app.debugDescription)
        openSuggestionOptions(app)
        let prior = app.buttons["meal_suggestion_previous"]
        XCTAssertTrue(prior.waitForExistence(timeout: 15), app.debugDescription)
        prior.tap()
        let originalTitle = app.staticTexts[originalName].firstMatch
        reveal(originalTitle, in: app)
        XCTAssertTrue(originalTitle.exists, app.debugDescription)
        openSuggestionOptions(app)
        let recipe = app.buttons["meal_suggestion_recipe"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 5)); recipe.tap()
        XCTAssertTrue(app.scrollViews["recipe_editor_scroll"].waitForExistence(timeout: 10), app.debugDescription)
        let recipeName = app.textFields["create_recipe_name"]
        reveal(recipeName, in: app)
        XCTAssertEqual(recipeName.value as? String, originalName, "Recipe review must retain the restored meal identity.")
        XCTAssertFalse(app.staticTexts["meal_suggestion_accepted"].exists)
    }

    private func openSuggestionOptions(_ app: XCUIApplication) {
        let options = app.buttons["meal_suggestion_options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15), app.debugDescription)
        reveal(options, in: app); options.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists, element.isHittable, element.frame.minY > 135, element.frame.maxY < app.frame.maxY - 110 { return }
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            if element.exists, element.frame.minY <= 135 { upper.press(forDuration: 0.08, thenDragTo: lower) } else { lower.press(forDuration: 0.08, thenDragTo: upper) }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func launch(reset: Bool, failure: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-suggestion"]
        if reset { app.launchArguments += ["-ui-testing-reset-editor-drafts"] }
        if failure { app.launchArguments += ["-ui-testing-food-save-failure"] }
        app.launch(); return app
    }
}
