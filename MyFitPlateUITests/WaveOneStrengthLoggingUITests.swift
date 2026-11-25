import XCTest

final class WaveOneStrengthLoggingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testClearedLoadAndRepsRequireCorrectionWhileExplicitZeroStillLogs() {
        let app = launch()
        let complete = firstCompletion(app)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let row = element(app, "strength_set_row_" + setID)
        let weight = row.textFields["set_weight_1"].firstMatch
        let reps = row.textFields["set_reps_1"].firstMatch

        replace(weight, with: "135", app: app)
        replace(reps, with: "9", app: app)
        erase(weight, app: app)
        app.buttons["workout_input_complete"].tap()
        let error = element(app, "set_entry_error_" + setID)
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("valid load"))
        XCTAssertEqual(complete.value as? String, "Not completed",
                       "A cleared load cannot silently log the last accepted 135 lb or prior history")
        XCTAssertTrue(element(app, "workout_input_context").label.contains("Load in"))

        replace(weight, with: "0", app: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertEqual(weight.value as? String, "0")
        XCTAssertEqual(reps.value as? String, "9")
        XCTAssertFalse(weight.isEnabled)

        reveal(complete, app: app); complete.tap()
        erase(reps, app: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("at least one rep"))
        XCTAssertEqual(complete.value as? String, "Not completed",
                       "A deliberately cleared rep count cannot reuse the recorded or previous count")
        XCTAssertTrue(element(app, "workout_input_context").label.contains("Reps"))
        XCTAssertEqual(weight.value as? String, "0")
        record(app, "Strength - cleared reps require correction")

        replace(reps, with: "7", app: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertEqual(weight.value as? String, "0")
        XCTAssertEqual(reps.value as? String, "7")
        XCTAssertFalse(reps.isEnabled)
    }

    @MainActor
    func testInputBrowsingKeepsInvalidTextAndOnlyLogCompletesTheSet() {
        let app = launch()
        let complete = firstCompletion(app)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let row = element(app, "strength_set_row_" + setID)
        let weight = row.textFields["set_weight_1"].firstMatch
        let reps = row.textFields["set_reps_1"].firstMatch
        replace(weight, with: ".", app: app)
        assertKeyboardCommandBounds(app)
        XCTAssertFalse(app.buttons["workout_input_previous"].isEnabled)
        let beforeReps = reps.value as? String
        app.buttons["workout_input_next"].tap()
        XCTAssertTrue(element(app, "workout_input_context").label.contains("Reps"))
        app.typeText("9")
        XCTAssertNotEqual(reps.value as? String, beforeReps, "Next must move the actual keyboard responder")
        XCTAssertEqual(weight.value as? String, ".", "Invalid weight text must survive input traversal")
        XCTAssertEqual(complete.value as? String, "Not completed")
        app.buttons["workout_input_previous"].tap()
        XCTAssertTrue(element(app, "workout_input_context").label.contains("Load in"))
        XCTAssertEqual(weight.value as? String, ".")
        app.buttons["workout_input_complete"].tap()
        XCTAssertTrue(element(app, "set_entry_error_" + setID).waitForExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "Not completed", "Browsing or rejected input cannot log a set")
        record(app, "Strength - invalid input retained while browsing")

        replace(weight, with: "135", app: app)
        app.buttons["workout_input_next"].tap()
        replace(reps, with: "9", app: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertEqual(weight.value as? String, "135")
        XCTAssertEqual(reps.value as? String, "9")
        XCTAssertFalse(weight.isEnabled)
        XCTAssertTrue(element(app, "set_logged_" + setID).exists)
    }

    @MainActor
    func testCompletedRowSettlesAndExplicitEditPreservesItsRecordedValues() {
        let app = launch()
        let complete = firstCompletion(app)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let row = element(app, "strength_set_row_" + setID)
        let details = app.buttons["set_details_" + setID]
        reveal(details, app: app); details.tap()
        let weight = row.textFields["set_weight_1"].firstMatch
        let reps = row.textFields["set_reps_1"].firstMatch
        reveal(weight, app: app)
        assertExpandedInputGeometry(weight, app: app)
        replace(weight, with: "135", app: app)
        reveal(reps, app: app)
        assertExpandedInputGeometry(reps, app: app)
        replace(reps, with: "9", app: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertFalse(details.exists, "A completed row should settle without overwrite controls")
        XCTAssertTrue(complete.label.contains("Reopen"))
        XCTAssertFalse(weight.isEnabled)
        XCTAssertFalse(reps.isEnabled)
        XCTAssertFalse(element(app, "set_type_" + setID).isEnabled)

        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' AND value == 'Not completed'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let nextID = next.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let nextWeight = element(app, "strength_set_row_" + nextID).textFields.firstMatch
        replace(nextWeight, with: "70", app: app)
        app.buttons["workout_input_done"].tap()
        XCTAssertEqual(weight.value as? String, "135")
        XCTAssertEqual(reps.value as? String, "9")
        XCTAssertEqual(complete.value as? String, "Completed")
        reveal(complete, app: app); complete.tap()
        XCTAssertEqual(complete.value as? String, "Not completed")
        XCTAssertTrue(weight.isEnabled)
        XCTAssertTrue(reps.isEnabled)
        XCTAssertEqual(weight.value as? String, "135", "Explicit Edit must keep the recorded load")
        XCTAssertEqual(reps.value as? String, "9")
        // Reopening restores editable compact inputs; secondary controls remain
        // available through the row inspector instead of opening automatically.
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        reveal(details, app: app); details.tap()
        let setType = element(app, "set_type_" + setID)
        XCTAssertTrue(setType.waitForExistence(timeout: 5))
        XCTAssertTrue(setType.isEnabled)
        XCTAssertEqual(weight.value as? String, "135")
        XCTAssertEqual(reps.value as? String, "9")
        XCTAssertEqual(complete.value as? String, "Not completed")
        record(app, "Strength - settled row and deliberate edit")
    }

    @MainActor
    func testLargestTextKeyboardCommandsRemainReachableWithoutLoggingOnNext() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let complete = firstCompletion(app)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let weight = element(app, "strength_set_row_" + setID).textFields["set_weight_1"].firstMatch
        reveal(weight, app: app); weight.tap()
        let next = app.buttons["workout_input_next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        assertKeyboardCommandBounds(app)
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(element(app, "strength_set_row_" + setID).textFields["set_reps_1"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["workout_input_previous"].isHittable)
        XCTAssertTrue(app.buttons["workout_input_complete"].isHittable)
        XCTAssertTrue(app.buttons["workout_input_done"].isHittable)
        XCTAssertEqual(complete.value as? String, "Not completed")
        record(app, "Strength - large text keyboard commands")
        app.buttons["workout_input_done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "Not completed")
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"] + flags
        app.launch()
        let fixture = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_'")).firstMatch
        if !fixture.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        return app
    }

    @MainActor
    private func firstCompletion(_ app: XCUIApplication) -> XCUIElement {
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        return result
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func assertKeyboardCommandBounds(_ app: XCUIApplication) {
        for suffix in ["previous", "decrease", "increase", "next", "complete", "done"] {
            let button = app.buttons["workout_input_" + suffix]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX - 1, suffix)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX + 1, suffix)
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.5, suffix)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, suffix)
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            let scroll = app.scrollViews.firstMatch
            let viewport = scroll.frame
            let top = viewport.minY + 4
            let bottom = (app.keyboards.firstMatch.exists
                          ? min(viewport.maxY, app.keyboards.firstMatch.frame.minY) : viewport.maxY) - 4
            let target = element.exists ? element.frame : .zero
            // Hittable can still mean a partly clipped field. Keep the entire input
            // inside the measured viewport before editing or checking its geometry.
            if element.exists, element.isHittable, target.minY >= top, target.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let above = element.exists && target.minY < top
            let gap = element.exists ? (above ? top - target.minY : target.maxY - bottom) : 80
            let distance = min(max(gap + 12, 35), min(110, (bottom - top) * 0.4))
            let startY = (top + bottom) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.maxX - 12, dy: startY))
            let end = origin.withOffset(CGVector(dx: viewport.maxX - 12, dy: startY + (above ? distance : -distance)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)\n\(app.debugDescription)")
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        guard (field.value as? String) != value else { return }
        field.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor
    private func erase(_ field: XCUIElement, app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
    }

    @MainActor
    private func assertExpandedInputGeometry(_ field: XCUIElement, app: XCUIApplication) {
        let viewport = app.scrollViews.firstMatch.frame
        let lowerEdge = app.keyboards.firstMatch.exists ? min(viewport.maxY, app.keyboards.firstMatch.frame.minY) : viewport.maxY
        XCTAssertTrue(field.isHittable)
        XCTAssertGreaterThanOrEqual(field.frame.width, 44, "Expanded numeric input must retain a usable hit width")
        XCTAssertGreaterThanOrEqual(field.frame.minY, viewport.minY)
        XCTAssertLessThanOrEqual(field.frame.maxY, lowerEdge, "The complete numeric field must be visible above the keyboard")
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
