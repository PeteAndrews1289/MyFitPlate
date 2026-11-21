import XCTest

final class EliteWorkoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLongTermTrendExplainsPlateauAndOpensLighterWeekReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-long-term-trend"]
        app.launch()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        reveal(review, app: app); review.tap()
        XCTAssertTrue(app.staticTexts["Holding steady"].waitForExistence(timeout: 8))
        let lighter = app.buttons["progression_lighter_week"]
        reveal(lighter, app: app)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Workout - longer-term progress"; evidence.lifetime = .keepAlways; add(evidence)
        lighter.tap()
        let reason = app.buttons["rescue_reason_A lighter training week"]
        XCTAssertTrue(reason.waitForExistence(timeout: 8))
        XCTAssertTrue(reason.isSelected)
        XCTAssertTrue(app.buttons["rescue_primary"].exists)
    }

    @MainActor
    func testReviewedTargetsCanCancelApplyUndoAndSurviveResume() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"]
        app.terminate()
        app.launch()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 15), app.debugDescription)
        let weight = app.textFields.matching(identifier: "set_weight_1").firstMatch
        reveal(weight, app: app)
        let original = weightValue(weight)
        reveal(review, app: app)
        review.tap()
        let target = app.textFields["progression_weight_1"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        reveal(target, app: app)
        replace(target, with: "", in: app)
        let finish = app.buttons["progression_finish_edit"]
        let done = finish.exists ? finish : app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.buttons["progression_apply"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["progression_apply"].isEnabled, "Target field after clearing: \(String(describing: target.value))")
        app.buttons["Cancel"].tap()
        reveal(weight, app: app)
        XCTAssertEqual(weightValue(weight), original)

        for attempt in 0..<2 {
            reveal(review, app: app)
            review.tap()
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            reveal(target, app: app)
            replace(target, with: "137.5", in: app)
            app.buttons["Done"].firstMatch.tap()
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = "Workout target review"
            evidence.lifetime = .keepAlways
            add(evidence)
            app.buttons["progression_apply"].tap()
            reveal(weight, app: app)
            XCTAssertEqual(weight.value as? String, "137.5")
            if attempt == 0 {
                let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_undo_' ")).firstMatch
                reveal(undo, app: app)
                undo.tap()
                reveal(weight, app: app)
                XCTAssertEqual(weightValue(weight), original)
            }
        }
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        reveal(weight, app: app)
        XCTAssertEqual(weight.value as? String, "137.5")
    }

    @MainActor
    func testPreviousWorkoutLoadFailureKeepsSetEntryAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-history-load-failure"]
        app.terminate()
        app.launch()
        let retry = app.buttons["workout_history_retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch.exists)
        let complete = firstComplete(app)
        reveal(complete, app: app)
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        reveal(retry, app: app)
        retry.tap()
        XCTAssertTrue(retry.isEnabled)
        reveal(complete, app: app)
        XCTAssertEqual(complete.value as? String, "Completed")
    }

    @MainActor
    func testSkippingRequiresConfirmationAndCancelKeepsProgramPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"]
        app.launch()
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let position = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Session ' AND label CONTAINS ' of '")).firstMatch
        let before = position.label
        app.buttons["workout_slot_options"].firstMatch.tap()
        app.buttons["Skip"].tap()
        let keep = app.buttons["Keep current plan"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertTrue(start.isEnabled)
        XCTAssertEqual(position.label, before)
    }

    @MainActor
    func testCompactSetEntryAndExpandedControlsSurviveWorkoutResume() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"]
        app.launch()
        let weight = app.textFields.matching(identifier: "set_weight_1").firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        reveal(weight, app: app)
        replace(weight, with: "137.5", in: app)
        let reps = app.textFields.matching(identifier: "set_reps_1").firstMatch
        replace(reps, with: "9", in: app)
        app.buttons["Done"].firstMatch.tap()
        let complete = firstComplete(app)
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let controls = app.buttons["set_details_" + setID]
        reveal(controls, app: app); controls.tap()
        reveal(complete, app: app)
        let effort = app.buttons["Rate of perceived exertion"].firstMatch
        reveal(effort, app: app)
        XCTAssertTrue(effort.waitForExistence(timeout: 5))
        app.buttons["Collapse set controls"].firstMatch.tap()
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Workout - compact set entry"
        evidence.lifetime = .keepAlways
        add(evidence)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        XCTAssertTrue(app.buttons["workout_resume"].waitForExistence(timeout: 10))
        app.buttons["workout_resume"].tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        reveal(weight, app: app)
        XCTAssertEqual(weight.value as? String, "137.5")
        XCTAssertEqual(reps.value as? String, "9")
        XCTAssertEqual(complete.value as? String, "Completed")
    }

    @MainActor
    func testLargeTextSetControlsAndCompletionRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-screenshot-dark-mode",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.terminate()
        app.launch()
        let fixture = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        // The first cold OS launch was observed with zero argv, ignoring every fixture
        // and text-size argument. Relaunch the now-running process once only for that
        // specific Welcome state; actual logger assertions below never retry.
        if !fixture.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        let complete = firstComplete(app)
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        reveal(complete, app: app)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Workout - largest text completion"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertTrue(complete.isHittable, "Completion control frame: \(complete.frame)")
        complete.tap()
        XCTAssertEqual(complete.value as? String, "Completed")
    }

    @MainActor
    private func weightValue(_ field: XCUIElement) -> Double? {
        guard let text = field.value as? String else { return nil }
        // A fresh zero uses an empty field with a "0" placeholder. After an
        // external update (including Undo), the same zero can be displayed.
        return text.isEmpty ? 0 : Double(text)
    }

    @MainActor
    private func firstComplete(_ app: XCUIApplication) -> XCUIElement {
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        return app.buttons[candidate.identifier]
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, in app: XCUIApplication) {
        reveal(field, app: app); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        guard !hasValue(value, field: field) else { return }
        // Some simulator keyboard configurations ignore Command-A. Use the same
        // native selection action a person uses, then verify the resulting entry.
        field.press(forDuration: 1)
        let selectAll = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        XCTAssertTrue(hasValue(value, field: field), "Expected \(value), actual \(String(describing: field.value))")
    }

    @MainActor
    private func hasValue(_ expected: String, field: XCUIElement) -> Bool {
        let actual = field.value as? String ?? ""
        return actual == expected || (expected.isEmpty && actual == (field.placeholderValue ?? ""))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication, preferEarlier: Bool = false) {
        var searchEarlier = preferEarlier
        var missingSteps = 0
        var searchLeg = 2
        for _ in 0..<16 {
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            if exists, element.isHittable,
               frame.minY >= app.frame.minY + 105, frame.maxY < app.frame.maxY - 90 { return }
            let above: Bool
            if exists && !frame.isEmpty {
                above = frame.midY < app.frame.midY
                searchEarlier = above
                missingSteps = 0
            } else {
                // Form virtualizes offscreen rows. Sweep both ways with growing
                // legs instead of repeatedly scrolling away from an absent row.
                above = searchEarlier
                missingSteps += 1
                if missingSteps == searchLeg {
                    missingSteps = 0
                    searchEarlier.toggle()
                    searchLeg += 2
                }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.30 : 0.73))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.63 : 0.40)))
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
}
