import XCTest

@MainActor
final class WeeklyTargetReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFailedTargetSaveKeepsExactReviewThenRelaunchRetriesTheSameDecision() {
        let app = launch(reset: true, failure: true)
        let proposal = app.staticTexts["weekly_proposed_calories"]
        reveal(proposal, app: app)
        let proposedText = proposal.label
        let before = app.staticTexts["weekly_current_calories"].label
        let accept = app.buttons["weekly_checkin_accept"]
        reveal(accept, app: app); accept.tap()
        let error = app.staticTexts["weekly_checkin_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Weekly check-in"].exists)
        reveal(proposal, app: app)
        XCTAssertEqual(proposal.label, proposedText)
        XCTAssertEqual(app.staticTexts["weekly_current_calories"].label, before)
        app.terminate()
        let resumed = launch(reset: false, failure: false)
        let retry = resumed.buttons["weekly_checkin_retry"]
        reveal(retry, app: resumed)
        XCTAssertTrue(retry.isEnabled, resumed.debugDescription)
        retry.tap()
        XCTAssertTrue(resumed.navigationBars["Weekly check-in"].waitForNonExistence(timeout: 15), resumed.debugDescription)
        resumed.terminate()
        let historyApp = launch(reset: false, failure: false)
        let history = historyApp.descendants(matching: .any)["weekly_checkin_history"].firstMatch
        reveal(history, app: historyApp); history.tap()
        let accepted = historyApp.staticTexts["Accepted suggested targets"]
        reveal(accepted, app: historyApp)
        XCTAssertTrue(accepted.exists, historyApp.debugDescription)
        attach(historyApp, "Weekly targets - confirmed retry is recorded in history")
    }

    func testKeepingTargetsIsAConfirmedDecisionAndHistoryRemainsReachable() {
        let app = launch(reset: true, failure: false)
        let keep = app.buttons["weekly_checkin_keep"]
        reveal(keep, app: app); keep.tap()
        XCTAssertTrue(app.navigationBars["Weekly check-in"].waitForNonExistence(timeout: 15), app.debugDescription)
        app.terminate()
        let resumed = launch(reset: false, failure: false)
        let history = resumed.descendants(matching: .any)["weekly_checkin_history"].firstMatch
        reveal(history, app: resumed); history.tap()
        let kept = resumed.staticTexts["Kept current targets"]
        reveal(kept, app: resumed)
        XCTAssertTrue(kept.exists, resumed.debugDescription)
        XCTAssertFalse(resumed.staticTexts["Accepted suggested targets"].exists)
        attach(resumed, "Weekly targets - keeping current targets is explicit")
    }

    private func launch(reset: Bool, failure: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "weekly-checkin-ready"]
        if reset { app.launchArguments.append("-ui-testing-reset-editor-drafts") }
        if failure { app.launchArguments.append("-ui-testing-weekly-save-failure") }
        app.launch()
        XCTAssertTrue(app.navigationBars["Weekly check-in"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["weekly_checkin_accept"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable, element.frame.minY > 75, element.frame.maxY < app.frame.maxY - 55 { return }
            let down = element.exists && element.frame.minY < 75
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.75 : 0.3)))
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
