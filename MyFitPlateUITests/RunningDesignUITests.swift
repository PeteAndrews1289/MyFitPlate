import XCTest

@MainActor
final class RunningDesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDirectOpenRunReachesReadinessWithoutStartingOrChangingHistory() {
        let app = launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "run_history_row_"))
        let count = rows.count
        XCTAssertGreaterThanOrEqual(count, 2)
        let first = rows.firstMatch
        XCTAssertTrue(first.isHittable, "Recent runs should be reachable before the separate records page.")
        // At normal text size these fixtures fit a date, metrics and source caption
        // without a trailing source badge squeezing the date into three lines.
        for index in 0..<min(count, 2) {
            XCTAssertLessThanOrEqual(rows.element(boundBy: index).frame.height, 132,
                                     "Recent-run dates and metrics need the full text-column width.")
        }
        let firstLabel = first.label
        XCTAssertFalse(any(app, "run_history_records").exists)
        app.buttons["run_history_open_records"].tap()
        XCTAssertTrue(any(app, "run_history_records").waitForExistence(timeout: 5))
        app.navigationBars["Running records"].buttons["Done"].tap()

        app.buttons["run_history_start"].tap()
        XCTAssertTrue(any(app, "run_recorder_ready").waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["run_ready_plan_name"].label, "Open run")
        XCTAssertTrue(app.buttons["run_recorder_start"].isHittable)
        XCTAssertFalse(any(app, "run_recorder_live").exists)
        XCTAssertFalse(app.buttons["run_open"].exists, "An ordinary run should skip the workout chooser.")
        capture(app, "Running - direct open waits at GPS readiness")
        app.buttons["run_recorder_close"].tap()
        XCTAssertTrue(app.buttons["run_history_start"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
        XCTAssertEqual(first.label, firstLabel)
        XCTAssertEqual(app.buttons["run_history_start"].label, "Open run")

        app.buttons["run_history_workouts"].tap()
        XCTAssertTrue(app.buttons["run_create_goal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["run_log_treadmill"].exists)
        XCTAssertFalse(any(app, "run_recorder_live").exists)
        app.buttons["app_sheet_close_button"].tap()
        capture(app, "Running - recent history before records with guided workouts retained")
    }

    func testHistoryResumeRestoresPausedWorkoutInsteadOfStartingAnotherRun() {
        let app = launch(screen: "run-recorder-workout")
        app.buttons["run_recorder_start"].tap()
        let elapsed = app.staticTexts["run_elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        app.buttons["run_pause_resume"].tap()
        let frozen = elapsed.label
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs"]
        app.launch()
        let resume = app.buttons["run_history_start"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertEqual(resume.label, "Resume run")
        XCTAssertFalse(app.buttons["run_history_workouts"].isEnabled)
        resume.tap()
        XCTAssertTrue(app.buttons["run_pause_resume"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["run_pause_resume"].label.contains("Resume"))
        XCTAssertEqual(elapsed.label, frozen)
        XCTAssertFalse(app.buttons["run_recorder_start"].exists)
        XCTAssertTrue(app.staticTexts["run_next_step"].exists)
        capture(app, "Running - history resumes the existing paused guided workout")
    }

    func testRunningBlockReviewSurvivesRelaunchAndAdoptsWithoutRecording() {
        let app = XCUIApplication()
        let flags = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "runs", "-ui-testing-run-block", "-ui-testing-reset-run-draft"]
        app.launchArguments = flags + ["-ui-testing-reset-editor-drafts"]
        app.launch()
        if !app.buttons["run_training_plan"].waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        app.buttons["run_training_plan"].tap()
        XCTAssertTrue(any(app, "run_training_block_screen").waitForExistence(timeout: 10))
        let confirmation = app.switches["run_block_confirm_baseline"]
        reveal(confirmation, app: app)
        if confirmation.value as? String != "1" {
            confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        }
        XCTAssertEqual(confirmation.value as? String, "1", app.debugDescription)
        let build = app.buttons["run_block_build"]
        reveal(build, app: app); XCTAssertTrue(build.isEnabled, app.debugDescription); build.tap()
        let accept = app.buttons["run_block_accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Running block - reviewed dates and bounded workload")
        app.navigationBars["Review running plan"].buttons["Keep for later"].tap()
        let keptReview = app.buttons["run_block_resume_review"]
        revealFromTop(keptReview, app: app)
        XCTAssertTrue(keptReview.exists, app.debugDescription)
        app.terminate(); app.launchArguments = flags; app.launch()
        XCTAssertTrue(app.buttons["run_training_plan"].waitForExistence(timeout: 15)); app.buttons["run_training_plan"].tap()
        let resume = app.buttons["run_block_resume_review"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(accept.waitForExistence(timeout: 5)); accept.tap()
        XCTAssertTrue(accept.waitForNonExistence(timeout: 10), app.debugDescription)
        let progress = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "run_block_progress_")).firstMatch
        reveal(progress, app: app)
        XCTAssertTrue(progress.label.contains("0 recorded"), "Adopting a block must not manufacture workouts")
        XCTAssertFalse(any(app, "run_recorder_live").exists)
        capture(app, "Running block - adopted plan with zero recorded outcomes")
        app.navigationBars["Running plan"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["run_history_start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["run_history_start"].label, "Open run")
    }

    private func revealFromTop(_ element: XCUIElement, app: XCUIApplication) {
        // Form lazily publishes its off-screen rows. Returning from a sheet retains
        // the bottom scroll position; the recovery row is at the top of this form.
        for _ in 0..<10 {
            if element.exists, element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists, element.isHittable, element.frame.minY > 85, element.frame.maxY < app.frame.maxY - 75 { return }
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            if element.exists, element.frame.minY < 85 { upper.press(forDuration: 0.08, thenDragTo: lower) } else { lower.press(forDuration: 0.08, thenDragTo: upper) }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func launch(screen: String = "runs") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen, "-ui-testing-reset-run-draft"]
        app.launch()
        let expected = app.buttons[screen == "runs" ? "run_history_start" : "run_recorder_start"]
        if !expected.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(expected.waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
