import XCTest

/// Disposable screenshot-account journeys. Never run on the owner's installed app.
final class WaveTwoMealWorkspaceDepthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testReusableMealEditorRestoresAmountsAndDiscardedReviewKeepsDraft() {
        let app = launch()
        openCompositions(app)
        let edit = app.buttons["Edit"].firstMatch
        reveal(edit, app: app); edit.tap()
        let name = app.textFields["composition_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        replace(name, with: "QA draft bowl")
        XCTAssertTrue(app.staticTexts["QA rice"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["QA egg"].exists, app.debugDescription)
        app.terminate()
        _ = launch(reset: false, app: app)
        openCompositions(app)
        reveal(edit, app: app); edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(name.value as? String, "QA draft bowl", app.debugDescription)
        let review = app.buttons["composition_review"]
        reveal(review, app: app); review.tap()
        XCTAssertTrue(app.navigationBars["Review library save"].waitForExistence(timeout: 10), app.debugDescription)
        let rice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "QA rice", "400 cal")).firstMatch
        let egg = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "QA egg", "100 cal")).firstMatch
        reveal(rice, app: app); XCTAssertTrue(rice.exists, app.debugDescription)
        reveal(egg, app: app); XCTAssertTrue(egg.exists, app.debugDescription)
        let discard = app.buttons["Discard review"]
        reveal(discard, app: app); discard.tap()
        XCTAssertTrue(app.navigationBars["Build a reusable meal"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(name.value as? String, "QA draft bowl", "Cancelling the library review retains the recoverable editor.\n\(app.debugDescription)")
        attach(app, "Meal workspace - restored components and discarded review preserve editor")
        app.navigationBars["Build a reusable meal"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["QA composed bowl"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["QA draft bowl"].exists, "An unsubmitted editor must not alter its library source")
    }

    @MainActor func testSubmittedCompositionReviewRestoresAndCancelsAtLargestText() {
        let flags = ["-ui-testing-workspace-pending", "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let app = launch(flags: flags)
        openCompositions(app)
        openLibraryResume("Resume saved-meal review", expectedName: "QA recovered bowl", app: app)
        checkPendingStatus(app)
        app.terminate()
        _ = launch(flags: flags, reset: false, app: app)
        openCompositions(app)
        openLibraryResume("Resume saved-meal review", expectedName: "QA recovered bowl", app: app)
        let cancel = app.buttons["Cancel pending save"]
        reveal(cancel, app: app); assertControl(cancel, app: app); cancel.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
        reveal(done, app: app); assertControl(done, app: app)
        attach(app, "Meal workspace - largest text restored library save and fenced cancellation")
        done.tap()
        XCTAssertTrue(app.navigationBars["Reusable meals"].waitForExistence(timeout: 10), app.debugDescription)
        let original = app.buttons["QA composed bowl"]
        reveal(original, app: app)
        XCTAssertTrue(original.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["QA recovered bowl"].exists, "Cancelled review must not replace the saved meal")
    }

    @MainActor func testSubmittedSavedWeekRecoversThenPreviewsIndependentDateReview() {
        let flags = ["-ui-testing-workspace-pending"]
        let app = launch(flags: flags)
        openSavedWeeks(app)
        openLibraryResume("Resume week-library save", expectedName: "QA recovered week", app: app)
        checkPendingStatus(app)
        app.terminate()
        _ = launch(flags: flags, reset: false, app: app)
        openSavedWeeks(app)
        openLibraryResume("Resume week-library save", expectedName: "QA recovered week", app: app)
        let cancel = app.buttons["Cancel pending save"]
        reveal(cancel, app: app); cancel.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription); done.tap()
        XCTAssertTrue(app.navigationBars["Saved meal weeks"].waitForExistence(timeout: 10), app.debugDescription)
        let saved = app.buttons["QA saved week"]
        reveal(saved, app: app); saved.tap()
        let preview = app.buttons["planner_template_preview"]
        reveal(preview, app: app); preview.tap()
        let use = app.buttons["planner_use_draft"]
        XCTAssertTrue(use.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(any(app, "planner_constraint_report").exists, app.debugDescription)
        attach(app, "Meal workspace - saved week preview is a separate checked date review")
        let discard = app.buttons["planner_discard_draft"]
        reveal(discard, app: app); discard.tap()
        let confirm = app.buttons["Discard draft"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription); confirm.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 10), app.debugDescription)
        let summary = any(app, "meal_plan_summary")
        reveal(summary, app: app)
        XCTAssertTrue(summary.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Berry Protein Oats"].exists, "Preview/discard must preserve the existing daily plan.\n\(app.debugDescription)")
    }

    @MainActor func testNamedTimerAdjustsOutsideCookAndPausedDeadlineSurvivesRelaunch() {
        let flags = ["-ui-testing-wave2-cooking-batch"]
        let app = launch(flags: flags, includesWorkspaceFixture: false)
        select("Cook", app: app)
        let mode = app.segmentedControls["meal_prep_mode_picker"]
        reveal(mode, app: app); mode.buttons["Steps"].tap()
        let add = app.buttons["cooking_add_named_timer"]
        reveal(add, app: app); add.tap()
        let field = app.textFields["cooking_timer_name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap(); field.typeText("QA rice timer\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        app.buttons["meal_prep_timer_start"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
        select("Plan", app: app)
        openNearestTimer(app)
        let timer = timerCard(app)
        let pause = timer.buttons["Pause"]
        reveal(pause, app: app); pause.tap()
        let resume = timer.buttons["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), app.debugDescription)
        let before = timerSeconds(timer)
        let extend = timer.buttons["+1 min"]
        assertControl(extend, app: app); extend.tap()
        let adjusted = timerSeconds(timer)
        XCTAssertEqual(adjusted, before + 60, "An adjustment changes a paused timer by exactly one minute")
        app.navigationBars["Cooking timers"].buttons["Done"].tap()
        app.terminate()
        _ = launch(flags: flags, reset: false, includesWorkspaceFixture: false, app: app)
        openNearestTimer(app)
        let restored = timerCard(app)
        XCTAssertTrue(restored.buttons["Resume"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(timerSeconds(restored), adjusted, "Inspector changes survive without reopening Cook")
        attach(app, "Meal workspace - adjusted paused timer restored outside Cook")
        let cancel = restored.buttons["Cancel"]
        reveal(cancel, app: app); assertControl(cancel, app: app); cancel.tap()
        XCTAssertTrue(restored.waitForNonExistence(timeout: 10), app.debugDescription)
        app.navigationBars["Cooking timers"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["planner_nearest_cooking_timer"].waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testIndependentPrepDatesPreserveLegacyChecksAndRestoreSelectedChecklist() {
        let flags = ["-ui-testing-independent-prep"]
        let app = launch(flags: flags, includesWorkspaceFixture: false)
        select("Cook", app: app)
        let mode = app.segmentedControls["meal_prep_mode_picker"]
        reveal(mode, app: app); mode.buttons["Steps"].tap()
        let first = app.buttons["meal_prep_step_0"], second = app.buttons["meal_prep_step_2"]
        reveal(first, app: app); XCTAssertEqual(first.value as? String, "Complete", app.debugDescription)
        reveal(second, app: app); XCTAssertEqual(second.value as? String, "Not complete", app.debugDescription)
        let sauce = app.buttons["meal_prep_step_4"]
        reveal(sauce, app: app); XCTAssertEqual(sauce.value as? String, "Complete", "Legacy sauce check must not become a second rice check.\n\(app.debugDescription)")
        let prep = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Prep sessions")).firstMatch
        reveal(prep, app: app); prep.tap()
        for identifier in ["cooking_requirement_repeated-rice-0", "cooking_requirement_repeated-sauce"] {
            let row = app.switches[identifier]
            reveal(row, app: app)
            let toggle = nativeSwitch(row)
            XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
            XCTAssertTrue(toggle.isHittable, app.debugDescription)
            toggle.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Prep selection must change before continuing.\n\(app.debugDescription)")
            XCTAssertEqual(nativeSwitch(row).value as? String, "0", app.debugDescription)
        }
        reveal(second, app: app); second.tap()
        XCTAssertEqual(second.value as? String, "Complete", app.debugDescription)
        XCTAssertFalse(first.exists, app.debugDescription)
        XCTAssertFalse(sauce.exists, app.debugDescription)
        assertSelectedChecklist(app)
        attach(app, "Independent prep - exact date selection and migrated checks")

        app.terminate()
        _ = launch(flags: flags, reset: false, includesWorkspaceFixture: false, app: app)
        select("Cook", app: app)
        reveal(mode, app: app); mode.buttons["Steps"].tap()
        reveal(second, app: app); XCTAssertEqual(second.value as? String, "Complete", app.debugDescription)
        XCTAssertEqual(app.buttons["meal_prep_step_3"].value as? String, "Not complete", app.debugDescription)
        XCTAssertFalse(first.exists, app.debugDescription)
        reveal(prep, app: app); prep.tap()
        assertSelectedChecklist(app)
        attach(app, "Independent prep - selected date and checklist restored")
    }

    @MainActor private func assertSelectedChecklist(_ app: XCUIApplication) {
        let preview = app.buttons["Preview checklist"]
        reveal(preview, app: app); preview.tap()
        let text = app.staticTexts["cooking_checklist_preview"]
        reveal(text, app: app)
        XCTAssertTrue(text.label.contains("☑ Rinse rice"), app.debugDescription)
        XCTAssertTrue(text.label.contains("☐ Cook rice"), app.debugDescription)
        XCTAssertFalse(text.label.contains("Mix sauce"), app.debugDescription)
        XCTAssertEqual(text.label.components(separatedBy: "QA repeated rice").count - 1, 1, app.debugDescription)
    }

    @MainActor private func launch(flags: [String] = [], reset: Bool = true, includesWorkspaceFixture: Bool = true, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan"]
            + (includesWorkspaceFixture ? ["-ui-testing-meal-workspace"] : []) + flags
            + (reset ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        let workspace = app.segmentedControls["planner_workspace"]
        if !workspace.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(workspace.waitForExistence(timeout: 10), app.debugDescription)
        return app
    }
    @MainActor private func openCompositions(_ app: XCUIApplication) {
        select("Plan", app: app)
        app.buttons["meal_plan_tools"].tap()
        let add = app.buttons["Add meal"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), app.debugDescription); add.tap()
        let create = app.buttons["planner_create_menu"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription); create.tap()
        let library = app.buttons["planner_compositions"]
        reveal(library, app: app); library.tap()
        XCTAssertTrue(app.navigationBars["Reusable meals"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openSavedWeeks(_ app: XCUIApplication) {
        app.buttons["meal_plan_tools"].tap()
        let library = app.buttons["Saved meal weeks"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), app.debugDescription); library.tap()
        XCTAssertTrue(app.navigationBars["Saved meal weeks"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openLibraryResume(_ label: String, expectedName: String, app: XCUIApplication) {
        let resume = app.buttons[label]
        reveal(resume, app: app); resume.tap()
        XCTAssertTrue(app.navigationBars["Review library save"].waitForExistence(timeout: 10), app.debugDescription)
        let name = app.staticTexts[expectedName]
        reveal(name, app: app); XCTAssertTrue(name.exists, app.debugDescription)
    }
    @MainActor private func checkPendingStatus(_ app: XCUIApplication) {
        let status = app.buttons["Check saved status"]
        reveal(status, app: app); assertControl(status, app: app); status.tap()
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No accepted receipt yet")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count) + value + "\n")
    }
    @MainActor private func select(_ workspace: String, app: XCUIApplication) {
        let control = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription); control.buttons[workspace].tap()
    }
    @MainActor private func openNearestTimer(_ app: XCUIApplication) {
        let nearest = app.buttons["planner_nearest_cooking_timer"]
        XCTAssertTrue(nearest.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(nearest.label.contains("QA rice timer"), app.debugDescription); nearest.tap()
        XCTAssertTrue(app.navigationBars["Cooking timers"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func timerCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "cooking_inspect_"))
            .containing(.staticText, identifier: "QA rice timer").firstMatch
    }
    @MainActor private func timerSeconds(_ container: XCUIElement) -> Int {
        let label = container.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2}")).firstMatch.label
        let parts = label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, container.debugDescription)
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    @MainActor private func nativeSwitch(_ element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
    }
    @MainActor private func assertControl(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.isHittable, app.debugDescription); XCTAssertTrue(app.frame.contains(element.frame), app.debugDescription)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, app.debugDescription)
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
            ?? app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
            ?? app.tables.allElementsBoundByIndex.last(where: \.isHittable)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for index in 0..<30 {
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(scroll?.frame.minY ?? 90, nav?.frame.maxY ?? 85) + 6
            var bottom = min(scroll?.frame.maxY ?? app.frame.maxY - 80, app.frame.maxY - 80) - 6
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            // Pinned actions are outside the List's viewport, but are reachable.
            // Use the same bounded criterion as the final assertion before scrolling.
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            guard bottom > top + 50 else { break }
            if element.exists, element.isHittable, app.frame.contains(element.frame),
               ["composition_review", "planner_use_draft", "planner_discard_draft"].contains(element.identifier) { return }
            let above = element.exists && element.frame.height > 0 ? element.frame.minY < top : index > 18
            let center = top + (bottom - top) / 2
            let distance = min(CGFloat(130), (bottom - top) * 0.38)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: center)).press(forDuration: 0.03,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: center + (above ? distance : -distance))))
        }
        XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame), "Expected reachable element \(element.identifier)\n\(app.debugDescription)")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
