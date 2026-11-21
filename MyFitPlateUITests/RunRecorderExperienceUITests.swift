import XCTest

final class RunRecorderExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDashboardRecoveryKeepsUnavailableSensorsBlankAndTimerPaused() {
        let app = launch()
        app.buttons["run_display_settings"].tap()
        let layout = app.segmentedControls["run_display_layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.buttons["Dashboard"].tap()
        app.buttons["app_sheet_close_button"].tap()
        app.buttons["run_recorder_start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["run_metric_dashboard"].waitForExistence(timeout: 5))
        for id in ["run_elapsed", "run_distance", "run_live_pace", "run_average_pace"] { XCTAssertTrue(app.staticTexts[id].exists, id) }
        app.buttons["run_pause_resume"].tap()
        let time = app.staticTexts["run_elapsed"].label
        let sensors = app.buttons["Sensors"]
        revealAboveRunControls(sensors, app: app)
        sensors.tap()
        XCTAssertTrue(app.staticTexts["Heart rate unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["run_live_heart_rate"].exists)
        XCTAssertFalse(app.staticTexts["run_live_cadence"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-draft" }
        app.launch()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertTrue(app.descendants(matching: .any)["run_metric_dashboard"].exists)
        XCTAssertEqual(app.staticTexts["run_elapsed"].label, time)
        attach(app, "Run recorder - dashboard restores without stale sensor readings")
        app.buttons["run_display_settings"].tap()
        app.segmentedControls["run_display_layout"].buttons["Focus"].tap()
        app.buttons["app_sheet_close_button"].tap()
    }

    @MainActor
    func testReadyScreenDoesNotStartTimerAndAudioPreferenceSurvivesStart() {
        let app = launch()
        XCTAssertTrue(app.buttons["run_recorder_start"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["run_elapsed"].exists)
        let audio = app.buttons["run_audio_cues"]
        XCTAssertTrue(audio.exists)
        let previous = audio.value as? String
        audio.tap()
        XCTAssertNotEqual(audio.value as? String, previous)
        let selection = audio.value as? String
        app.buttons["run_recorder_start"].tap()
        XCTAssertTrue(app.staticTexts["run_elapsed"].waitForExistence(timeout: 5))
        XCTAssertEqual(audio.value as? String, selection)
        XCTAssertTrue(app.buttons["run_pause_resume"].isHittable)
        XCTAssertTrue(app.buttons["run_finish"].isHittable)
        attach(app, "Run recorder - deliberate start and glanceable controls")
    }

    @MainActor
    func testPauseFreezesClockAndCancellingFinishKeepsRunPaused() {
        let app = launch()
        app.buttons["run_recorder_start"].tap()
        let timer = app.staticTexts["run_elapsed"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        app.buttons["run_pause_resume"].tap()
        let frozen = timer.label
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", frozen), object: timer)
        stable.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 2), .completed)
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        app.buttons["run_finish"].tap()
        XCTAssertTrue(app.alerts["Short recording"].waitForExistence(timeout: 3))
        // iOS can expose the SwiftUI alert action as nested nodes for the same button.
        let review = app.alerts["Short recording"]
        XCTAssertTrue(review.buttons.matching(identifier: "run_confirm_short_save").firstMatch.isEnabled,
                      "A positive short recording can be saved after deliberate review")
        review.buttons["Keep paused"].firstMatch.tap()
        XCTAssertEqual(timer.label, frozen)
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        app.buttons["run_pause_resume"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", frozen), object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 4), .completed)
        attach(app, "Run recorder - paused time and deliberate finish")
    }

    @MainActor
    func testShortRecordingRequiresReviewThenSavesExactPausedTimeWithoutDistance() {
        let app = launch()
        app.buttons["run_recorder_start"].tap()
        let timer = app.staticTexts["run_elapsed"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        app.buttons["run_pause_resume"].tap()
        let frozen = timer.label
        app.buttons["run_finish"].tap()
        let review = app.alerts["Short recording"]
        XCTAssertTrue(review.waitForExistence(timeout: 3))
        XCTAssertTrue(review.label.contains("Short recording"))
        XCTAssertFalse(app.descendants(matching: .any)["run_recorder_summary"].exists)
        let save = review.buttons.matching(identifier: "run_confirm_short_save").firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["run_recorder_summary"].waitForExistence(timeout: 5))
        let activeTime = app.descendants(matching: .any)["run_summary_timing_active"].firstMatch
        XCTAssertTrue(activeTime.waitForExistence(timeout: 5))
        XCTAssertEqual(activeTime.label, "Active time, \(frozen)", "The summary retains the paused active time")
        XCTAssertTrue(app.buttons["run_summary_done"].exists)
        attach(app, "Run recorder - reviewed short recording retains active time")
    }

    @MainActor
    func testLargestTextKeepsRecordingControlsReachableAndWorkoutVisible() {
        let app = launch("run-recorder-workout", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let start = app.buttons["run_recorder_start"]
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        XCTAssertLessThanOrEqual(start.frame.maxY, app.frame.maxY)
        // A short held touch makes the simulator deliver a complete press/release
        // after the accessibility-size layout has settled.
        start.press(forDuration: 0.2)
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["run_pause_resume"].isHittable)
        XCTAssertTrue(app.buttons["run_finish"].isHittable)
        for _ in 0..<5 where !app.staticTexts["run_next_step"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["run_next_step"].isHittable)
        XCTAssertTrue(app.buttons["run_pause_resume"].isHittable)
        attach(app, "Run recorder - largest text workout guidance")
    }

    @MainActor
    func testInterruptedWorkoutRecoversPausedWithItsStepAndFrozenTime() {
        let app = launch("run-recorder-workout")
        app.buttons["run_recorder_start"].tap()
        XCTAssertTrue(app.staticTexts["run_elapsed"].waitForExistence(timeout: 5))
        app.buttons["run_pause_resume"].tap()
        let elapsed = app.staticTexts["run_elapsed"].label
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-draft" }
        app.launch()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertEqual(app.staticTexts["run_elapsed"].label, elapsed)
        XCTAssertFalse(app.buttons["run_recorder_start"].exists, "A saved run must not be replaced by a fresh start")
        XCTAssertTrue(app.staticTexts["run_next_step"].exists)
        for _ in 0..<4 where !app.otherElements["run_recovery_notice"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.otherElements["run_recovery_notice"].exists)
        attach(app, "Run recorder - interrupted workout recovered paused")
    }

    @MainActor
    func testDisplayChoiceSurvivesRecoveryAndKeepsEveryMetricAvailable() {
        let app = launch()
        app.buttons["run_display_settings"].tap()
        let distance = app.buttons["run_display_distance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 5))
        distance.tap()
        XCTAssertEqual(distance.value as? String, "Selected")
        app.buttons["app_sheet_close_button"].tap()
        app.buttons["run_recorder_start"].tap()
        let hero = app.descendants(matching: .any)["run_metric_hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(hero.staticTexts["run_distance"].exists)
        for id in ["run_elapsed", "run_live_pace", "run_average_pace"] {
            XCTAssertTrue(app.staticTexts[id].exists, id)
        }
        app.buttons["run_pause_resume"].tap()
        let paused = app.staticTexts["run_elapsed"].label
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-draft" }
        app.launch()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertEqual(app.staticTexts["run_elapsed"].label, paused)
        XCTAssertTrue(app.descendants(matching: .any)["run_metric_hero"].staticTexts["run_distance"].exists)
        attach(app, "Run recorder - personalized distance display recovered paused")
        app.buttons["run_display_settings"].tap()
        app.buttons["run_display_time"].tap()
        app.buttons["app_sheet_close_button"].tap()
    }

    @MainActor
    func testLargestTextDisplaySettingsAndUnavailablePaceStayUsable() {
        let app = launch(extra: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["run_display_settings"].tap()
        let pace = app.buttons["run_display_pace"]
        XCTAssertTrue(pace.waitForExistence(timeout: 5))
        for _ in 0..<4 where !pace.isHittable { app.swipeUp() }
        XCTAssertTrue(pace.isHittable)
        XCTAssertGreaterThanOrEqual(pace.frame.height, 44)
        pace.tap()
        attach(app, "Run recorder - largest text display settings")
        app.buttons["app_sheet_close_button"].tap()
        app.buttons["run_recorder_start"].press(forDuration: 0.2)
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 5))
        let hero = app.descendants(matching: .any)["run_metric_hero"]
        XCTAssertEqual(hero.staticTexts["run_live_pace"].label, "—", "No GPS must not invent a live pace")
        XCTAssertTrue(app.buttons["run_pause_resume"].isHittable)
        XCTAssertTrue(app.buttons["run_finish"].isHittable)
        app.buttons["run_pause_resume"].tap()
        app.buttons["run_display_settings"].tap()
        app.buttons["run_display_time"].tap()
        app.buttons["app_sheet_close_button"].tap()
    }

    @MainActor
    func testRecoveredRouteKeepsItsSegmentReviewAndPausedControlsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "run-recorder",
                               "-ui-testing-reset-run-draft", "-ui-testing-seed-run-route-checkpoint"]
        app.launch()
        if !app.buttons["run_pause_resume"].waitForExistence(timeout: 8), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertFalse(app.buttons["run_recorder_start"].exists)
        let frozenTime = app.staticTexts["run_elapsed"].label
        let frozenDistance = app.staticTexts["run_distance"].label
        let routeReview = app.buttons["run_recovered_route_review"]
        revealAboveRunControls(routeReview, app: app)
        XCTAssertTrue(routeReview.isHittable)
        routeReview.tap()
        XCTAssertFalse(app.alerts["Short recording"].exists, "Route review must not tap through to the pinned Finish control")
        XCTAssertEqual(routeReview.value as? String, "Expanded", app.debugDescription)
        let recoveredMap = app.descendants(matching: .any)["run_recovered_route_map"]
        for _ in 0..<3 where !recoveredMap.exists { app.swipeUp() }
        XCTAssertTrue(recoveredMap.waitForExistence(timeout: 4), app.debugDescription)
        attach(app, "Run recovery - earlier route segments and explicit resume")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-draft" || $0 == "-ui-testing-seed-run-route-checkpoint" }
        app.launch()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertEqual(app.staticTexts["run_elapsed"].label, frozenTime)
        XCTAssertEqual(app.staticTexts["run_distance"].label, frozenDistance)
        revealAboveRunControls(app.buttons["run_recovered_route_review"], app: app)
        XCTAssertTrue(app.buttons["run_recovered_route_review"].isHittable)
    }

    @MainActor
    func testRepeatBuilderRestoresExactDraftAcrossRelaunchAndSavesOneTemplate() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs",
                               "-ui-testing-reset-run-draft", "-ui-testing-reset-run-builder"]
        app.launch()
        if !app.buttons["run_history_workouts"].waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        app.buttons["run_history_workouts"].tap()
        let create = app.buttons["run_create_repeats"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        create.tap()
        let field = app.textFields["run_workout_name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        let original = field.value as? String ?? ""
        let title = "QA restored intervals \(UUID().uuidString.prefix(6))"
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + title)
        XCTAssertEqual(field.value as? String, title)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-builder" }
        app.launch()
        XCTAssertTrue(app.buttons["run_history_workouts"].waitForExistence(timeout: 10))
        app.buttons["run_history_workouts"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        create.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(field.value as? String, title)
        XCTAssertTrue(app.descendants(matching: .any)["run_builder_restored"].exists)
        app.buttons["run_workout_save"].tap()
        XCTAssertTrue(app.buttons["run_workout_save"].waitForNonExistence(timeout: 8), app.debugDescription)
        let saved = app.staticTexts[title]
        for _ in 0..<8 where !saved.isHittable { app.swipeDown() }
        XCTAssertTrue(saved.exists, app.debugDescription)
        XCTAssertEqual(app.staticTexts.matching(identifier: title).count, 1)
        attach(app, "Running builder - restored draft accepted as one saved template")
    }

    @MainActor
    func testNestedOutlineRestoresAndUseOnceReviewsWithoutSavingOrStarting() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs",
                               "-ui-testing-reset-run-builder", "-ui-testing-reset-run-draft"]
        app.launch()
        if !app.buttons["run_history_workouts"].waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        var originalPlanIDs: Set<String>?
        func openBuilder() {
            let workouts = app.buttons["run_history_workouts"]
            XCTAssertTrue(workouts.waitForExistence(timeout: 10))
            XCTAssertTrue(workouts.isEnabled, "This builder fixture must start without another test's recoverable recording. " + app.debugDescription)
            workouts.tap()
            let plans = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "run_plan_"))
            XCTAssertTrue(app.buttons["run_create_steps"].waitForExistence(timeout: 6))
            let currentPlanIDs = Set(plans.allElementsBoundByIndex.map(\.identifier))
            if let originalPlanIDs { XCTAssertEqual(currentPlanIDs, originalPlanIDs) } else { originalPlanIDs = currentPlanIDs }
            let create = app.buttons["run_create_steps"]
            for _ in 0..<6 where !create.isHittable { app.swipeUp() }
            XCTAssertTrue(create.isHittable); create.tap()
            XCTAssertTrue(app.buttons["run_workout_outline"].waitForExistence(timeout: 6))
        }
        openBuilder()
        app.buttons["run_workout_outline"].tap()
        let addGroup = app.buttons["run_outline_add_group_0"]
        XCTAssertTrue(addGroup.waitForExistence(timeout: 5)); addGroup.tap()
        app.staticTexts["Repeat group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Inside repeat group"].waitForExistence(timeout: 5))
        let innerGroup = app.buttons["run_outline_add_group_1"]
        XCTAssertTrue(innerGroup.waitForExistence(timeout: 5)); innerGroup.tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-builder" || $0 == "-ui-testing-reset-run-draft" }
        app.launch()
        openBuilder()
        XCTAssertTrue(app.staticTexts["4 outline items · 27 executed steps"].exists, app.debugDescription)
        let useOnce = app.buttons["run_workout_use_once"]
        revealAboveEditorActions(useOnce, app: app)
        XCTAssertTrue(useOnce.isEnabled); useOnce.tap()
        XCTAssertTrue(app.buttons["run_plan_start"].waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertFalse(app.buttons["run_pause_resume"].exists)
        XCTAssertFalse(app.buttons["run_plan_edit"].exists, "A one-off preview must not become a saved template")
        attach(app, "Running outline - nested draft restored and reviewed as a one-off workout")
        app.buttons["app_sheet_close_button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["run_plan_start"].waitForNonExistence(timeout: 6))
        XCTAssertTrue(app.buttons["run_create_steps"].waitForExistence(timeout: 6))
        let remaining = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "run_plan_"))
        XCTAssertEqual(Set(remaining.allElementsBoundByIndex.map(\.identifier)), originalPlanIDs,
                       "Review and use once must leave the saved workout library unchanged")
    }

