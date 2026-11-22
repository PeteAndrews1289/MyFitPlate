import XCTest

final class PlannerWorkflowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ route: String = "meal-plan", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route,
                               "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] + arguments
        app.launch()
        return app
    }

    @MainActor
    func testPortionEditUpdatesNutritionAndUndoRestoresMeal() {
        let app = launch()
        let edit = app.buttons["planner_edit_planned-0-0"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        attach(app, "Planner - daily meals")
        reveal(edit, in: app); edit.tap()
        let nutrition = app.staticTexts["planner_portion_nutrition"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.label.contains("475"))
        let increase = app.buttons["planner_portions-Increment"]
        increase.tap(); increase.tap()
        XCTAssertTrue(nutrition.label.contains("713"))
        attach(app, "Planner - portion review")
        app.buttons["planner_save_meal"].tap()
        XCTAssertTrue(app.buttons["planner_save_meal"].waitForNonExistence(timeout: 5))
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.label.contains("713"))
        app.buttons["Cancel"].tap()
        undo(app)
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.label.contains("475"))
    }

    @MainActor
    func testDayOpensOnMealsAndLogsTheShownPortionOnce() {
        let app = launch()
        let log = app.buttons["meal_plan_log_planned-0-0"]
        XCTAssertTrue(log.waitForExistence(timeout: 12))
        XCTAssertTrue(log.isHittable)
        XCTAssertEqual(log.label, "Log my portion")
        XCTAssertFalse(app.buttons["planner_previous_week"].exists)
        attach(app, "Planner - meals and inline actions")
        log.tap()
        let logged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Logged"), object: log)
        XCTAssertEqual(XCTWaiter.wait(for: [logged], timeout: 8), .completed)
        XCTAssertFalse(log.isEnabled)
        app.buttons["planner_undo_logged_portion"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Log my portion"), object: log)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
        XCTAssertTrue(log.isEnabled)
        app.buttons["planner_meal_options_planned-0-0"].tap()
        app.buttons["Adjust before logging"].tap()
        XCTAssertTrue(app.buttons["planned_log_action"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.buttons["planner_edit_planned-0-0"].tap()
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].label.contains("475"))
    }

    @MainActor
    func testCopyDayAppendsAndCanUndoWithoutLosingExistingMeals() {
        let app = launch()
        let copy = app.buttons["planner_copy_day"]
        reveal(copy, in: app); copy.tap()
        let confirm = app.buttons["planner_transfer_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["3 added · 3 existing meals kept"].waitForExistence(timeout: 5))
        attach(app, "Planner - copy review preserves meals")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        selectDay(1, in: app)
        XCTAssertTrue(app.staticTexts["Berry Protein Oats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Veggie Egg Scramble"].exists)
        undo(app)
        XCTAssertTrue(app.staticTexts["Berry Protein Oats"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Veggie Egg Scramble"].exists)
    }

    @MainActor
    func testMoveMealUsesReviewAndUndoRestoresSource() {
        let app = launch()
        let options = app.buttons["planner_meal_options_planned-0-0"]
        reveal(options, in: app); options.tap()
        app.buttons["Move to date"].tap()
        let confirm = app.buttons["planner_transfer_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["1 added · 3 existing meals kept"].waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["planner_edit_planned-0-0"].waitForNonExistence(timeout: 5))
        undo(app)
        XCTAssertTrue(app.buttons["planner_edit_planned-0-0"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFoodSearchOpensPortionReviewAndAddsToPlan() {
        let app = launch()
        let add = app.buttons["meal_plan_add_meal"]
        reveal(add, in: app); add.tap()
        let search = app.textFields["food_search_field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("apple\n")
        let choice = app.buttons["food_picker_row_ui-test-apple"]
        reveal(choice, in: app); choice.tap()
        let save = app.buttons["planner_save_meal"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Choosing a food must open the portion review directly")
        XCTAssertFalse(app.buttons["food_detail_log_action"].exists)
        attach(app, "Planner - everyday food review")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        undo(app)
    }

    @MainActor
    func testFailedSaveRetainsEditedPortionAndOriginalPlan() {
        let app = launch(arguments: ["-ui-testing-meal-plan-save-failure"])
        let edit = app.buttons["planner_edit_planned-0-0"]
        reveal(edit, in: app); edit.tap()
        app.buttons["planner_portions-Increment"].tap()
        let changed = app.staticTexts["planner_portion_nutrition"].label
        app.buttons["planner_save_meal"].tap()
        XCTAssertTrue(app.staticTexts["planner_edit_error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["planner_portion_nutrition"].label, changed)
        XCTAssertTrue(app.buttons["planner_save_meal"].isEnabled)
        attach(app, "Planner - failed save keeps edits")
        app.buttons["Cancel"].tap()
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.staticTexts["planner_portion_nutrition"].label.contains("475"))
    }

    @MainActor
    func testWeekNavigationAndReuseAreReviewedBeforeSave() {
        let app = launch()
        app.buttons["planner_view_mode"].tap()
        let next = app.buttons["planner_next_week"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let range = app.staticTexts["planner_week_range"].label
        next.tap()
        XCTAssertNotEqual(app.staticTexts["planner_week_range"].label, range)
        app.buttons["meal_plan_tools"].tap()
        app.buttons["Reuse previous week"].tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 8))
        let keep = app.staticTexts["Keeps your existing meals"]
        XCTAssertTrue(keep.exists)
        let options = app.buttons["Plan options"]
        let scroll = app.scrollViews.containing(.button, identifier: "Plan options").firstMatch
        for _ in 0..<8 where options.frame.maxY >= keep.frame.minY - 8 { scroll.swipeUp() }
        options.tap()
        XCTAssertTrue(app.staticTexts["Your existing meals stay. This plan fills the remaining slots."].waitForExistence(timeout: 5))
        let replace = app.switches["planner_draft_replace"]
        if replace.exists {
            XCTAssertEqual(replace.value as? String, "0", "Keep existing meals by default")
        } else {
            XCTAssertTrue(app.staticTexts["Existing meal slots are locked"].exists)
        }
        XCTAssertTrue(use.isEnabled)
        attach(app, "Planner - reuse week review")
        use.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 8))
        XCTAssertEqual(app.buttons["planner_view_mode"].label, "Show selected day")
        XCTAssertTrue(app.staticTexts["Berry Protein Oats"].waitForExistence(timeout: 5))
        attach(app, "Planner - weekly agenda")
        undo(app)
        app.buttons["planner_previous_week"].tap()
        XCTAssertEqual(app.staticTexts["planner_week_range"].label, range)
    }

    @MainActor
    func testWorkoutUpcomingSessionPreviewAndScheduleAccess() {
        let app = launch("train")
        openProgramOverview(in: app)
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "training_preview_")).firstMatch
        reveal(preview, in: app)
        let original = preview.label
        attach(app, "Workout - upcoming sessions")
        preview.tap()
        XCTAssertTrue(app.navigationBars["Session preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Equipment to have ready"].exists)
        XCTAssertTrue(app.staticTexts["training_preview_equipment"].label.contains("Dumbbell or Kettlebell"))
        attach(app, "Workout - session preparation")
        app.buttons["Done"].tap()
        XCTAssertEqual(preview.label, original, "Preview must preserve the active slot")
        let adjust = app.buttons["training_adjust_week"]
        reveal(adjust, in: app); adjust.tap()
        XCTAssertTrue(app.buttons["rescue_primary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGenerationFailureKeepsChoicesInsteadOfSavingAFallback() {
        let app = launch("meal-plan-survey-cooking")
        let ideas = app.segmentedControls["planner_generation_source"].buttons["Maia ideas"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 10)); ideas.tap()
        let generate = app.buttons["meal_plan_generate_plan"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10)); generate.tap()
        let feedback = app.staticTexts["meal_plan_generation_error"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertTrue(feedback.label.contains("choices are still here"))
        XCTAssertTrue(ideas.isSelected)
        XCTAssertTrue(generate.isEnabled)
        XCTAssertFalse(app.buttons["planner_use_draft"].exists)
        attach(app, "Planner - generation failure retains choices")
    }

    @MainActor
    func testRecipeDetailAddsWithoutReplacingExistingMeals() {
        let app = launch("recipes")
        let recipe = app.buttons["recipe_open_demo-recipe-chicken-bowl"]
        reveal(recipe, in: app); recipe.tap()
        let add = app.buttons["recipe_add_to_plan"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let save = app.buttons["recipe_plan_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        attach(app, "Planner - recipe detail add")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 8))
        add.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 meals")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecipeDetailFailedSaveKeepsChoices() {
        let app = launch("recipes", arguments: ["-ui-testing-meal-plan-save-failure"])
        let recipe = app.buttons["recipe_open_demo-recipe-chicken-bowl"]
        reveal(recipe, in: app); recipe.tap()
        let add = app.buttons["recipe_add_to_plan"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let save = app.buttons["recipe_plan_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        save.tap()
        let alert = app.alerts["Could Not Add Recipe"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["OK"].tap()
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 meal")).firstMatch.exists)
    }

    @MainActor
    func testShoppingUsesTheBrowsedWeek() {
        let app = launch(arguments: ["-ui-testing-stock-reservations"])
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "account_loading_screen")
            .firstMatch.waitForNonExistence(timeout: 10))
        workspace.buttons["Plan"].tap()
        XCTAssertTrue(app.buttons["meal_plan_add_meal"].waitForExistence(timeout: 10))
        app.buttons["planner_view_mode"].tap()
        let next = app.buttons["planner_next_week"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap(); next.tap()
        // This week contains a distinct planned rice batch two weeks from today.
        let nextDate = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        let selectedDate = app.buttons["planner_choose_date"]
        let selectedWeek = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", nextDate.formatted(date: .complete, time: .omitted)), object: selectedDate)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedWeek], timeout: 5), .completed)
        let shop = workspace.buttons["Shop"]
        XCTAssertTrue(shop.isHittable); shop.tap()
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: nextDate)!.start
        let heading = app.staticTexts["grocery_week_heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "Week of \(start.formatted(date: .abbreviated, time: .omitted))")
        let rice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@",
                                                  "grocery_item_", "dry rice")).firstMatch
        revealShoppingControl(rice, in: app)
        attach(app, "Planner - groceries for selected week")
        XCTAssertTrue(workspace.buttons["Cook"].isHittable); workspace.buttons["Cook"].tap()
        XCTAssertTrue(app.segmentedControls["meal_prep_mode_picker"].waitForExistence(timeout: 5))
        attach(app, "Planner - prep for selected week")
    }

    @MainActor
    func testWeekAndWorkoutPreviewSupportLargestTextInDarkMode() {
        let arguments = ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let app = launch(arguments: arguments)
        let mode = app.buttons["planner_view_mode"]
        reveal(mode, in: app); mode.tap()
        let day = app.buttons["planner_agenda_\(dayID(0))"]
        reveal(day, in: app)
        XCTAssertGreaterThanOrEqual(day.frame.minX, 0)
        XCTAssertLessThanOrEqual(day.frame.maxX, app.frame.maxX)
        attach(app, "Planner - large text week")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-reset-workout-draft"] + arguments
        app.launch()
        openProgramOverview(in: app)
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "training_preview_")).firstMatch
        reveal(preview, in: app); preview.tap()
        XCTAssertTrue(app.navigationBars["Session preview"].waitForExistence(timeout: 5))
        attach(app, "Workout - large text preview")
    }

    private func dayID(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor
    private func openProgramOverview(in app: XCUIApplication) {
        let overview = app.buttons["train_program_overview"]
        reveal(overview, in: app); overview.tap()
        XCTAssertTrue(app.navigationBars["Program & schedule"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func selectDay(_ offset: Int, in app: XCUIApplication) {
        let mode = app.buttons["planner_view_mode"]
        reveal(mode, in: app); mode.tap()
        let calendar = Calendar.current
        let today = Date()
        if let target = calendar.date(byAdding: .day, value: offset, to: today),
           !calendar.isDate(target, equalTo: today, toGranularity: .weekOfYear) {
            app.buttons[offset > 0 ? "planner_next_week" : "planner_previous_week"].tap()
        }
        let day = app.buttons["planner_agenda_\(dayID(offset))"]
        reveal(day, in: app); day.tap()
    }

    @MainActor
    private func undo(_ app: XCUIApplication) {
        let button = app.buttons["planner_undo"]
        reveal(button, in: app); button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<24 {
            let frame = element.frame
            let tallerThanViewport = frame.height > app.frame.height - 195
            if element.isHittable && frame.minY >= app.frame.minY + 110
                && (frame.maxY < app.frame.maxY - 85 || (tallerThanViewport && frame.minY < app.frame.midY)) { return }
            let up = frame.minY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.75 : 0.28))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: up ? 0.40 : 0.62)))
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func revealShoppingControl(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.matching(identifier: "grocery_list").firstMatch
        let dock = app.descendants(matching: .any).matching(identifier: "main_navigation_dock").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(scroll.exists)
        for _ in 0..<12 {
            let top = scroll.frame.minY + 8
            let bottom = dock.frame.minY - 8
            let frame = element.frame
            if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
            let center = (top + bottom) / 2
            let delta = center - frame.midY
            let distance = (delta < 0 ? -1.0 : 1.0) * min(160, max(36, abs(delta)))
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: scroll.frame.midX, dy: center))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        attach(app, "Shopping - explanation control visibility failure")
        XCTFail("Shopping control must be visible above the dock.\n\(app.debugDescription)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
