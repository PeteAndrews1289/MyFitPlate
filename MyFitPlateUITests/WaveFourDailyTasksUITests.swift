import XCTest

/// Action counts describe named tasks, not elapsed XCTest time or rendering latency.
/// All accepted saves below belong to the disposable screenshot account.
@MainActor
final class WaveFourDailyTasksUITests: XCTestCase {
    private var taps = 0
    private var scrolls = 0

    override func setUpWithError() throws { continueAfterFailure = false }

    func testFinishingCurrentPHULSessionOpensNextSlotAndKeepsPreviousSessionReviewable() {
        let app = launch("train", reset: true, extra: ["-ui-testing-wave2-phul"])
        XCTAssertTrue(app.staticTexts["Session 40 of 48"].waitForExistence(timeout: 10))
        app.buttons["Start workout"].tap()
        let complete = app.buttons["set_complete_wave2-set-3-0-0"]
        reveal(complete, app: app)
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        app.buttons["Finish Workout"].tap()
        app.buttons["Finish Anyway"].tap()
        let done = app.buttons["workout_summary_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let next = app.staticTexts["workout_summary_program_status"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertTrue(next.label.contains("Upper Power"))
        done.tap()
        XCTAssertTrue(app.staticTexts["Session 41 of 48"].waitForExistence(timeout: 10), "Finishing session 40 should put Train on session 41.")
        XCTAssertTrue(app.buttons["Start workout"].isHittable)
        app.buttons["Previous session"].tap()
        let review = app.buttons["Review Session"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), "The recorded session should open from its original PHUL slot.")
        review.tap()
        XCTAssertTrue(app.buttons["workout_summary_edit"].waitForExistence(timeout: 8))
    }

