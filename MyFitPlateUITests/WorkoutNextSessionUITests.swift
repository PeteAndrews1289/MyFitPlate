import XCTest

/// The isolated screenshot account exercises a reviewed one-slot change, never owner data.
@MainActor
final class WorkoutNextSessionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFutureTargetReviewRetainsManualValuesAndUnsubmittedDraftBeforeCheckedSave() {
        let app = launch()
        let review = app.buttons["workout_next_targets_review"]
        reveal(review, in: app.scrollViews["workout_summary"], app: app); review.tap()
        XCTAssertTrue(app.buttons["next_session_review_save"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["next_session_review_save"].isEnabled)
        let movement = app.buttons["next_session_movement_wave2-exercise-0-0"]
        reveal(movement, in: app.scrollViews["next_session_review"], app: app); movement.tap()
        let weight = app.textFields["progression_weight_1"]
        reveal(weight, in: app.collectionViews["progression_targets_form"], app: app); replace(weight, with: "42.5", app: app)
        app.buttons["progression_finish_edit"].tap()
        let reps = app.textFields["progression_reps_1"]
        reveal(reps, in: app.collectionViews["progression_targets_form"], app: app); replace(reps, with: "9", app: app)
        app.buttons["progression_finish_edit"].tap()
        let use = app.buttons["progression_apply"]
        XCTAssertEqual(use.label, "Use in review")
        XCTAssertTrue(use.isEnabled); use.tap()
        let staged = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Your reviewed targets", "42.5 lb × 9")).firstMatch
        XCTAssertTrue(staged.waitForExistence(timeout: 5))
        let saveReview = app.buttons["next_session_review_save"]
        XCTAssertTrue(saveReview.isEnabled); saveReview.tap()
        let saveBlock = app.buttons["block_save"]
        XCTAssertTrue(saveBlock.waitForExistence(timeout: 10), app.debugDescription)
        let target = app.buttons["block_session_40"]
        reveal(target, in: app.scrollViews["workout_block_editor_scroll"], app: app)
        XCTAssertTrue(target.label.contains("Week-specific targets"), "The final review starts on the actual proposed week.")
        XCTAssertEqual(saveBlock.label, "Save block")
        app.buttons["block_close"].tap()
        XCTAssertTrue(staged.waitForExistence(timeout: 5), "Closing the final review keeps manually staged values.")
        saveReview.tap()
        let existing = app.buttons["next_session_existing_draft"]
        reveal(existing, in: app.scrollViews["next_session_review"], app: app); existing.tap()
        XCTAssertTrue(saveBlock.waitForExistence(timeout: 10))
        // Recovery is a persistent state receipt, separate from the latest local checkpoint status.
        let restoredReceipt = any(app, "block_restored_draft")
        reveal(restoredReceipt, in: app.scrollViews["workout_block_editor_scroll"], app: app)
        XCTAssertTrue(restoredReceipt.label.contains("Restored your unfinished block."), app.debugDescription)
        reveal(target, in: app.scrollViews["workout_block_editor_scroll"], app: app)
        XCTAssertTrue(target.label.contains("Week-specific targets"), "An incoming one-slot proposal survives closing and reopening.")
        record(app, "Next session - restored one-slot targets remain unsubmitted")
        saveBlock.tap()
        XCTAssertTrue(saveBlock.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["workout_summary_done"].waitForExistence(timeout: 10))
        app.buttons["workout_summary_done"].tap()
        let overview = app.buttons["train_program_overview"]
        reveal(overview, in: app.scrollViews.firstMatch, app: app); overview.tap()
        let fullProgram = app.buttons["training_full_program"]
        XCTAssertTrue(fullProgram.waitForExistence(timeout: 5)); fullProgram.tap()
        let progress = any(app, "program_progress_summary")
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.label, "39 of 48 sessions passed")
        record(app, "Next session - accepted targets retain PHUL39")
    }

    func testCompletedBlockPrioritizesNextBlockWithoutOfferingAnotherTargetOccurrence() {
        let app = launch(flags: ["-ui-testing-completed-phul"])
        let next = app.buttons["workout_next_block_review"]
        reveal(next, in: app.scrollViews["workout_summary"], app: app)
        XCTAssertFalse(app.buttons["workout_next_targets_review"].exists)
        next.tap()
        XCTAssertTrue(app.buttons["successor_save"].waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "successor_accepted").exists)
        record(app, "Next time - completed block opens existing next-block review")
        app.buttons["successor_close"].tap()
        XCTAssertTrue(app.buttons["workout_summary_done"].waitForExistence(timeout: 5))
    }

    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-summary",
            "-ui-testing-wave2-phul", "-ui-testing-reset-workout-draft", "-ui-testing-reset-editor-drafts"] + flags
        app.launch()
        if !app.buttons["workout_summary_done"].waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(app.buttons["workout_summary_done"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        if (field.value as? String) != value {
            field.press(forDuration: 1)
            let selectAll = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
            if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
            field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        }
        XCTAssertEqual(field.value as? String, value, "The driver must replace the whole value before reviewing it.")
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<18 {
            let bounds = scroll.frame.intersection(app.frame)
            let top = max(bounds.minY + 12, 110.0)
            let bottom = min(bounds.maxY - 12, app.frame.maxY - 105)
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let moveDown = element.exists && element.frame.minY < top
            let distance = element.exists ? min(180, max(60, abs(element.frame.midY - (top + bottom) / 2))) : 180
            let startY = moveDown ? top + 24 : bottom - 24
            let endY = moveDown ? min(bottom - 24, startY + distance) : max(top + 24, startY - distance)
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: bounds.midX - scroll.frame.minX, dy: startY - scroll.frame.minY))
            let end = origin.withOffset(CGVector(dx: bounds.midX - scroll.frame.minX, dy: endY - scroll.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let bounds = scroll.frame.intersection(app.frame)
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(element.frame.minY, max(bounds.minY + 12, 110), "The control must clear the sheet header before tapping.")
        XCTAssertLessThanOrEqual(element.frame.maxY, min(bounds.maxY - 12, app.frame.maxY - 105), "The control must clear the persistent footer before tapping.")
    }

    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
