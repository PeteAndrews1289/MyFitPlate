import XCTest

@MainActor
final class WaveFourWorkoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEarlyNextSetGetsItsOwnRestAndReopeningEarlierSetKeepsThatRest() {
        let app = launch()
        let initial = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        let firstID = initial.identifier
        let first = app.buttons[firstID]
        let firstRow = row(firstID, app: app)
        let weight = firstRow.textFields["set_weight_1"].firstMatch.value as? String
        let reps = firstRow.textFields["set_reps_1"].firstMatch.value as? String
        reveal(first, app: app); first.tap()
        waitValue(first, "Completed")
        let rest = any(app, "workout_rest_timer")
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        for _ in 0..<3 { app.buttons["workout_rest_add"].tap() }
        let extendedDeadline = deadline(rest)

        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' AND value == 'Not completed'")).firstMatch
        let nextID = next.identifier
        reveal(next, app: app); next.tap()
        waitValue(app.buttons[nextID], "Completed")
        XCTAssertTrue(rest.exists)
        let nextDeadline = deadline(rest)
        XCTAssertLessThan(nextDeadline, extendedDeadline - 10,
                          "A new completed set starts its full rest instead of inheriting the previous +90s rest.")
        XCTAssertEqual(firstRow.textFields["set_weight_1"].firstMatch.value as? String, weight)
        XCTAssertEqual(firstRow.textFields["set_reps_1"].firstMatch.value as? String, reps)

