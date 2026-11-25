import XCTest

@MainActor
final class MealPlannerTabNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEmptyPlannerOpensFromHomeAndRestoresEachWorkspaceAfterLeavingTab() {
        exerciseTabNavigation(empty: true)
    }

    func testSavedPlannerOpensFromHomeAndRestoresEachWorkspaceAfterLeavingTab() {
        exerciseTabNavigation(empty: false)
    }

    func testPlannerKeepsSelectedDateAndDayWeekViewAcrossTabReturns() {
        let app = launchDesignFixture()
        app.buttons["tab_meal_plan"].tap()
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15))
        workspace.buttons["Plan"].tap()
        let mode = app.buttons["planner_view_mode"]
        XCTAssertEqual(mode.label, "Show week")
        mode.tap()
        let previous = app.buttons["planner_previous_week"]
        XCTAssertTrue(previous.waitForExistence(timeout: 10)); previous.tap()
        let calendar = app.buttons["planner_choose_date"]
        let selectedDate = calendar.value as? String
        XCTAssertNotNil(selectedDate)

        app.buttons["tab_home"].tap()
        app.buttons["tab_meal_plan"].tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        XCTAssertEqual(calendar.value as? String, selectedDate, "Tab return keeps the browsed plan date.")
        XCTAssertEqual(mode.label, "Show selected day", "Tab return keeps the weekly overview.")

        workspace.buttons["Shop"].tap()
        app.buttons["tab_home"].tap()
        app.buttons["tab_meal_plan"].tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        XCTAssertTrue(workspace.buttons["Shop"].isSelected)
        XCTAssertEqual(calendar.value as? String, selectedDate, "Shopping stays on the same week.")
        workspace.buttons["Plan"].tap()
        XCTAssertEqual(mode.label, "Show selected day")

        calendar.tap()
        XCTAssertTrue(app.navigationBars["Choose plan date"].waitForExistence(timeout: 5), "The visible date opens the calendar directly.")
        app.navigationBars["Choose plan date"].buttons["Cancel"].tap()
        XCTAssertEqual(calendar.value as? String, selectedDate)
        record(app, name: "Design - planner retains date and view, with direct calendar access")
    }

    func testCookingCompletesAndAdvancesOneStepThenRestoresItsCheck() {
        let app = launchDesignFixture(flags: ["-ui-testing-wave2-cooking-batch"])
        app.buttons["tab_meal_plan"].tap()
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15)); workspace.buttons["Cook"].tap()
        let mode = app.segmentedControls["meal_prep_mode_picker"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15)); mode.buttons["Steps"].tap()
        let current = app.descendants(matching: .any).matching(identifier: "cooking_current_step").firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        let complete = app.buttons["cooking_complete_current_step"]
        revealDesignControl(complete, app: app)
        XCTAssertEqual(complete.label, "Complete & next")
        let before = current.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        complete.tap()
        let nextStep = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            current.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ") != before
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [nextStep], timeout: 5), .completed)
        let previous = app.buttons["cooking_previous_step"]
        revealDesignControl(previous, app: app); previous.tap()
        XCTAssertEqual(complete.label, "Mark incomplete", "Completing and advancing preserves the previous step's saved check.")

        app.buttons["tab_home"].tap()
        app.buttons["tab_meal_plan"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        XCTAssertTrue(mode.buttons["Steps"].isSelected, "Returning to cooking keeps the active task without another mode switch.")
        revealDesignControl(complete, app: app)
        XCTAssertEqual(complete.label, "Mark incomplete", "The saved check survives reconstruction of the cooking workspace.")
        mode.buttons["Ingredients"].tap()
        app.buttons["tab_home"].tap()
        app.buttons["tab_meal_plan"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        XCTAssertTrue(mode.buttons["Ingredients"].isSelected, "A deliberate mode change is remembered too.")
        record(app, name: "Design - cooking completes and advances without losing checked work")
    }

    private func launchDesignFixture(flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home",
                               "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] + flags
        app.launch()
        let home = app.buttons["tab_home"]
        if !home.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func revealDesignControl(_ control: XCUIElement, app: XCUIApplication) {
        let surface = app.scrollViews.matching(identifier: "meal_prep_scroll").firstMatch
        for _ in 0..<8 {
            if control.exists, control.isHittable, control.frame.maxY < app.frame.maxY - 120 { return }
            if surface.exists { surface.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(control.isHittable, app.debugDescription)
    }

    func testLargestTextTrainAndPlannerExposeNamedReachableControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-screenshot-mode", "-screenshot-screen", "train",
            "-ui-testing-wave2-phul", "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft",
            "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        let program = app.buttons["train_program_overview"]
        if !program.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(program.waitForExistence(timeout: 15), app.debugDescription)
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        record(app, name: "Largest text - Train named controls and touch targets")

        app.buttons["tab_meal_plan"].tap()
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15), app.debugDescription)
        for mode in ["Plan", "Shop", "Cook"] {
            workspace.buttons[mode].tap()
            assertWorkspace(mode, app: app)
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
            record(app, name: "Largest text - \(mode) named controls and touch targets")
        }
    }

    private func record(_ app: XCUIApplication, name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func exerciseTabNavigation(empty: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home",
                               "-ui-testing-wave2-phul", "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"]
            + (empty ? ["-ui-testing-planner-blank"] : [])
        app.launch()
        let home = app.buttons["tab_home"]
        if !home.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        let planner = app.buttons["tab_meal_plan"]
        planner.tap()
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 15), "The real tab-bar entry must keep the app running.\n\(app.debugDescription)")
        for mode in ["Plan", "Shop", "Cook"] {
            workspace.buttons[mode].tap()
            assertWorkspace(mode, app: app)
            home.tap()
            XCTAssertTrue(home.waitForExistence(timeout: 5))
            planner.tap()
            XCTAssertTrue(workspace.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(workspace.buttons[mode].isSelected, "Returning must restore the selected workspace")
            assertWorkspace(mode, app: app)
        }
        workspace.buttons["Plan"].tap()
        XCTAssertTrue(app.buttons["meal_plan_tools"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = empty ? "Tab entry - empty planner remains usable" : "Tab entry - saved planner remains usable"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func assertWorkspace(_ mode: String, app: XCUIApplication) {
        let id = mode == "Shop" ? "grocery_list" : mode == "Cook" ? "meal_prep_screen" : "meal_plan_tools"
        let surface = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 15), "\(mode) must render after entry.\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["tab_home"].isHittable)
    }
}
