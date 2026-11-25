import XCTest

final class WaveZeroCompletionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testFastingWithoutLockScreenSurvivesRelaunchAndEndsWithReceipt() {
        let app = launch("fasting-detail", flags: ["-ui-testing-fasting-no-projection", "-ui-testing-reset-fasting"])
        XCTAssertTrue(app.buttons["start_fast_button"].waitForExistence(timeout: 15))
        app.buttons["start_fast_button"].tap()
        XCTAssertTrue(any(app, "fasting_active_session").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "fasting_projection_status").exists)
        record(app, "Fasting - durable without Lock Screen")
        app.terminate()
        app.launchArguments = arguments("fasting-detail", flags: ["-ui-testing-fasting-no-projection"])
        app.launch()
        XCTAssertTrue(app.buttons["end_fast_button"].waitForExistence(timeout: 15))
        reveal(app.buttons["end_fast_button"], app: app)
        app.buttons["end_fast_button"].tap()
        XCTAssertTrue(any(app, "fasting_completion_receipt").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["start_fast_button"].exists)
        record(app, "Fasting - accepted end receipt")
    }

    @MainActor
    func testFastingStorageFailureCannotShowAnActiveFast() {
        let app = launch("fasting-detail", flags: ["-ui-testing-fasting-no-projection", "-ui-testing-fasting-storage-failure"])
        XCTAssertTrue(app.buttons["start_fast_button"].waitForExistence(timeout: 15))
        app.buttons["start_fast_button"].tap()
        XCTAssertTrue(any(app, "fasting_save_error").waitForExistence(timeout: 5))
        XCTAssertFalse(any(app, "fasting_active_session").exists)
        record(app, "Fasting - honest storage rejection")
    }

    @MainActor
    func testQuickMacroFailureRestoresOriginalDestinationAndRetries() {
        let app = launch("quick-add-macros", flags: ["-ui-testing-reset-editor-drafts", "-ui-testing-food-save-failure"])
        let save = app.buttons["quick_add_action"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        let destination = any(app, "quick_add_destination").label
        save.tap()
        XCTAssertTrue(any(app, "quick_add_error").waitForExistence(timeout: 8))
        XCTAssertTrue(save.label.contains("Retry"))
        record(app, "Quick macros - rejected frozen entry")
        app.terminate()
        app.launchArguments = arguments("quick-add-macros")
        app.launch()
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertEqual(any(app, "quick_add_destination").label, destination)
        XCTAssertTrue(save.label.contains("Retry"))
        save.tap()
        expectGone(save, timeout: 10)
    }

    @MainActor
    func testGoalCloseDoesNotApplyPreviewAndRejectedSaveKeepsDraft() {
        let app = launch("settings-goals", flags: ["-ui-testing-goal-save-failure"])
        let age = app.textFields["settings_goals_age"].firstMatch
        XCTAssertTrue(age.waitForExistence(timeout: 15))
        let original = age.value as? String
        replace(age, with: "41", app: app)
        app.buttons["app_sheet_close_button"].firstMatch.tap()
        let category = app.buttons["settings_open_goals"]
        reveal(category, app: app); category.tap()
        let reopen = app.buttons["settings_calorie_goals"]
        reveal(reopen, app: app)
        reopen.tap()
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        XCTAssertEqual(age.value as? String, original)
        replace(age, with: "42", app: app)
        XCTAssertEqual(age.value as? String, "42")
        let save = app.buttons["settings_goals_save"].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let error = any(app, "settings_goals_save_error")
        reveal(error, app: app)
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertEqual(age.value as? String, "42")
        XCTAssertTrue(save.isEnabled)
        record(app, "Goals - rejected local draft retained")
    }

    @MainActor
    func testGroceryRejectedCheckRemainsVisibleAndRetriesAfterRelaunch() {
        let app = launch("grocery", flags: ["-ui-testing-reset-editor-drafts", "-ui-testing-grocery-save-failure"])
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grocery_item_' AND value CONTAINS 'not checked'")).firstMatch
        reveal(first, app: app)
        XCTAssertTrue(first.exists, app.debugDescription)
        let rowID = first.identifier
        first.tap()
        XCTAssertTrue(any(app, "grocery_save_status").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons[rowID].firstMatch.exists)
        record(app, "Grocery - rejected check remains accounted for")
        app.terminate()
        app.launchArguments = arguments("grocery")
        app.launch()
        let row = app.buttons[rowID].firstMatch
        reveal(row, app: app)
        XCTAssertTrue(row.exists)
        XCTAssertTrue((row.value as? String)?.contains("checked") == true)
        XCTAssertFalse((row.value as? String)?.contains("not checked") == true)
        let retry = app.buttons["Retry grocery changes"].firstMatch
        if retry.exists { reveal(retry, app: app); retry.tap() }
        expectGone(any(app, "grocery_save_status"), timeout: 10)
    }

    @MainActor
    func testAtomicReceiptFailureRestoresFrozenRowsAndRetryAcceptsAll() {
        // The legacy flag rejects one row before the atomic inventory mutation commits.
        let app = launch("receipt-review", flags: ["-ui-testing-reset-editor-drafts", "-ui-testing-receipt-partial"])
        let save = app.buttons["receipt_add_to_pantry_button"].firstMatch
        let purchaseDate = app.datePickers.firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        @MainActor func revealPurchaseDate() {
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<16 {
                let top = max(scroll.frame.minY + 8, app.frame.minY + 110)
                let bottom = min(scroll.frame.maxY - 8, save.frame.minY - 8)
                if purchaseDate.exists {
                    let frame = purchaseDate.frame
                    if frame.height > 0, frame.minY >= top, frame.maxY <= bottom { return }
                    if frame.minY >= top { scroll.swipeUp(velocity: .slow); continue }
                }
                // Submitted dates are deliberately disabled; visibility must not depend on hittability.
                scroll.swipeDown(velocity: .slow)
            }
            XCTFail("The frozen purchase date must be visible above the save footer.\n\(app.debugDescription)")
        }
        revealPurchaseDate()
        XCTAssertTrue(purchaseDate.isEnabled)
        let originalDate = purchaseDate.buttons.firstMatch.value as? String
        XCTAssertNotNil(originalDate, app.debugDescription)

        @MainActor func assertFrozenRows(_ state: String) {
            let expected = [("Greek Yogurt", "2 tubs"), ("Baby Spinach", "1 bag"), ("Jasmine Rice", "1 bag")]
            for (index, row) in expected.enumerated() {
                let identifier = "receipt_row_status_\(index)"
                let amount = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                    identifier, "\(row.1) · \(state)"))
                reveal(amount.firstMatch, app: app)
                XCTAssertTrue(amount.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertEqual(amount.count, 1, "Each reviewed receipt row must appear once.")
                let name = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", identifier, row.0))
                XCTAssertEqual(name.count, 1, "The exact reviewed name must stay with its quantity.\n\(app.debugDescription)")
            }
            XCTAssertFalse(any(app, "receipt_row_status_3").exists, "Recovery must not append another reviewed row.")
            revealPurchaseDate()
            XCTAssertFalse(purchaseDate.isEnabled, "A submitted receipt keeps its reviewed purchase day frozen.")
            XCTAssertEqual(purchaseDate.buttons.firstMatch.value as? String, originalDate)
        }

        save.tap()
        let error = any(app, "receipt_save_error")
        XCTAssertTrue(error.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(error.label.contains("atomic receipt"), app.debugDescription)
        XCTAssertEqual(save.label, "Retry exact receipt")
        assertFrozenRows("Pending")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label ENDSWITH %@",
            "receipt_row_status_", " · Accepted")).firstMatch.exists, "A failed atomic purchase cannot accept a prefix.")
        record(app, "Receipt - atomic failure keeps every reviewed row pending")

        app.terminate()
        app.launchArguments = arguments("receipt-review")
        app.launch()
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertEqual(save.label, "Retry exact receipt")
        assertFrozenRows("Pending")
        save.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Done'"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed, app.debugDescription)
        assertFrozenRows("Accepted")
        XCTAssertFalse(any(app, "receipt_save_error").exists, app.debugDescription)
        record(app, "Receipt - one exact retry accepts all three reviewed rows")

        // An accepted checkpoint must restore as complete even if a fresh write would fail.
        // Exact stock-count/idempotency assertions live in ShoppingReceiptRecoveryDepthTests;
        // this direct UI fixture exposes reviewed rows and completion, not the repository ledger.
        app.terminate()
        app.launchArguments = arguments("receipt-review", flags: ["-ui-testing-receipt-partial"])
        app.launch()
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertEqual(save.label, "Done", "Accepted rows must not become another retry after relaunch.")
        assertFrozenRows("Accepted")
        XCTAssertFalse(any(app, "receipt_save_error").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["receipt_check_status"].exists)
        record(app, "Receipt - accepted checkpoint restores without another import")
    }

    @MainActor
    func testBarcodeReviewAccountsForMissAndDuplicateAcrossFailedSave() {
        let app = launch("barcode-review", flags: ["-ui-testing-reset-editor-drafts", "-ui-testing-food-save-failure"])
        let save = app.buttons["barcode_batch_log_action"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertTrue(any(app, "barcode_batch_counts").label.contains("4 scanned"))
        XCTAssertTrue(save.label.contains("2"))
        let destination = any(app, "barcode_batch_destination").label
        save.tap()
        app.buttons["Log matched items and leave unresolved out"].firstMatch.tap()
        XCTAssertTrue(any(app, "barcode_batch_error").waitForExistence(timeout: 8))
        record(app, "Barcode - every scan reconciled before retry")
        app.terminate()
        app.launchArguments = arguments("barcode-review")
        app.launch()
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertEqual(any(app, "barcode_batch_destination").label, destination)
        XCTAssertTrue(any(app, "barcode_batch_counts").label.contains("4 scanned"))
        save.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Done'"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 8), .completed)
    }

    @MainActor
    func testExportFailureShowsErrorAndNeverOpensAnEmptyShare() {
        let app = launch("settings", flags: ["-ui-testing-export-failure"])
        XCTAssertTrue(any(app, "settings_screen").waitForExistence(timeout: 15))
        let data = app.buttons["settings_open_data"]
        reveal(data, app: app)
        XCTAssertTrue(data.isHittable)
        data.tap()
        XCTAssertTrue(any(app, "settings_category_data").waitForExistence(timeout: 5))
        let export = app.buttons["settings_export_start"].firstMatch
        reveal(export, app: app)
        XCTAssertTrue(export.exists, app.debugDescription)
        export.tap()
        let error = any(app, "settings_export_error")
        reveal(error, app: app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(export.label.contains("Retry export"))
        record(app, "Export - failed domain is visible")
    }

    @MainActor
    func testCompletedWorkoutCorrectionKeepsSummaryAndAcceptsOriginalDayProjection() {
        let app = launch("workout-summary", flags: ["-ui-testing-workout-correction", "-ui-testing-reset-workout-correction"])
        let edit = app.buttons["workout_summary_edit"].firstMatch
        reveal(edit, app: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        edit.tap()
        let elapsed = app.textFields["workout_editor_elapsed_seconds"].firstMatch
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        replace(elapsed, with: "900", app: app)
        app.buttons["workout_editor_save"].firstMatch.tap()
        expectGone(app.buttons["workout_editor_save"].firstMatch, timeout: 10)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        record(app, "Workout correction - accepted without resetting program")
        edit.tap()
        elapsed.assertTextValue("900", within: app)
    }

    @MainActor
    func testWidgetRefreshReturnsFromYesterdayToTodaysDiary() throws {
        let app = launch("home")
        let previous = app.buttons["home_diary_previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        previous.tap()
        let calendar = app.buttons["home_diary_calendar"]
        let historical = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Historical day"), object: calendar)
        XCTAssertEqual(XCTWaiter.wait(for: [historical], timeout: 10), .completed)
        app.open(try XCTUnwrap(URL(string: "myfitplate://today")))
        let today = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Today"), object: calendar)
        XCTAssertEqual(XCTWaiter.wait(for: [today], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["home_diary_next"].isEnabled)
    }

    @MainActor
    func testActivityLinkOpensOnlyItsSavedWorkout() {
        let app = launch("home", flags: ["-ui-testing-active-workout-link-fixture", "-deep-link-url", "myfitplate://active-workout?id=old-workout"])
        XCTAssertTrue(app.staticTexts["Workout unavailable"].firstMatch.waitForExistence(timeout: 15))
        app.terminate()
        app.launchArguments = arguments("home", flags: ["-deep-link-url", "myfitplate://active-workout?id=qa-activity-workout"])
        app.launch()
        XCTAssertTrue(any(app, "workout_resumed").waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testRunAndFastActivityLinksReopenTheirOwnControls() {
        let app = launch("home", flags: ["-ui-testing-active-run-link-fixture", "-ui-testing-open-run-activity"])
        let resume = app.buttons["run_pause_resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(resume.label.localizedCaseInsensitiveContains("resume"), resume.label)
        app.terminate()
        app.launchArguments = arguments("home", flags: ["-ui-testing-open-fast-activity"])
        app.launch()
        XCTAssertTrue(any(app, "fasting_active_session").waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testExpiredRunAndFastLinksExplainTheMissingSession() {
        for (host, title) in [("active-run", "Run unavailable"), ("active-fast", "Fast unavailable")] {
            let app = launch("home", flags: ["-deep-link-url", "myfitplate://" + host + "?id=closed-session"])
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    @MainActor
    func testUnknownDeepLinkShowsUnavailableInsteadOfSilentlyOpeningHome() {
        let app = launch("home", flags: ["-deep-link-url", "myfitplate://unshipped-destination"])
        XCTAssertTrue(any(app, "deep_link_unavailable").waitForExistence(timeout: 15))
        app.buttons["deep_link_unavailable_home"].firstMatch.tap()
        expectGone(any(app, "deep_link_unavailable"), timeout: 5)
        XCTAssertTrue(app.scrollViews["home_scroll"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHistoricalRunGearStaysExplicitlyUnassignedAfterRelaunch() {
        let app = launch("run-detail-unassigned", flags: ["-ui-testing-reset-gear-assignment"])
        let gear = any(app, "run_detail_gear")
        reveal(gear, app: app)
        XCTAssertTrue(app.staticTexts["Unassigned"].firstMatch.exists)
        let change = app.buttons["Change running shoe"].firstMatch
        change.tap()
        app.buttons["QA · Wave 0 trainer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Gear tagged"].firstMatch.waitForExistence(timeout: 5))
        change.tap()
        app.buttons["None"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Unassigned"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments("run-detail-unassigned")
        app.launch()
        reveal(gear, app: app)
        XCTAssertTrue(app.staticTexts["Unassigned"].firstMatch.exists)
        record(app, "Gear - historical run stays explicitly unassigned")
    }

    @MainActor
    func testGearLifetimeMileageIncludesRunOutsideRecentHistory() {
        let app = launch("shoe-gear-lifetime")
        let total = any(app, "shoe_lifetime_distance_qa-wave0-lifetime-shoe")
        reveal(total, app: app)
        XCTAssertTrue(total.exists)
        XCTAssertTrue(total.label.contains("50.0 km") || total.label.contains("31.1 mi"), total.label)
        record(app, "Gear - lifetime includes 500-day-old run")
    }

    @MainActor
    func testSettingsAndProfileDeepLinksPresentRealDestinations() {
        let app = launch("home", flags: ["-deep-link-url", "myfitplate://settings"])
        XCTAssertTrue(any(app, "settings_screen").waitForExistence(timeout: 15))
        record(app, "Deep link - real Settings destination")
        app.buttons["Done"].firstMatch.tap()
        expectGone(any(app, "settings_screen"), timeout: 5)
        XCTAssertTrue(app.scrollViews["home_scroll"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments("home", flags: ["-deep-link-url", "myfitplate://profile"])
        app.launch()
        XCTAssertTrue(any(app, "profile_progress_summary").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["profile_weekly_challenges_button"].exists)
        record(app, "Deep link - real Profile destination")
        app.buttons["Done"].firstMatch.tap()
        expectGone(any(app, "profile_progress_summary"), timeout: 5)
        XCTAssertTrue(app.scrollViews["home_scroll"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(_ screen: String, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments(screen, flags: flags)
        app.launch()
        return app
    }

    private func arguments(_ screen: String, flags: [String] = []) -> [String] {
        ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags
    }

    @MainActor
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        if element.exists, element.isHittable { return }
        for _ in 0..<4 {
            app.scrollViews.firstMatch.swipeDown()
            if element.exists, element.isHittable { return }
        }
        for _ in 0..<14 {
            if element.exists, element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
    }

    @MainActor
    private func replace(_ field: XCUIElement, with value: String, app: XCUIApplication) {
        reveal(field, app: app)
        field.replaceContents(with: value, in: app)
    }

    private func expectGone(_ element: XCUIElement, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
