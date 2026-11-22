import XCTest

/// Exercises the actual editor and logging rows; the fixture is local and no diary save is performed.
final class RecipeIngredientQuantityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testKeyboardDoneRetainsIngredientAmountWithoutSavingOrClosingEditor() {
        let app = launch(reset: true)
        openRecipe(app)
        app.navigationBars["Recipe"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Recipe"].waitForExistence(timeout: 10), app.debugDescription)
        let quantity = app.textFields["recipe_ingredient_quantity_qa-quantity-rice"]
        reveal(quantity, app: app)
        replace(quantity, with: "200", app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let done = app.buttons["recipe_editor_keyboard_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(done.isHittable, app.debugDescription); done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Edit Recipe"].exists, "Done dismisses only the keyboard")
        XCTAssertEqual(quantity.value as? String, "200 g", "Dismissal preserves the edited amount and stable row")
        XCTAssertTrue(app.buttons["create_recipe_action"].exists, "The recipe still requires its explicit save")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recipe - keyboard Done preserves amount and editor"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars["Edit Recipe"].buttons["Cancel"].tap()
        let saved = metrics("recipe_nutrition_summary", inside: "recipe_detail", app: app)
        reveal(saved, app: app); assertCalories("160 cal", inside: saved, app: app)
    }

    @MainActor func testStableIngredientUpdatesRowAndBatchPreviewRestoresDraftAndAdjustsLogOnly() {
        let app = launch(reset: true)
        openRecipe(app)
        app.navigationBars["Recipe"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Recipe"].waitForExistence(timeout: 10), app.debugDescription)
        let recalculate = app.buttons["recipe_recalculate_ingredients"]
        reveal(recalculate, app: app); recalculate.tap()
        let quantity = app.textFields["recipe_ingredient_quantity_qa-quantity-rice"]
        reveal(quantity, app: app, preferEarlier: true)
        XCTAssertEqual(quantity.value as? String, "180 g", app.debugDescription)
        replace(quantity, with: "4", app: app)
        assertRiceNutrition("14 cal", app: app)
        // No re-tap: each digit must keep the same focused text field alive.
        quantity.typeText("0")
        quantity.assertTextValue("40 g", within: ingredientScreen(app))
        assertRiceNutrition("142 cal", app: app)
        quantity.typeText("0")
        quantity.assertTextValue("400 g", within: ingredientScreen(app))
        assertRiceNutrition("1,422 cal", app: app)
        assertRiceNutrition("P 27 g", app: app)
        assertRiceNutrition("C 320 g", app: app)
        let preview = metrics("create_recipe_nutrition", inside: "recipe_editor_scroll", app: app)
        reveal(preview, app: app)
        assertCalories("1,422 cal", inside: preview, app: app)
        let initialShot = XCTAttachment(screenshot: app.screenshot()); initialShot.name = "Recipe - stable ingredient row and whole batch update after typing"; initialShot.lifetime = .keepAlways; add(initialShot)

        app.terminate()
        _ = launch(reset: false, app: app)
        openRecipe(app); app.navigationBars["Recipe"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Recipe"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(quantity, app: app)
        XCTAssertEqual(quantity.value as? String, "400 g", "The unsaved full-content draft must survive relaunch.\n\(app.debugDescription)")
        assertRiceNutrition("1,422 cal", app: app)
        reveal(preview, app: app); assertCalories("1,422 cal", inside: preview, app: app)

        // Fractional and four-digit amounts must survive restoration without
        // rounding or treating a grouping separator as a decimal separator.
        reveal(quantity, app: app, preferEarlier: true)
        replace(quantity, with: "1250.125", app: app)
        assertRiceNutrition("4,445 cal", app: app)
        app.terminate()
        _ = launch(reset: false, app: app)
        openRecipe(app); app.navigationBars["Recipe"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Recipe"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(quantity, app: app)
        XCTAssertEqual(quantity.value as? String, "1250.125 g", "Restoration must retain the exact ingredient amount.\n\(app.debugDescription)")
        assertRiceNutrition("4,445 cal", app: app)
        reveal(preview, app: app); assertCalories("4,445 cal", inside: preview, app: app)
        app.navigationBars["Edit Recipe"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Recipe"].waitForNonExistence(timeout: 10), app.debugDescription)

        let addToLog = app.buttons["recipe_add_to_log"]
        reveal(addToLog, app: app); addToLog.tap()
        XCTAssertTrue(app.navigationBars["Log recipe"].waitForExistence(timeout: 10), app.debugDescription)
        reveal(quantity, app: app)
        XCTAssertEqual(quantity.value as? String, "180 g", "Library content was not changed by the interrupted editor")
        replace(quantity, with: "400", app: app)
        assertRiceNutrition("1,422 cal", app: app)
        let personal = metrics("recipe_log_nutrition", inside: "recipe_logging", app: app)
        reveal(personal, app: app, preferEarlier: true)
        assertCalories("356 cal", inside: personal, app: app)
        XCTAssertTrue(app.buttons["recipe_log_save_variation"].exists, app.debugDescription)
        app.navigationBars["Log recipe"].buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Log recipe"].waitForNonExistence(timeout: 10), app.debugDescription)
        let saved = metrics("recipe_nutrition_summary", inside: "recipe_detail", app: app)
        reveal(saved, app: app); assertCalories("160 cal", inside: saved, app: app)
        let finalShot = XCTAttachment(screenshot: app.screenshot()); finalShot.name = "Recipe - log-only amount adjustment leaves saved library unchanged"; finalShot.lifetime = .keepAlways; add(finalShot)
    }
    @MainActor private func launch(reset: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "recipes", "-ui-testing-recipe-quantity"]
            + (reset ? ["-ui-testing-reset-editor-drafts"] : [])
        app.launch()
        if !app.navigationBars["My Recipes"].waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.navigationBars["My Recipes"].waitForExistence(timeout: 15), app.debugDescription); return app
    }
    @MainActor private func openRecipe(_ app: XCUIApplication) {
        let recipe = app.buttons["recipe_open_qa-quantity-recipe"]
        reveal(recipe, app: app); recipe.tap()
        if !app.navigationBars["Recipe"].waitForExistence(timeout: 5), app.navigationBars["My Recipes"].exists {
            reveal(recipe, app: app); recipe.tap()
        }
        XCTAssertTrue(app.navigationBars["Recipe"].waitForExistence(timeout: 8), app.debugDescription)
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func metrics(_ id: String, inside scrollID: String, app: XCUIApplication) -> XCUIElement {
        app.scrollViews[scrollID].otherElements.matching(identifier: id).firstMatch
    }
    @MainActor private func replace(_ field: XCUIElement, with amount: String, app: XCUIApplication) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        // The keyboard lifts the save footer over the field's previous position.
        // Recalculate its visible bounds before the selection gesture.
        reveal(field, app: app)
        field.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + amount)
        field.assertTextValue("\(amount) g", within: ingredientScreen(app))
    }
    @MainActor private func ingredientScreen(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews[app.navigationBars["Edit Recipe"].exists ? "recipe_editor_scroll" : "recipe_logging"]
    }
    @MainActor private func assertRiceNutrition(_ text: String, app: XCUIApplication,
                                                file: StaticString = #filePath, line: UInt = #line) {
        let updatedLabel = ingredientScreen(app).staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "recipe_ingredient_nutrition_qa-quantity-rice", text
        )).firstMatch
        XCTAssertTrue(updatedLabel.waitForExistence(timeout: 8), "Expected \(text) in the active ingredient row.\n\(app.debugDescription)",
                      file: file, line: line)
    }
    @MainActor private func assertCalories(_ text: String, inside element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let value = element.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5), "Expected \(text) in \(element.identifier).\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication, preferEarlier: Bool = false,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let destinations = [("Edit Recipe", "recipe_editor_scroll", "create_recipe_action"), ("Log recipe", "recipe_logging", "recipe_log_action"),
                            ("Recipe", "recipe_detail", "recipe_add_to_log"), ("My Recipes", "recipe_library", "")]
        let destination = destinations.first { app.navigationBars[$0.0].exists && app.navigationBars[$0.0].isHittable }
        let region = destination.map { any(app, $0.1) } ?? app
        for attempt in 0..<16 {
            let top = max(destination.map { app.navigationBars[$0.0].frame.maxY + 8 } ?? 80, region.frame.minY + 8)
            var bottom = min(app.frame.maxY - 20, region.frame.maxY - 8)
            if let id = destination?.2, !id.isEmpty {
                let footer = app.buttons[id]
                if footer.exists, footer.isHittable { bottom = min(bottom, footer.frame.minY - 8) }
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            if target.exists, target.isHittable, app.frame.contains(target.frame) {
                if target.identifier == destination?.2 || (target.frame.minY >= top && target.frame.maxY <= bottom) { return }
            }
            guard bottom - top > 60 else { break }
            let center = (top + bottom) / 2
            let searchDirection = attempt < 8 ? (preferEarlier ? 150.0 : -150.0) : (preferEarlier ? -150.0 : 150.0)
            let needed = target.exists && target.frame.height > 0 ? center - target.frame.midY : searchDirection
            let translation = (needed < 0 ? -1.0 : 1.0) * min(180, max(40, abs(needed)))
            let gestureX = min(region.frame.maxX - 20, region.frame.minX + 28)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: gestureX, dy: center))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: translation)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("Could not reveal recipe quantity control.\n\(app.debugDescription)", file: file, line: line)
    }
}
