import XCTest

/// Uses the isolated screenshot account. Browsing must never log work or move PHUL.
@MainActor
final class TrainingDesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProgramWorkspacesPreservePHULAndExposeRestoreHistory() {
        let app = launch("train", flags: ["-ui-testing-wave2-phul"])
        let program = app.buttons["train_program_overview"]
        XCTAssertTrue(program.waitForExistence(timeout: 10)); program.tap()
        let fullProgram = app.buttons["training_full_program"]
        XCTAssertTrue(fullProgram.waitForExistence(timeout: 10))
        XCTAssertTrue(fullProgram.isHittable, "Full program appears before the upcoming-session list.")
        fullProgram.tap()
        let workspace = app.segmentedControls["program_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15))
        let summary = any(app, "program_progress_summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "39 of 48 sessions passed")
        XCTAssertTrue(workspace.buttons["Overview"].isSelected)
        record(app, "Program - focused overview with preserved PHUL position")

        workspace.buttons["Schedule"].tap()
        XCTAssertTrue(any(app, "program_schedule").waitForExistence(timeout: 5))
        let updateSchedule = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Update Schedule")).firstMatch
        for _ in 0..<6 where !updateSchedule.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        XCTAssertTrue(updateSchedule.isHittable, "Schedule editing remains reachable in its dedicated workspace.")
        XCTAssertFalse(app.buttons["program_next_block"].exists)
        workspace.buttons["Progress"].tap()
        XCTAssertTrue(any(app, "program_progress").waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "39 of 48 sessions passed")
        XCTAssertTrue(app.buttons["program_next_block"].exists)
        record(app, "Program - progress and next block have a dedicated workspace")

        workspace.buttons["Overview"].tap()
        XCTAssertEqual(summary.label, "39 of 48 sessions passed")
        XCTAssertTrue(app.staticTexts["Includes 3 explicitly skipped sessions"].exists)
        app.buttons["program_options"].tap()
        let history = app.buttons["program_migration_history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let done = app.navigationBars["Original rotations"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(summary.label, "39 of 48 sessions passed")
        XCTAssertFalse(app.buttons["workout_resume"].exists)
    }

    func testCompletedBlockOpensNextBlockDirectlyWithoutSavingOrChangingProgress() {
        let app = launch("program-detail", flags: ["-ui-testing-completed-phul"])
        let workspace = app.segmentedControls["program_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15))
        XCTAssertTrue(workspace.buttons["Overview"].isSelected)
        let progress = any(app, "program_progress_summary")
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.label, "48 of 48 sessions passed")
        let next = app.buttons["program_next_block"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "A completed block presents its next action directly on Overview.")
        for _ in 0..<6 where !next.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        XCTAssertTrue(next.isHittable); next.tap()

        let close = app.buttons["successor_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "successor_source_progress").label, "48 of 48 positions passed in the source plan")
        let save = app.buttons["successor_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, "Save new block", "Opening a proposal does not submit it.")
        XCTAssertFalse(any(app, "successor_accepted").exists)
        close.tap()

        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        XCTAssertTrue(workspace.buttons["Overview"].isSelected)
        XCTAssertEqual(progress.label, "48 of 48 sessions passed")
        workspace.buttons["Progress"].tap()
        XCTAssertEqual(progress.label, "48 of 48 sessions passed")
        XCTAssertFalse(next.exists, "The completed block's next action has one clear home.")
        workspace.buttons["Overview"].tap()
        XCTAssertEqual(progress.label, "48 of 48 sessions passed")
        for _ in 0..<6 where !next.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        next.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, "Save new block", "The dismissed proposal remains unsubmitted on reopening.")
        XCTAssertFalse(any(app, "successor_accepted").exists)
        close.tap()
        record(app, "Program - completed block opens an unsubmitted next-block review and keeps all 48 positions")
    }

    func testCurrentSetReturnsRepeatedlyWithoutLoggingAndKeepsRestDirect() {
        let app = launch("workout-player")
        let complete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        let setID = complete.identifier
        let weight = any(app, "strength_set_row_" + setID.replacingOccurrences(of: "set_complete_", with: "")).textFields.firstMatch
        let originalWeight = weight.value as? String
        XCTAssertEqual(complete.value as? String, "Not completed")
        let current = app.buttons["workout_current_set"]
        XCTAssertTrue(current.isHittable)
        XCTAssertGreaterThanOrEqual(current.frame.height, 44)
        XCTAssertTrue(app.buttons["workout_session_tools"].isHittable)
        XCTAssertTrue(app.buttons["workout_adapt_remaining"].isHittable)
        XCTAssertTrue(app.buttons["workout_plate_calculator"].isHittable)
        XCTAssertTrue(app.buttons["workout_finish"].isHittable)
        XCTAssertTrue(app.switches["workout_auto_rest"].exists)
        let routineTitle = app.staticTexts["workout_routine_title"]
        XCTAssertTrue(routineTitle.exists)
        XCTAssertEqual(routineTitle.label, "Upper A - Press & Row")
        let close = app.buttons["Close workout"]
        XCTAssertTrue(close.isHittable)
        XCTAssertLessThanOrEqual(routineTitle.frame.maxX, close.frame.minX)
        XCTAssertTrue(app.staticTexts["workout_elapsed_time"].exists)
        let viewport = app.scrollViews.firstMatch.frame
        XCTAssertTrue(weight.isHittable, "The first editable load is visible before any scrolling.")
        XCTAssertGreaterThanOrEqual(weight.frame.minY, viewport.minY)
        XCTAssertLessThanOrEqual(weight.frame.maxY, min(viewport.maxY, current.frame.minY))
        XCTAssertTrue(complete.isHittable, "The routine title must not push the first set below the controls.")
        XCTAssertLessThanOrEqual(complete.frame.maxY, current.frame.minY)
        record(app, "Workout - first set and one-row controls")

        for _ in 0..<2 {
            let scroll = app.scrollViews.firstMatch
            scroll.swipeUp(); scroll.swipeUp()
            XCTAssertTrue(current.isHittable)
            current.tap()
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: complete)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
            XCTAssertTrue(app.frame.contains(complete.frame))
            XCTAssertLessThanOrEqual(complete.frame.maxY, current.frame.minY)
            XCTAssertEqual(complete.value as? String, "Not completed")
            XCTAssertEqual(weight.value as? String, originalWeight)
        }
        XCTAssertFalse(any(app, "workout_rest_controls").exists)
        record(app, "Workout - repeated current-set return leaves logged work unchanged")
    }

    func testSetInspectorRevealsSecondaryControlsWithoutChangingUnperformedValues() {
        let app = launch("workout-player")
        let completions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' "))
        XCTAssertTrue(completions.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(completions.count, 1)
        let complete = completions.element(boundBy: 1)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let row = any(app, "strength_set_row_" + setID)
        let weight = row.textFields.firstMatch
        let reps = row.textFields.element(boundBy: 1)
        let originalWeight = weight.value as? String
        let originalReps = reps.value as? String
        XCTAssertFalse(app.staticTexts["set_previous_" + setID].exists, "Upcoming rows keep secondary comparison controls quiet.")
        let details = app.buttons["set_details_" + setID]
        reveal(details, app: app); details.tap()
        XCTAssertTrue(any(app, "set_type_" + setID).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["set_previous_" + setID].exists)
        XCTAssertEqual(weight.value as? String, originalWeight)
        XCTAssertEqual(reps.value as? String, originalReps)
        XCTAssertEqual(complete.value as? String, "Not completed")
        let collapse = app.buttons["Collapse set controls"]
        reveal(collapse, app: app); collapse.tap()
        XCTAssertTrue(details.exists)
        XCTAssertEqual(weight.value as? String, originalWeight)
        XCTAssertEqual(reps.value as? String, originalReps)
        XCTAssertEqual(complete.value as? String, "Not completed")
        record(app, "Strength - secondary controls reveal without changing set values")
    }

    func testSavedGymIsAvailableDirectlyAndSelectionDoesNotApplyToWorkout() {
        let app = launch("workout-player")
        let equipment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strength_equipment_' ")).firstMatch
        XCTAssertTrue(equipment.waitForExistence(timeout: 10))
        let originalEquipment = equipment.label
        let complete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let weight = any(app, "strength_set_row_" + setID).textFields.firstMatch
        let originalWeight = weight.value as? String
        app.buttons["workout_session_tools"].tap()
        app.buttons["session_choose_gym"].tap()
        let add = app.buttons["gym_profile_add"]
        reveal(add, app: app); add.tap()
        let name = app.textFields["gym_profile_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("QA inline gym")
        app.buttons["gym_profile_keyboard_done"].tap()
        app.buttons["gym_profile_add_implement"].tap()
        let saveEquipment = app.buttons["equipment_save"]
        XCTAssertTrue(saveEquipment.waitForExistence(timeout: 5)); XCTAssertTrue(saveEquipment.isEnabled); saveEquipment.tap()
        XCTAssertTrue(saveEquipment.waitForNonExistence(timeout: 5))
        app.buttons["gym_profile_save"].tap()
        let use = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gym_profile_use_' ")).firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 5)); use.tap()
        let cancel = app.navigationBars["Gym & session targets"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertEqual(equipment.label, originalEquipment)
        XCTAssertEqual(weight.value as? String, originalWeight)
        XCTAssertEqual(complete.value as? String, "Not completed")

        app.buttons["workout_session_tools"].tap()
        let quickGym = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session_quick_gym_' ")).firstMatch
        XCTAssertTrue(quickGym.waitForExistence(timeout: 5)); XCTAssertTrue(quickGym.isHittable)
        XCTAssertTrue(quickGym.label.contains("QA inline gym"))
        quickGym.tap()
        XCTAssertEqual(quickGym.value as? String, "Selected for review")
        XCTAssertFalse(any(app, "gym_profile_library").exists, "Selecting a saved gym no longer opens another chooser sheet.")
        XCTAssertFalse(app.buttons["session_tools_apply"].isEnabled, "A gym choice with no mapped movements must not apply an implicit conversion.")
        record(app, "Strength - saved gym opens its review directly")
        cancel.tap()
        XCTAssertEqual(equipment.label, originalEquipment)
        XCTAssertEqual(weight.value as? String, originalWeight)
        XCTAssertEqual(complete.value as? String, "Not completed")
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 0.2), element.isHittable,
               element.frame.minY >= 70, element.frame.maxY <= app.frame.maxY - 95 { return }
            let scroll = app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
                ?? app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
            if element.exists, element.frame.minY < 70 { scroll?.swipeDown() } else { scroll?.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func launch(_ screen: String, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen,
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-reset-editor-drafts"] + flags
        app.launch()
        let identifier = screen == "program-detail" ? "program_workspace"
            : screen == "train" ? "train_screen_header" : "workout_player"
        if !any(app, identifier).waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(any(app, identifier).waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
