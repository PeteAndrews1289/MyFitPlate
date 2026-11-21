import XCTest

@MainActor
final class MaiaContinuityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTopicDraftAndContextSurviveSwitchAndRelaunch() {
        let app = launch(reset: true)
        let input = app.textFields["maia_message_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("Tomorrow's lifting question")
        app.buttons["maia_context_controls"].tap()
        let history = app.switches["maia_context_history"]
        reveal(history, app: app)
        if history.value as? String == "1" {
            history.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let switchedOff = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: history)
        XCTAssertEqual(XCTWaiter.wait(for: [switchedOff], timeout: 4), .completed,
                       "The context review must reflect the explicit choice before saving. " + app.debugDescription)
        let notes = app.textFields["maia_context_notes"]
        reveal(notes, app: app); notes.tap(); notes.typeText("Keep explanations practical")
        app.buttons["maia_context_save"].tap()
        XCTAssertTrue(app.buttons["maia_conversations"].waitForExistence(timeout: 5))
        app.buttons["maia_context_controls"].tap()
        reveal(app.switches["maia_context_history"], app: app)
        XCTAssertEqual(app.switches["maia_context_history"].value as? String, "0")
        XCTAssertEqual(app.textFields["maia_context_notes"].value as? String, "Keep explanations practical")
        app.buttons["Cancel"].tap()
        app.buttons["maia_conversations"].tap()
        app.buttons["maia_new_conversation"].tap()
        XCTAssertTrue(["", "Ask Maia anything"].contains(input.value as? String ?? ""))
        app.buttons["maia_conversations"].tap()
        let draft = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Draft: Tomorrow's lifting question")).firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap()
        XCTAssertEqual(input.value as? String, "Tomorrow's lifting question")
        app.terminate()
        let reopened = launch(reset: false)
        XCTAssertTrue(reopened.textFields["maia_message_input"].waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.textFields["maia_message_input"].value as? String, "Tomorrow's lifting question")
        reopened.buttons["maia_context_controls"].tap()
        reveal(reopened.switches["maia_context_history"], app: reopened)
        XCTAssertEqual(reopened.switches["maia_context_history"].value as? String, "0")
        XCTAssertEqual(reopened.textFields["maia_context_notes"].value as? String, "Keep explanations practical")
        capture(reopened, name: "Maia - topic context restored without sending a question")
    }

    func testPausedPlaybackHasReachableSentenceControlsAndNeverStartsAutomatically() {
        let app = launch(reset: true, flags: ["-ui-testing-maia-playback"])
        let controls = app.otherElements["maia_playback_controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 15))
        let resume = app.buttons["maia_playback_toggle"]
        XCTAssertEqual(resume.label, "Resume")
        XCTAssertTrue(resume.isHittable)
        XCTAssertTrue(app.buttons["maia_playback_next"].isHittable)
        XCTAssertTrue(app.buttons["maia_playback_previous"].isHittable)
        app.buttons["maia_playback_next"].tap()
        XCTAssertEqual(resume.label, "Resume", "Changing a paused sentence must not start audio.")
        XCTAssertFalse(app.buttons["maia_playback_next"].isEnabled)
        XCTAssertTrue(app.staticTexts["maia_playback_sentence"].label.contains("Record how the set felt"))
        capture(app, name: "Maia - paused sentence recovery and playback controls")
    }

    private func launch(reset: Bool, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "maia"] + flags
        if reset { app.launchArguments.append("-ui-testing-reset-editor-drafts") }
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY >= 100 && element.frame.maxY <= app.frame.maxY - 70 { return }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
