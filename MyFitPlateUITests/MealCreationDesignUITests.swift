import XCTest

/// Local screenshot fixtures only: selection is reversible and never touches the owner's account.
final class MealCreationDesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testSharedSearchKeepsDateAndSlotAcrossRecipeMealReviewsAndCancellation() {
        let app = launch()
        let date = app.buttons["planner_view_mode"].value as? String
        XCTAssertNotNil(date, "The selected planner date must be available for the review check")
        openChooser(app)
        let compactDate = app.staticTexts["planner_choice_date"].label
        let slot = app.buttons["planner_add_slot"]
        slot.tap()
        app.buttons["Lunch"].tap()
        let search = app.textFields["food_search_field"]
        search.tap(); search.typeText("rice\n")
        let scopes = app.segmentedControls["planner_choice_scope"]
        scopes.buttons["Recipes"].tap()
        let recipe = app.buttons["planner_choose_recipe_demo-wave2-batch"]
        reveal(recipe, app: app); recipe.tap()
        XCTAssertTrue(app.navigationBars["Review planned meal"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lunch")).firstMatch.exists, app.debugDescription)
        assertReview(app, date: date, name: "Four-serving rice batch", calories: "400")
        attach(app, "Meal review - compact destination portion and nutrition")
        app.buttons["planner_measured_unit"].tap()
        app.buttons["Grams"].tap()
        let amount = app.textFields["planner_measured_amount"]
        let measured = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "200"), object: amount)
        XCTAssertEqual(XCTWaiter.wait(for: [measured], timeout: 5), .completed, "One portion of this cooked batch is 200 grams")
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].label.contains("400"), "Changing the display unit keeps planned nutrition unchanged")
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let done = app.buttons["planner_portion_keyboard_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(done.isHittable, app.debugDescription); done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Review planned meal"].exists, "Done dismisses only the keyboard")
        XCTAssertEqual(amount.value as? String, "200", "Dismissing the keyboard preserves the reviewed cooked grams")
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].label.contains("400"), "Keyboard Done leaves planned nutrition unchanged")
        let save = app.buttons["planner_save_meal"]
        XCTAssertTrue(save.exists && save.isHittable && app.frame.contains(save.frame), "The review still requires its reachable explicit Save")
        app.buttons["planner_measured_unit"].tap()
        app.buttons["Ounces (mass)"].tap()
        assertReview(app, date: date, name: "Four-serving rice batch", calories: "400")
        let displayedOunces = Double((amount.value as? String ?? "").replacingOccurrences(of: ",", with: "."))
        XCTAssertNotNil(displayedOunces, "The ounce amount remains numeric after the responsive layout changes")
        XCTAssertEqual(displayedOunces ?? -.infinity, 7.0548, accuracy: 0.0001, "Changing 200 cooked grams to ounces must convert the displayed amount")
        attach(app, "Meal review - full ounce unit and portion controls stay visible")
        app.navigationBars["Review planned meal"].buttons["Cancel"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(search.value as? String, "rice")
        XCTAssertEqual(app.staticTexts["planner_choice_date"].label, compactDate)
        XCTAssertTrue(slot.label.contains("Lunch") || (slot.value as? String)?.contains("Lunch") == true, app.debugDescription)

        scopes.buttons["Meals"].tap()
        let meal = app.buttons["planner_choose_composition_workspace-composition"]
        reveal(meal, app: app); meal.tap()
        assertReview(app, date: date, name: "QA composed bowl", calories: "500")
        app.navigationBars["Review planned meal"].buttons["Cancel"].tap()
        XCTAssertEqual(search.value as? String, "rice", "Changing sources must preserve the one shared query")
        app.navigationBars["Add meal"].buttons["Cancel"].tap()
        let original = app.buttons["planner_edit_planned-0-0"]
        reveal(original, app: app)
        XCTAssertFalse(app.staticTexts["QA composed bowl"].exists, "Cancelled choices must not write a planned meal")
        original.tap()
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].label.contains("475"), "The existing plan must retain its original amount")
        attach(app, "Meal creation - cancelled mixed choices preserve the original plan")
    }

    @MainActor func testReusableMealOpensPortionReviewDirectlySavesAndUndoPreservesExistingMeals() {
        let app = launch(dark: true)
        openChooser(app)
        attach(app, "Meal creation - one chooser for foods recipes and meals")
        app.segmentedControls["planner_choice_scope"].buttons["Meals"].tap()
        let meal = app.buttons["planner_choose_composition_workspace-composition"]
        reveal(meal, app: app); meal.tap()
        assertReview(app, date: nil, name: "QA composed bowl", calories: "500")
        XCTAssertFalse(app.navigationBars["Reusable meals"].exists, "Picking a saved meal needs no intervening management screen")
        let increase = app.buttons["planner_portions-Increment"]
        reveal(increase, app: app, preferEarlier: true); increase.tap(); increase.tap()
        let nutrition = app.staticTexts["planner_portion_nutrition"]
        reveal(nutrition, app: app)
        XCTAssertTrue(nutrition.label.contains("750"), "One and a half saved meals must plan one and a half of every component")
        attach(app, "Meal review - dark reusable portion retains explicit save")
        app.buttons["planner_save_meal"].tap()
        XCTAssertTrue(app.buttons["planner_save_meal"].waitForNonExistence(timeout: 10), app.debugDescription)
        let added = app.staticTexts["QA composed bowl"]
        reveal(added, app: app)
        XCTAssertTrue(added.exists, app.debugDescription)
        let undo = app.buttons["planner_undo"]
        reveal(undo, app: app, preferEarlier: true); undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(added.waitForNonExistence(timeout: 5), app.debugDescription)
        let original = app.buttons["planner_edit_planned-0-0"]
        reveal(original, app: app, preferEarlier: true); original.tap()
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(nutrition.label.contains("475"), "Undo must preserve earlier meals and portions")
    }

    @MainActor private func launch(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan",
                               "-ui-testing-meal-workspace", "-ui-testing-recipe-portions",
                               "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"]
            + (dark ? ["-screenshot-dark-mode"] : [])
        app.launch()
        let workspace = app.segmentedControls["planner_workspace"]
        if !workspace.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(workspace.waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    @MainActor private func openChooser(_ app: XCUIApplication) {
        let add = app.buttons["meal_plan_add_meal"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription); add.tap()
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.segmentedControls["planner_choice_scope"].exists, app.debugDescription)
    }

    @MainActor private func assertReview(_ app: XCUIApplication, date: String?, name: String, calories: String) {
        XCTAssertTrue(app.navigationBars["Review planned meal"].waitForExistence(timeout: 5), app.debugDescription)
        let reviewedName = app.collectionViews["planner_edit_form"].staticTexts[name]
        XCTAssertTrue(reviewedName.exists, app.debugDescription)
        if let date { XCTAssertTrue(app.staticTexts[date].exists, "The planner's selected date must carry into review.\n\(app.debugDescription)") }
        let nutrition = app.staticTexts["planner_portion_nutrition"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5), app.debugDescription)
        assertFirstViewport(app, controls: [reviewedName, app.staticTexts["planner_review_date"],
            app.buttons["planner_review_slot"], app.textFields["planner_measured_amount"],
            app.buttons["planner_measured_unit"], app.buttons["planner_portions-Increment"], nutrition])
        XCTAssertTrue(nutrition.label.contains(calories), app.debugDescription)
        XCTAssertFalse(app.buttons["food_detail_log_action"].exists, "Selecting a planned meal must never become diary logging")
    }

    @MainActor private func assertFirstViewport(_ app: XCUIApplication, controls: [XCUIElement], file: StaticString = #filePath, line: UInt = #line) {
        let save = app.buttons["planner_save_meal"]
        XCTAssertTrue(save.exists && save.isHittable, "Explicit save remains pinned and reachable", file: file, line: line)
        let navigation = app.navigationBars["Review planned meal"]
        for control in controls {
            XCTAssertTrue(control.exists && control.isHittable, "The review's essential choices need no scrolling.\n\(app.debugDescription)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(control.frame.minY, navigation.frame.maxY, file: file, line: line)
            XCTAssertLessThanOrEqual(control.frame.maxY, save.frame.minY - 8, "The pinned save must not cover a review choice", file: file, line: line)
            XCTAssertTrue(app.frame.contains(control.frame), "The compact review must not clip a control horizontally", file: file, line: line)
        }
    }

    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication, preferEarlier: Bool = false) {
        for attempt in 0..<12 {
            let navigation = app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY + 8 : app.frame.minY + 110
            let save = app.buttons["planner_save_meal"]
            let bottom = min(app.frame.maxY - 95, save.exists && save.isHittable
                ? save.frame.minY - 8 : app.frame.maxY - 95)
            if target.exists, target.isHittable, target.frame.minY >= top, target.frame.maxY <= bottom { return }
            let upwards = target.exists && target.frame.height > 0 ? target.frame.midY > (top + bottom) / 2
                : (attempt < 6 ? !preferEarlier : preferEarlier)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.maxX - 24, dy: upwards ? bottom - 12 : top + 100))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: upwards ? -160 : 160)))
        }
        XCTAssertTrue(target.exists && target.isHittable, app.debugDescription)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
