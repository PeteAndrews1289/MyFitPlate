import XCTest

final class AdaptiveToolsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(_ screen: String, extra: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen, "-ui-testing-reset-workout-draft"] + extra
        if reset { app.launchArguments.append("-ui-testing-reset-editor-drafts") }
        app.launch()
        return app
    }

    @MainActor private func reveal(
        _ element: XCUIElement, in app: XCUIApplication,
        requiringHittable: Bool = true, searchUpWhenMissing: Bool = false
    ) {
        var moveDown = searchUpWhenMissing
        var visibleBottom = app.frame.maxY - 65
        for _ in 0..<24 {
            // A presented Form is virtualized. Scroll it, not the page underneath its sheet.
            let viewport = app.frame
            let onScreen: (XCUIElement) -> Bool = { candidate in
                let visible = candidate.frame.intersection(viewport)
                return !visible.isNull && !visible.isEmpty && candidate.isHittable
            }
            let scroll = app.collectionViews.allElementsBoundByIndex.last(where: onScreen)
                ?? app.scrollViews.allElementsBoundByIndex.last(where: onScreen) ?? app
            let bounds = scroll.frame.intersection(app.frame)
            let top = max(bounds.minY + 12, 110.0)
            // Forms use the whole visible collection and have no pinned footer.
            let bottomInset: CGFloat = scroll.elementType == .collectionView ? 12 : 65
            let bottom = min(bounds.maxY - 12, app.frame.maxY - bottomInset)
            visibleBottom = bottom
            let frame = element.exists ? element.frame : nil
            if let frame, frame.height > 0 {
                if !requiringHittable || element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                moveDown = frame.minY < top
            }
            // Short drags do not fling a rating row above the sheet header. Keep the
            // chosen search direction when a previously visible row is virtualized.
            let distance = frame.map { min(160, max(70, abs($0.midY - (top + bottom) / 2))) } ?? 160
            let startY = moveDown ? top + 24 : bottom - 24
            let endY = moveDown ? min(bottom - 24, startY + distance) : max(top + 24, startY - distance)
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            // Form rows begin 16 points inside the collection. Its outer gutter
            // avoids segmented pickers and switches intercepting vertical drags.
            let dragX = scroll.elementType == .collectionView ? bounds.minX + 8 : bounds.midX
            let start = origin.withOffset(CGVector(dx: dragX - scroll.frame.minX, dy: startY - scroll.frame.minY))
            let end = origin.withOffset(CGVector(dx: dragX - scroll.frame.minX, dy: endY - scroll.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertGreaterThanOrEqual(element.frame.minY, 110)
        XCTAssertLessThanOrEqual(element.frame.maxY, visibleBottom)
        if requiringHittable { XCTAssertTrue(element.isHittable, app.debugDescription) }
    }

    @MainActor private func confirmWorkout(_ confirmation: XCUIElement, in app: XCUIApplication) {
        reveal(confirmation, in: app, searchUpWhenMissing: true)
        XCTAssertFalse(confirmation.isSelected)
        confirmation.tap()
        XCTAssertTrue(confirmation.wait(for: \.isSelected, toEqual: true, timeout: 5), app.debugDescription)
    }

    @MainActor private func choose(_ identifier: String, option: String, in app: XCUIApplication) {
        let picker = app.buttons[identifier]
        reveal(picker, in: app)
        var previous = CGRect.null
        var since = ProcessInfo.processInfo.systemUptime
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard picker.exists, picker.isEnabled, picker.isHittable else { return false }
            if previous != picker.frame { previous = picker.frame; since = ProcessInfo.processInfo.systemUptime; return false }
            return ProcessInfo.processInfo.systemUptime - since >= 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        picker.press(forDuration: 0.1)
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        choice.tap()
    }

    @MainActor func testLighterWeekReviewsVolumeAndUndoes() {
        let app = launch("week-rescue")
        let reason = app.buttons["rescue_reason_A lighter training week"]
        XCTAssertTrue(reason.waitForExistence(timeout: 15))
        reveal(reason, in: app); reason.tap()
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.staticTexts["Review all changes"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'fewer sets total'")).firstMatch.exists)
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.staticTexts["rescue_applied"].waitForExistence(timeout: 5), app.debugDescription)
        let undo = app.buttons["rescue_undo"]
        reveal(undo, in: app); undo.tap()
        XCTAssertTrue(app.staticTexts["Review what Undo restores"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["rescue_primary"].label, "Undo reviewed changes")
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.buttons["rescue_primary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["rescue_status"].label.contains("undone"))
    }

    @MainActor func testRescueReviewsAppliesAndUndoesWithoutChangingActivePlan() {
        let app = launch("week-rescue")
        XCTAssertTrue(app.buttons["rescue_primary"].waitForExistence(timeout: 15), app.debugDescription)
        choose("rescue_recipe", option: "Blueberry Protein Overnight Oats", in: app)
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.staticTexts["Review all changes"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rescue_primary"].label.contains("Apply"))
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.staticTexts["rescue_applied"].waitForExistence(timeout: 5), app.debugDescription)
        let undo = app.buttons["rescue_undo"]
        reveal(undo, in: app)
        undo.tap()
        XCTAssertTrue(app.staticTexts["Review what Undo restores"].waitForExistence(timeout: 5))
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.buttons["rescue_primary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rescue_applied"].exists)
        XCTAssertTrue(app.staticTexts["rescue_status"].label.contains("undone"))
    }

    @MainActor func testUnavailableSavedProgramOffersRetry() {
        let app = launch("week-rescue", extra: ["-ui-testing-workout-load-failure"])
        let retry = app.buttons["adaptive_program_retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["rescue_primary"].exists)
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rescue_primary"].exists)
    }

    @MainActor func testRescueFailureKeepsReviewAndAllowsRetry() {
        let app = launch("week-rescue", extra: ["-ui-testing-workout-save-failure"])
        XCTAssertTrue(app.buttons["rescue_primary"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["rescue_primary"].tap()
        XCTAssertTrue(app.buttons["rescue_primary"].label.contains("Apply"))
        app.buttons["rescue_primary"].tap()
        let error = app.staticTexts["rescue_status"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(error.label.isEmpty)
        XCTAssertTrue(app.buttons["rescue_check_status"].exists)
        XCTAssertTrue(app.buttons["rescue_cancel_pending"].exists)
        XCTAssertFalse(app.staticTexts["rescue_applied"].exists)
        XCTAssertTrue(app.buttons["rescue_primary"].isEnabled)
    }

    @MainActor func testOneQuestionUpdatesPortionAndKeepsReviewAfterSaveFailure() {
        let app = launch("useful-question", extra: ["-ui-testing-food-save-failure"])
        let answer = app.buttons["meal_question_450"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15), app.debugDescription)
        reveal(answer, in: app)
        answer.tap()
        XCTAssertTrue(app.staticTexts["meal_question_preview"].exists)
        app.buttons["meal_question_apply"].tap()
        XCTAssertTrue(app.staticTexts["meal_question_response"].label.contains("450 g"))
        XCTAssertFalse(app.buttons["meal_question_skip"].exists)
        app.buttons["ai_summary_log_action"].tap()
        let error = app.staticTexts["ai_summary_save_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Could not save this meal"), error.label)
        XCTAssertTrue(app.buttons["ai_summary_log_action"].isEnabled)
        app.terminate()
        let restored = launch("useful-question", extra: ["-ui-testing-food-save-failure"], reset: false)
        let receipt = restored.staticTexts["meal_question_response"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15), restored.debugDescription)
        XCTAssertTrue(receipt.label.contains("450 g"))
        XCTAssertFalse(restored.buttons["meal_question_apply"].exists)
    }

    @MainActor func testUnknownPortionKeepsOriginalEstimateAfterRelaunch() {
        let app = launch("useful-question")
        let skip = app.buttons["meal_question_skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15), app.debugDescription)
        reveal(skip, in: app); skip.tap()
        XCTAssertTrue(app.staticTexts["meal_question_response"].label.contains("Kept the photo estimate"))
        app.terminate()
        let restored = launch("useful-question", reset: false)
        XCTAssertTrue(restored.staticTexts["meal_question_response"].waitForExistence(timeout: 15))
        XCTAssertTrue(restored.staticTexts["meal_question_response"].label.contains("Kept the photo estimate"))
        XCTAssertFalse(restored.buttons["meal_question_skip"].exists)
    }

    @MainActor func testComparisonSurvivesRelaunchAndRecordsRealWorkoutCheckIn() {
        let app = launch("meal-experiments")
        XCTAssertTrue(app.buttons["experiment_routine"].waitForExistence(timeout: 15), app.debugDescription)
        choose("experiment_routine", option: "Upper body", in: app)
        choose("experiment_meal_a", option: "Blueberry Protein Overnight Oats", in: app)
        choose("experiment_meal_b", option: "Weeknight Chicken Power Bowl", in: app)
        XCTAssertTrue(app.buttons["experiment_meal_a"].label.contains("Blueberry Protein Overnight Oats"), "Choosing B must not invalidate recipe A's picker identity.")
        XCTAssertTrue(app.buttons["experiment_meal_b"].label.contains("Weeknight Chicken Power Bowl"))
        let consent = app.buttons["experiment_consent"]
        let start = app.buttons["experiment_start"]
        reveal(start, in: app, requiringHittable: false)
        XCTAssertFalse(start.isEnabled, "Choosing both meals still requires explicit consent.")
        let oats = "Blueberry Protein Overnight Oats"
        let bowl = "Weeknight Chicken Power Bowl"
        for (picker, replacement, original) in [("experiment_meal_a", bowl, oats), ("experiment_meal_b", oats, bowl)] {
            reveal(consent, in: app)
            XCTAssertFalse(consent.isSelected)
            consent.tap()
            XCTAssertTrue(consent.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(start.isEnabled)
            choose(picker, option: replacement, in: app)
            XCTAssertTrue(app.staticTexts["Choose a different meal for A or B."].waitForExistence(timeout: 5))
            reveal(consent, in: app)
            XCTAssertFalse(consent.isSelected, "Changing \(picker) must clear consent.")
            choose(picker, option: original, in: app)
            reveal(start, in: app, requiringHittable: false)
            XCTAssertFalse(start.isEnabled, "Restoring a valid pair still needs fresh consent.")
        }
        reveal(consent, in: app)
        consent.tap()
        XCTAssertTrue(consent.wait(for: \.isSelected, toEqual: true, timeout: 5))
        reveal(start, in: app)
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.staticTexts["experiment_result"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["experiment_result"].label, "Still learning")
        let reminders = app.buttons["experiment_reminder_review"]
        reveal(reminders, in: app); reminders.tap()
        let reminderEnabled = app.switches["reminder_enabled"]
        XCTAssertTrue(reminderEnabled.waitForExistence(timeout: 5))
        XCTAssertEqual(reminderEnabled.value as? String, "0", "Starting a comparison must not opt into reminders.")
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-experiments", "-ui-testing-comparison-workout"]
        app.launch()
        XCTAssertTrue(app.staticTexts["experiment_result"].waitForExistence(timeout: 15))
        let checkIn = app.buttons["experiment_checkin_0"]
        reveal(checkIn, in: app)
        checkIn.tap()
        XCTAssertTrue(app.buttons["experiment_session"].waitForExistence(timeout: 5))
        app.buttons["experiment_session"].tap()
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Date().formatted(date: .abbreviated, time: .omitted))).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        let legacy = app.buttons["experiment_confirm_legacy"]
        XCTAssertTrue(legacy.waitForExistence(timeout: 5), "The legacy fixture must require an explicit program/session confirmation.")
        let energy = app.segmentedControls["checkin_energy"]
        reveal(energy, in: app); energy.buttons["4"].tap()
        let comfort = app.segmentedControls["checkin_comfort"]
        reveal(comfort, in: app); comfort.buttons["5"].tap()
        let save = app.buttons["experiment_save_checkin"]
        reveal(save, in: app, requiringHittable: false)
        XCTAssertFalse(save.isEnabled, "Both ratings are filled; the unconfirmed legacy linkage must still prevent Save.")
        confirmWorkout(legacy, in: app)
        let session = app.buttons["experiment_session"]
        reveal(session, in: app, searchUpWhenMissing: true)
        session.tap()
        app.buttons["Choose the completed session"].tap()
        session.tap()
        option.tap()
        reveal(save, in: app)
        XCTAssertFalse(save.isEnabled, "Re-selecting a legacy session must require a new confirmation.")
        confirmWorkout(legacy, in: app)
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Meal check-in"].waitForNonExistence(timeout: 5))
        let savedStatus = app.staticTexts["experiment_status"]
        reveal(savedStatus, in: app)
        XCTAssertTrue(savedStatus.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(savedStatus.label.contains("Check-in saved"), app.debugDescription)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["experiment_result"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["experiment_checkin_0"].exists)
        XCTAssertEqual(app.staticTexts["experiment_result"].label, "Still learning")
        let correct = app.buttons["experiment_correct_0"]
        reveal(correct, in: app); correct.tap()
        let correctedEnergy = app.segmentedControls["checkin_energy"]
        reveal(correctedEnergy, in: app)
        XCTAssertTrue(correctedEnergy.buttons["4"].isSelected)
        correctedEnergy.buttons["3"].tap()
        let confirm = app.buttons["experiment_confirm_legacy"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirmWorkout(confirm, in: app)
        let saveCorrection = app.buttons["experiment_save_checkin"]
        reveal(saveCorrection, in: app)
        XCTAssertEqual(saveCorrection.label, "Save correction"); saveCorrection.tap()
        XCTAssertTrue(app.navigationBars["Meal check-in"].waitForNonExistence(timeout: 5))
        let corrected = app.staticTexts["experiment_status"]
        reveal(corrected, in: app)
        XCTAssertTrue(corrected.label.contains("Check-in corrected"))
        let export = app.buttons["experiment_export"]
        reveal(export, in: app); XCTAssertTrue(export.isHittable)
        reveal(correct, in: app); correct.tap()
        reveal(app.segmentedControls["checkin_energy"], in: app)
        XCTAssertTrue(app.segmentedControls["checkin_energy"].buttons["3"].isSelected)
        app.navigationBars["Meal check-in"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["experiment_result"].exists)
    }
}
