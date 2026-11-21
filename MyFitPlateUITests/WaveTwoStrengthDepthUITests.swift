import XCTest

final class WaveTwoStrengthDepthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSavedGymMappingAndConditionalUndoSurviveWorkoutRecovery() {
        let app = launch()
        let equipment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strength_equipment_' ")).firstMatch
        XCTAssertTrue(equipment.waitForExistence(timeout: 10))
        let equipmentID = equipment.identifier
        let exerciseID = equipmentID.replacingOccurrences(of: "strength_equipment_", with: "")
        open(app.buttons["workout_session_tools"], app: app)
        open(app.buttons["session_choose_gym"], app: app)
        open(app.buttons["gym_profile_add"], app: app)
        replace(app.textFields["gym_profile_name"], with: "Travel gym", app: app)
        finishKeyboard(app)
        open(app.buttons["gym_profile_add_implement"], app: app)
        replace(app.textFields["equipment_name"], with: "Travel dumbbells", app: app)
        finishKeyboard(app)
        selectWeightMeaning("Per hand", app: app)
        replace(app.textFields["equipment_weights"], with: "10 15 20 25 30", app: app)
        finishKeyboard(app)
        open(app.buttons["equipment_save"], app: app)
        XCTAssertTrue(app.buttons["equipment_save"].waitForNonExistence(timeout: 5))
        open(app.buttons["gym_profile_save"], app: app)
        XCTAssertTrue(app.buttons["gym_profile_save"].waitForNonExistence(timeout: 5))
        let use = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gym_profile_use_")).firstMatch
        open(use, app: app)
        XCTAssertTrue(any(app, "gym_profile_library").waitForNonExistence(timeout: 5))
        let mapping = app.buttons["session_gym_mapping_" + exerciseID]
        open(mapping, app: app)
        XCTAssertTrue(app.buttons["Travel dumbbells"].waitForExistence(timeout: 5)); app.buttons["Travel dumbbells"].tap()
        let apply = app.buttons["session_tools_apply"]
        XCTAssertTrue(apply.isEnabled)
        record(app, "Strength - one gym mapping reviewed before application")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons[equipmentID].label.contains("Travel dumbbells"))
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertEqual(completion.value as? String, "Not completed")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train"]
        app.launch()
        let resume = app.buttons["workout_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15)); resume.tap()
        let restoredEquipment = app.buttons[equipmentID]
        reveal(restoredEquipment, app: app)
        XCTAssertTrue(restoredEquipment.label.contains("Travel dumbbells"))
        let undo = app.buttons["workout_session_tools_undo"]
        open(undo, app: app)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
        XCTAssertFalse(restoredEquipment.label.contains("Travel dumbbells"))
        XCTAssertEqual(completion.value as? String, "Not completed")
        record(app, "Strength - recovered gym setup and session Undo without logging")
    }

    @MainActor
    func testGeneratedWarmupRampReplacesUnfinishedRampWithoutLoggingWorkingSet() {
        let app = launch()
        let equipment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strength_equipment_' ")).firstMatch
        XCTAssertTrue(equipment.waitForExistence(timeout: 10))
        let exerciseID = equipment.identifier.replacingOccurrences(of: "strength_equipment_", with: "")
        let card = any(app, "exercise_card_" + exerciseID)
        let originalCompletion = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        let originalID = originalCompletion.identifier
        open(equipment, app: app)
        open(app.buttons["equipment_preset_barbell"], app: app)
        selectWeightMeaning("Total load", app: app)
        open(app.buttons["equipment_save"], app: app)
        XCTAssertTrue(app.buttons["equipment_save"].waitForNonExistence(timeout: 5))
        let originalRow = any(app, "strength_set_row_" + originalID.replacingOccurrences(of: "set_complete_", with: ""))
        let weight = originalRow.textFields.firstMatch
        replace(weight, with: "165", app: app)
        finishKeyboard(app)
        let originalCount = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).count
        openWarmup(app, exerciseID: exerciseID)
        let working = app.textFields["warmup_working_load"]
        XCTAssertEqual(Double(working.value as? String ?? ""), 165)
        let apply = app.buttons["warmup_apply"]
        XCTAssertTrue(apply.isEnabled)
        record(app, "Strength - attainable barbell warm-up review")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5))
        let completions = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' "))
        XCTAssertEqual(completions.count, originalCount + 3)
        XCTAssertEqual(app.buttons[originalID].value as? String, "Not completed")
        openWarmup(app, exerciseID: exerciseID)
        XCTAssertTrue(app.buttons["warmup_apply"].isEnabled); app.buttons["warmup_apply"].tap()
        XCTAssertTrue(app.buttons["warmup_apply"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(completions.count, originalCount + 3, "Reapplying replaces only the untouched generated rows")
        XCTAssertEqual(app.buttons[originalID].value as? String, "Not completed")
        record(app, "Strength - repeated ramp does not stack or complete sets")
    }

    @MainActor
    func testLargestTextWholeSessionTargetsApplyAndUndoWithoutCompletingSets() {
        let app = launch(flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let complete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'set_complete_' ")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        let setID = complete.identifier
        open(app.buttons["workout_session_tools"], app: app)
        let mode = app.segmentedControls["session_tools_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.buttons["Targets"].tap()
        let apply = app.buttons["session_tools_apply"]
        XCTAssertTrue(apply.isEnabled)
        XCTAssertTrue(apply.isHittable)
        XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
        XCTAssertTrue(app.frame.contains(apply.frame))
        record(app, "Strength - largest text whole-session targets")
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.buttons[setID].value as? String, "Not completed")
        let undo = app.buttons["workout_session_tools_undo"]
        open(undo, app: app)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons[setID].value as? String, "Not completed")
        record(app, "Strength - whole-session Undo retains unperformed status")
    }

    @MainActor
    private func launch(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "workout-player",
                               "-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-reset-editor-drafts"] + flags
        app.launch()
        let root = any(app, "workout_player")
        if !root.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func selectWeightMeaning(_ title: String, app: XCUIApplication) {
        let picker = app.buttons["equipment_meaning"]
        reveal(picker, app: app)
        if (picker.value as? String) == title || picker.label.contains(title) { return }
        picker.tap()
        let choice = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        if !choice.waitForExistence(timeout: 2) {
            // Native Form pickers can expose the whole row to accessibility while
            // their selected-value area receives the menu interaction. Retry that
            // area only when the first tap did not visibly open the choices.
            reveal(picker, app: app)
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Weight convention choices did not open\n\(app.debugDescription)")
        choice.tap()
        XCTAssertTrue((picker.value as? String) == title || picker.label.contains(title),
                      "Weight convention did not select \(title)\n\(app.debugDescription)")
    }
    @MainActor private func openWarmup(_ app: XCUIApplication, exerciseID: String) {
        open(app.buttons["exercise_options_" + exerciseID], app: app)
        let review = app.buttons["warmup_review_" + exerciseID]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        XCTAssertTrue(app.buttons["warmup_apply"].waitForExistence(timeout: 5))
    }
    @MainActor private func open(_ element: XCUIElement, app: XCUIApplication) {
        reveal(element, app: app); element.tap()
    }
    @MainActor private func replace(_ field: XCUIElement, with text: String, app: XCUIApplication) {
        reveal(field, app: app)
        field.tap()
        field.press(forDuration: 1.2)
        let selectAll = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() } else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(XCUIKeyboardKey.delete.rawValue + text)
        XCTAssertEqual(field.value as? String, text)
    }
    @MainActor private func finishKeyboard(_ app: XCUIApplication) {
        for identifier in ["gym_profile_keyboard_done", "equipment_finish_edit", "equipment_keyboard_done", "workout_input_done"] {
            let done = app.buttons[identifier]
            if done.exists, done.isHittable { done.tap(); return }
        }
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }
    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        let surfaces = ["strength_equipment_form", "warmup_review_form", "gym_profile_editor", "gym_profile_library", "session_tools_form", "workout_player"]
        let surface = surfaces.lazy.compactMap { id -> XCUIElement? in
            for type in [XCUIElement.ElementType.collectionView, .table, .scrollView] {
                let value = app.descendants(matching: type)[id].firstMatch
                if value.exists { return value }
            }
            return nil
        }.first ?? app.collectionViews.allElementsBoundByIndex.first
            ?? app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
        for step in 0..<30 {
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(surface?.frame.minY ?? 100, nav?.frame.maxY ?? 100) + 4
            var bottom = min(surface?.frame.maxY ?? app.frame.maxY - 75, app.frame.maxY - 75) - 4
            let pinned = ["warmup_apply", "session_tools_apply", "gym_profile_save", "equipment_save"].map { app.buttons[$0] }
                .filter { $0.exists && $0.isHittable }
            if target.exists, target.isHittable, pinned.contains(where: { $0.identifier == target.identifier }), app.frame.contains(target.frame) { return }
            if let footer = pinned.map(\.frame.minY).filter({ $0 > top }).min() { bottom = min(bottom, footer - 4) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            if target.exists, target.isHittable, target.frame.minY >= top, target.frame.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let earlier = target.exists && target.frame.height > 0 ? target.frame.minY < top : step > 20
            let distance = min(CGFloat(180), (bottom - top) * 0.4)
            let start = top + (bottom - top) * 0.5
            let end = min(bottom - 5, max(top + 5, start + (earlier ? distance : -distance)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)))
        }
        XCTAssertTrue(target.exists && target.isHittable, "Could not reach \(target.identifier)\n\(app.debugDescription)")
    }
    @MainActor private func record(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
