import XCTest

final class StrengthExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testEquipmentRestrictsReviewedTargetsAndKeyboardWeightSteps() {
        let app = launch()
        let equipment = equipmentButton(app)
        open(equipment, in: app)
        setAvailableWeights("25 30 35 40 45 50 55 60", in: app)
        saveEquipment(in: app)

        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch
        open(review, in: app)
        let target = app.textFields["progression_weight_1"]
        replace(target, with: "42.5", in: app)
        dismissTargetKeyboard(app)
        XCTAssertFalse(app.buttons["progression_apply"].isEnabled, "Targets must fit the selected equipment")
        replace(target, with: "45", in: app)
        dismissTargetKeyboard(app)
        XCTAssertTrue(app.buttons["progression_apply"].isEnabled)
        app.buttons["Cancel"].tap()

        let weight = firstWeight(app)
        let complete = firstComplete(app)
        replace(weight, with: "40", in: app)
        app.buttons["workout_input_increase"].tap()
        XCTAssertEqual(numericValue(weight), 45)
        app.buttons["workout_input_decrease"].tap()
        XCTAssertEqual(numericValue(weight), 40)
        app.buttons["workout_input_next"].tap()
        let reps = firstReps(app)
        let before = numericValue(reps) ?? 0
        app.buttons["workout_input_increase"].tap()
        XCTAssertEqual(numericValue(reps), before + 1)
        XCTAssertEqual(numericValue(weight), 40)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertFalse(equipment.isEnabled, "Completed sets retain their equipment interpretation")
        attach(app, "Strength - equipment steps and completed set")
    }

    @MainActor
    func testTargetWeightKeepsKeyboardFocusWhenValidationChanges() {
        let app = launch()
        open(equipmentButton(app), in: app)
        setAvailableWeights("25 30 35 40 45 50 55 60", in: app)
        saveEquipment(in: app)
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch
        open(review, in: app)
        XCTAssertTrue(app.buttons["progression_apply"].isEnabled, "The edit must start with valid suggested targets")
        let target = app.textFields["progression_weight_1"]
        replace(target, with: "40", in: app)
        XCTAssertTrue(app.buttons["progression_finish_edit"].exists)

        // These app-level keystrokes must keep using the existing responder. A
        // field.typeText or replacement helper could silently tap/refocus it.
        app.typeText("6")
        XCTAssertEqual(target.value as? String, "406")
        app.typeText("0")
        XCTAssertEqual(target.value as? String, "4060", "Validation must not interrupt a multi-digit edit")
        dismissTargetKeyboard(app)
        XCTAssertFalse(app.buttons["progression_apply"].isEnabled)
        attach(app, "Strength - target validation preserves typing focus")
    }

    @MainActor
    func testCompletedSetRequiresReopeningBeforeEditingOrUsingLastPerformance() {
        let app = launch()
        let weight = firstWeight(app), reps = firstReps(app)
        let complete = firstComplete(app)
        let setID = complete.identifier.replacingOccurrences(of: "set_complete_", with: "")
        let useLast = app.buttons["set_use_last_" + setID]
        open(useLast, in: app)
        XCTAssertEqual(numericValue(weight), 38)
        XCTAssertEqual(numericValue(reps), 12)
        replace(weight, with: "135", in: app)
        replace(reps, with: "9", in: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        reveal(complete, in: app)
        XCTAssertFalse(weight.isEnabled)
        XCTAssertFalse(reps.isEnabled)
        XCTAssertFalse(useLast.exists, "Completed results must not expose an overwrite shortcut")
        XCTAssertEqual(numericValue(weight), 135)
        XCTAssertEqual(numericValue(reps), 9)

        complete.tap()
        XCTAssertEqual(complete.value as? String, "Not completed")
        XCTAssertTrue(weight.isEnabled)
        XCTAssertTrue(reps.isEnabled)
        open(useLast, in: app)
        XCTAssertEqual(numericValue(weight), 38, "Use last must explicitly copy the prior load")
        XCTAssertEqual(numericValue(reps), 12, "Use last must explicitly copy the prior reps")
        XCTAssertEqual(complete.value as? String, "Not completed", "Copying history must not log a set")
        attach(app, "Strength - completed set protected and explicitly reopened")
    }

    @MainActor
    func testReviewedTargetEditsSurviveLighterSuggestionAndCanBeReset() {
        let app = launch()
        let complete = firstComplete(app)
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progression_review_' ")).firstMatch
        open(review, in: app)
        let weight = app.textFields["progression_weight_1"]
        let reps = app.textFields["progression_reps_1"]
        let untouchedWeight = app.textFields["progression_weight_2"]
        reveal(untouchedWeight, in: app)
        XCTAssertEqual(numericValue(untouchedWeight), 43)
        replace(weight, with: "135", in: app)
        replace(reps, with: "9", in: app)
        dismissTargetKeyboard(app)
        let lighter = app.switches["progression_lighter"]
        reveal(lighter, in: app, preferEarlier: true)
        recordLighterSwitchDiagnostics(in: app)
        let nativeSwitch = lighter.descendants(matching: .switch).firstMatch
        let switchToTap = nativeSwitch.exists ? nativeSwitch : lighter
        // Interact with the native switch rather than the surrounding form label.
        switchToTap.press(forDuration: 0.2)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: lighter)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed,
                       "The visible lighter switch should turn on after one tap. \(switchToTap.debugDescription)")
        XCTAssertEqual(lighter.value as? String, "1")
        let reset = app.buttons["progression_reset_edits"]
        XCTAssertTrue(reset.isEnabled)
        reveal(weight, in: app)
        XCTAssertEqual(numericValue(weight), 135)
        XCTAssertEqual(numericValue(reps), 9)
        reveal(untouchedWeight, in: app)
        XCTAssertEqual(numericValue(untouchedWeight), 35, "Untouched targets must still receive the lighter suggestion")

        reveal(reset, in: app, preferEarlier: true); reset.tap()
        XCTAssertFalse(reset.isEnabled)
        reveal(weight, in: app)
        XCTAssertEqual(numericValue(weight), 30)
        XCTAssertEqual(numericValue(reps), 8)
        reveal(untouchedWeight, in: app)
        XCTAssertEqual(numericValue(untouchedWeight), 35)
        let apply = app.buttons["progression_apply"]
        XCTAssertTrue(apply.isEnabled); apply.tap()
        let appliedWeight = firstWeight(app)
        reveal(appliedWeight, in: app)
        XCTAssertEqual(numericValue(appliedWeight), 30)
        XCTAssertEqual(numericValue(firstReps(app)), 8)
        XCTAssertEqual(complete.value as? String, "Not completed", "Reviewing targets must not advance completed work")
        attach(app, "Strength - target overrides retained and deliberately reset")
    }

    @MainActor
    func testEquipmentAndCompletedSetResumeWithoutAdvancingProgram() {
        let app = launch("train")
        // Upcoming sessions live on Program & schedule, not the compact Train home.
        let program = app.buttons["train_program_overview"]
        open(program, in: app)
        let upcoming = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'training_preview_' ")).firstMatch
        XCTAssertTrue(upcoming.waitForExistence(timeout: 10))
        let originalSlot = upcoming.label
        let originalSlotID = upcoming.identifier
        app.navigationBars["Program & schedule"].buttons.firstMatch.tap()
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); open(start, in: app)
        open(equipmentButton(app), in: app)
        let units = app.segmentedControls["equipment_units"]
        XCTAssertTrue(units.waitForExistence(timeout: 5)); reveal(units, in: app, preferEarlier: true); units.buttons["kg"].tap()
        setAvailableWeights("10 15 20 25", in: app)
        saveEquipment(in: app)
        let complete = firstComplete(app)
        replace(firstWeight(app), with: "20", in: app)
        app.buttons["workout_input_next"].tap()
        replace(firstReps(app), with: "9", in: app)
        app.buttons["workout_input_complete"].tap()
        XCTAssertEqual(complete.value as? String, "Completed")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        open(program, in: app)
        XCTAssertTrue(upcoming.waitForExistence(timeout: 5))
        XCTAssertEqual(upcoming.identifier, originalSlotID, "Draft recovery must not advance the program slot")
        XCTAssertEqual(upcoming.label, originalSlot, "Editing a session must preserve the active program slot")
        app.navigationBars["Program & schedule"].buttons.firstMatch.tap()
        open(resume, in: app)
        let weight = firstWeight(app)
        reveal(weight, in: app)
        XCTAssertEqual(numericValue(weight), 20)
        XCTAssertEqual(numericValue(firstReps(app)), 9)
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertTrue(equipmentButton(app).label.contains("kg"))
        XCTAssertFalse(equipmentButton(app).isEnabled)
        attach(app, "Strength - equipment and set recovered")
    }

    @MainActor
    func testInvalidInventoryKeepsChoicesAndCancelPreservesTheSession() {
        let app = launch()
        let weight = firstWeight(app)
        reveal(weight, in: app)
        let original = numericValue(weight)
        let equipment = equipmentButton(app)
        open(equipment, in: app)
        setAvailableWeights("25 wrong 50", in: app)
        XCTAssertFalse(app.buttons["equipment_save"].isEnabled)
        XCTAssertTrue(app.staticTexts["equipment_validation"].exists)
        XCTAssertTrue((weightsField(app).value as? String)?.contains("wrong") == true)
        attach(app, "Strength - invalid inventory retains choices")
        app.buttons["Cancel"].tap()
        reveal(weight, in: app)
        XCTAssertEqual(numericValue(weight), original)
        XCTAssertTrue(equipment.label.contains("Set up equipment"))
    }

    @MainActor
    func testBarbellSetupUsesPlatePairsAndConvertsUnits() {
        let app = launch()
        open(equipmentButton(app), in: app)
        app.buttons["equipment_preset_barbell"].tap()
        let plates = input("equipment_plates", in: app)
        replace(plates, with: "25 10 5 2.5", in: app)
        dismissEquipmentKeyboard(app)
        let summary = app.staticTexts["equipment_load_summary"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.label.contains("45–130 lb"), summary.label)
        let units = app.segmentedControls["equipment_units"]
        reveal(units, in: app, preferEarlier: true); units.buttons["kg"].tap()
        let bar = input("equipment_bar_weight", in: app)
        reveal(bar, in: app)
        XCTAssertEqual(numericValue(bar) ?? -1, 20.412, accuracy: 0.0001)
        reveal(units, in: app, preferEarlier: true); units.buttons["lb"].tap()
        reveal(bar, in: app)
        XCTAssertEqual(numericValue(bar) ?? -1, 45, accuracy: 0.0001)
        attach(app, "Strength - bar and plate pair setup")
        saveEquipment(in: app)
        open(equipmentButton(app), in: app)
        reveal(bar, in: app)
        XCTAssertEqual(numericValue(bar) ?? -1, 45, accuracy: 0.0001)
        XCTAssertEqual(plates.value as? String, "25 10 5 2.5")
    }

    @MainActor
    func testLargestTextEquipmentSetupCanBeSavedAndReopenedInDarkMode() {
        let app = launch(arguments: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open(equipmentButton(app), in: app)
        let preset = app.buttons["equipment_preset_dumbbells"]
        reveal(preset, in: app); preset.tap()
        let save = app.buttons["equipment_save"]
        XCTAssertTrue(save.isHittable)
        attach(app, "Strength - large text equipment setup")
        saveEquipment(in: app)
        open(equipmentButton(app), in: app)
        let weights = weightsField(app)
        reveal(weights, in: app)
        XCTAssertTrue((weights.value as? String)?.contains("100") == true)
        XCTAssertTrue(save.isEnabled)
        attach(app, "Strength - large text saved equipment")
    }

    @MainActor
    func testQuickCompletionUndoAndRestSurviveInterruption() {
        let app = launch(arguments: ["-ui-testing-auto-rest"])
        let complete = firstComplete(app)
        open(complete, in: app)
        XCTAssertEqual(complete.value as? String, "Completed")
        let rest = restTimer(in: app)
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        let undo = app.buttons["Undo set"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5)); undo.tap()
        XCTAssertEqual(complete.value as? String, "Not completed")
        XCTAssertTrue(rest.waitForNonExistence(timeout: 3))
        open(complete, in: app)
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-auto-rest"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(rest.waitForExistence(timeout: 8), "Rest must recover from the saved deadline")
        attach(app, "Strength - recovered rest and completed set")
        let skip = app.buttons["workout_rest_skip"]
        XCTAssertTrue(skip.isHittable); skip.tap()
        XCTAssertTrue(rest.waitForNonExistence(timeout: 3))
        app.terminate(); app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertFalse(rest.exists, "Explicitly stopped rest must not return on resume")
    }

    @MainActor
    func testLargestTextRestCanBeSkippedFromPersistentControls() {
        let app = launch(arguments: ["-ui-testing-auto-rest", "-screenshot-dark-mode",
                                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let complete = firstComplete(app)
        open(complete, in: app)
        XCTAssertEqual(complete.value as? String, "Completed")
        let skip = app.buttons["workout_rest_skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(skip.isHittable, "Rest controls must remain available when the header scrolls away")
        skip.tap()
        XCTAssertTrue(restTimer(in: app).waitForNonExistence(timeout: 3))
        let ended = app.descendants(matching: .any)["workout_rest_completion"].firstMatch
        XCTAssertTrue(ended.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Rest skipped"].exists)
        XCTAssertEqual(complete.value as? String, "Completed")
        attach(app, "Strength - largest text persistent rest controls")
    }

    @MainActor
    func testFocusedLoggingKeepsRestAndKeyboardControlsReachable() {
        let app = launch(arguments: ["-ui-testing-auto-rest"])
        let complete = firstComplete(app)
        open(complete, in: app)
        let rest = restTimer(in: app)
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        let nextWeight = app.textFields.matching(identifier: "set_weight_2").firstMatch
        open(nextWeight, in: app)
        XCTAssertTrue(app.buttons["workout_finish"].waitForNonExistence(timeout: 3), "Finish controls should leave room for set entry")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Verify the layout with the software keyboard visible")
        XCTAssertTrue(nextWeight.isHittable)
        XCTAssertTrue(app.buttons["workout_input_complete"].isHittable)
        XCTAssertTrue(app.buttons["workout_rest_add"].isHittable)
        XCTAssertTrue(app.buttons["workout_rest_skip"].isHittable)
        let undo = app.buttons["workout_undo_set"]
        XCTAssertLessThanOrEqual(nextWeight.frame.maxY, undo.frame.minY,
                                "The full weight control must stay above the fixed Undo row")
        let nextReps = app.textFields.matching(identifier: "set_reps_2").firstMatch
        XCTAssertLessThanOrEqual(nextReps.frame.maxY, undo.frame.minY,
                                "The full reps control must stay visible with the software keyboard")
        attach(app, "Strength - focused entry and rest controls")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["workout_finish"].waitForExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "Completed")
    }

    @MainActor
    func testRestAdjustmentsPreserveDeadlineAcrossResumeAndSkipStaysStopped() {
        let app = launch(arguments: ["-ui-testing-auto-rest"])
        let complete = firstComplete(app)
        open(complete, in: app)
        XCTAssertEqual(complete.value as? String, "Completed")
        let rest = restTimer(in: app)
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        let initialDeadline = restDeadline(rest)
        let add = app.buttons["workout_rest_add"]
        XCTAssertTrue(add.isHittable); add.tap()
        let extendedDeadline = restDeadline(rest)
        XCTAssertEqual(extendedDeadline - initialDeadline, 30, accuracy: 2)
        let subtract = app.buttons["workout_rest_subtract"]
        XCTAssertTrue(subtract.isHittable); subtract.tap()
        let adjustedDeadline = restDeadline(rest)
        XCTAssertEqual(adjustedDeadline - extendedDeadline, -15, accuracy: 2)
        attach(app, "Strength - adjusted rest deadline")

        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-auto-rest"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        XCTAssertTrue(rest.waitForExistence(timeout: 8))
        XCTAssertEqual(restDeadline(rest), adjustedDeadline, accuracy: 2, "Resume must retain the adjusted wall-clock deadline")
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "Completed")
        let skip = app.buttons["workout_rest_skip"]
        XCTAssertTrue(skip.isHittable); skip.tap()
        XCTAssertTrue(rest.waitForNonExistence(timeout: 3))
        app.terminate(); app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 10)); resume.tap()
        reveal(complete, in: app, preferEarlier: true)
        XCTAssertTrue(complete.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(complete.value as? String, "Completed")
        XCTAssertFalse(rest.exists, "Skipping adjusted rest must remain stopped after relaunch")
    }

    @MainActor
    private func launch(_ route: String = "workout-player", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route,
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment"] + arguments
        app.terminate()
        app.launch()
        // The simulator can cold-start a freshly installed app without its test
        // arguments. Retry only that confirmed Welcome surface, never assertions
        // about the workout itself.
        let fixture = route == "train" ? app.buttons["Start workout"]
            : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        if !fixture.waitForExistence(timeout: 5), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate()
            app.launch()
        }
        return app
    }

    @MainActor
    private func equipmentButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strength_equipment_' ")).firstMatch
    }

    @MainActor
    private func firstWeight(_ app: XCUIApplication) -> XCUIElement { app.textFields.matching(identifier: "set_weight_1").firstMatch }

    @MainActor
    private func firstReps(_ app: XCUIApplication) -> XCUIElement { app.textFields.matching(identifier: "set_reps_1").firstMatch }

    @MainActor
    private func firstComplete(_ app: XCUIApplication) -> XCUIElement {
        let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        return app.buttons[candidate.identifier]
    }

    @MainActor
    private func restTimer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "workout_rest_timer").firstMatch
    }

    @MainActor
    private func recordLighterSwitchDiagnostics(in app: XCUIApplication) {
        let matches = app.switches.matching(identifier: "progression_lighter").allElementsBoundByIndex
        var details = ["Matching lighter switches: \(matches.count)"]
        for (index, element) in matches.enumerated() {
            details.append("Switch \(index): frame=\(element.frame), value=\(String(describing: element.value)), enabled=\(element.isEnabled)")
            details.append(element.debugDescription)
            for (childIndex, child) in element.descendants(matching: .switch).allElementsBoundByIndex.enumerated() {
                details.append("Native child \(childIndex): frame=\(child.frame), value=\(String(describing: child.value)), enabled=\(child.isEnabled)")
                details.append(child.debugDescription)
            }
        }
        let summary = details.joined(separator: "\n")
        print(summary)
        let diagnostic = XCTAttachment(string: app.debugDescription + "\n\n" + summary)
        diagnostic.name = "Strength - lighter switch hierarchy before one tap"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }

    @MainActor
    private func restDeadline(_ timer: XCUIElement) -> TimeInterval {
        let text = timer.value as? String ?? ""
        let parts = text.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
              minutes >= 0, (0..<60).contains(seconds) else {
            XCTFail("Expected a rest countdown in mm:ss, received \(text)")
            return 0
        }
        return Date().timeIntervalSince1970 + Double(minutes * 60 + seconds)
    }

    @MainActor
    private func input(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func weightsField(_ app: XCUIApplication) -> XCUIElement { input("equipment_weights", in: app) }

    @MainActor
    private func setAvailableWeights(_ text: String, in app: XCUIApplication) {
        let field = weightsField(app)
        replace(field, with: text, in: app)
        dismissEquipmentKeyboard(app)
    }

    @MainActor
    private func saveEquipment(in app: XCUIApplication) {
        let save = app.buttons["equipment_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func dismissEquipmentKeyboard(_ app: XCUIApplication) {
        let finish = app.buttons["equipment_finish_edit"]
        let done = finish.exists ? finish : app.buttons["equipment_keyboard_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    }

    @MainActor
    private func dismissTargetKeyboard(_ app: XCUIApplication) {
        let finish = app.buttons["progression_finish_edit"]
        let done = finish.exists ? finish : app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(app.buttons["progression_apply"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func open(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app); element.tap()
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, in app: XCUIApplication) {
        reveal(field, in: app)
        if ["equipment_weights", "equipment_plates"].contains(field.identifier) {
            let clearID = field.identifier == "equipment_weights" ? "equipment_clear_weights" : "equipment_clear_plates"
            let clear = app.buttons[clearID]
            reveal(clear, in: app)
            if clear.isEnabled { clear.tap() }
            reveal(field, in: app); field.tap()
            if !value.isEmpty { field.typeText(value) }
            XCTAssertTrue(hasValue(value, field: field), "Expected \(value), actual \(String(describing: field.value))")
            return
        }
        field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        guard !hasValue(value, field: field) else { return }
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
    private func numericValue(_ field: XCUIElement) -> Double? {
        guard let value = field.value as? String else { return nil }
        return value.isEmpty ? 0 : Double(value)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, preferEarlier: Bool = false) {
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

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
