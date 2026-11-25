import XCTest

/// Selected, synthetic acceptance journeys. Run only in the dedicated QA simulator;
/// the launch reset flags intentionally clear that synthetic account's editor drafts.
final class WaveTwoContinuationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCopyFutureWeekKeepsPHULPositionAndPersistsIndependentTargets() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul"])
        openBlock(app)
        let tools = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "block_week_tools", "Week tools")).firstMatch
        reveal(tools, app: app); tools.tap()
        let copy = app.buttons["block_copy_week"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Expanded Week tools must expose Copy this week.\n\(app.debugDescription)")
        reveal(copy, app: app); copy.tap()
        let use = app.buttons["block_copy_apply"]
        XCTAssertTrue(use.waitForExistence(timeout: 10))
        XCTAssertEqual(use.label, "Use in Week 11")
        XCTAssertTrue(any(app, "block_copy_source").label.contains("Week 10"))
        XCTAssertTrue(use.isEnabled)
        record(app, "PHUL - reviewed independent week copy")
        use.tap()
        XCTAssertTrue(use.waitForNonExistence(timeout: 5))
        let copied = app.buttons["block_session_40"]
        reveal(copied, app: app)
        XCTAssertTrue(copied.label.contains("Week-specific targets"))
        app.buttons["block_save"].tap()
        XCTAssertTrue(app.buttons["block_save"].waitForNonExistence(timeout: 15))
        assertPHULPosition(app)
        openBlock(app)
        let picker = app.buttons["block_week_picker"]
        reveal(picker, app: app); picker.tap()
        let week = app.buttons["Week 11"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5)); week.tap()
        reveal(copied, app: app)
        XCTAssertTrue(copied.label.contains("Week-specific targets"))
        record(app, "PHUL - copied targets survive saved block reopen")
    }

    @MainActor
    func testWeekCopyRejectsPassedDestinationWithoutChangingPHULProgress() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul"])
        openBlock(app)
        let tools = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "block_week_tools", "Week tools")).firstMatch
        reveal(tools, app: app); tools.tap()
        let copy = app.buttons["block_copy_week"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Expanded Week tools must expose Copy this week.\n\(app.debugDescription)")
        reveal(copy, app: app); copy.tap()
        let destination = app.buttons["block_copy_destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap()
        let passedWeek = app.buttons["Week 1 · Week 1"].firstMatch
        XCTAssertTrue(passedWeek.waitForExistence(timeout: 5)); passedWeek.tap()
        XCTAssertFalse(app.buttons["block_copy_apply"].isEnabled)
        let error = any(app, "block_copy_error")
        reveal(error, app: app)
        XCTAssertTrue(error.exists)
        record(app, "PHUL - passed week replacement blocked")
        app.buttons["block_copy_cancel"].tap()
        app.buttons["block_close"].tap()
        assertPHULPosition(app)
    }

    @MainActor
    func testHouseholdCookingAndLeftoversKeepPersonalNutritionAndPurchaseOnce() {
        let app = launch("meal-plan", flags: ["-ui-testing-wave2-cooking"])
        prepareFourPortionBatch(app)
        let edit = app.buttons["planner_edit_wave2-cooking-dinner"]
        reveal(edit, app: app); edit.tap()
        let nutrition = any(app, "planner_portion_nutrition")
        reveal(nutrition, app: app)
        XCTAssertTrue(nutrition.exists)
        XCTAssertTrue(nutrition.label.contains("400"))
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        let options = app.buttons["planner_meal_options_wave2-cooking-dinner"]
        reveal(options, app: app); options.tap()
        let leftovers = app.buttons["planner_plan_leftovers_wave2-cooking-dinner"]
        XCTAssertTrue(leftovers.waitForExistence(timeout: 5)); leftovers.tap()
        let confirm = app.buttons["planner_leftover_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let review = any(app, "planner_leftover_review")
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        record(app, "Meal planning - reviewed allocation from one household batch")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))
        selectWorkspace("Shop", app: app)
        let riceRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@",
                                                        "grocery_item_", "dry rice"))
        let rice = riceRows.firstMatch
        reveal(rice, app: app)
        XCTAssertTrue(rice.exists, "The household batch buys 400 g once; its leftover must not buy another 100 g")
        XCTAssertEqual(riceRows.count, 1)
        XCTAssertTrue((rice.value as? String ?? "").contains("400 g"))
        record(app, "Meal planning - one purchase requirement for dinner and leftover")
        selectWorkspace("Plan", app: app)
        let mode = app.buttons["planner_view_mode"]
        reveal(mode, app: app); mode.tap()
        let calendar = Calendar.current
        let today = Date()
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: today),
           !calendar.isDate(today, equalTo: nextDay, toGranularity: .weekOfYear) {
            app.buttons["planner_next_week"].tap()
        }
        let tomorrow = app.buttons["planner_agenda_\(dayID(1))"]
        reveal(tomorrow, app: app); tomorrow.tap()
        let names = app.staticTexts["Four-portion rice batch"]
        XCTAssertTrue(names.firstMatch.waitForExistence(timeout: 5))
        let summary = any(app, "meal_plan_summary")
        reveal(summary, app: app)
        let summaryText = ([summary.label] + summary.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
        XCTAssertTrue(summaryText.contains("400"), "The planned leftover keeps its own one-portion nutrition")
        record(app, "Meal planning - leftover destination and personal nutrition")
    }

    @MainActor
    func testRejectedHouseholdSaveKeepsReviewAndOriginalPersonalPortion() {
        let app = launch("meal-plan", flags: ["-ui-testing-wave2-cooking", "-ui-testing-meal-plan-save-failure"])
        openHouseholdEditor(app)
        let nutrition = any(app, "planner_portion_nutrition")
        reveal(nutrition, app: app)
        XCTAssertTrue(nutrition.label.contains("400"))
        app.buttons["planner_save_meal"].tap()
        XCTAssertTrue(any(app, "planner_edit_error").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["planner_save_meal"].isEnabled)
        XCTAssertTrue(nutrition.label.contains("400"))
        record(app, "Meal planning - failed household save retains review")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        let edit = app.buttons["planner_edit_wave2-cooking-dinner"]
        reveal(edit, app: app); edit.tap()
        let batch = app.switches["planner_household_batch"]
        reveal(batch, app: app)
        XCTAssertEqual(batch.value as? String, "0", "A rejected batch edit must not appear accepted")
    }

    @MainActor
    func testRejectedLeftoverSaveResumesFrozenReviewAndCancelsWithUsableControls() {
        let flags = ["-ui-testing-wave2-cooking-batch", "-ui-testing-meal-plan-save-failure"]
        let app = launch("meal-plan", flags: flags)
        let options = app.buttons["planner_meal_options_wave2-cooking-dinner"]
        reveal(options, app: app); options.tap()
        let leftovers = app.buttons["planner_plan_leftovers_wave2-cooking-dinner"]
        XCTAssertTrue(leftovers.waitForExistence(timeout: 5)); leftovers.tap()
        let confirm = app.buttons["planner_leftover_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(any(app, "planner_leftover_review").waitForExistence(timeout: 10))
        let available = any(app, "planner_leftover_available").label
        confirm.tap()
        let error = any(app, "planner_leftover_error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        let check = app.buttons["planner_leftover_check_status"]
        reveal(check, app: app); assertRecoveryControl(check, app: app); check.tap()
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "No saved receipt yet"), object: error)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 10), .completed)
        let cancel = app.buttons["planner_leftover_cancel_pending"]
        reveal(cancel, app: app); assertRecoveryControl(cancel, app: app)
        record(app, "Leftovers - failed save exposes usable status and cancellation")
        app.navigationBars["Plan leftovers"].buttons["Cancel"].tap()
        let resume = app.buttons["planner_resume_leftover_review"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        app.terminate()
        _ = launch("meal-plan", flags: flags, resets: false, app: app)
        reveal(resume, app: app); resume.tap()
        XCTAssertTrue(any(app, "planner_leftover_restored").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "planner_leftover_available").label, available)
        XCTAssertFalse(any(app, "planner_leftover_destination").exists,
                       "A submitted review must not be retargeted after relaunch")
        XCTAssertFalse(any(app, "planner_leftover_portions").exists)
        reveal(check, app: app); assertRecoveryControl(check, app: app)
        reveal(cancel, app: app); assertRecoveryControl(cancel, app: app); cancel.tap()
        let cancelled = any(app, "planner_leftover_cancelled")
        reveal(cancelled, app: app)
        XCTAssertTrue(cancelled.exists)
        let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Done"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 5), .completed)
        record(app, "Leftovers - frozen review restored and server-fenced cancellation")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))
        XCTAssertTrue(resume.waitForNonExistence(timeout: 10))
        let originalBatch = any(app, "planner_batch_summary_wave2-cooking-dinner")
        reveal(originalBatch, app: app)
        XCTAssertTrue(originalBatch.label.contains("3 unallocated"), "Cancelled leftovers must not consume an allocation")
    }

    @MainActor
    func testCookingStepsAndRunningThenPausedTimerSurviveRelaunch() {
        let app = launch("meal-prep-steps")
        let allSteps = app.buttons["cooking_all_steps"]
        let step = app.buttons["meal_prep_step_0"]
        reveal(allSteps, app: app); allSteps.tap()
        reveal(step, app: app); step.tap()
        XCTAssertEqual(step.value as? String, "Complete")
        let start = app.buttons["meal_prep_start_timer"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let timerStart = app.buttons["meal_prep_timer_start"]
        XCTAssertTrue(timerStart.waitForExistence(timeout: 5)); timerStart.tap()
        let timer = any(app, "meal_prep_active_timer")
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let before = timerSeconds(app)
        app.terminate()
        _ = launch("meal-prep-steps", resets: false, app: app)
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        reveal(allSteps, app: app); allSteps.tap()
        reveal(step, app: app)
        XCTAssertEqual(step.value as? String, "Complete")
        XCTAssertGreaterThan(timerSeconds(app), 0)
        XCTAssertLessThan(timerSeconds(app), before, "A recovered running timer uses its original deadline")
        let pause = app.buttons["Pause timer"]
        XCTAssertTrue(pause.isHittable); pause.tap()
        let paused = timerSeconds(app)
        app.terminate()
        _ = launch("meal-prep-steps", resets: false, app: app)
        XCTAssertTrue(app.buttons["Resume timer"].waitForExistence(timeout: 10))
        XCTAssertEqual(timerSeconds(app), paused, "A paused timer keeps its remaining duration")
        reveal(allSteps, app: app); allSteps.tap()
        reveal(step, app: app)
        XCTAssertEqual(step.value as? String, "Complete")
        record(app, "Cooking - step and running/paused timer recovery")
        app.buttons["Clear timer"].tap()
    }

    @MainActor
    func testPlanShopCookWorkspaceSupportsLargestTextAndSelectedWeek() {
        let app = launch("meal-plan", flags: ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName",
                                               "UICTContentSizeCategoryAccessibilityXXXL"])
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        for title in ["Plan", "Shop", "Cook"] {
            let button = workspace.buttons[title]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        app.buttons["planner_view_mode"].tap()
        let next = app.buttons["planner_next_week"]
        reveal(next, app: app); next.tap()
        let week = any(app, "planner_week_range").label
        selectWorkspace("Shop", app: app)
        XCTAssertTrue(app.scrollViews["grocery_list"].waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "planner_week_range").label, week)
        record(app, "Planner - large text shopping workspace")
        selectWorkspace("Cook", app: app)
        XCTAssertTrue(any(app, "meal_prep_screen").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "planner_week_range").label, week)
        record(app, "Planner - large text cooking workspace")
        let inlineTimer = app.buttons["meal_prep_start_timer"]
        XCTAssertTrue(inlineTimer.waitForExistence(timeout: 5))
        XCTAssertTrue(inlineTimer.isHittable)
        XCTAssertGreaterThanOrEqual(inlineTimer.frame.height, 44)
        XCTAssertGreaterThanOrEqual(inlineTimer.frame.width, 44)
        XCTAssertTrue(app.frame.contains(inlineTimer.frame))
        let quickLog = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLog.exists)
        XCTAssertLessThanOrEqual(inlineTimer.frame.maxY, quickLog.frame.minY,
                                 "The inline cooking action must stay above the lifted Quick Log control")
        inlineTimer.tap()
        let setup = any(app, "meal_prep_timer_setup")
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        let setupStart = app.buttons["meal_prep_timer_start"]
        XCTAssertTrue(setupStart.waitForExistence(timeout: 5))
        XCTAssertTrue(setupStart.isHittable)
        XCTAssertGreaterThanOrEqual(setupStart.frame.height, 44)
        XCTAssertGreaterThanOrEqual(setupStart.frame.width, 44)
        XCTAssertTrue(app.frame.contains(setupStart.frame))
        XCTAssertFalse(quickLog.isHittable, "The timer sheet must take focus over the background tab controls")
        record(app, "Planner - large text inline cooking timer setup")
        let close = setup.buttons["app_sheet_close_button"]
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
        XCTAssertTrue(inlineTimer.isHittable)
        XCTAssertFalse(any(app, "meal_prep_active_timer").exists, "Closing setup must not start a cooking timer")
        inlineTimer.tap()
        XCTAssertTrue(setupStart.waitForExistence(timeout: 5)); setupStart.tap()
        let active = any(app, "meal_prep_active_timer")
        XCTAssertTrue(active.waitForExistence(timeout: 5))
        let reading = active.descendants(matching: .any).matching(identifier: "meal_prep_timer_reading").firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertEqual(reading.label, "Cooking timer")
        XCTAssertGreaterThan(timerSeconds(app), 0)
        let pause = app.buttons["Pause timer"]
        let clear = app.buttons["Clear timer"]
        for control in [pause, clear] {
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertTrue(app.frame.contains(control.frame))
            XCTAssertLessThanOrEqual(reading.frame.maxY, control.frame.minY,
                                     "The stacked countdown must not overlap its timer controls")
            XCTAssertLessThanOrEqual(control.frame.maxY, quickLog.frame.minY,
                                     "Timer controls must remain above the lifted Quick Log control")
        }
        XCTAssertTrue(app.frame.contains(reading.frame))
        XCTAssertLessThanOrEqual(pause.frame.maxX, clear.frame.minX, "Pause and Clear must have distinct touch areas")
        record(app, "Planner - large text active cooking timer and reachable controls")
        pause.tap()
        XCTAssertTrue(app.buttons["Resume timer"].waitForExistence(timeout: 5))
        XCTAssertEqual(reading.label, "Timer paused")
        clear.tap()
        XCTAssertTrue(active.waitForNonExistence(timeout: 5))
        XCTAssertTrue(inlineTimer.isHittable)
        selectWorkspace("Plan", app: app)
        XCTAssertTrue(app.buttons["planner_view_mode"].waitForExistence(timeout: 5))
        XCTAssertEqual(any(app, "planner_week_range").label, week)
    }

    @MainActor
    private func launch(_ screen: String, flags: [String] = [], resets: Bool = true,
                        app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags
            + (resets ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        let expected = screen == "program-detail" ? app.buttons["program_edit_block"]
            : screen.hasPrefix("meal-prep") ? any(app, "meal_prep_screen") : app.segmentedControls["planner_workspace"]
        if !expected.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(expected.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func openBlock(_ app: XCUIApplication) {
        let open = app.buttons["program_edit_block"]
        reveal(open, app: app); open.tap()
        XCTAssertTrue(app.buttons["block_save"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertPHULPosition(_ app: XCUIApplication) {
        let progress = any(app, "program_progress_summary")
        reveal(progress, app: app)
        XCTAssertTrue(progress.label.contains("39 of 48"))
    }

    @MainActor
    private func openHouseholdEditor(_ app: XCUIApplication) {
        let edit = app.buttons["planner_edit_wave2-cooking-dinner"]
        reveal(edit, app: app); edit.tap()
        let batch = app.switches["planner_household_batch"]
        reveal(batch, app: app)
        if batch.value as? String != "1" {
            // Form exposes the label and switch as one wide AX element; target its native control.
            batch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: batch)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        let increase = app.buttons["planner_cooking_portions-Increment"]
        reveal(increase, app: app)
        for _ in 0..<8 { increase.tap() }
    }

    @MainActor
    private func prepareFourPortionBatch(_ app: XCUIApplication) {
        openHouseholdEditor(app)
        let nutrition = any(app, "planner_portion_nutrition")
        reveal(nutrition, app: app)
        XCTAssertTrue(nutrition.label.contains("400"), "Household quantity must not multiply personal calories")
        record(app, "Meal planning - household cooking is separate from personal nutrition")
        app.buttons["planner_save_meal"].tap()
        XCTAssertTrue(app.buttons["planner_save_meal"].waitForNonExistence(timeout: 10))
    }

    @MainActor
    private func selectWorkspace(_ title: String, app: XCUIApplication) {
        let mode = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertTrue(mode.buttons[title].isHittable); mode.buttons[title].tap()
    }

    @MainActor
    private func timerSeconds(_ app: XCUIApplication) -> Int {
        let clock = any(app, "meal_prep_active_timer").descendants(matching: .any)
            .matching(identifier: "meal_prep_timer_reading").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        let pieces = (clock.value as? String ?? "").split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(pieces.count, 2)
        return pieces.count == 2 ? pieces[0] * 60 + pieces[1] : -1
    }

    private func dayID(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @MainActor
    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let identifiers = ["block_copy_scroll", "planner_leftover_form", "planner_edit_form", "workout_block_editor_scroll",
                           "meal_prep_steps", "meal_prep_screen", "grocery_list", "program_detail", "meal_plan_scroll"]
        let scroll = identifiers.lazy.compactMap { identifier -> XCUIElement? in
            let scroller = app.scrollViews[identifier].firstMatch
            if scroller.exists { return scroller }
            let form = app.collectionViews[identifier].firstMatch
            if form.exists { return form }
            let table = app.tables[identifier].firstMatch
            return table.exists ? table : nil
        }.first ?? app.scrollViews.allElementsBoundByIndex.first(where: \.isHittable)
            ?? app.collectionViews.allElementsBoundByIndex.first(where: \.isHittable)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for index in 0..<35 {
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            var top = max(scroll?.frame.minY ?? app.frame.minY + 90, nav?.frame.maxY ?? app.frame.minY + 90) + 4
            let workspace = app.segmentedControls["planner_workspace"]
            if workspace.exists, workspace.isHittable, !app.navigationBars["Edit meal"].exists {
                top = max(top, workspace.frame.maxY + 4)
            }
            var bottom = min(scroll?.frame.maxY ?? app.frame.maxY - 80, app.frame.maxY - 80) - 4
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            let pinnedIDs = ["block_copy_apply", "block_save", "planner_save_meal", "planner_leftover_confirm",
                             "meal_prep_start_timer", "planner_resume_leftover_review"]
            let pinned = pinnedIDs.map { app.buttons[$0] }.filter { $0.exists && $0.isHittable }
            if element.exists, element.isHittable,
               pinned.contains(where: { $0.identifier == element.identifier }), app.frame.contains(element.frame) { return }
            if let footerTop = pinned.map(\.frame.minY).filter({ $0 > top }).min() { bottom = min(bottom, footerTop - 5) }
            let leftoverFooter = any(app, "planner_leftover_footer")
            if leftoverFooter.exists, leftoverFooter.isHittable { bottom = min(bottom, leftoverFooter.frame.minY - 5) }
            if element.exists, element.isHittable, element.frame.minY >= top,
               element.frame.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let above = element.exists && element.frame.height > 0 ? element.frame.minY < top : index > 20
            let distance = min(CGFloat(170), (bottom - top) * 0.4)
            let start = top + (bottom - top) * 0.5
            let end = min(bottom - 8, max(top + 8, start + (above ? distance : -distance)))
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)\n\(app.debugDescription)")
    }

    @MainActor
    private func assertRecoveryControl(_ control: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(control.isHittable)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44)
        XCTAssertTrue(app.frame.contains(control.frame))
        let footer = any(app, "planner_leftover_footer")
        if footer.exists {
            XCTAssertLessThanOrEqual(control.frame.maxY, footer.frame.minY,
                                     "Recovery controls must remain above the whole pinned error/action footer")
        } else {
            XCTAssertLessThanOrEqual(control.frame.maxY, app.buttons["planner_leftover_confirm"].frame.minY)
        }
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
