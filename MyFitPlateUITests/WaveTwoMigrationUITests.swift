import XCTest

final class WaveTwoMigrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testCheckedLegacyAdoptionAndReviewedRestoreKeepPHULProgress() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "program-detail",
            "-ui-testing-migration-review", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let progress = any(app, "program_progress_summary")
        reveal(progress, app: app); XCTAssertTrue(progress.label.contains("39 of 48"), progress.label)
        let block = app.buttons["program_edit_block"]
        reveal(block, app: app); block.tap()
        let save = app.buttons["block_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10)); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
        reveal(progress, app: app); XCTAssertTrue(progress.label.contains("39 of 48"), progress.label)
        let options = app.buttons["program_options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5)); options.tap()
        let history = app.buttons["program_migration_history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'migration_history_'")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let review = app.buttons["migration_restore_review"]
        reveal(review, app: app); review.tap()
        let acknowledgement = app.switches["I reviewed restoring the original rotation"]
        reveal(acknowledgement, app: app)
        let actualSwitch = nativeSwitch(acknowledgement)
        XCTAssertTrue(["0", "1"].contains(actualSwitch.value as? String ?? ""), "Acknowledgement must expose a real binary switch state")
        if actualSwitch.value as? String != "1" { actualSwitch.tap() }
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: actualSwitch)
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 5), .completed)
        XCTAssertEqual(nativeSwitch(acknowledgement).value as? String, "1")
        let confirm = app.buttons["migration_restore_confirm"]
        reveal(confirm, app: app); XCTAssertTrue(confirm.isEnabled); XCTAssertGreaterThanOrEqual(confirm.frame.height, 44); confirm.tap()
        let message = any(app, "migration_restore_message")
        reveal(message, app: app)
        XCTAssertTrue(message.label.contains("Original rotation restored"), message.label)
        XCTAssertFalse(app.buttons["migration_restore_retry"].exists)
        capture(app, "Migration - accepted original restore keeps PHUL progress and history")
        let back = app.buttons["migration_restore_done"]
        reveal(back, app: app); back.tap()
        app.navigationBars["Original rotations"].buttons["Done"].tap()
        reveal(progress, app: app); XCTAssertTrue(progress.label.contains("39 of 48"), progress.label)
        reveal(block, app: app); block.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Restored legacy rotation must remain eligible for explicit future adoption")
        capture(app, "Migration - same PHUL position after restore")
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func nativeSwitch(_ element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<22 {
            let top = (app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? 90) + 5
            let dock = app.buttons["tab_home"].firstMatch
            let bottom = dock.exists && dock.isHittable ? dock.frame.minY - 5 : app.frame.maxY - 25
            if element.waitForExistence(timeout: 0.3), element.isHittable,
               element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let offset: CGFloat = element.exists && element.frame.minY < top ? 120 : -120
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.9, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not reveal \(element.identifier). \(app.debugDescription)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
