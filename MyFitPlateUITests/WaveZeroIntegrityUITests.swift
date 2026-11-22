import XCTest

final class WaveZeroIntegrityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLegacyPHULWorkoutKeepsSetsAndRequiresExplicitProgramChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train",
                               "-ui-testing-legacy-program-draft"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        let canResume = resume.waitForExistence(timeout: 15)
        record(app, "Legacy PHUL - recovered diary state")
        XCTAssertTrue(canResume, app.debugDescription)
        let nextStep = app.descendants(matching: .any)["train_next_step"].firstMatch
        resume.tap()
        XCTAssertTrue(app.staticTexts["workout_resumed"].waitForExistence(timeout: 5))
        let completedSet = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' AND value == 'Completed'")).firstMatch
        XCTAssertTrue(completedSet.waitForExistence(timeout: 5))
        let completedSetID = completedSet.identifier
        app.buttons["Finish Workout"].tap()
        app.buttons["Finish Anyway"].tap()
        let count = app.buttons["workout_legacy_count_screenshot_demo_program_5"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(count.label.contains("PHUL"))
        XCTAssertTrue(count.label.contains("Week 2, Day 2"))
        XCTAssertTrue(app.buttons["workout_legacy_save_standalone"].exists)
        record(app, "Legacy PHUL - explicit program choice")
        app.buttons["Keep Workout Open"].firstMatch.tap()
        XCTAssertEqual(app.buttons[completedSetID].value as? String, "Completed")
        app.buttons["Finish Workout"].tap()
        app.buttons["Finish Anyway"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        count.tap()
        let done = app.buttons["workout_summary_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
        record(app, "Legacy PHUL - accepted completion")
        done.tap()
        XCTAssertTrue(app.staticTexts["train_screen_header"].firstMatch.waitForExistence(timeout: 5))
        let recoveryCleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["workout_resume"])
        XCTAssertEqual(XCTWaiter.wait(for: [recoveryCleared], timeout: 10), .completed)
        for _ in 0..<10 where !nextStep.staticTexts["Week 2 · Day 3"].exists {
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3)))
        }
        XCTAssertTrue(nextStep.staticTexts["Week 2 · Day 3"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        XCTAssertTrue(app.staticTexts["train_screen_header"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["workout_resume"].exists, "Accepted legacy completion must not return as an unfinished draft")
    }

    @MainActor
    func testTextReviewSurvivesRejectedSaveAndRelaunchThenRetries() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "ai-text-results",
                               "-ui-testing-reset-editor-drafts", "-ui-testing-food-save-failure"]
        app.launch()
        let save = app.buttons["ai_text_log_action"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        let destination = app.staticTexts["ai_review_destination"].label
        let firstItem = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'ai_review_item_'")).firstMatch
        for _ in 0..<8 where !firstItem.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(firstItem.exists, app.debugDescription)
        let originalItemID = firstItem.identifier
        save.tap()
        XCTAssertTrue(app.staticTexts["ai_text_save_error"].waitForExistence(timeout: 8))
        XCTAssertEqual(save.label, "Retry saving")
        record(app, "Text review - failed save retained")

        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "ai-text-results"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Unfinished review restored"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["ai_review_destination"].label, destination)
        let restoredItem = app.descendants(matching: .any)[originalItemID].firstMatch
        for _ in 0..<8 where !restoredItem.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(restoredItem.exists, app.debugDescription)
        XCTAssertEqual(app.buttons["ai_text_log_action"].label, "Retry saving")
        app.buttons["ai_text_log_action"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["ai_text_log_action"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        record(app, "Text review - accepted retry")
    }

    @MainActor
    func testActualDiaryActivityEditKeepsFailedCorrection() {
        let app = openActivityEditor(rejectSave: true)
        replaceCalories("123.5", in: app)
        app.buttons["manual_exercise_save"].tap()
        XCTAssertTrue(app.staticTexts["manual_exercise_save_error"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["manual_exercise_save"].exists)
        XCTAssertEqual(app.textFields["manual_exercise_calories"].value as? String, "123.5")
        XCTAssertTrue(app.staticTexts["Corrections stay on this activity's original day."].exists)
        record(app, "Activity edit - failed correction retained")
    }

    @MainActor
    func testActualDiaryActivityEditAcceptsCorrection() {
        let app = openActivityEditor(rejectSave: false)
        replaceCalories("123.5", in: app)
        app.buttons["manual_exercise_save"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["manual_exercise_save"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
        let edit = app.buttons["past_workout_edit_entry"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textFields["manual_exercise_calories"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["manual_exercise_calories"].value as? String, "123.5")
        record(app, "Activity edit - accepted value reopened")
    }

    @MainActor
    private func openActivityEditor(rejectSave: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home"]
        if rejectSave { app.launchArguments.append("-ui-testing-food-save-failure") }
        app.launch()
        XCTAssertTrue(app.scrollViews["home_scroll"].waitForExistence(timeout: 15))
        let activity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'diary_activity_' AND label CONTAINS 'Upper Body Strength'")).firstMatch
        for _ in 0..<22 {
            if activity.exists, activity.isHittable, activity.frame.maxY < app.frame.maxY - 100 { break }
            let scroll = app.scrollViews["home_scroll"]
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(activity.isHittable, app.debugDescription)
        activity.tap()
        let edit = app.buttons["past_workout_edit_entry"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), app.debugDescription)
        edit.tap()
        XCTAssertTrue(app.textFields["manual_exercise_calories"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func replaceCalories(_ value: String, in app: XCUIApplication) {
        let field = app.textFields["manual_exercise_calories"]
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        let done = app.buttons["Done"].firstMatch
        if done.exists { done.tap() }
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