    @MainActor
    func testReviewedGearBatchUnassignsAndUndoRestoresExactLifetimeMileage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "shoe-gear-lifetime"]
        app.launch()
        let tools = app.buttons["shoe_mileage_tools"]
        if !tools.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(tools.waitForExistence(timeout: 10)); tools.tap()
        let assign = app.buttons["shoe_batch_assignment"]
        XCTAssertTrue(assign.waitForExistence(timeout: 10), app.debugDescription)
        assign.tap()
        XCTAssertTrue(app.descendants(matching: .any)["shoe_batch_screen"].waitForExistence(timeout: 5))
        for id in ["qa-wave0-gear-recent", "qa-wave0-gear-old"] {
            let row = app.buttons["shoe_batch_run_\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        }
        let review = app.buttons["shoe_batch_review"]
        for _ in 0..<5 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isEnabled); review.tap()
        let confirm = app.buttons["shoe_batch_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attach(app, "Running gear - review selected runs before clearing assignments")
        confirm.tap()
        let undo = app.buttons["shoe_batch_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.buttons["shoe_batch_review"].waitForExistence(timeout: 5))
        app.navigationBars["Assign past runs"].buttons["Done"].tap()
        let total = app.staticTexts["shoe_lifetime_distance_qa-wave0-lifetime-shoe"]
        for _ in 0..<8 where !total.isHittable { app.swipeUp() }
        XCTAssertTrue(total.exists)
        XCTAssertTrue(total.label.contains("50") || total.label.contains("31.1"), total.label)
        attach(app, "Running gear - Undo restores the 500-day-old and recent mileage")
    }

    @MainActor
    func testManualLapSurvivesRecoveryWithoutChangingPrescribedStep() {
        let app = launch("run-recorder-workout")
        app.buttons["run_recorder_start"].tap()
        let timer = app.staticTexts["run_elapsed"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let before = timer.label
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: timer)], timeout: 4), .completed)
        let step = app.staticTexts["run_next_step"].label
        let lap = app.buttons["run_mark_lap"]
        revealAboveRunControls(lap, app: app)
        lap.tap()
        XCTAssertTrue(app.staticTexts["Lap 1 saved. Workout step unchanged."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["run_next_step"].label, step)
        app.buttons["run_pause_resume"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-run-draft" }
        app.launch()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertEqual(app.staticTexts["run_next_step"].label, step)
        let laps = app.descendants(matching: .any)["run_manual_laps"].firstMatch
        revealAboveRunControls(laps, app: app)
        XCTAssertTrue(app.buttons["Manual laps · 1"].exists || app.staticTexts["Manual laps · 1"].exists, app.debugDescription)
        attach(app, "Running - manual lap checkpoint survives interruption without skipping a step")
    }

    @MainActor
    func testHistorySearchHasExplicitEmptyStateAndRouteRowsAreSelectable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs", "-ui-testing-reset-run-draft"]
        app.launch()
        if !app.buttons["run_history_start"].waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        let search = app.textFields["run_history_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("unmatched-qa-query")
        let empty = app.staticTexts["No runs match these filters. Try another date, source or search."]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "unmatched-qa-query".count))
        app.buttons["Route map"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "run_route_select_"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Choose a run"].exists)
        XCTAssertTrue(app.buttons["Open run details"].firstMatch.exists)
        attach(app, "Running - exact search scope and selectable route history")
    }

    @MainActor
    private func revealAboveEditorActions(_ element: XCUIElement, app: XCUIApplication) {
        let save = app.buttons["run_workout_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        // SwiftUI can report an offscreen scroll element as hittable beneath the
        // pinned footer. Keep its entire frame in the content viewport before tapping.
        for _ in 0..<8 {
            if element.exists, element.isHittable, element.frame.minY > 115,
               element.frame.maxY < save.frame.minY - 12 { return }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: save.frame.minY - 30))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: 160)))
        }
        XCTAssertTrue(element.exists && element.isHittable && element.frame.minY > 115
                      && element.frame.maxY < save.frame.minY - 12, app.debugDescription)
    }

    @MainActor
    private func revealAboveRunControls(_ element: XCUIElement, app: XCUIApplication) {
        let controls = app.buttons["run_finish"]
        for _ in 0..<8 {
            if element.exists, element.isHittable, element.frame.minY > 85,
               element.frame.maxY < controls.frame.minY - 12 { return }
            let bottom = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: controls.frame.minY - 28))
            let top = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: 160))
            bottom.press(forDuration: 0.05, thenDragTo: top)
        }
        XCTAssertTrue(element.exists && element.isHittable && element.frame.maxY < controls.frame.minY, app.debugDescription)
    }

    @MainActor
    private func launch(_ route: String = "run-recorder", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route,
                               "-ui-testing-reset-run-draft"] + extra
        app.terminate()
        app.launch()
        if !app.buttons["run_recorder_start"].waitForExistence(timeout: 6),
           app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.buttons["run_recorder_start"].waitForExistence(timeout: 8))
        // Every independent test establishes its baseline through the real UI.
        // Recovery checks relaunch this app directly and intentionally retain the
        // layout selected within that test, including Dashboard.
        app.buttons["run_display_settings"].tap()
        let layout = app.segmentedControls["run_display_layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.buttons["Focus"].tap()
        XCTAssertTrue(layout.buttons["Focus"].isSelected)
        app.buttons["app_sheet_close_button"].tap()
        XCTAssertTrue(app.buttons["run_recorder_start"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
