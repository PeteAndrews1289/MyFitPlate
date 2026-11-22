import XCTest

/// Synthetic-account journeys, never run on the owner's installed app or original simulator.
final class InventoryFlowsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private let rawID = "00000000-0000-0000-0000-000000000201"
    private let legacyID = "00000000-0000-0000-0000-000000000202"

    @MainActor
    func testLegacyQuantityConfirmationCookConsumeAndStockUndo() {
        let app = launch()
        openPantry(app)
        let legacyOptions = app.buttons["Options for Legacy pantry amount"]
        reveal(legacyOptions, app: app); legacyOptions.tap()
        let edit = app.buttons["Edit / confirm amount"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let quantity = app.textFields["inventory_item_quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["inventory_item_name"].value as? String, "Legacy pantry amount", app.debugDescription)
        XCTAssertTrue(text(app, "inventory_item_editor").contains("original amount"))
        let review = app.buttons["inventory_item_review"]
        reveal(review, app: app)
        XCTAssertTrue(review.isHittable, app.debugDescription)
        review.tap()
        saveReview(app)
        closePantry(app)
        select("Cook", app: app)
        recordCooking(app)
        let remaining = any(app, "inventory_batch_remaining_wave2-cooking-batch")
        reveal(remaining, app: app)
        XCTAssertTrue(remaining.label.contains("4 original portions"))
        select("Plan", app: app)
        let use = app.buttons["planner_use_stock_wave2-cooking-dinner"]
        reveal(use, app: app); use.tap()
        let alsoLog = app.switches["inventory_consume_also_log"]
        XCTAssertTrue(alsoLog.waitForExistence(timeout: 5))
        app.buttons["inventory_consume_review"].tap()
        XCTAssertTrue(any(app, "inventory_review_list").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "inventory_review_list").contains("Food diary"))
        saveReview(app)
        let recorded = any(app, "planner_stock_used_wave2-cooking-dinner")
        reveal(recorded, app: app)
        XCTAssertTrue(recorded.exists, "The same planned occurrence no longer offers another stock deduction")
        app.buttons["tab_home"].tap()
        let foods = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'diary_food_' AND NOT identifier BEGINSWITH 'diary_food_options_' AND label CONTAINS %@",
            "Four-portion rice batch"))
        reveal(foods.firstMatch, app: app)
        XCTAssertEqual(foods.count, 1, app.debugDescription)
        XCTAssertTrue(foods.firstMatch.label.contains("400"), "The accepted stock portion must appear once with its personal nutrition.\n\(app.debugDescription)")
        app.buttons["tab_meal_plan"].tap()
        openPantry(app)
        let tools = app.buttons["inventory_tools"]
        reveal(tools, app: app); tools.tap()
        let history = app.buttons["inventory_history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inventory_undo_")).firstMatch
        reveal(undo, app: app); undo.tap()
        XCTAssertTrue(any(app, "inventory_review_list").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "inventory_review_list").contains("Remove linked food entry"))
        saveReview(app)
        app.navigationBars["Stock history"].buttons["Done"].tap()
        closePantry(app)
        select("Plan", app: app)
        reveal(use, app: app)
        XCTAssertTrue(use.isEnabled, "Undo restores this allocation's stock-use availability without resetting the plan")
        app.buttons["tab_home"].tap()
        XCTAssertTrue(foods.firstMatch.waitForNonExistence(timeout: 10), "Checked stock Undo removes its matching diary food.\n\(app.debugDescription)")
        attach(app, "Inventory - confirmed legacy quantity, cooked batch, consumed planned portion, and checked Undo")
    }

    @MainActor
    func testShoppingStopsRebuyingCookedBatchAndPreservesManualNeed() {
        let app = launch()
        select("Shop", app: app)
        let rice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@", "grocery_item_", "dry rice")).firstMatch
        reveal(rice, app: app)
        XCTAssertTrue((rice.value as? String ?? "").contains("400 g"))
        select("Cook", app: app)
        recordCooking(app)
        select("Shop", app: app)
        XCTAssertTrue(rice.waitForNonExistence(timeout: 10), "An actually cooked batch must not request its raw ingredients again")
        let manual = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@", "grocery_item_", "Electrolyte packets")).firstMatch
        reveal(manual, app: app)
        XCTAssertTrue(manual.exists)
        attach(app, "Inventory - cooked batch removes duplicate raw purchase while manual need stays")
    }

    /// One connected journey across two actual plan dates. Committed mock server
    /// records are process-local; native repository tests cover their durable replay.
    @MainActor
    func testFourPortionBatchAndNextDayLeftoverShareStockWithoutRebuyingOrDuplicateDiaryFood() {
        let app = launch(flags: ["-ui-testing-inventory-yesterday-batch"])
        selectPlannedDay(offset: -1, app: app)
        select("Shop", app: app)
        let rice = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[cd] %@", "grocery_item_", "dry rice")).firstMatch
        reveal(rice, app: app)
        XCTAssertTrue((rice.value as? String ?? "").contains("400 g"), "The shared batch needs four original 100 g portions once")

        select("Cook", app: app)
        recordCooking(app)
        assertRecordedPortions(4, app: app)
        select("Plan", app: app)
        consumePlannedPortion(app.buttons["planner_use_stock_wave2-cooking-dinner"], app: app)
        XCTAssertTrue(any(app, "planner_stock_used_wave2-cooking-dinner").waitForExistence(timeout: 10))
        select("Cook", app: app)
        assertRecordedPortions(3, app: app)
        select("Shop", app: app)
        XCTAssertTrue(rice.waitForNonExistence(timeout: 10), "Eating the first portion cannot purchase the cooked raw ingredients again")

        app.buttons["tab_home"].tap()
        let previous = app.buttons["home_diary_previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10)); previous.tap()
        assertOneRiceFood(app)
        app.buttons["tab_meal_plan"].tap()
        // The app reconstructs this tab at Today; its workspace is remembered,
        // while the earlier source date is selected explicitly for this action.
        selectPlannedDay(offset: -1, app: app)
        let options = app.buttons["planner_meal_options_wave2-cooking-dinner"]
        reveal(options, app: app); options.tap()
        let leftovers = app.buttons["planner_plan_leftovers_wave2-cooking-dinner"]
        XCTAssertTrue(leftovers.waitForExistence(timeout: 5)); leftovers.tap()
        let confirm = app.buttons["planner_leftover_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let review = any(app, "planner_leftover_review")
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let nutrition = app.staticTexts["planner_leftover_nutrition"]
        XCTAssertTrue(nutrition.waitForExistence(timeout: 10))
        XCTAssertEqual(nutrition.label, "400 cal · 25 g protein", "The next-day allocation remains one personal portion")
        let readyToSave = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Plan leftovers"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [readyToSave], timeout: 10), .completed)
        reveal(confirm, app: app)
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10))

        let today = app.buttons["planner_return_today"]
        reveal(today, app: app); today.tap()
        let nextDayUse = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "planner_use_stock_")).firstMatch
        XCTAssertTrue(nextDayUse.waitForExistence(timeout: 10))
        let leftoverID = nextDayUse.identifier.replacingOccurrences(of: "planner_use_stock_", with: "")
        consumePlannedPortion(nextDayUse, app: app)
        let used = any(app, "planner_stock_used_" + leftoverID)
        XCTAssertTrue(used.waitForExistence(timeout: 10), "The actual leftover occurrence receives its own accepted stock-use receipt")

        openPantry(app)
        assertPantryQuantity(named: "dry rice", quantity: "600", app: app)
        assertPantryQuantity(named: "Four-portion rice batch", quantity: "2", app: app)
        closePantry(app)
        select("Shop", app: app)
        XCTAssertTrue(rice.waitForNonExistence(timeout: 10), "Planning and eating the leftover cannot reintroduce the original raw shopping requirement")
        app.buttons["tab_home"].tap()
        let diaryToday = app.buttons["home_diary_today"]
        XCTAssertTrue(diaryToday.waitForExistence(timeout: 10)); diaryToday.tap()
        assertOneRiceFood(app)

        // Reopening each ordinary destination must read accepted outcomes without
        // offering another deduction or generating another food for either date.
        app.buttons["tab_meal_plan"].tap()
        select("Plan", app: app)
        reveal(used, app: app)
        XCTAssertTrue(used.exists)
        XCTAssertFalse(nextDayUse.exists)
        app.buttons["tab_home"].tap()
        assertOneRiceFood(app)
        app.buttons["home_diary_previous"].tap()
        assertOneRiceFood(app)
        attach(app, "Four portions - dinner and next-day leftover retain raw 600 g, cooked 2 portions, and one food on each day")
    }

    @MainActor
    func testFailedStockReviewSurvivesRelaunchAndCanBeFencedCancelled() {
        let flags = ["-ui-testing-inventory-save-failure"]
        let app = launch(flags: flags)
        select("Cook", app: app)
        openCookingReview(app)
        let save = rejectStockSave(app)
        app.navigationBars["Review stock"].buttons["Close"].tap()
        app.navigationBars["Record cooking"].buttons["Cancel"].tap()
        app.terminate(); _ = launch(flags: flags, reset: false, app: app)
        select("Cook", app: app)
        let resume = app.buttons["inventory_cook_resume"]
        reveal(resume, app: app); resume.tap()
        waitForStockReview(app)
        let check = app.buttons["inventory_check_status"]
        reveal(check, app: app); XCTAssertGreaterThanOrEqual(check.frame.height, 44); check.tap()
        let pending = any(app, "inventory_review_error")
        let pendingExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "No saved receipt yet"), object: pending)
        XCTAssertEqual(XCTWaiter.wait(for: [pendingExpectation], timeout: 10), .completed)
        let cancel = app.buttons["inventory_cancel_pending"]
        reveal(cancel, app: app); XCTAssertGreaterThanOrEqual(cancel.frame.height, 44); cancel.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Done"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed)
        save.tap()
        let record = app.buttons["inventory_record_cooked_wave2-cooking-batch"]
        reveal(record, app: app)
        XCTAssertTrue(record.exists, "A cancelled cooking save creates neither cooked stock nor a raw deduction")
        attach(app, "Inventory - frozen failed review resumed and cancelled with server fence")
    }

    @MainActor
    func testLargestTextDarkRejectedStockSaveKeepsFeedbackAndRecoveryReachable() {
        let app = launch(flags: ["-ui-testing-inventory-save-failure", "-screenshot-dark-mode",
                                 "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        select("Cook", app: app)
        openCookingReview(app)
        let save = rejectStockSave(app)
        let error = any(app, "inventory_review_error")
        let footer = any(app, "inventory_review_footer")
        XCTAssertTrue(error.isHittable, app.debugDescription)
        XCTAssertTrue(app.frame.contains(error.frame), app.debugDescription)
        XCTAssertLessThanOrEqual(error.frame.maxY, save.frame.minY, "Feedback must remain above the action.\n\(app.debugDescription)")
        XCTAssertTrue(footer.frame.contains(error.frame), app.debugDescription)
        XCTAssertTrue(footer.frame.contains(save.frame), app.debugDescription)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44, app.debugDescription)
        let check = app.buttons["inventory_check_status"]
        reveal(check, app: app)
        XCTAssertTrue(check.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44, app.debugDescription)
        XCTAssertLessThanOrEqual(check.frame.maxY, footer.frame.minY, app.debugDescription)
        check.tap()
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "No saved receipt yet"), object: error)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 10), .completed, app.debugDescription)
        let cancel = app.buttons["inventory_cancel_pending"]
        reveal(cancel, app: app)
        XCTAssertTrue(cancel.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44, app.debugDescription)
        XCTAssertLessThanOrEqual(cancel.frame.maxY, footer.frame.minY, app.debugDescription)
        attach(app, "Inventory - largest text dark rejected save feedback and recovery")
        cancel.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Done"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed, app.debugDescription)
        save.tap()
    }

    @MainActor
    func testIndependentNamedTimersPersistAcrossRelaunch() {
        let app = launch()
        select("Cook", app: app)
        addNamedTimer("Rice", app: app)
        addNamedTimer("Oven", app: app)
        let timers = app.descendants(matching: .other).matching(NSPredicate(format: "identifier BEGINSWITH 'cooking_named_timer_'"))
        let pauseRice = timers.buttons["Pause Rice"]
        reveal(pauseRice, app: app); pauseRice.tap()
        XCTAssertTrue(timers.buttons["Resume Rice"].waitForExistence(timeout: 5))
        app.terminate(); _ = launch(reset: false, app: app)
        select("Cook", app: app)
        let resumeRice = timers.buttons["Resume Rice"]
        reveal(resumeRice, app: app)
        XCTAssertTrue(resumeRice.exists)
        let pauseOven = timers.buttons["Pause Oven"]
        reveal(pauseOven, app: app)
        XCTAssertTrue(pauseOven.exists, "Pausing Rice must not pause Oven")
        attach(app, "Cooking - independent named timers restored")
    }

    @MainActor
    private func launch(flags: [String] = [], reset: Bool = true, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan", "-ui-testing-wave2-inventory"]
            + flags + (reset ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        let workspace = app.segmentedControls["planner_workspace"]
        // A newly installed simulator app can first launch without fixture arguments.
        // Retry only its recognized Welcome surface, never a failed stock assertion.
        if !workspace.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(workspace.waitForExistence(timeout: 10), app.debugDescription)
        return app
    }
    @MainActor private func select(_ mode: String, app: XCUIApplication) {
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5)); workspace.buttons[mode].tap()
    }
    @MainActor private func selectPlannedDay(offset: Int, app: XCUIApplication) {
        select("Plan", app: app)
        let mode = app.buttons["planner_view_mode"]
        reveal(mode, app: app); mode.tap()
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["planner_agenda_" + formatter.string(from: date)]
        if !day.waitForExistence(timeout: 5) {
            let previous = app.buttons["planner_previous_week"]
            reveal(previous, app: app); previous.tap()
        }
        reveal(day, app: app); day.tap()
        XCTAssertTrue(app.buttons["planner_meal_options_wave2-cooking-dinner"].waitForExistence(timeout: 10))
    }
    @MainActor private func assertRecordedPortions(_ amount: Int, app: XCUIApplication) {
        let remaining = any(app, "inventory_batch_remaining_wave2-cooking-batch")
        reveal(remaining, app: app)
        XCTAssertTrue(remaining.label.contains("\(amount) original portions left"), remaining.label)
    }
    @MainActor private func consumePlannedPortion(_ use: XCUIElement, app: XCUIApplication) {
        reveal(use, app: app); XCTAssertTrue(use.isEnabled); use.tap()
        XCTAssertTrue(app.switches["inventory_consume_also_log"].waitForExistence(timeout: 5))
        let review = app.buttons["inventory_consume_review"]
        reveal(review, app: app); review.tap()
        XCTAssertTrue(any(app, "inventory_review_list").waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, "inventory_review_list").contains("Food diary"))
        saveReview(app)
    }
    @MainActor private func assertPantryQuantity(named name: String, quantity: String, app: XCUIApplication) {
        let options = app.buttons["Options for " + name]
        reveal(options, app: app); options.tap()
        let edit = app.buttons["Edit / confirm amount"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let amount = app.textFields["inventory_item_quantity"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, quantity, "The accepted stock amount must be read back independently from the receipt")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
    }
    @MainActor private func assertOneRiceFood(_ app: XCUIApplication) {
        let foods = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'diary_food_' AND NOT identifier BEGINSWITH 'diary_food_options_' AND label CONTAINS %@",
            "Four-portion rice batch"))
        reveal(foods.firstMatch, app: app)
        XCTAssertEqual(foods.count, 1, app.debugDescription)
        XCTAssertTrue(foods.firstMatch.label.contains("400"), "Each day contains its own one-portion nutrition.\n\(app.debugDescription)")
    }
    @MainActor private func openPantry(_ app: XCUIApplication) {
        select("Shop", app: app)
        let pantry = app.buttons["planner_shop_pantry"]
        reveal(pantry, app: app); pantry.tap()
        XCTAssertTrue(app.textFields["inventory_search"].waitForExistence(timeout: 10))
    }
    @MainActor private func closePantry(_ app: XCUIApplication) {
        let close = app.buttons["Close Smart Pantry"].firstMatch
        if close.exists { close.tap() } else {
            let closeButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] %@", "Close")).firstMatch
            XCTAssertTrue(closeButton.exists); closeButton.tap()
        }
    }
    @MainActor private func openCookingReview(_ app: XCUIApplication) {
        let record = app.buttons["inventory_record_cooked_wave2-cooking-batch"]
        reveal(record, app: app); record.tap()
        XCTAssertTrue(app.navigationBars["Record cooking"].waitForExistence(timeout: 10), app.debugDescription)
        let picker = app.buttons["inventory_cook_lot_0"]
        reveal(picker, app: app)
        XCTAssertTrue(picker.isHittable, app.debugDescription)
        picker.tap()
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[cd] %@", "dry rice")).firstMatch
        XCTAssertTrue(raw.waitForExistence(timeout: 5), app.debugDescription)
        raw.tap()
        let review = app.buttons["inventory_cook_review"]
        reveal(review, app: app)
        XCTAssertTrue(review.isHittable, app.debugDescription)
        review.tap()
        waitForStockReview(app)
        let amount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "600")).firstMatch
        reveal(amount, app: app)
        XCTAssertTrue(amount.label.contains("600"), app.debugDescription)
    }
    @MainActor private func recordCooking(_ app: XCUIApplication) { openCookingReview(app); saveReview(app) }
    @MainActor private func waitForStockReview(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Review stock"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(any(app, "inventory_review_list").waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func rejectStockSave(_ app: XCUIApplication) -> XCUIElement {
        waitForStockReview(app)
        let save = app.buttons["inventory_review_confirm"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(save.isHittable, app.debugDescription)
        save.tap()
        XCTAssertTrue(any(app, "inventory_review_error").waitForExistence(timeout: 10), app.debugDescription)
        return save
    }
    @MainActor private func saveReview(_ app: XCUIApplication) {
        waitForStockReview(app)
        let save = app.buttons["inventory_review_confirm"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(save.isHittable, app.debugDescription)
        save.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Done"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 15), .completed, app.debugDescription)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func addNamedTimer(_ name: String, app: XCUIApplication) {
        let add = app.buttons["cooking_add_named_timer"]
        reveal(add, app: app); add.tap()
        let field = app.textFields["cooking_timer_name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.tap(); field.typeText(name + "\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        let start = app.buttons["meal_prep_timer_start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(start.isHittable, app.debugDescription)
        start.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }
    @MainActor private func text(_ app: XCUIApplication, _ id: String) -> String {
        let element = any(app, id)
        return ([element.label] + element.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let identifiers = ["planner_leftover_form", "inventory_review_list", "inventory_item_editor", "inventory_cook_form", "inventory_consume_form",
                           "inventory_history_list", "inventory_pantry_scroll", "meal_prep_screen", "grocery_list", "meal_plan_scroll", "home_scroll"]
        let scroll = identifiers.lazy.compactMap { id -> XCUIElement? in
            let list = app.collectionViews[id].firstMatch
            if list.exists, list.isHittable { return list }
            let view = app.scrollViews[id].firstMatch
            if view.exists, view.isHittable { return view }
            let table = app.tables[id].firstMatch
            if table.exists, table.isHittable { return table }
            let root = self.any(app, id)
            guard root.exists else { return nil }
            return (root.collectionViews.allElementsBoundByIndex + root.scrollViews.allElementsBoundByIndex
                + root.tables.allElementsBoundByIndex).filter(\.isHittable)
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        }.first ?? (app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex)
            .filter { $0.isHittable && $0.identifier != "meal_plan_week" }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for index in 0..<35 {
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            var top = max(scroll?.frame.minY ?? app.frame.minY + 90, nav?.frame.maxY ?? app.frame.minY + 20) + 5
            let workspace = app.segmentedControls["planner_workspace"]
            if nav == nil, workspace.exists, workspace.isHittable { top = max(top, workspace.frame.maxY + 5) }
            var bottom = min(scroll?.frame.maxY ?? app.frame.maxY - 70, app.frame.maxY - 70) - 5
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            let pinnedIDs = ["inventory_review_confirm", "inventory_item_review", "inventory_cook_review", "inventory_consume_review",
                             "meal_prep_timer_start", "planner_leftover_confirm"]
            let pinned = pinnedIDs.map { app.buttons[$0] }.filter { $0.exists && $0.isHittable }
            if element.exists, element.isHittable, app.frame.contains(element.frame),
               pinned.contains(where: { $0.identifier == element.identifier }) { return }
            if let footerTop = pinned.map(\.frame.minY).filter({ $0 > top }).min() { bottom = min(bottom, footerTop - 5) }
            let footer = any(app, "inventory_review_footer")
            if footer.exists, footer.isHittable { bottom = min(bottom, footer.frame.minY - 5) }
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let above = element.exists && element.frame.height > 0 ? element.frame.minY < top : index > 20
            let distance = min(CGFloat(150), (bottom - top) * 0.4)
            let start = top + (bottom - top) * 0.5
            let end = min(bottom - 8, max(top + 8, start + (above ? distance : -distance)))
            origin.withOffset(CGVector(dx: app.frame.midX, dy: start))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable control: \(element.identifier)\n\(app.debugDescription)")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