        reveal(first, app: app); first.tap()
        waitValue(first, "Not completed")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "workout_input_context").label.contains("Reps"))
        XCTAssertEqual(deadline(rest), nextDeadline, accuracy: 2,
                       "Editing an earlier set must leave the later set's rest unchanged.")
        let input = firstRow.textFields["set_reps_1"].firstMatch
        XCTAssertTrue(input.isHittable)
        XCTAssertTrue(any(app, "workout_focused_header").exists)
        XCTAssertFalse(app.buttons["workout_finish"].exists)
        XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY)
        replace(input, with: "9", app: app)
        app.buttons["workout_rest_skip"].tap()
        XCTAssertTrue(rest.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Skipping rest must not dismiss the active input.")
        XCTAssertEqual(input.value as? String, "9")
        app.buttons["workout_input_increase"].tap()
        XCTAssertEqual(input.value as? String, "10", "The keyboard command still targets the edited reps.")
        app.buttons["workout_input_complete"].tap()
        waitValue(first, "Completed")
        XCTAssertEqual(input.value as? String, "10")
        XCTAssertEqual(app.buttons[nextID].value as? String, "Completed")
        XCTAssertTrue(rest.waitForExistence(timeout: 5), "A deliberate correction can start its own fresh rest.")
        record(app, "Wave 4 - early set rest and deliberate correction")
    }

    func testFocusedFieldStaysVisibleAndRestSkipDoesNotLoseTyping() {
        let app = launch()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        reveal(first, app: app); first.tap()
        waitValue(first, "Completed")
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' AND value == 'Not completed'")).firstMatch
        let nextID = next.identifier
        let input = row(nextID, app: app).textFields.firstMatch
        reveal(input, app: app); input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let header = any(app, "workout_focused_header")
        XCTAssertTrue(header.exists)
        XCTAssertLessThanOrEqual(header.frame.height, 64)
        XCTAssertTrue(app.buttons["workout_rest_add"].isHittable)
        XCTAssertTrue(app.buttons["workout_rest_skip"].isHittable)
        XCTAssertGreaterThanOrEqual(input.frame.minY, any(app, "workout_player").scrollViews.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(input.frame.maxY, any(app, "workout_input_context").frame.minY)
        replace(input, with: "45", app: app)
        app.buttons["workout_rest_skip"].tap()
        XCTAssertTrue(any(app, "workout_rest_completion").waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(input.value as? String, "45")
        app.buttons["workout_input_next"].tap()
        XCTAssertTrue(any(app, "workout_input_context").label.contains("Reps"))
        XCTAssertEqual(app.buttons[nextID].value as? String, "Not completed")
        record(app, "Wave 4 - compact header and typing through rest skip")
        app.buttons["workout_input_done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workout_finish"].exists)
        XCTAssertEqual(input.value as? String, "45")
    }

    func testUndoWhileTypingReturnsToUndoneRepsWithoutLoggingNextSet() {
        let app = launch()
        let initial = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        let firstID = initial.identifier
        let first = app.buttons[firstID]
        let firstRow = row(firstID, app: app)
        let firstWeight = firstRow.textFields["set_weight_1"].firstMatch.value as? String
        let originalReps = Int(firstRow.textFields["set_reps_1"].firstMatch.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(originalReps, 0)
        reveal(first, app: app); first.tap()
        waitValue(first, "Completed")

        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' AND value == 'Not completed'")).firstMatch
        let nextID = next.identifier
        let nextRow = row(nextID, app: app)
        let nextWeight = nextRow.textFields.firstMatch
        replace(nextWeight, with: "45", app: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["workout_undo_set"].tap()

        waitValue(first, "Not completed")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let context = any(app, "workout_input_context")
        XCTAssertTrue(context.label.contains("Set 1"))
        XCTAssertTrue(context.label.contains("Reps"))
        let reopenedReps = firstRow.textFields["set_reps_1"].firstMatch
        XCTAssertTrue(reopenedReps.isHittable)
        XCTAssertLessThanOrEqual(reopenedReps.frame.maxY, context.frame.minY)
        XCTAssertEqual(firstRow.textFields["set_weight_1"].firstMatch.value as? String, firstWeight)
        XCTAssertEqual(nextWeight.value as? String, "45", "Undo preserves the later set's typed load.")
        XCTAssertEqual(app.buttons[nextID].value as? String, "Not completed")

        app.buttons["workout_input_increase"].tap()
        XCTAssertEqual(reopenedReps.value as? String, String(originalReps + 1),
                       "Undo retargets keyboard commands to the reopened set's reps.")
        XCTAssertEqual(first.value as? String, "Not completed", "Editing after Undo must not log a set.")
        XCTAssertEqual(app.buttons[nextID].value as? String, "Not completed")
        app.buttons["workout_input_complete"].tap()
        waitValue(first, "Completed")
        XCTAssertEqual(app.buttons[nextID].value as? String, "Not completed")
        XCTAssertEqual(nextWeight.value as? String, "45")
    }

    func testExerciseMenuBrowsesLaterLiftAndReturnsToCurrentSet() {
        let app = launch()
        let menu = app.buttons["workout_exercise_menu"]
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise_options_'"))
        XCTAssertGreaterThan(options.count, 2)
        let later = app.buttons["Options for Dumbbell Shoulder Press"]
        XCTAssertTrue(later.exists)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_'")).firstMatch
        let active = app.staticTexts["workout_current_exercise"]
        let original = active.label
        XCTAssertFalse(later.isHittable)
        menu.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3. Dumbbell Shoulder Press")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        record(app, "Workout - exercise jump menu")
        choice.tap()
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: later)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        XCTAssertEqual(active.label, original)
        app.buttons["workout_current_set"].tap()
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertEqual(first.value as? String, "Not completed")
        XCTAssertFalse(app.buttons["workout_undo_set"].exists)
    }

    func testDoLaterSurvivesRelaunchAndFinishingCanReturnToParkedLift() {
        let app = launch()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_'")).firstMatch
        let set = app.buttons[first.identifier]; reveal(set, app: app); set.tap()
        waitValue(set, "Completed")
        let options = app.buttons["Options for Dumbbell Bench Press"]
        reveal(options, app: app); options.tap(); app.buttons["Do Later"].tap()
        let active = app.staticTexts["workout_current_exercise"]
        XCTAssertEqual(active.label, "Dumbbell Row")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-workout-draft" }
        app.launch()
        XCTAssertTrue(active.waitForExistence(timeout: 15)); XCTAssertEqual(active.label, "Dumbbell Row")
        app.buttons["workout_finish"].tap()
        let restore = app.buttons["Return to Dumbbell Bench Press"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        XCTAssertEqual(active.label, "Dumbbell Bench Press")
        XCTAssertEqual(set.value as? String, "Completed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'resume_parked_'")).firstMatch.exists)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
            "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-auto-rest"]
        app.launch()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        if !first.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.isEnabled)
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func row(_ completeID: String, app: XCUIApplication) -> XCUIElement {
        any(app, "strength_set_row_" + completeID.replacingOccurrences(of: "set_complete_", with: ""))
    }

    private func waitValue(_ element: XCUIElement, _ value: String) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 5), .completed)
    }

    private func deadline(_ element: XCUIElement) -> TimeInterval {
        let parts = (element.value as? String ?? "").split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else {
            XCTFail("Missing valid rest countdown"); return 0
        }
        return Date().timeIntervalSince1970 + Double(minutes * 60 + seconds)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            let viewport = any(app, "workout_player").scrollViews.firstMatch.frame
            let top = viewport.minY + 3
            let bottom = min(viewport.maxY, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : viewport.maxY) - 3
            let rect = element.exists ? element.frame : .zero
            if element.exists && element.isHittable && rect.minY >= top && rect.maxY <= bottom { return }
            let above = element.exists && rect.minY < top
            let startY = (top + bottom) / 2
            let amount = min(110, (bottom - top) * 0.35)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.maxX - 12, dy: startY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: viewport.maxX - 12, dy: startY + (above ? amount : -amount))), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        if (field.value as? String) != value {
            field.press(forDuration: 1)
            let select = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
            if select.waitForExistence(timeout: 2) { select.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
            field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        }
        XCTAssertEqual(field.value as? String, value)
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
