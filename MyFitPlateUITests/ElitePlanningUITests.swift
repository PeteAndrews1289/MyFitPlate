import XCTest

final class ElitePlanningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testUnfinishedProgramAndNestedRoutineRestoreAfterTermination() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-builder", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let name = app.textFields["program_builder_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["program_draft_status"].exists, "Opening an unchanged plan must not create a stale draft.")
        name.tap()
        name.typeText(" draft")
        let editedName = (name.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        app.buttons["Add routine"].tap()
        let routineName = app.textFields["routine_builder_name"]
        XCTAssertTrue(routineName.waitForExistence(timeout: 5))
        routineName.tap()
        routineName.typeText("Unfinished upper")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-builder"]
        app.launch()
        XCTAssertTrue(routineName.waitForExistence(timeout: 10))
        XCTAssertEqual(routineName.value as? String, "Unfinished upper")
        XCTAssertTrue(app.staticTexts["routine_draft_status"].exists)
        app.buttons["routine_builder_close"].tap()
        app.buttons["Keep draft & close"].tap()
        XCTAssertTrue(app.buttons["program_continue_routine"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["program_builder_save"].isEnabled)
        XCTAssertEqual(name.value as? String, editedName)
        app.buttons["program_builder_close"].tap()
        app.buttons["Discard Changes"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertNotEqual(name.value as? String, editedName)
        XCTAssertFalse(app.staticTexts["program_draft_status"].exists)
        XCTAssertFalse(app.buttons["routine_builder_close"].exists)
    }
}
