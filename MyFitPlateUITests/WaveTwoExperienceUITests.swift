import XCTest

final class WaveTwoExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testRelevantBrandsSettleAheadOfGenericFood() {
        verifyBrandOrder(flags: [])
    }

    @MainActor
    func testBrandedFlavorAndPrintedSizeAreVisibleBeforeOpeningPortion() {
        let app = launch("food-search", flags: ["-ui-testing-branded-food-search", "-ui-testing-product-sizes"])
        let search = app.textFields["food_search_field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("Chobani vanilla 5.3oz\n")
        let row = app.buttons["food_picker_row_ui-vanilla-small"]
        reveal(row, app: app)
        for value in ["Chobani", "Vanilla", "5.3 oz"] { XCTAssertTrue(row.label.contains(value)) }
        XCTAssertFalse(app.buttons["food_picker_row_ui-vanilla-large"].exists)
        XCTAssertFalse(app.buttons["food_picker_row_ui-strawberry-small"].exists)
        record(app, "Branded search - exact flavor and stated serving")
    }

    @MainActor
    func testBrandedSearchRetainsGenericFallbackAtLargestText() {
        verifyBrandOrder(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    }

    @MainActor
    func testRecipeServingsAndCookedGramsKeepTheSameReviewedAmount() {
        let app = launch("recipes", flags: ["-ui-testing-recipe-portions"])
        openRecipe(app)
        app.buttons["recipe_add_to_log"].tap()
        let amount = app.textFields["recipe_log_portion_amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        replace(amount, with: "1.5", app: app)
        let equivalent = any(app, "recipe_log_portion_equivalent")
        XCTAssertTrue(equivalent.label.contains("37.5%"))
        select("Cooked grams", picker: app.buttons["recipe_log_portion_unit"], app: app)
        XCTAssertEqual(Double(amount.value as? String ?? ""), 300)
        select("Servings", picker: app.buttons["recipe_log_portion_unit"], app: app)
        XCTAssertEqual(Double(amount.value as? String ?? ""), 1.5)
        XCTAssertTrue(app.buttons["recipe_log_action"].isEnabled)
        record(app, "Recipe - equivalent servings and cooked grams")
        app.navigationBars.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(any(app, "recipe_detail_title").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recipe_add_to_log"].exists)
    }

    @MainActor
    func testReviewedRecipePortionLogsOnceInTheDiary() {
        let app = launch("recipes", flags: ["-ui-testing-recipe-portions"])
        openRecipe(app); app.buttons["recipe_add_to_log"].tap()
        let amount = app.textFields["recipe_log_portion_amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        replace(amount, with: "1.5", app: app)
        let save = app.buttons["recipe_log_action"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
        let back = app.navigationBars["Recipe"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5)); XCTAssertTrue(back.isHittable); back.tap()
        let done = app.navigationBars["My Recipes"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.scrollViews["recipe_library"].waitForNonExistence(timeout: 5))
        let home = app.buttons["tab_home"]
        XCTAssertTrue(home.isHittable); home.tap()
        let foods = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'diary_food_' AND NOT identifier BEGINSWITH 'diary_food_options_' AND label CONTAINS %@",
            "Four-serving rice batch"))
        let food = foods.firstMatch
        reveal(food, app: app)
        XCTAssertTrue(food.exists)
        XCTAssertEqual(foods.count, 1)
        XCTAssertTrue(food.label.contains("600"), "The reviewed 1.5-serving portion must keep its 600 calories")
        record(app, "Recipe - one accepted diary portion")
    }

    @MainActor
    func testRecipeYieldEditKeepsWholeBatchAndPlanningUsesTheSamePortionRules() {
        let app = launch("recipes", flags: ["-ui-testing-recipe-portions"])
        openRecipe(app); app.navigationBars.buttons["Edit"].tap()
        select("The whole batch", picker: app.buttons["recipe_yield_basis"], app: app)
        replace(app.textFields["recipe_yield"], with: "6", app: app)
        replace(app.textFields["recipe_cooked_weight"], with: "800", app: app)
        app.buttons["create_recipe_action"].tap()
        XCTAssertTrue(app.buttons["create_recipe_action"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(any(app, "recipe_detail_title").exists)
        app.buttons["recipe_add_to_plan"].tap()
        let amount = app.textFields["recipe_plan_portion_amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        select("Cooked grams", picker: app.buttons["recipe_plan_portion_unit"], app: app)
        replace(amount, with: "300", app: app)
        let equivalent = any(app, "recipe_plan_portion_equivalent")
        reveal(equivalent, app: app)
        XCTAssertTrue(equivalent.label.contains("2.25 servings"))
        XCTAssertTrue(equivalent.label.contains("37.5%"))
        XCTAssertTrue(app.buttons["recipe_plan_save"].isEnabled)
        record(app, "Recipe - confirmed batch yield and planning portion")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor
    func testRejectedRecipeSaveResumesFrozenAndCancelsSafely() {
        let app = launch("recipes", flags: ["-ui-testing-recipe-portions", "-ui-testing-recipe-save-failure"])
        openRecipe(app); app.navigationBars.buttons["Edit"].tap()
        select("The whole batch", picker: app.buttons["recipe_yield_basis"], app: app)
        replace(app.textFields["recipe_yield"], with: "6", app: app)
        app.buttons["create_recipe_action"].tap()
        XCTAssertTrue(any(app, "recipe_pending_save").waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "create_recipe_error").exists)
        XCTAssertFalse(app.textFields["recipe_yield"].exists, "A submitted save must not be retargetable")
        app.terminate()
        _ = launch("recipes", flags: ["-ui-testing-recipe-portions"], resets: false, app: app)
        openRecipe(app); app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(any(app, "recipe_pending_save").waitForExistence(timeout: 10))
        let pendingName = any(app, "recipe_pending_name")
        reveal(pendingName, app: app)
        XCTAssertTrue(pendingName.label.contains("Four-serving rice batch"))
        let check = app.buttons["recipe_pending_check_status"]
        reveal(check, app: app); check.tap()
        XCTAssertTrue(app.buttons["recipe_pending_cancel"].waitForExistence(timeout: 5))
        let cancel = app.buttons["recipe_pending_cancel"]
        reveal(cancel, app: app); assertVisibleControl(cancel, app: app); cancel.tap()
        XCTAssertTrue(app.buttons["create_recipe_action"].waitForNonExistence(timeout: 15))
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertFalse(any(app, "recipe_pending_save").exists)
        select("The whole batch", picker: app.buttons["recipe_yield_basis"], app: app)
        XCTAssertEqual(Double(app.textFields["recipe_yield"].value as? String ?? ""), 4)
        record(app, "Recipe - rejected save recovered and fenced cancellation")
    }

    @MainActor
    func testPHULBlockSavePreservesPositionAtLargestText() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul", "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openBlock(app)
        let name = any(app, "block_name")
        replace(name, with: "PHUL working block", app: app)
        let save = app.buttons["block_save"]
        XCTAssertTrue(save.isEnabled)
        assertVisibleControl(save, app: app)
        record(app, "PHUL - large text block review")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
        let progress = any(app, "program_progress_summary")
        reveal(progress, app: app)
        XCTAssertTrue(progress.label.contains("39 of 48"))
        openBlock(app)
        XCTAssertEqual(any(app, "block_name").value as? String, "PHUL working block")
        let current = app.buttons["block_session_39"]
        reveal(current, app: app)
        XCTAssertTrue(current.isEnabled)
        record(app, "PHUL - progress intact after authored block")
    }

    @MainActor
    func testWeekSpecificStructuredTargetSurvivesNestedSaveAndReopen() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul"])
        openBlock(app)
        let session = app.buttons["block_session_39"]
        reveal(session, app: app); session.tap()
        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Barbell Front Squat")).firstMatch
        reveal(exercise, app: app); exercise.tap()
        let structure = app.buttons["edit_prescription_0"]
        reveal(structure, app: app); structure.tap()
        replace(app.textFields["prescription_lower"], with: "6", app: app)
        replace(app.textFields["prescription_upper"], with: "8", app: app)
        let use = app.buttons["prescription_save"]
        XCTAssertTrue(use.isEnabled); use.tap()
        let saveExercise = app.buttons["Save Exercise"].firstMatch
        XCTAssertTrue(saveExercise.waitForExistence(timeout: 5)); saveExercise.tap()
        let saveRoutine = app.buttons["routine_builder_save"]
        XCTAssertTrue(saveRoutine.waitForExistence(timeout: 5)); saveRoutine.tap()
        let saveBlock = app.buttons["block_save"]
        XCTAssertTrue(saveBlock.waitForExistence(timeout: 5)); saveBlock.tap()
        XCTAssertTrue(saveBlock.waitForNonExistence(timeout: 15))
        openBlock(app); reveal(session, app: app); session.tap()
        reveal(exercise, app: app); exercise.tap()
        reveal(structure, app: app); structure.tap()
        XCTAssertEqual(Double(app.textFields["prescription_lower"].value as? String ?? ""), 6)
        XCTAssertEqual(Double(app.textFields["prescription_upper"].value as? String ?? ""), 8)
        record(app, "PHUL - authored set prescription round trip")
    }

    @MainActor
    func testRejectedBlockSaveKeepsFrozenIntentAfterRestart() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul", "-ui-testing-block-save-failure"])
        openBlock(app); replace(any(app, "block_name"), with: "PHUL pending block", app: app)
        app.buttons["block_save"].tap()
        XCTAssertTrue(any(app, "block_save_error").waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "block_name").isEnabled)
        app.terminate()
        _ = launch("program-detail", flags: ["-ui-testing-wave2-phul"], resets: false, app: app)
        openBlock(app)
        XCTAssertEqual(any(app, "block_name").value as? String, "PHUL pending block")
        XCTAssertFalse(any(app, "block_name").isEnabled)
        app.buttons["block_save"].tap()
        XCTAssertTrue(app.buttons["block_save"].waitForNonExistence(timeout: 15))
        let progress = any(app, "program_progress_summary"); reveal(progress, app: app)
        XCTAssertTrue(progress.label.contains("39 of 48"))
        record(app, "PHUL - exact rejected block retry with progress preserved")
    }

    @MainActor
    private func verifyBrandOrder(flags: [String]) {
        let app = launch("food-search", flags: ["-ui-testing-branded-food-search"] + flags)
        let search = app.textFields["food_search_field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("yogurt\n")
        let branded = app.buttons["food_picker_row_ui-chobani-yogurt"]
        reveal(branded, app: app)
        XCTAssertTrue(branded.exists)
        XCTAssertTrue(branded.label.contains("Chobani"))
        XCTAssertFalse(app.buttons["food_picker_row_ui-unrelated-pineapple"].exists)
        let generic = app.buttons["food_picker_row_ui-generic-yogurt"]
        XCTAssertTrue(generic.exists, "Generic fallback must remain available")
        let fage = app.buttons["food_picker_row_ui-fage-yogurt"]
        XCTAssertTrue(fage.exists)
        XCTAssertLessThan(branded.frame.minY, generic.frame.minY)
        XCTAssertLessThan(fage.frame.minY, generic.frame.minY)
        let history = app.buttons["food_picker_row_search-yogurt"]
        reveal(history, app: app)
        XCTAssertTrue(history.exists, "The usual generic food remains available below relevant brands")
        XCTAssertLessThan(branded.frame.minY, history.frame.minY)
        XCTAssertLessThan(fage.frame.minY, history.frame.minY)
        record(app, "Food search - relevant branded foods first")
    }

    @MainActor
    private func launch(_ screen: String, flags: [String], resets: Bool = true, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags
            + (resets ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        let expected = screen == "recipes" ? app.buttons["recipe_open_demo-wave2-batch"]
            : screen == "program-detail" ? app.buttons["program_edit_block"] : app.textFields["food_search_field"].firstMatch
        if !expected.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        return app
    }
    @MainActor private func openRecipe(_ app: XCUIApplication) {
        let recipe = app.buttons["recipe_open_demo-wave2-batch"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10)); reveal(recipe, app: app); recipe.tap()
        let navigation = app.navigationBars["Recipe"]
        if !navigation.waitForExistence(timeout: 5), app.navigationBars["My Recipes"].exists, recipe.isHittable {
            // A sheet's initial presentation can consume the first navigation tap.
            // Retry only after confirming this read-only library destination remains open.
            recipe.staticTexts["Four-serving rice batch"].tap()
        }
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), app.debugDescription)
        let title = any(app, "recipe_detail_title")
        reveal(title, app: app)
        XCTAssertTrue(title.exists)
    }
    @MainActor private func openBlock(_ app: XCUIApplication) {
        let open = app.buttons["program_edit_block"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); reveal(open, app: app); open.tap()
        XCTAssertTrue(app.buttons["block_save"].waitForExistence(timeout: 10))
    }
    @MainActor private func select(_ title: String, picker: XCUIElement, app: XCUIApplication) {
        let done = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["recipe_log_portion_done", "recipe_plan_portion_done"])).firstMatch
        if done.exists, done.isHittable { done.tap() }
        reveal(picker, app: app); picker.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app); field.tap(); field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        if field.value as? String == value { return }
        field.press(forDuration: 1)
        let all = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if all.waitForExistence(timeout: 2) { all.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        XCTAssertEqual(field.value as? String, value)
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let surfaces = ["prescription_editor_form", "exercise_editor_scroll", "routine_builder", "workout_block_editor_scroll",
                        "recipe_editor_scroll", "recipe_logging", "recipe_plan_scroll", "recipe_detail", "recipe_library", "food_search_results_scroll",
                        "program_detail", "home_scroll"]
        let preferred = surfaces.lazy.compactMap { identifier -> (String, XCUIElement)? in
            let view = app.scrollViews[identifier].firstMatch
            if view.exists { return (identifier, view) }
            let form = app.collectionViews[identifier].firstMatch
            if form.exists { return (identifier, form) }
            let table = app.tables[identifier].firstMatch
            return table.exists ? (identifier, table) : nil
        }.first
        let scroll = preferred?.1 ?? app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
            ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable) ?? app.scrollViews.firstMatch
        let titles = ["prescription_editor_form": "Set prescription", "exercise_editor_scroll": "Edit Exercise",
                      "routine_builder": "Edit Routine", "workout_block_editor_scroll": "Training block",
                      "recipe_editor_scroll": "Edit Recipe", "recipe_logging": "Log recipe", "recipe_plan_scroll": "Add to Plan",
                      "recipe_detail": "Recipe", "recipe_library": "My Recipes", "food_search_results_scroll": "Log food", "program_detail": "Program"]
        let namedNav = app.navigationBars[titles[preferred?.0 ?? ""] ?? ""].firstMatch
        let nav = namedNav.exists ? namedNav : app.navigationBars.firstMatch
        let footerIDs = ["prescription_editor_form": "prescription_save", "exercise_editor_scroll": "exercise_editor_save",
                         "routine_builder": "routine_builder_save", "workout_block_editor_scroll": "block_save",
                         "recipe_editor_scroll": "create_recipe_action", "recipe_logging": "recipe_log_action",
                         "recipe_plan_scroll": "recipe_plan_save"]
        let footer = footerIDs[preferred?.0 ?? ""].map { app.buttons[$0] }
        var above = false
        for step in 0..<30 {
            let top = max(nav.exists ? nav.frame.maxY + 4 : 90, scroll.exists ? scroll.frame.minY + 4 : 90)
            let pinned = [footer].compactMap { $0 }.filter { $0.exists && $0.frame.height > 0 && $0.isHittable }
            var bottom = min(scroll.exists ? scroll.frame.maxY - 4 : app.frame.maxY - 12, app.frame.maxY - 12)
            if let edge = pinned.map(\.frame.minY).min() { bottom = min(bottom, edge - 5) }
            if preferred?.0 == "recipe_editor_scroll" {
                let footerContainer = any(app, "recipe_editor_footer")
                if footerContainer.exists { bottom = min(bottom, footerContainer.frame.minY - 5) }
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            if element.exists, element.isHittable {
                if pinned.contains(where: { $0.identifier == element.identifier }), app.frame.contains(element.frame) { return }
                if element.frame.minY >= top, element.frame.maxY <= bottom { return }
            }
            guard bottom - top > 50 else { break }
            let distance: CGFloat
            if element.exists, element.frame.height > 0 {
                above = element.frame.minY < top
                distance = min(180, max(24, (above ? top - element.frame.minY : element.frame.maxY - bottom) + 12))
            } else {
                if step == 15 { above.toggle() }
                distance = min(180, (bottom - top) * 0.4)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let startY = top + (bottom - top) * 0.5
            let endY = min(bottom - 8, max(top + 8, startY + (above ? distance : -distance)))
            let gestureX = scroll.exists ? min(scroll.frame.maxX - 20, scroll.frame.minX + 28) : app.frame.width * 0.1
            origin.withOffset(CGVector(dx: gestureX, dy: startY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: gestureX, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTFail("Could not reveal complete control: \(element.identifier). \(app.debugDescription)")
    }
    @MainActor private func assertVisibleControl(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.isHittable); XCTAssertTrue(app.frame.contains(element.frame))
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
