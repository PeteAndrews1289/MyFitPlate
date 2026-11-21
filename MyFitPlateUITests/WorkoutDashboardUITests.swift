import XCTest

final class WorkoutDashboardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "train",
            "-ui-testing-reset-workout-draft",
            "-ui-testing-reset-editor-drafts"
        ]
        app.launch()
        if !app.staticTexts["train_screen_header"].firstMatch.waitForExistence(timeout: 15),
           app.buttons["welcome_get_started"].exists {
            app.terminate()
            app.launch()
        }
    }

    @MainActor
    func testWorkoutDashboardNavigationAndButtons() throws {
        let trainHeader = app.staticTexts["train_screen_header"].firstMatch
        XCTAssertTrue(trainHeader.waitForExistence(timeout: 10), "Train should open directly for deterministic dashboard coverage")

        XCTAssertTrue(app.descendants(matching: .any)["train_next_step"].waitForExistence(timeout: 5))
        attach("Train - compact home")
        XCTAssertFalse(app.descendants(matching: .any)["train_program_week"].exists, "Schedule detail belongs on the program page")
        XCTAssertFalse(app.descendants(matching: .any)["train_readiness"].exists, "Fuel and recovery belong on their focused page")
        let program = app.buttons["train_program_overview"]
        reveal(program); program.tap()
        XCTAssertTrue(app.descendants(matching: .any)["train_program_overview_screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["train_program_week"].exists)
        let fullProgram = app.buttons["training_full_program"]
        reveal(fullProgram); fullProgram.tap()
        XCTAssertTrue(app.buttons["program_edit_block"].waitForExistence(timeout: 10))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let explore = app.buttons["train_explore_plans"]
        reveal(explore); explore.tap()
        let prebuilt = app.buttons["prebuilt_programs_button"]
        XCTAssertTrue(prebuilt.waitForExistence(timeout: 10), app.debugDescription)
        prebuilt.tap()
        XCTAssertTrue(app.navigationBars["Pre-built Programs"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        app.buttons["ai_workout_generator_button"].tap()
        XCTAssertTrue(app.buttons["ai_program_generate"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(prebuilt.waitForExistence(timeout: 5), app.debugDescription)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let preparation = app.buttons["train_preparation"]
        reveal(preparation); preparation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["train_preparation_screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["train_readiness"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["muscle_recovery_map"].exists)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["running_history_button"].exists)
        attach("Train - focused next session and secondary destinations")
    }

    @MainActor
    func testFailedProgramLoadShowsRecoveryInsteadOfFreshStart() {
        app.terminate()
        app.launchArguments = [
            "-ui-testing", "-screenshot-mode", "-screenshot-screen", "train",
            "-ui-testing-reset-workout-draft", "-ui-testing-workout-load-failure"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your saved programs couldn’t load"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Training Hub"].exists)
        let retry = app.buttons["Retry"].firstMatch
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Your saved programs couldn’t load"].exists)
        XCTAssertFalse(app.staticTexts["Training Hub"].exists)
        attach("Workout library - recoverable load failure")
    }

    @MainActor
    func testProgramSaveFailureKeepsEditsAndAllowsRetry() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-builder",
                               "-ui-testing-workout-save-failure", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let save = app.buttons["program_builder_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        let name = app.textFields["program_builder_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Dumbbell Strength QA\n")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let feedback = app.staticTexts["program_builder_feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(feedback.label.contains("This exact proposal is kept"), feedback.label)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.buttons["Check save status"].exists)
        for _ in 0..<6 where !name.exists { app.swipeDown() }
        XCTAssertEqual(name.value as? String, "Dumbbell Strength QA")
        attach("Program save - recoverable failure")
    }

    @MainActor
    func testCancelingNewRoutineDoesNotAddEmptyWorkoutToPlan() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-builder"]
        app.launch()
        let add = app.buttons["Add routine"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add)
        add.tap()
        let close = app.buttons["routine_builder_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["routine_builder_save"].isEnabled)
        close.tap()
        XCTAssertTrue(app.buttons["program_builder_save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["program_builder_save"].isEnabled)
        XCTAssertFalse(app.staticTexts["Untitled Routine"].exists)
    }

    @MainActor
    func testWorkoutRestoresCompletedSetAfterTermination() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft"]
        app.launch()
        let complete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete '")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        // Completing changes the label to "Reopen …"; retain the set's identity
        // so the live firstMatch query cannot move to the next incomplete set.
        let setIdentifier = complete.identifier
        XCTAssertTrue(setIdentifier.hasPrefix("set_complete_"))
        let selectedSet = app.buttons[setIdentifier]
        reveal(selectedSet)
        selectedSet.tap()
        let completed = NSPredicate(format: "value == %@", "Completed")
        expectation(for: completed, evaluatedWith: selectedSet)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(app.staticTexts["workout_resumed"].waitForExistence(timeout: 5))
        let restored = app.buttons[setIdentifier]
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        reveal(restored)
        expectation(for: completed, evaluatedWith: restored)
        waitForExpectations(timeout: 5)
        attach("Workout - restored completed set")
        app.buttons["Close workout"].tap()
        app.buttons["Discard Workout"].tap()
    }

    @MainActor
    func testCompletedWorkoutShowsSummaryAndClearsRecoveryDraft() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft"]
        app.launch()
        let complete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete '")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        reveal(complete)
        complete.tap()
        app.buttons["Finish Workout"].tap()
        app.buttons["Finish Anyway"].tap()
        let done = app.buttons["workout_summary_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(done.isHittable)
        let volume = app.descendants(matching: .any)["workout_summary_volume"].firstMatch
        let duration = app.descendants(matching: .any)["workout_summary_duration"].firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        XCTAssertTrue(duration.exists)
        XCTAssertTrue(app.frame.contains(volume.frame))
        XCTAssertTrue(app.frame.contains(duration.frame))
        XCTAssertEqual(volume.frame.minY, duration.frame.minY, accuracy: 1, "The summary's main metrics share one reading line.")
        XCTAssertLessThanOrEqual(volume.frame.maxY, done.frame.minY)
        XCTAssertLessThanOrEqual(duration.frame.maxY, done.frame.minY)
        let edit = app.buttons.matching(identifier: "workout_summary_edit")
        XCTAssertEqual(edit.count, 1, "Editing has one consistent destination in the summary header.")
        XCTAssertTrue(edit.firstMatch.isHittable)
        attach("Workout - completion accepted")
        done.tap()
        XCTAssertTrue(app.staticTexts["train_screen_header"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout_resume"].exists)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        XCTAssertTrue(app.staticTexts["train_screen_header"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["workout_resume"].exists, "Completed sessions must not return as unfinished drafts")
    }

    @MainActor
    func testWorkoutSaveFailureKeepsSessionForRetry() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-workout-save-failure"]
        app.launch()
        let complete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Complete '")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        reveal(complete)
        complete.tap()
        app.buttons["Finish Workout"].tap()
        app.buttons["Finish Anyway"].tap()
        let retry = app.buttons["Retry saving"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close workout"].exists)
        app.buttons["Close workout"].tap()
        XCTAssertFalse(app.buttons["Discard Workout"].exists, "Partially saved completion must be finished, not silently dropped")
        app.buttons["Save & Leave"].tap()
        XCTAssertTrue(app.buttons["workout_resume"].waitForExistence(timeout: 5))
        attach("Workout - failed save retained for retry")
    }

    @MainActor
    func testProgramBuilderActionsFitLargestText() {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-builder",
                               "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let save = app.buttons["program_builder_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxX, app.frame.maxX)
        let weekdays = app.buttons["Monday"]
        reveal(weekdays)
        XCTAssertGreaterThanOrEqual(weekdays.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(weekdays.frame.maxX, app.frame.maxX)
        attach("Program builder - largest text schedule")
    }

    @MainActor
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<18 {
            let top: CGFloat = 90
            let bottom = app.frame.maxY - 110
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let goesDown = element.exists && element.frame.minY < top
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 28, dy: (top + bottom) / 2))
            let distance = min(160, (bottom - top) * 0.4)
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: goesDown ? distance : -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