    func testStandaloneFromTrainRecordsItsSetWithoutAdvancingActivePHUL() throws {
        let flags = ["-ui-testing-wave2-phul"]
        let app = launch("train", reset: true, extra: flags)
        XCTAssertTrue(app.staticTexts["Session 40 of 48"].waitForExistence(timeout: 10))
        let saved = app.buttons["train_saved_routines"]
        reveal(saved, app: app); saved.tap()
        let start = app.buttons["Start Lower Hypertrophy"]
        reveal(start, app: app); start.tap()
        let origin = app.staticTexts["workout_session_origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        XCTAssertEqual(origin.label, "Standalone workout")
        let complete = app.buttons["set_complete_wave2-set-3-0-0"]
        reveal(complete, app: app); complete.tap()
        app.buttons["Finish Workout"].tap(); app.buttons["Finish Anyway"].tap()
        let done = app.buttons["workout_summary_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["workout_summary_program_status"].label.contains("Standalone workout"))
        let sets = app.descendants(matching: .any)["workout_summary_breakdown"].firstMatch
        XCTAssertTrue(sets.waitForExistence(timeout: 5))
        XCTAssertLessThan(sets.frame.minY, done.frame.minY)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '×'")).firstMatch.exists)
        try record("Standalone - saved set before recovery", app: app)
        done.tap()
        if !saved.isHittable, app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["Session 40 of 48"].waitForExistence(timeout: 8))
        app.terminate(); app.launchArguments = arguments("train", reset: false, extra: flags); app.launch()
        XCTAssertTrue(app.staticTexts["Session 40 of 48"].waitForExistence(timeout: 10))
    }

    func testSwapFromExerciseNameKeepsLoggedSetRecoversAndUndoes() {
        let fixture = ["-ui-testing-wave2-phul"]
        let app = launch("train", reset: true, extra: fixture)
        app.buttons["Start workout"].tap()
        let first = app.buttons["set_complete_wave2-set-3-0-0"]
        let second = app.buttons["set_complete_wave2-set-3-0-1"]
        reveal(first, app: app)
        first.tap()
        XCTAssertEqual(first.value as? String, "Completed")

        let dropdown = app.buttons["exercise_swap_wave2-exercise-3-0"]
        reveal(dropdown, app: app)
        dropdown.tap()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout_swap_choice_'")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        let opened = XCTAttachment(screenshot: app.screenshot())
        opened.name = "PHUL exercise replacement dropdown"
        opened.lifetime = .keepAlways
        add(opened)
        let replacement = choice.label
        choice.tap()
        let replacementDropdown = app.buttons.matching(NSPredicate(format: "label == %@", "Swap " + replacement)).firstMatch
        reveal(replacementDropdown, app: app)
        XCTAssertTrue(replacementDropdown.exists)
        XCTAssertFalse(second.exists)

        app.terminate()
        app.launchArguments = arguments("train", reset: false, extra: fixture)
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        resume.tap()
        reveal(first, app: app)
        XCTAssertEqual(first.value as? String, "Completed")
        XCTAssertTrue(replacementDropdown.exists)
        let undo = app.buttons["Undo swap"]
        reveal(undo, app: app)
        undo.tap()
        reveal(second, app: app)
        XCTAssertEqual(second.value as? String, "Not completed")
        XCTAssertEqual(first.value as? String, "Completed")
        XCTAssertFalse(undo.exists)

        reveal(dropdown, app: app)
        dropdown.tap()
        let browse = app.buttons["workout_swap_browse"]
        reveal(browse, app: app)
        browse.tap()
        XCTAssertTrue(app.navigationBars["Choose replacement"].waitForExistence(timeout: 5))
        app.buttons["Close exercise library"].tap()
        XCTAssertEqual(first.value as? String, "Completed")
        XCTAssertFalse(undo.exists)
    }

    func testVisibleUsualFoodSavesInOneActionAndPortionReviewOpensDirectly() throws {
        let app = launch("food-search", reset: true)
        let destination = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(destination.waitForExistence(timeout: 15))
        let originalDestination = destination.label
        let addFood = app.buttons["repeat_food_add_0"]
        reveal(addFood, app: app)
        resetCount()
        tap(addFood)
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        XCTAssertEqual(destination.label, originalDestination)
        XCTAssertFalse(app.buttons["food_search_review_meal"].exists)
        XCTAssertEqual(taps, 1)
        try record("Visible usual food → accepted save", app: app)

        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
        let review = app.buttons["repeat_food_review_0"]
        reveal(review, app: app)
        resetCount()
        tap(review)
        let serving = any(app, "food_detail_serving_controls")
        reveal(serving, app: app)
        XCTAssertTrue(serving.exists)
        XCTAssertTrue(app.buttons["food_detail_cancel"].isHittable)
        XCTAssertEqual(taps, 1)
        try record("Visible usual food → portion editor", app: app)
        app.buttons["food_detail_cancel"].tap()
        XCTAssertEqual(destination.label, originalDestination)
        XCTAssertFalse(undo.exists)
    }

    func testThreeUsualFoodsLogFromSelectionInFiveTapsAndUndo() throws {
        let app = launch("food-search", reset: true)
        let mode = app.buttons["food_search_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        let destination = app.buttons["food_search_meal_menu"].label
        resetCount()
        tap(mode)
        for index in 0..<3 { tap(app.buttons["repeat_food_add_\(index)"]) }
        let save = app.buttons["food_search_log_selected"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.label, "Log 3 foods")
        tap(save)
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        XCTAssertEqual(taps, 5)
        XCTAssertFalse(save.exists)
        XCTAssertEqual(app.buttons["food_search_meal_menu"].label, destination)
        try record("Three foods logged in five taps", app: app)
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
    }

    func testPhotoAndUsualFoodsStaySelectedUntilOneMealIsLogged() {
        let app = launch("food-search", reset: true, extra: ["-ui-testing-selected-meal-photo"])
        app.buttons["food_search_mode"].tap()
        app.buttons["repeat_food_add_0"].tap()
        app.buttons["food_search_action_camera"].tap()
        let select = app.buttons["ai_summary_log_action"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertEqual(select.label, "Select 2 foods")
        select.tap()
        let tray = app.buttons["food_search_review_meal"]
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        XCTAssertTrue(tray.label.contains("3 foods"))
        XCTAssertFalse(app.buttons["food_search_undo"].exists)
        app.terminate()
        app.launchArguments = arguments("food-search", reset: false)
        app.launch()
        XCTAssertTrue(tray.waitForExistence(timeout: 15))
        XCTAssertTrue(tray.label.contains("3 foods"))
        let save = app.buttons["food_search_log_selected"]
        if save.exists { save.tap() } else { tray.tap(); app.buttons["meal_draft_log"].tap() }
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
    }

    func testPortionPresetsAndMassUnitsPreserveTheReviewedAmount() throws {
        let app = launch("food-search", reset: true)
        // Undo restores the diary. Remembered portions are a separate preference.
        app.buttons["food_search_more_actions"].tap()
        app.buttons["Food preferences"].tap()
        app.buttons["Reset remembered servings"].tap()
        app.buttons["repeat_food_review_0"].tap()
        let total = app.staticTexts["food_detail_portion_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 8))
        let starting = total.label
        let amount = app.textFields["Quantity"]
        let originalAmount = try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String)))
        app.buttons["food_portion_half"].tap()
        XCTAssertNotEqual(total.label, starting)
        XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String))), originalAmount / 2, accuracy: 0.00001)
        app.buttons["food_portion_original"].tap()
        XCTAssertEqual(total.label, starting)
        let gramButton = app.buttons["food_portion_g"]
        let ounceButton = app.buttons["food_portion_oz"]
        XCTAssertTrue(gramButton.isHittable)
        gramButton.tap()
        let grams = try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String)))
        ounceButton.tap()
        let ounces = try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String)))
        XCTAssertEqual(grams, ounces * 28.349523125, accuracy: 0.001)
        XCTAssertEqual(total.label, starting)
        app.buttons["food_portion_double"].tap()
        XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String))), ounces * 2, accuracy: 0.001)
        app.buttons["food_portion_original"].tap()
        let increase = app.buttons["food_portion_increase"]
        let decrease = app.buttons["food_portion_decrease"]
        increase.tap(); decrease.tap()
        XCTAssertEqual(total.label, starting)
        try record("Reviewed portion with equivalent units", app: app)
        resetCount()
        tap(gramButton)
        tap(increase)
        XCTAssertEqual(try XCTUnwrap(Double(try XCTUnwrap(amount.value as? String))), grams + 5, accuracy: 0.001)
        XCTAssertNotEqual(total.label, starting)
        let log = app.buttons["food_detail_log_action"]
        XCTAssertEqual(log.label, "Log to Dinner")
        tap(log)
        XCTAssertEqual(taps, 3)
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["food_search_field"].isHittable)
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
    }

    func testCustomPortionCanBeTypedAndLoggedWithTheKeyboardOpen() {
        let app = launch("food-search", reset: true)
        app.buttons["repeat_food_review_0"].tap()
        let amount = app.textFields["Quantity"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        amount.replaceContents(with: "0", in: app)
        let log = app.buttons["food_detail_log_action"]
        XCTAssertTrue(log.wait(for: \.isEnabled, toEqual: false, timeout: 5))
        amount.replaceContents(with: "3.75", in: app)
        XCTAssertEqual(amount.value as? String, "3.75")
        XCTAssertTrue(log.isHittable)
        log.tap()
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
    }

    func testThreeItemMealHasOneReviewAndOneAcceptedSave() throws {
        let app = launch("food-search", reset: true)
        let mode = app.buttons["food_search_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        let destination = app.buttons["food_search_meal_menu"].label
        resetCount()
        tap(mode)
        for index in 0..<3 {
            let addFood = app.buttons["repeat_food_add_\(index)"]
            reveal(addFood, app: app)
            tap(addFood)
            XCTAssertFalse(app.buttons["meal_draft_log"].exists)
        }
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.label.contains("3 foods"))
        tap(review)
        let total = app.staticTexts["meal_draft_total"]
        reveal(total, app: app)
        XCTAssertTrue(total.label.hasPrefix("3 foods"))
        let save = app.buttons["meal_draft_log"]
        reveal(save, app: app)
        tap(save)
        XCTAssertTrue(app.buttons["food_search_undo"].waitForExistence(timeout: 8))
        XCTAssertFalse(review.exists)
        XCTAssertEqual(app.buttons["food_search_meal_menu"].label, destination)
        XCTAssertEqual(taps, 6, "Build meal, three selections, Review, Log; scrolling is counted separately.")
        try record("Log food → three usual foods accepted together", app: app)
    }

    func testStartPrefilledSetRestAndResumeKeepDirectActions() throws {
        let app = launch("train", reset: true, extra: ["-ui-testing-auto-rest"])
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        resetCount()
        reveal(start, app: app)
        tap(start)
        let player = any(app, "workout_player")
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(taps, 2)
        try record("Train → start the identified next workout", app: app)

        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        let firstID = first.identifier
        let setID = String(firstID.dropFirst("set_complete_".count))
        let load = any(app, "strength_set_row_\(setID)").textFields["set_weight_1"].firstMatch
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '32'"), object: load)
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 10), .completed, "The last goblet squat in the test history was 32 lb.")
        reveal(first, app: app)
        resetCount()
        tap(first)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Completed'"), object: app.buttons[firstID])
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)
        XCTAssertTrue(any(app, "workout_rest_timer").waitForExistence(timeout: 5))
        XCTAssertEqual(taps, 1)
        try record("Visible prefilled set → complete", app: app)

        resetCount()
        tap(app.buttons["workout_rest_add"])
        XCTAssertTrue(any(app, "workout_rest_timer").exists)
        XCTAssertEqual(taps, 1)
        try record("Active rest → add 30 seconds", app: app)
        resetCount()
        tap(app.buttons["workout_rest_skip"])
        XCTAssertTrue(any(app, "workout_rest_timer").waitForNonExistence(timeout: 5))
        XCTAssertEqual(taps, 1)
        try record("Active rest → Skip", app: app)

        app.terminate()
        app.launchArguments = arguments("train", reset: false, extra: ["-ui-testing-auto-rest"])
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        resetCount()
        reveal(resume, app: app)
        tap(resume)
        XCTAssertTrue(player.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons[firstID].value as? String, "Completed")
        XCTAssertFalse(any(app, "workout_rest_timer").exists)
        XCTAssertEqual(taps, 1)
        try record("Train → resume the saved workout", app: app)
    }

    func testTechniqueStepsOpenOfflineAndReturnWithoutChangingTheSet() throws {
        let app = launch("workout-player", reset: true)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let firstID = first.identifier
        let weight = app.textFields["set_weight_1"].firstMatch.value as? String
        let reps = app.textFields["set_reps_1"].firstMatch.value as? String
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise_options_' ")).firstMatch
        reveal(options, app: app); options.tap()
        let information = app.buttons["History & technique"]
        XCTAssertTrue(information.waitForExistence(timeout: 5))
        XCTAssertTrue(information.wait(for: \.isHittable, toEqual: true, timeout: 5))
        information.tap()
        let section = app.segmentedControls["exercise_information_section"]
        XCTAssertTrue(section.waitForExistence(timeout: 8))
        section.buttons["Technique"].tap()
        let cue = any(app, "exercise_technique_cue")
        XCTAssertTrue(cue.waitForExistence(timeout: 8))
        let firstViewport = XCTAttachment(screenshot: app.screenshot())
        firstViewport.name = "Technique - quick cue and setup"
        firstViewport.lifetime = .keepAlways; add(firstViewport)
        let setup = any(app, "exercise_technique_setup_1")
        reveal(setup, app: app)
        XCTAssertTrue(setup.exists)
        XCTAssertFalse(setup.label.isEmpty)
        let execution = any(app, "exercise_technique_execution_1")
        reveal(execution, app: app)
        XCTAssertTrue(execution.exists)
        let corrections = any(app, "exercise_technique_corrections")
        reveal(corrections, app: app); corrections.tap()
        let correction = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "One weight racing ahead")).firstMatch
        for _ in 0..<5 where !correction.exists { app.swipeUp() }
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        let reference = any(app, "exercise_technique_reference")
        for _ in 0..<8 {
            if reference.exists && reference.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reference.exists && reference.isHittable)
        XCTAssertTrue(reference.label.contains("ACE"), "The online source should be identified before opening it.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Technique - offline steps and corrections"
        screenshot.lifetime = .keepAlways; add(screenshot)
        let done = app.buttons["exercise_information_done"]
        XCTAssertTrue(done.isHittable)
        resetCount(); tap(done)
        XCTAssertTrue(section.waitForNonExistence(timeout: 5))
        reveal(app.buttons[firstID], app: app)
        XCTAssertEqual(app.buttons[firstID].value as? String, "Not completed")
        XCTAssertEqual(app.textFields["set_weight_1"].firstMatch.value as? String, weight)
        XCTAssertEqual(app.textFields["set_reps_1"].firstMatch.value as? String, reps)
        XCTAssertEqual(taps, 1)
        try record("Technique sheet → unchanged workout", app: app)
    }

    private func arguments(_ route: String, reset: Bool, extra: [String] = []) -> [String] {
        ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route,
         "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        + (reset ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"] : [])
        + extra
    }

    private func launch(_ route: String, reset: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(route, reset: reset, extra: extra)
        app.launch()
        let expected: XCUIElement
        switch route {
        case "train": expected = app.buttons["Start workout"]
        case "food-search": expected = app.buttons["food_search_mode"]
        default: expected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        }
        if !expected.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func resetCount() { taps = 0; scrolls = 0 }
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.isHittable)
        element.tap(); taps += 1
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<14 {
            let frame = element.exists ? element.frame : .zero
            // A sheet's pinned Save already occupies its own safe area. Do not scroll
            // the content fourteen times trying to move that fixed control upward.
            let pinned = element.exists && ["meal_draft_log", "food_search_review_meal"].contains(element.identifier)
            if pinned, element.isHittable { return }
            if element.exists, element.isHittable, frame.minY >= 105, frame.maxY < app.frame.maxY - 90 { return }
            let earlier = element.exists && frame.midY < app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: earlier ? 0.32 : 0.70))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: earlier ? 0.63 : 0.42)))
            scrolls += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func record(_ task: String, app: XCUIApplication) throws {
        let process = ProcessInfo.processInfo
        let device = process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS device"
        let os = process.operatingSystemVersion
        let value: [String: Any] = ["task": task, "deliberate_taps": taps, "scroll_gestures": scrolls,
            "text_entries": 0, "profile": "\(device) iOS \(os.majorVersion).\(os.minorVersion), standard text, seeded disposable account",
            "scope": "Observed UI task count; excludes launch/setup. Not a latency measurement."]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("WAVE4_TASK_COUNT \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.name = task; attachment.lifetime = .keepAlways; add(attachment)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = task; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
