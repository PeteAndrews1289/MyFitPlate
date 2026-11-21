import XCTest

final class WaveTwoAuthoringDepthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testAIOutlineUsesNormalDraftEditorAndRecoversBeforeLibrarySave() {
        let app = XCUIApplication()
        launch(app, reset: true)
        let edit = app.buttons["ai_program_edit_outline"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15)); reveal(edit, app: app); XCTAssertTrue(edit.isEnabled)
        recordEditorEntry(edit, app: app)
        edit.tap()
        let name = app.textFields["program_builder_name"]
        if !name.waitForExistence(timeout: 8) {
            let diagnostic = XCTAttachment(screenshot: app.screenshot()); diagnostic.name = "AI outline - editor entry diagnostic"
            diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertTrue(name.exists, app.debugDescription); reveal(name, app: app); name.tap()
        let existing = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Reviewed outline")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        let use = app.buttons["program_builder_save"]
        XCTAssertEqual(use.label, "Use reviewed proposal")
        reveal(use, app: app); use.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Reviewed outline"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["ai_program_save"].isEnabled, "Reviewing the outline must leave the final library save available")
        app.terminate()
        launch(app, reset: false)
        XCTAssertTrue(edit.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Reviewed outline"].waitForExistence(timeout: 8), app.debugDescription)
        reveal(edit, app: app); edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertEqual(name.value as? String, "Reviewed outline", app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "AI proposal - normal outline editor restored before library save"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["program_builder_close"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 8))
        let save = app.buttons["ai_program_save"]
        reveal(save, app: app); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-open-ai-generator"]
        app.launch()
        XCTAssertTrue(app.buttons["ai_program_generate"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["ai_program_edit_outline"].exists, "A successfully saved proposal must not be recreated by onDisappear checkpointing")
    }
    @MainActor private func recordEditorEntry(_ edit: XCUIElement, app: XCUIApplication) {
        let closeFrames = app.buttons.matching(identifier: "app_sheet_close_button").allElementsBoundByIndex.map {
            "label=\($0.label), frame=\($0.frame), hittable=\($0.isHittable)"
        }.joined(separator: "\n")
        let details = "Edit frame=\(edit.frame), hittable=\(edit.isHittable), enabled=\(edit.isEnabled)\nClose controls:\n\(closeFrames)\n\(app.debugDescription)"
        let tree = XCTAttachment(string: details); tree.name = "AI outline - BEFORE tap frames and hierarchy"; tree.lifetime = .keepAlways; add(tree)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "AI outline - BEFORE editor tap"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor private func launch(_ app: XCUIApplication, reset: Bool) {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "train", "-ui-testing-ai-outline"]
            + (reset ? ["-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"] : [])
        app.launch()
        if !app.buttons["ai_program_edit_outline"].waitForExistence(timeout: 12), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        for _ in 0..<22 {
            if target.exists, ["program_builder_save", "ai_program_save"].contains(target.identifier),
               target.isHittable, app.frame.contains(target.frame) { return }
            let editor = app.navigationBars["Edit proposal"]
            let hasEditor = editor.exists && editor.isHittable
            let scroll = hasEditor ? app.scrollViews["program_builder"] : app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(scroll?.frame.minY ?? app.frame.minY, hasEditor ? editor.frame.maxY : app.frame.minY) + 4
            var bottom = min(scroll?.frame.maxY ?? app.frame.maxY, app.frame.maxY) - 4
            let footer = app.buttons[hasEditor ? "program_builder_save" : "ai_program_save"]
            if footer.exists, footer.isHittable { bottom = min(bottom, footer.frame.minY - 8) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            if target.exists, target.isHittable, target.frame.minY >= top, target.frame.maxY <= bottom { return }
            guard bottom > top + 50 else { break }
            let needed: CGFloat = target.exists ? (target.frame.minY < top ? top - target.frame.minY : bottom - target.frame.maxY) : -100
            let amount = (needed < 0 ? -1.0 : 1.0) * min(140, max(40, abs(needed)))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: amount)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not reveal authoring control. \(app.debugDescription)")
    }
}
