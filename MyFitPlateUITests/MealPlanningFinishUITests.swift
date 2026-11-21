import XCTest

final class MealPlanningFinishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testRecipeReadinessAndPartialWeekRepairKeepReviewExplicit() {
        let app = launch("meal-plan-survey", flags: ["-ui-testing-planner-blank", "-ui-testing-constrained-recipes"])
        let readiness = app.staticTexts["planner_recipe_readiness"]
        reveal(readiness, app: app)
        XCTAssertTrue(readiness.label.hasPrefix("1 of "), app.debugDescription)
        let slots = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Meals to plan")).firstMatch
        // Recipe readiness is below this row. A native Form may virtualize the earlier row.
        reveal(slots, app: app, preferEarlier: true); slots.tap()
        for name in ["breakfast", "dinner", "snack"] {
            let toggle = app.switches["planner_slot_\(name)"]
            set(toggle, to: "0", app: app)
        }
        XCTAssertTrue(slots.label.contains("1 selected"), app.debugDescription)
        slots.tap()
        let repeatMeals = app.switches["planner_repeat_meals"]
        set(repeatMeals, to: "0", app: app)
        let cooking = app.buttons["Cooking days and open meals"]
        reveal(cooking, app: app); cooking.tap()
        let lastDay = app.steppers["planner_cooking_day_6"]
        reveal(lastDay, app: app)
        let decrement = lastDay.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", "-Decrement", "Decrement")).firstMatch
        for _ in 0..<4 { decrement.tap() }
        XCTAssertTrue(lastDay.label.contains("No cooking"), app.debugDescription)
        app.buttons["meal_plan_generate_plan"].tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15)); XCTAssertFalse(use.isEnabled)
        let partial = any(app, "planner_partial_review")
        // SwiftUI propagates the partial-card identifier to its child controls.
        // This fixture has exactly one unresolved slot; address its visible action.
        let addTime = app.buttons.matching(NSPredicate(format: "label == %@", "Add 15 cooking minutes")).firstMatch
        reveal(addTime, app: app); XCTAssertTrue(partial.exists); addTime.tap(); addTime.tap()
        // A partial draft offers regeneration beside its repair controls, without opening Plan options.
        let regenerate = app.buttons["planner_regenerate_gaps"]
        reveal(regenerate, app: app); regenerate.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: use)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, app.debugDescription)
        XCTAssertFalse(any(app, "planner_partial_review").exists)
        record(app, "Practical week - specific cooking repair resolves partial draft")
    }
    @MainActor func testConstrainedWeekReviewsHouseholdAndSaves() {
        let app = launch("meal-plan-survey", flags: ["-ui-testing-planner-blank", "-ui-testing-constrained-recipes"])
        let build = app.buttons["meal_plan_generate_plan"]
        XCTAssertTrue(build.waitForExistence(timeout: 15)); build.tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15)); XCTAssertTrue(use.isEnabled)
        XCTAssertTrue(any(app, "planner_constraint_report").exists)
        record(app, "Checked saved-recipe week")
        use.tap(); XCTAssertTrue(use.waitForNonExistence(timeout: 15))
        XCTAssertFalse(any(app, "planner_draft_error").exists)
    }
    @MainActor func testPracticalWeekKeepsOpenDinnerAndCookingBriefThroughReview() {
        let app = launch("meal-plan-survey", flags: ["-ui-testing-planner-blank", "-ui-testing-constrained-recipes"])
        let slots = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Meals to plan")).firstMatch
        reveal(slots, app: app); slots.tap()
        for slot in ["breakfast", "snack"] {
            let toggle = app.switches.matching(NSPredicate(format: "label == %@", slot.capitalized)).firstMatch
            reveal(toggle, app: app); toggle.tap()
        }
        slots.tap()
        let cooking = app.buttons["Cooking days and open meals"]
        reveal(cooking, app: app); cooking.tap()
        let preset = app.buttons["Use two cooking days"]
        reveal(preset, app: app); preset.tap()
        let open = app.buttons["planner_open_meals_5"]
        reveal(open, app: app); open.tap()
        app.buttons["Dinner"].firstMatch.tap()
        XCTAssertTrue(open.label.contains("Dinner"))
        record(app, "Practical week - selected cooking days and restaurant evening")
        app.buttons["meal_plan_generate_plan"].tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(use.isEnabled, app.debugDescription)
        let openDinner = app.staticTexts["Left open · Dinner"]
        reveal(openDinner, app: app); XCTAssertTrue(openDinner.exists)
        record(app, "Practical week - reviewed open dinner and shared batches")
        use.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 15), app.debugDescription)
    }
    @MainActor func testRejectedWeekResumesFrozenAndFencedCancellation() {
        let flags = ["-ui-testing-planner-blank", "-ui-testing-constrained-recipes"]
        let app = launch("meal-plan-survey", flags: flags + ["-ui-testing-meal-plan-save-failure"])
        app.buttons["meal_plan_generate_plan"].tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15)); use.tap()
        XCTAssertTrue(any(app, "planner_draft_error").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planner_draft_check_status"].exists)
        app.terminate()
        _ = launch("meal-plan", flags: flags, reset: false, app: app)
        let resume = app.buttons["planner_resume_week_review"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15)); resume.tap()
        let cancel = app.buttons["planner_draft_cancel_pending"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        let finish = app.buttons["planner_draft_finish"]
        reveal(finish, app: app); finish.tap()
        XCTAssertTrue(resume.waitForNonExistence(timeout: 10))
    }
    @MainActor func testPastedRecipeIsReviewedAndInterruptedFormIsKept() {
        let flags = ["-ui-testing-recipe-draft"]
        let app = launch("recipes", flags: flags)
        let create = app.buttons["Create recipe"]
        XCTAssertTrue(create.waitForExistence(timeout: 15)); create.tap()
        let mode = app.segmentedControls["create_recipe_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10)); mode.buttons["Paste"].tap()
        let text = app.textViews["create_recipe_text_input"]
        text.tap(); text.typeText("Ingredients: 200 g beans and 100 g rice. Instructions: cook rice and mix beans.")
        app.buttons["create_recipe_action"].tap()
        XCTAssertTrue(any(app, "recipe_import_draft").waitForExistence(timeout: 15))
        let name = app.textFields["create_recipe_name"]
        reveal(name, app: app); XCTAssertEqual(name.value as? String, "Reviewed test soup")
        record(app, "Recipe draft before library save")
        app.terminate()
        _ = launch("recipes", flags: flags, reset: false, app: app)
        app.buttons["Create recipe"].tap()
        XCTAssertTrue(any(app, "recipe_import_draft").waitForExistence(timeout: 10))
        reveal(app.textFields["create_recipe_name"], app: app)
        XCTAssertEqual(app.textFields["create_recipe_name"].value as? String, "Reviewed test soup")
    }
    @MainActor func testLargestTextBriefAndWeekReviewKeepPrimaryActionReachable() {
        let app = launch("meal-plan-survey", flags: ["-ui-testing-planner-blank", "-ui-testing-constrained-recipes", "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let build = app.buttons["meal_plan_generate_plan"]
        XCTAssertTrue(build.waitForExistence(timeout: 15)); assertControl(build, app: app); record(app, "Largest text planning brief")
        build.tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15)); XCTAssertTrue(use.isEnabled); assertControl(use, app: app)
        record(app, "Largest text checked week review")
    }
    @MainActor func testNextBlockSaveLeavesPHULActiveAndUnchanged() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul"])
        let workspace = app.segmentedControls["program_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10)); workspace.buttons["Progress"].tap()
        let next = app.buttons["program_next_block"]
        reveal(next, app: app); next.tap()
        let save = app.buttons["successor_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled)
        record(app, "Reviewed separate PHUL successor")
        save.tap()
        let keep = app.buttons["successor_keep_current"]
        XCTAssertTrue(keep.waitForExistence(timeout: 15)); keep.tap()
        let summary = any(app, "program_progress_summary")
        reveal(summary, app: app); XCTAssertTrue(summary.label.contains("39 of 48"))
    }
    @MainActor private func launch(_ screen: String, flags: [String] = [], reset: Bool = true, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags + (reset ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        if !app.buttons[screen == "recipes" ? "Create recipe" : screen == "program-detail" ? "program_edit_block" : screen == "meal-plan" ? "meal_plan_tools" : "meal_plan_generate_plan"].waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        return app
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func set(_ toggle: XCUIElement, to value: String, app: XCUIApplication) {
        reveal(toggle, app: app)
        if toggle.value as? String != value {
            // A Form switch exposes the full row as its frame; its center can be the label.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed, app.debugDescription)
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, preferEarlier: Bool = false) {
        for _ in 0..<25 {
            if element.exists, element.isHittable, element.frame.minY > 85, element.frame.maxY < app.frame.maxY - 85 { return }
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            let searchEarlier = element.exists ? element.frame.minY < 85 : preferEarlier
            if searchEarlier { upper.press(forDuration: 0.08, thenDragTo: lower) } else { lower.press(forDuration: 0.08, thenDragTo: upper) }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    @MainActor private func assertControl(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.isHittable); XCTAssertTrue(app.frame.contains(element.frame)); XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }
    @MainActor private func record(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
