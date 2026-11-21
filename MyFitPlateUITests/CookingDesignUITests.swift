import XCTest

@MainActor
final class CookingDesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStepTimerStaysReachableInGuidedCookingWithDirectPauseAndInspector() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan",
                               "-ui-testing-wave2-cooking-batch", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let workspace = app.segmentedControls["planner_workspace"]
        if !workspace.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(workspace.waitForExistence(timeout: 15)); workspace.buttons["Cook"].tap()
        let mode = app.segmentedControls["meal_prep_mode_picker"]
        reveal(mode, app: app); mode.buttons["Steps"].tap()
        let ingredients = app.buttons["cooking_step_ingredients"]
        let amount = app.descendants(matching: .any).matching(identifier: "cooking_step_ingredient_0").firstMatch
        reveal(ingredients, app: app); ingredients.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(amount.label.lowercased().contains("dry rice"))
        XCTAssertTrue(amount.label.contains("400"), "Guided cooking shows the whole four-portion batch.")
        XCTAssertTrue(mode.buttons["Steps"].isSelected)
        let reference = XCTAttachment(screenshot: app.screenshot())
        reference.name = "Guided cooking - batch ingredient reference"
        reference.lifetime = .keepAlways; add(reference)
        ingredients.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let start = app.buttons["cooking_start_step_timer"]
        reveal(start, app: app); start.tap()
        let name = app.textFields["cooking_timer_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Guided rice timer\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["meal_prep_timer_start"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        let timer = app.buttons["cooking_featured_timer_manage"]
        reveal(timer, app: app)
        XCTAssertTrue(mode.buttons["Steps"].isSelected)
        XCTAssertTrue(timer.label.contains("Guided rice timer"))
        let duplicateTimer = app.buttons["planner_nearest_cooking_timer"]
        if duplicateTimer.exists {
            XCTAssertFalse(duplicateTimer.label.contains("Guided rice timer"), "The active cooking timer has one clear control surface.")
        }
        XCTAssertNotEqual(timer.value as? String, "00:00")
        let pause = app.buttons["cooking_featured_timer_toggle"]
        XCTAssertTrue(pause.isHittable)
        XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
        XCTAssertEqual(pause.value as? String, "Running")
        pause.tap()
        XCTAssertEqual(pause.value as? String, "Paused")
        let retained = timer.value as? String
        pause.tap()
        XCTAssertEqual(pause.value as? String, "Running")
        pause.tap()
        XCTAssertEqual(pause.value as? String, "Paused")
        XCTAssertNotNil(retained)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Guided cooking - step timer remains visible and pausable"
        attachment.lifetime = .keepAlways; add(attachment)

        timer.tap()
        let done = app.navigationBars["Cooking timers"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Guided rice timer"].exists)
        done.tap()
        XCTAssertTrue(mode.buttons["Steps"].isSelected)
        XCTAssertEqual(pause.value as? String, "Paused")

        workspace.buttons["Plan"].tap()
        XCTAssertTrue(duplicateTimer.waitForExistence(timeout: 5), "The timer remains available outside Cook.")
        XCTAssertTrue(duplicateTimer.label.contains("Guided rice timer"))
        workspace.buttons["Cook"].tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertEqual(pause.value as? String, "Paused")
        XCTAssertFalse(duplicateTimer.exists, "Returning to Cook restores the inline timer without a duplicate header.")
    }

    func testInstructionTimersStartDirectlyAndOfferASelectableRange() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan",
                               "-ui-testing-wave2-cooking-batch", "-ui-testing-instruction-times", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let cook = app.segmentedControls["planner_workspace"].buttons["Cook"]
        if !cook.waitForExistence(timeout: 12), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(cook.waitForExistence(timeout: 12)); cook.tap()
        let steps = app.segmentedControls["meal_prep_mode_picker"].buttons["Steps"]
        reveal(steps, app: app); steps.tap()
        let button = app.buttons["cooking_start_step_timer"]
        reveal(button, app: app); XCTAssertEqual(button.label, "Start 12 min"); button.tap()
        let timer = app.buttons["cooking_featured_timer_manage"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5)); XCTAssertEqual(button.label, "View step timer")
        let next = app.buttons["cooking_next_step"]; reveal(next, app: app); next.tap()
        reveal(button, app: app); XCTAssertEqual(button.label, "10–15 min…"); button.tap()
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5)); stepper.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["11 min"].exists)
        app.buttons["meal_prep_timer_start"].tap()
        reveal(timer, app: app); XCTAssertTrue(timer.label.contains("Step 2"))
        XCTAssertEqual(button.label, "View step timer")
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<18 {
            if element.waitForExistence(timeout: 0.2), element.isHittable,
               element.frame.minY >= 60, element.frame.maxY <= app.frame.maxY - 90 { return }
            let scroll = app.scrollViews["meal_prep_screen"].firstMatch
            guard scroll.waitForExistence(timeout: 3) else { break }
            if element.exists, element.frame.minY < 60 { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
