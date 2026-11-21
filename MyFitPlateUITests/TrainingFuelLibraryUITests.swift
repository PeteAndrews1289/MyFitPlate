import XCTest

@MainActor final class TrainingFuelLibraryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTwoSessionsAndManualUndoSurviveRelaunchWithoutLoggingFood() {
        let app = XCUIApplication()
        let flags = ["-ui-testing", "-screenshot-mode", "-ui-testing-fuel-library"]
        app.launchArguments = flags + ["-ui-testing-reset-editor-drafts"]
        app.launch()
        openFuel(app)
        app.buttons["fuel_history"].tap()
        XCTAssertTrue(app.navigationBars["Fuel history"].waitForExistence(timeout: 10))
        let morning = app.buttons["fuel_history_plan_qa-fuel-morning"]
        let evening = app.buttons["fuel_history_plan_qa-fuel-evening"]
        reveal(morning, app: app); XCTAssertTrue(morning.exists)
        XCTAssertTrue(evening.exists, "Planning another session retains the first one")
        morning.tap()
        let undo = app.buttons["fuel_undo_manual"]
        reveal(undo, app: app); XCTAssertTrue(undo.exists); undo.tap()
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Two fuel sessions - corrected manual outcome"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launchArguments = flags; app.launch()
        openFuel(app); app.buttons["fuel_history"].tap()
        XCTAssertTrue(app.navigationBars["Fuel history"].waitForExistence(timeout: 10))
        reveal(morning, app: app); morning.tap()
        XCTAssertFalse(undo.exists, "The accepted Undo must survive reopening")
        XCTAssertTrue(app.staticTexts["No foods explicitly linked. Other diary foods still use your daily budget."].exists)
    }

    func testPersonalFuelBriefRestoresConfirmedMeasurementWithoutLoggingFood() {
        let app = XCUIApplication()
        let flags = ["-ui-testing", "-screenshot-mode", "-ui-testing-fuel-library"]
        app.launchArguments = flags + ["-ui-testing-reset-editor-drafts"]
        app.launch(); openFuel(app)
        if app.navigationBars["Review training fuel"].exists {
            let newSession = app.buttons["fuel_new_session"]
            reveal(newSession, app: app); newSession.tap()
        }
        XCTAssertTrue(app.navigationBars["Training fuel"].waitForExistence(timeout: 5))
        let personalize = app.buttons["Personalize this estimate"]
        reveal(personalize, app: app); personalize.tap()
        let enabled = app.switches["fuel_personalize"]
        reveal(enabled, app: app); enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let adult = app.switches["fuel_adult_confirm"]
        reveal(adult, app: app); adult.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let weight = app.buttons["fuel_confirm_weight"]
        reveal(weight, app: app); weight.tap()
        let chosen = app.descendants(matching: .any)["fuel_chosen_protein"].firstMatch
        reveal(chosen, app: app); XCTAssertTrue(chosen.exists, app.debugDescription)
        app.terminate(); app.launchArguments = flags; app.launch()
        openFuel(app); reveal(personalize, app: app); personalize.tap()
        reveal(adult, app: app)
        XCTAssertEqual(adult.value as? String, "1")
        reveal(chosen, app: app); XCTAssertTrue(chosen.exists, "The accepted measurement is retained in the unfinished brief")
        XCTAssertTrue(app.buttons["fuel_history"].exists, "Ordinary saved sessions remain available")
    }
    private func openFuel(_ app: XCUIApplication) {
        if !app.buttons["home_supporting_insights"].waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        let disclosure = app.buttons["home_supporting_insights"]
        reveal(disclosure, app: app); XCTAssertTrue(disclosure.exists, app.debugDescription)
        if !app.buttons["training_fuel_open"].exists { disclosure.tap() }
        let open = app.buttons["training_fuel_open"]
        reveal(open, app: app); XCTAssertTrue(open.exists, app.debugDescription); open.tap()
        XCTAssertTrue(app.buttons["fuel_history"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<15 {
            if element.exists, element.isHittable, element.frame.minY > 100, element.frame.maxY < app.frame.maxY - 60 { return }
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            if element.exists, element.frame.minY < 100 { upper.press(forDuration: 0.08, thenDragTo: lower) } else { lower.press(forDuration: 0.08, thenDragTo: upper) }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
