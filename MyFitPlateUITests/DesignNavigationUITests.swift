import XCTest

/// Read-only navigation checks against the mock screenshot account. These journeys never
/// start a workout, log a food, change a plan, or reset any saved draft.
@MainActor
final class DesignNavigationUITests: XCTestCase {
    private let destinations: [(id: String, label: String, surface: String)] = [
        ("tab_home", "Home", "home_screen_header"),
        ("tab_train", "Train", "train_screen_header"),
        ("tab_meal_plan", "Meal Plan", "planner_workspace"),
        ("tab_reports", "Reports", "reports_screen_header"),
        ("tab_maia", "Maia", "maia_screen_header")
    ]

    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompactDockKeepsEveryDestinationAndFoodSearchReachable() throws {
        try exerciseNavigation(largestText: false)
    }

    func testLargestTextDockKeepsEveryDestinationAndFoodSearchReachable() throws {
        try exerciseNavigation(largestText: true)
    }

    func testGlobalPlusKeepsBackdatedDestinationAndOnlyUndoesTheReviewedPortion() throws {
        let app = launch(largestText: false)
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let previous = app.buttons["home_diary_previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 8))
        previous.tap()
        let energy = app.descendants(matching: .any).matching(identifier: "home_calories_remaining").firstMatch
        XCTAssertTrue(energy.waitForExistence(timeout: 8))
        let before = energy.label
        app.buttons["quick_log_button"].tap()
        let destination = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        XCTAssertTrue(destination.label.contains(yesterday.formatted(date: .complete, time: .omitted)))
        destination.tap()
        app.buttons["Lunch"].tap()
        let field = app.textFields["food_search_field"]
        field.tap()
        field.typeText("apple\n")
        app.buttons["food_picker_row_ui-test-apple"].tap()
        app.buttons["food_portion_double"].tap()
        app.buttons["food_detail_log_action"].tap()
        let undo = app.buttons["food_search_undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 8))
        XCTAssertTrue(destination.label.contains("Lunch"))
        XCTAssertTrue(destination.label.contains(yesterday.formatted(date: .complete, time: .omitted)))
        undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(energy.waitForExistence(timeout: 8))
        XCTAssertEqual(energy.label, before)
    }

    func testMealDisclosureAndTrainingPreviewsAreReversible() {
        let app = launch(largestText: false)
        let meal = app.buttons["diary_toggle_Breakfast"]
        for _ in 0..<5 where !meal.isHittable { app.scrollViews["home_scroll"].swipeUp() }
        XCTAssertTrue(meal.isHittable)
        meal.tap()
        XCTAssertEqual(meal.value as? String, "Collapsed")
        XCTAssertTrue(app.buttons["diary_add_Breakfast"].isHittable)
        meal.tap()
        XCTAssertEqual(meal.value as? String, "Expanded")

        app.buttons["tab_train"].tap()
        let current = app.staticTexts["Session 40 of 48"]
        XCTAssertTrue(current.waitForExistence(timeout: 8))
        let preview = app.buttons["train_exercise_preview"]
        preview.tap()
        XCTAssertEqual(preview.value as? String, "Expanded")
        app.buttons["Next session"].tap()
        XCTAssertTrue(app.staticTexts["Session 41 of 48"].exists)
        app.buttons["train_return_to_current"].tap()
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertEqual(preview.value as? String, "Collapsed")
    }

    func testMaiaComposerMakesRoomForTypingAndRestoresNavigation() {
        let app = launch(largestText: false)
        app.buttons["tab_maia"].tap()
        let input = app.textFields["maia_message_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        let close = app.buttons["maia_close_keyboard"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["tab_home"].exists)
        if app.keyboards.firstMatch.exists && app.keyboards.firstMatch.frame.minY < app.frame.height {
            XCTAssertLessThanOrEqual(input.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        }
        close.tap()
        XCTAssertTrue(app.buttons["tab_home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["maia_recommended_action"].isHittable)
        record(app, name: "Maia - coaching and composer")
    }

    func testReportDateControlsStayAvailableAcrossFocusChanges() {
        let app = launch(largestText: false)
        app.buttons["tab_reports"].tap()
        let dates = app.segmentedControls["reports_timeframe"]
        XCTAssertTrue(dates.waitForExistence(timeout: 8))
        dates.buttons["30 days"].tap()
        let focus = app.segmentedControls["reports_focus"]
        focus.buttons["Training"].tap()
        XCTAssertTrue(dates.buttons["30 days"].isSelected)
        dates.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        dates.buttons["7 days"].tap()
        XCTAssertFalse(app.datePickers.firstMatch.exists)
    }

    private func exerciseNavigation(largestText: Bool) throws {
        let app = launch(largestText: largestText)
        let presentation = largestText ? "Largest text dark" : "Compact light"
        XCTAssertLessThanOrEqual(app.frame.width, 430,
                                 "Run these compact navigation checks on an iPhone simulator at most 430 points wide.")

        for destination in destinations {
            let tab = app.buttons[destination.id]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), app.debugDescription)
            tab.tap()
            let surface = app.descendants(matching: .any)
                .matching(identifier: destination.surface).firstMatch
            XCTAssertTrue(surface.waitForExistence(timeout: 15),
                          "The \(destination.label) destination must actually render.\n\(app.debugDescription)")
            waitForSelection(tab)
            assertDock(app, selectedID: destination.id)
            record(app, name: "\(presentation) - \(destination.label)")
        }

        app.buttons["tab_home"].tap()
        waitForSelection(app.buttons["tab_home"])
        // Keep everyday navigation independent from the separately requested
        // large-text audit so the normal flow remains a focused regression check.
        if largestText { try auditDock(app) }

        // Opening and closing search is intentionally read-only. A food is never selected.
        app.buttons["quick_log_button"].tap()
        let field = app.textFields["food_search_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(field.isHittable)
        record(app, name: "\(presentation) - food search in one tap")
        XCTAssertTrue(app.buttons["food_search_action_camera"].exists)
        XCTAssertTrue(app.buttons["food_search_action_barcode"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), app.debugDescription)
        assertDock(app, selectedID: "tab_home")
    }

    private func launch(largestText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-screenshot-mode", "-screenshot-screen", "home",
            "-living-day-home", "-ui-testing-wave2-phul",
            "-UIPreferredContentSizeCategoryName",
            largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ] + (largestText ? ["-screenshot-dark-mode"] : [])
        app.launch()
        let home = app.buttons["tab_home"]
        if !home.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func waitForSelection(_ tab: XCUIElement) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The destination must expose its selected accessibility trait.")
    }

    private func assertDock(_ app: XCUIApplication, selectedID: String) {
        let dock = app.descendants(matching: .any).matching(identifier: "main_navigation_dock").firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertLessThanOrEqual(dock.frame.height, 90,
                                 "Navigation must remain one compact row instead of covering the lower content.")
        let controls = destinations.map { app.buttons[$0.id] } + [app.buttons["quick_log_button"]]
        for control in controls {
            XCTAssertTrue(control.isHittable, "\(control.identifier) must remain reachable.")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, control.identifier)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, control.identifier)
            XCTAssertTrue(app.frame.insetBy(dx: -0.5, dy: -0.5).contains(control.frame),
                          "\(control.identifier) must be fully on screen.")
            XCTAssertTrue(dock.frame.insetBy(dx: -0.5, dy: -0.5).contains(control.frame),
                          "\(control.identifier) must have its entire touch region inside the dock.")
        }
        for first in controls.indices {
            for second in controls.indices where second > first {
                let overlap = controls[first].frame.intersection(controls[second].frame)
                XCTAssertTrue(overlap.isNull || overlap.width < 0.5 || overlap.height < 0.5,
                              "\(controls[first].identifier) must not overlap \(controls[second].identifier).")
            }
        }
        for destination in destinations {
            let tab = app.buttons[destination.id]
            XCTAssertEqual(tab.label, destination.label)
            XCTAssertEqual(tab.isSelected, destination.id == selectedID, destination.id)
        }
        XCTAssertEqual(app.buttons["quick_log_button"].label, "Log food")
    }

    private func auditDock(_ app: XCUIApplication) throws {
        let dock = app.descendants(matching: .any).matching(identifier: "main_navigation_dock").firstMatch
        let dockIdentifiers = Set(dock.descendants(matching: .any).allElementsBoundByIndex
            .map(\.identifier).filter { !$0.isEmpty }).union(["main_navigation_dock"])
        let requiredIdentifiers = Set(destinations.map(\.id) + ["quick_log_button"])
        XCTAssertTrue(requiredIdentifiers.isSubset(of: dockIdentifiers),
                      "All six navigation controls must be actual descendants of the dock.")
        // This test owns the shared dock. Other feature surfaces have their own audits.
        // Scroll content may retain frames below its clipped viewport; geometric overlap
        // would incorrectly treat those partially visible rows as navigation controls.
        // Unidentified findings still fail rather than being silently waived.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped]) { issue in
            guard let element = issue.element, !element.identifier.isEmpty else { return false }
            return !dockIdentifiers.contains(element.identifier)
        }
    }

    private func record(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let evidence = XCTAttachment(string: app.debugDescription)
        evidence.name = "\(name) - accessibility tree and frames"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
