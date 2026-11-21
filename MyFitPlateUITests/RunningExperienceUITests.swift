import XCTest

final class RunningExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testImportedNotePersistsAcrossRelaunchWithoutChangingOriginalTotals() {
        let app = launch()
        let rowID = "run_history_row_demo-run-10k"
        let row = app.buttons[rowID]
        reveal(row, in: app)
        XCTAssertTrue(row.label.contains("6.21 mi"), row.label)
        XCTAssertTrue(row.label.contains("49:08 active"), row.label)
        row.tap()
        app.buttons["run_detail_options"].tap()
        app.buttons["Add or edit personal note"].firstMatch.tap()
        let note = "UI note " + String(UUID().uuidString.prefix(8)) + " steady effort"
        let field = app.descendants(matching: .any)["run_import_note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replace(field, with: note, in: app)
        open(app.buttons["run_import_note_save"], in: app)
        XCTAssertEqual(app.buttons["run_import_note_save"].label, "Save reviewed note")
        app.buttons["run_import_note_save"].tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let restoredRow = app.buttons[rowID]
        open(restoredRow, in: app)
        let saved = app.staticTexts[note]
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists)
        let active = timingElement("active", in: app)
        reveal(active, in: app)
        XCTAssertEqual(active.label, "Active time, 49:08")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Distance, 6.21 mi")).firstMatch.exists,
                      "A note must not change imported distance")
        attach(app, "Running - imported note survives relaunch with original measurements")
    }

    @MainActor
    func testExactSecondGoalCanBeFavoritedAndReopenedWithoutStartingRecording() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        let exactGoalRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'run_plan_' AND label CONTAINS %@", "23:45 run"))
        let existingGoalIDs = Set(exactGoalRows.allElementsBoundByIndex.map(\.identifier))
        open(app.buttons["run_create_goal"], in: app)
        replace(app.textFields["run_goal_value"], with: "23:45", in: app)
        finishGoalEditing(app)
        app.buttons["run_goal_review"].tap()
        XCTAssertTrue(app.staticTexts["run_plan_summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["run_plan_summary"].label.contains("23:45 timed"))
        let favorite = app.buttons["run_plan_favorite"]
        reveal(favorite, in: app)
        favorite.tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "Remove favorite")
        closeSheet(containing: "run_plan_summary", type: .staticText, in: app)
        let createdRows = exactGoalRows.allElementsBoundByIndex.filter { !existingGoalIDs.contains($0.identifier) }
        XCTAssertEqual(createdRows.count, 1, "Only the newly created exact goal may be reopened or removed")
        guard let saved = createdRows.first else { return }
        reveal(saved, in: app)
        let id = saved.identifier
        saved.tap()
        XCTAssertTrue(app.staticTexts["Run for 23:45"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["run_plan_favorite"].label, "Remove favorite")
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        attach(app, "Running - exact goal favorite retained for next time")
        closeSheet(containing: "run_plan_summary", type: .staticText, in: app)
        let row = app.buttons[id]
        reveal(row, in: app)
        row.press(forDuration: 1)
        app.collectionViews.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete workout"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testPauseReviewPreservesRecoveryGapAndDoesNotApplyWithoutReason() {
        let app = launch(arguments: ["-ui-testing-run-timing-fixtures"])
        let recorded = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "3.11 mi", "20:00 active")).firstMatch
        open(recorded, in: app)
        app.buttons["run_detail_options"].tap()
        app.buttons["Review pause times"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recovery gap · preserved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Explicit pause"].exists)
        XCTAssertFalse(app.buttons["run_pause_correction_save"].isEnabled)
        XCTAssertEqual(app.buttons.matching(identifier: "Remove this pause").count, 1, "Recovery gaps must have no removal control")
        attach(app, "Running - explicit pauses review retains recovery evidence")
        closeSheet(containing: "run_pause_correction_save", type: .button, in: app)
        XCTAssertEqual(timingElement("active", in: app).label, "Active time, 20:00")
    }

    @MainActor
    func testQuickTimeGoalReviewsOneStepBeforeRecorderReady() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_create_goal"], in: app)
        app.buttons["run_goal_preset_20"].tap()
        XCTAssertEqual(app.textFields["run_goal_value"].value as? String, "20")
        app.buttons["run_goal_review"].tap()
        let summary = app.staticTexts["run_plan_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 step"), summary.label)
        XCTAssertTrue(summary.label.contains("20:00 timed"), summary.label)
        XCTAssertTrue(app.staticTexts["Run for 20:00"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        app.buttons["run_plan_start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["run_recorder_ready"].waitForExistence(timeout: 8))
        let readyPlan = app.staticTexts["run_ready_plan_name"]
        XCTAssertTrue(readyPlan.waitForExistence(timeout: 5))
        XCTAssertEqual(readyPlan.label, "20 min run", "The reviewed goal must reach the recorder unchanged")
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        attach(app, "Running - reviewed time goal waits for deliberate start")
        app.buttons["run_recorder_close"].tap()
    }

    @MainActor
    func testPausedGoalEditorOpensAndCancelKeepsOriginalGoalThroughRecovery() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_create_goal"], in: app)
        app.buttons["run_goal_preset_20"].tap()
        app.buttons["run_goal_review"].tap()
        XCTAssertTrue(app.buttons["run_plan_start"].waitForExistence(timeout: 5))
        app.buttons["run_plan_start"].tap()
        XCTAssertTrue(app.buttons["run_recorder_start"].waitForExistence(timeout: 8))
        app.buttons["run_recorder_start"].tap()
        let pause = app.buttons["run_pause_resume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.tap()
        let elapsed = app.staticTexts["run_elapsed"]
        let distance = app.staticTexts["run_distance"]
        let pausedTime = elapsed.label
        let pausedDistance = distance.label
        let remaining = app.staticTexts["run_step_remaining"].label

        // Regression: this action lives on the paused screen, not on the final summary.
        open(app.buttons["run_goal_change"], in: app)
        let apply = app.buttons["run_goal_revision_apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5), "Paused goal review must present before a run is finished")
        let minutes = app.textFields["Minutes"]
        XCTAssertEqual(minutes.value as? String, "20")
        replace(minutes, with: "35", in: app)
        XCTAssertTrue(apply.isEnabled)
        closeSheet(containing: "run_goal_revision_apply", type: .button, in: app)
        XCTAssertTrue(pause.label.contains("Resume"), "Cancel must leave the original run paused")
        XCTAssertEqual(elapsed.label, pausedTime)
        XCTAssertEqual(distance.label, pausedDistance)
        XCTAssertEqual(app.staticTexts["run_step_remaining"].label, remaining)

        // Cancelling an unsaved edit must not change the recoverable workout prescription.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs"]
        app.launch()
        let resume = app.buttons["run_history_start"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); XCTAssertEqual(resume.label, "Resume run")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 8)); XCTAssertTrue(pause.label.contains("Resume"))
        XCTAssertEqual(elapsed.label, pausedTime)
        XCTAssertEqual(distance.label, pausedDistance)
        open(app.buttons["run_goal_change"], in: app)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertEqual(minutes.value as? String, "20", "The cancelled 35-minute proposal must never enter the saved recording")
        XCTAssertFalse(apply.isEnabled)
        attach(app, "Running - cancelled paused goal edit keeps original recording after recovery")
        closeSheet(containing: "run_goal_revision_apply", type: .button, in: app)
    }

    @MainActor
    func testQuickDistanceGoalRejectsZeroAndPreservesCustomMiles() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_create_goal"], in: app)
        app.segmentedControls["run_goal_kind"].buttons["Distance"].tap()
        let distance = app.textFields["run_goal_value"]
        replace(distance, with: "0", in: app)
        finishGoalEditing(app)
        XCTAssertFalse(app.buttons["run_goal_review"].isEnabled)
        replace(distance, with: "3.11", in: app)
        finishGoalEditing(app)
        XCTAssertEqual(distance.value as? String, "3.11")
        XCTAssertTrue(app.staticTexts["run_goal_validation"].label.contains("Only measured GPS distance counts"))
        app.buttons["run_goal_review"].tap()
        let summary = app.staticTexts["run_plan_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("3.11 mi distance blocks"), summary.label)
        XCTAssertFalse(summary.label.contains("timed"), "A distance goal must not invent an estimated finish time")
        XCTAssertTrue(app.staticTexts["Run 3.11 mi"].exists)
        attach(app, "Running - precise distance goal and honest measurement")
        app.buttons["run_plan_start"].tap()
        XCTAssertTrue(app.staticTexts["run_ready_plan_name"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["run_ready_plan_name"].label, "3.11 mi run")
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        app.buttons["run_recorder_close"].tap()
    }

    @MainActor
    func testPacingReviewUsesEqualDistanceHalvesAndExcludesFastPartialTailFromBest() {
        let app = launch(arguments: ["-ui-testing-run-pacing-fixtures"])
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "1.55 mi", "12:00 active")).firstMatch
        open(run, in: app)
        let finish = app.staticTexts["run_pacing_finish"]
        reveal(finish, in: app)
        XCTAssertEqual(finish.label, "Second half was 3:13 /mi faster.")
        let fastest = app.staticTexts["run_pacing_fastest"]
        XCTAssertEqual(fastest.label, "Fastest full split: 2", "The fast 500 m tail must not win against full kilometer splits")
        XCTAssertTrue(app.staticTexts["run_pacing_note"].label.contains("including a partial final split"))
        XCTAssertFalse(app.buttons["Pace Heatmap"].exists)
        XCTAssertFalse(app.buttons["run_detail_recovery_action"].exists, "An old run must not trigger a fresh 45-minute meal prompt")
        attach(app, "Running - distance-weighted pacing and full split comparison")
    }

    @MainActor
    func testManualTreadmillEstimatesDoNotProduceMeasuredPacingAchievements() {
        let app = launch(arguments: ["-ui-testing-run-pacing-fixtures"])
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "1.86 mi", "13:00 active")).firstMatch
        open(run, in: app)
        let timing = timingElement("active", in: app)
        reveal(timing, in: app)
        XCTAssertEqual(timing.label, "Active time, 13:00")
        XCTAssertFalse(app.descendants(matching: .any)["run_detail_pacing"].exists)
        XCTAssertFalse(app.buttons["run_detail_recovery_action"].exists)
        attach(app, "Running - manual split estimates remain estimates")
    }

    @MainActor
    func testGuidedWorkoutCanBeReviewedBeforeEnteringRecorderReadyState() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_plan_5x400m"], in: app)
        let summary = app.staticTexts["run_plan_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("21:00 timed"), summary.label)
        XCTAssertTrue(summary.label.contains("distance blocks"), summary.label)
        XCTAssertTrue(app.staticTexts["Fast but controlled"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_ready"].exists)
        app.buttons["run_plan_start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["run_recorder_ready"].waitForExistence(timeout: 8))
        let readyPlan = app.staticTexts["run_ready_plan_name"]
        XCTAssertTrue(readyPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(readyPlan.label.contains("400"), readyPlan.label)
        XCTAssertTrue(app.staticTexts["11 workout steps"].exists)
        XCTAssertTrue(app.buttons["run_recorder_start"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        attach(app, "Running - reviewed workout ready without recording")
        app.buttons["run_recorder_close"].tap()
    }

    @MainActor
    func testTreadmillPreviewRetainsExactDistanceAndSecondsAndRejectsInvalidEntry() {
        let app = launch()
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_log_treadmill"], in: app)
        let distance = app.textFields["treadmill_distance"]
        let minutes = app.textFields["treadmill_minutes"]
        let seconds = app.textFields["treadmill_seconds"]
        replace(distance, with: "3.11", in: app)
        replace(minutes, with: "26", in: app)
        replace(seconds, with: "47", in: app)
        finishTreadmillEditing(app)
        XCTAssertEqual(distance.value as? String, "3.11")
        XCTAssertEqual(minutes.value as? String, "26")
        XCTAssertEqual(seconds.value as? String, "47")
        let pace = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "8:37 /mi")).firstMatch
        XCTAssertTrue(pace.exists, "Average pace must use the exact 26:47 over 3.11 miles")
        XCTAssertTrue(app.buttons["treadmill_save"].isEnabled)
        attach(app, "Running - exact treadmill preview")
        replace(distance, with: "0", in: app)
        replace(minutes, with: "0", in: app)
        replace(seconds, with: "15", in: app)
        finishTreadmillEditing(app)
        XCTAssertTrue(app.buttons["treadmill_save"].isEnabled)
        app.buttons["treadmill_save"].tap()
        XCTAssertTrue(app.alerts["Save short treadmill run?"].waitForExistence(timeout: 5))
        let shortReview = app.alerts["Save short treadmill run?"]
        XCTAssertTrue(shortReview.buttons.matching(identifier: "treadmill_confirm_short_save").firstMatch.isEnabled)
        shortReview.buttons["Keep editing"].firstMatch.tap()
        XCTAssertEqual(seconds.value as? String, "15")
        replace(distance, with: "", in: app)
        finishTreadmillEditing(app)
        XCTAssertFalse(app.buttons["treadmill_save"].isEnabled)
        replace(distance, with: "3.11", in: app)
        replace(seconds, with: "60", in: app)
        finishTreadmillEditing(app)
        XCTAssertFalse(app.buttons["treadmill_save"].isEnabled)
        // Preview and cancel only: this test must not write a HealthKit workout.
        app.buttons["app_sheet_close_button"].tap()
        XCTAssertTrue(app.buttons["run_history_start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomWorkoutEditingRetainsTheSavedPlanIdentity() {
        let app = launch()
        let name = "UI intervals " + String(UUID().uuidString.prefix(6))
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_create_steps"], in: app)
        replace(app.textFields["run_workout_name"], with: name, in: app)
        app.buttons["run_workout_save"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'run_plan_' AND label CONTAINS %@", name)).firstMatch
        reveal(saved, in: app)
        let planID = saved.identifier
        saved.tap()
        open(app.buttons["run_plan_edit"], in: app)
        replace(app.textFields["run_workout_name"], with: name + " revised", in: app)
        app.buttons["run_workout_save"].tap()
        let revised = app.buttons[planID]
        reveal(revised, in: app)
        XCTAssertTrue(revised.label.contains(name + " revised"), revised.label)
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_live"].exists)
        attach(app, "Running - edited custom workout retains identity")
        revised.press(forDuration: 1)
        // The native context menu and SwiftUI's backing menu both expose Delete.
        // Select the visible menu cell rather than its duplicate backing element.
        app.collectionViews.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete workout"].tap()
        XCTAssertTrue(revised.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testShoeMileageInputsAcceptTypingValidateAndCancelWithoutSaving() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "shoe-gear-add"]
        app.launch()
        let brand = app.textFields["add_shoe_brand"]
        XCTAssertTrue(brand.waitForExistence(timeout: 12))
        let model = app.textFields["add_shoe_name"]
        let startingDistance = app.textFields["shoe_edit_initial_distance"]
        let reminder = app.textFields["shoe_edit_reminder"]
        let save = app.buttons["add_shoe_save"]
        let originalReminder = reminder.value as? String
        let testIdentity = "Input check " + String(UUID().uuidString.prefix(8))

        replace(brand, with: "QA", in: app)
        replace(model, with: testIdentity, in: app)
        // Tapping the field itself must focus it; a merged whole-row target misses
        // the visible narrow input and fails before these exact-value checks.
        replace(startingDistance, with: "12.34", in: app)
        replace(reminder, with: "0", in: app)
        XCTAssertEqual(startingDistance.value as? String, "12.34")
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertFalse(save.isEnabled, "A zero-distance reminder must remain invalid")
        let validation = app.staticTexts["shoe_edit_validation"]
        XCTAssertTrue(validation.exists)
        XCTAssertTrue(validation.label.contains("at least 1 km"), validation.label)

        replace(reminder, with: "250.5", in: app)
        XCTAssertEqual(reminder.value as? String, "250.5")
        XCTAssertEqual(startingDistance.value as? String, "12.34")
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(validation.exists, "Valid mileage must clear the validation message")
        attach(app, "Running - shoe mileage accepts direct typing and validates")

        // Never submit the inventory mutation: cancellation returns to the library.
        closeSheet(containing: "add_shoe_save", type: .button, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["shoe_gear_screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", testIdentity)).firstMatch.exists)
        open(app.buttons["Add shoe"], in: app)
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        XCTAssertTrue(["", "Brand"].contains(brand.value as? String ?? ""))
        XCTAssertTrue(["", "Model"].contains(model.value as? String ?? ""))
        XCTAssertEqual(startingDistance.value as? String, "0")
        XCTAssertEqual(reminder.value as? String, originalReminder)
        XCTAssertFalse(save.isEnabled, "A cancelled shoe must reopen as a fresh unsaved form")
        closeSheet(containing: "add_shoe_save", type: .button, in: app)
    }

    @MainActor
    func testLargestTextWorkoutPreviewKeepsThePrimaryActionReachableInDarkMode() {
        let app = launch(arguments: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_plan_tempo-starter"], in: app)
        let useWorkout = app.buttons["run_plan_start"]
        XCTAssertTrue(useWorkout.waitForExistence(timeout: 5))
        XCTAssertTrue(useWorkout.isHittable)
        XCTAssertGreaterThanOrEqual(useWorkout.frame.height, 44)
        XCTAssertGreaterThanOrEqual(useWorkout.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(useWorkout.frame.maxX, app.frame.maxX)
        let firstStep = app.descendants(matching: .any)["run_plan_step_1"]
        reveal(firstStep, in: app)
        XCTAssertTrue(firstStep.isHittable, "Workout review must expose the steps as well as the primary action")
        XCTAssertTrue(useWorkout.isHittable)
        attach(app, "Running - largest text workout preview")
    }

    @MainActor
    func testLargestTextQuickGoalKeepsChoicesReviewAndStartReachable() {
        let app = launch(arguments: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open(app.buttons["run_history_workouts"], in: app)
        open(app.buttons["run_create_goal"], in: app)
        open(app.buttons["run_goal_preset_20"], in: app)
        XCTAssertEqual(app.textFields["run_goal_value"].value as? String, "20")
        XCTAssertTrue(app.buttons["run_goal_review"].isHittable)
        app.buttons["run_goal_review"].tap()
        let step = app.descendants(matching: .any)["run_plan_step_1"]
        reveal(step, in: app)
        XCTAssertTrue(step.isHittable)
        XCTAssertTrue(app.buttons["run_plan_start"].isHittable)
        app.buttons["run_plan_start"].tap()
        XCTAssertTrue(app.staticTexts["run_ready_plan_name"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["run_ready_plan_name"].label, "20 min run")
        XCTAssertTrue(app.buttons["run_recorder_start"].isHittable)
        attach(app, "Running - largest text goal retained at ready screen")
        app.buttons["run_recorder_close"].tap()
    }

    @MainActor
    func testRecordedTimingSeparatesActiveElapsedPausedAndRecoveredTimeAway() {
        let app = launch(arguments: ["-ui-testing-run-timing-fixtures"])
        let recorded = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "3.11 mi", "20:00 active")).firstMatch
        open(recorded, in: app)
        let active = timingElement("active", in: app)
        reveal(active, in: app)
        XCTAssertEqual(active.label, "Active time, 20:00")
        XCTAssertEqual(timingElement("elapsed", in: app).label, "Elapsed time, 25:00")
        XCTAssertEqual(timingElement("paused", in: app).label, "Paused, 3:00")
        let recovery = timingElement("recovery", in: app)
        reveal(recovery, in: app)
        XCTAssertEqual(recovery.label, "Time away, 2:00")
        let note = timingElement("note", in: app)
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("interrupted recording was recovered"), note.label)
        attach(app, "Running - complete active and pause timing receipt")
    }

    @MainActor
    func testLargestTextTimingRowsRemainReadableAndInsideTheScreen() {
        let app = launch(arguments: ["-ui-testing-run-timing-fixtures", "-screenshot-dark-mode",
                                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let recorded = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "3.11 mi", "20:00 active")).firstMatch
        open(recorded, in: app)
        for (key, label) in [("active", "Active time, 20:00"), ("elapsed", "Elapsed time, 25:00"),
                             ("paused", "Paused, 3:00"), ("recovery", "Time away, 2:00")] {
            let row = timingElement(key, in: app)
            reveal(row, in: app)
            XCTAssertEqual(row.label, label)
            XCTAssertGreaterThanOrEqual(row.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX)
        }
        attach(app, "Running - largest text timing rows in dark mode")
    }

    @MainActor
    func testLegacyTimingDoesNotInventPausesFromTheDurationDifference() {
        let app = launch(arguments: ["-ui-testing-run-timing-fixtures"])
        let legacy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "3.73 mi", "18:00 active")).firstMatch
        open(legacy, in: app)
        let active = timingElement("active", in: app)
        reveal(active, in: app)
        XCTAssertEqual(active.label, "Active time, 18:00")
        XCTAssertEqual(timingElement("elapsed", in: app).label, "Elapsed time, 21:00")
        let paused = timingElement("paused", in: app)
        reveal(paused, in: app)
        XCTAssertEqual(paused.label, "Pause history, Not recorded")
        XCTAssertFalse(timingElement("recovery", in: app).exists)
        let note = timingElement("note", in: app)
        reveal(note, in: app)
        XCTAssertTrue(note.label.contains("Exact pause events can't be reconstructed for Apple Health"), note.label)
        attach(app, "Running - unknown legacy pause timing remains unknown")
    }

    @MainActor
    private func timingElement(_ suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "run_detail_timing_" + suffix).firstMatch
    }

    @MainActor
    private func closeSheet(containing anchor: String, type: XCUIElement.ElementType, in app: XCUIApplication) {
        // Nested scaffolds expose both the picker and preview close buttons. Scope
        // the control to the sheet containing this screen's unique content.
        let scopes = app.otherElements.containing(type, identifier: anchor).allElementsBoundByIndex
        let sheet = scopes.first { scope in
            let controls = scope.buttons.matching(identifier: "app_sheet_close_button")
            return controls.count == 1 && controls.element(boundBy: 0).isHittable
        }
        guard let sheet else { XCTFail("No unambiguous visible close control for \(anchor)"); return }
        sheet.buttons["app_sheet_close_button"].tap()
        XCTAssertTrue(app.descendants(matching: type)[anchor].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs", "-ui-testing-reset-run-draft"] + arguments
        app.launch()
        if !app.buttons["run_history_start"].waitForExistence(timeout: 5),
           app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.buttons["run_history_start"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func finishTreadmillEditing(_ app: XCUIApplication) {
        let keyboardDone = app.buttons["treadmill_keyboard_done"]
        let done = keyboardDone.exists ? keyboardDone : app.buttons["treadmill_finish_edit"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.buttons["treadmill_save"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func finishGoalEditing(_ app: XCUIApplication) {
        let keyboardDone = app.buttons["run_goal_keyboard_done"]
        let done = keyboardDone.exists ? keyboardDone : app.buttons["run_goal_finish_edit"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.buttons["run_goal_review"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, in app: XCUIApplication) {
        reveal(field, in: app); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        func matches() -> Bool {
            let actual = field.value as? String ?? ""
            return actual == value || (value.isEmpty && actual == (field.placeholderValue ?? ""))
        }
        guard !matches() else { return }
        field.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        XCTAssertTrue(matches(), "Expected \(value.debugDescription), received \(String(describing: field.value))")
    }

    @MainActor
    private func open(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app); element.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var earlier = false
        var missing = 0
        for _ in 0..<14 {
            let frame = element.exists ? element.frame : .zero
            let visibleTop = app.frame.minY + 90
            var visibleBottom = app.frame.maxY - 80
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = keyboard.exists
            if keyboardVisible {
                visibleBottom = min(visibleBottom, keyboard.frame.minY - 20)
                // The shoe editor keeps validation/Save above the keyboard.
                // Scroll within the remaining form, never from the keyboard or footer.
                for footer in [app.buttons["add_shoe_save"], app.staticTexts["shoe_edit_validation"]] {
                    if footer.exists, footer.isHittable {
                        visibleBottom = min(visibleBottom, footer.frame.minY - 12)
                    }
                }
            }
            if element.exists, element.isHittable, frame.minY >= visibleTop, frame.maxY < visibleBottom { return }
            if !frame.isEmpty { earlier = frame.midY < (keyboardVisible ? (visibleTop + visibleBottom) / 2 : app.frame.midY); missing = 0 } else {
                missing += 1
                if missing.isMultiple(of: 3) { earlier.toggle() }
            }
            if keyboardVisible {
                let visibleHeight = max(44, visibleBottom - visibleTop)
                let upper = visibleTop + visibleHeight * 0.2
                let lower = visibleTop + visibleHeight * 0.85
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: app.frame.width * 0.95, dy: (earlier ? upper : lower) - app.frame.minY))
                let end = origin.withOffset(CGVector(dx: app.frame.width * 0.95, dy: (earlier ? lower : upper) - app.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: earlier ? 0.3 : 0.72))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: earlier ? 0.65 : 0.4)))
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
