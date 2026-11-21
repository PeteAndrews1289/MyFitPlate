import XCTest

/// A disposable mock account; history is seeded by a real checked recipe revision.
final class RecipeVersionHistoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testSavedVersionInspectsUnknownOriginAndReviewedRestoreUpdatesOnlyCurrentYield() {
        let app = launch()
        openRecipe(app)
        let initialBasis = any(app, "recipe_detail").staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "8 servings per recipe")).firstMatch
        XCTAssertTrue(initialBasis.waitForExistence(timeout: 5), app.debugDescription)
        let history = app.buttons["recipe_version_history"]
        assertControl(history, app: app); history.tap()
        XCTAssertTrue(app.navigationBars["Recipe versions"].waitForExistence(timeout: 10), app.debugDescription)
        let versionID = "edit-D9000000-0000-0000-0000-000000000037-before"
        let origin = any(app, "recipe_version_origin_" + versionID)
        reveal(origin, app: app)
        XCTAssertTrue(origin.label.contains("Not recorded"), app.debugDescription)
        XCTAssertTrue(origin.label.contains("unknown nutrients stay unknown"), app.debugDescription)
        let disclosure = app.buttons["recipe_version_inspect_" + versionID]
        reveal(disclosure, app: app); assertControl(disclosure, app: app); disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded", app.debugDescription)
        let rice = any(app, "recipe_version_ingredient_" + versionID + "_0")
        reveal(rice, app: app)
        XCTAssertEqual(rice.label.lowercased(), "400 g rice", "The selected historical snapshot must expose its own original ingredient.\n\(app.debugDescription)")
        let restore = app.buttons["recipe_version_review_" + versionID]
        reveal(restore, app: app); assertControl(restore, app: app); restore.tap()
        XCTAssertTrue(app.navigationBars["Review version restore"].waitForExistence(timeout: 10), app.debugDescription)
        let yield = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Current yield: 8", "restored yield: 4")).firstMatch
        reveal(yield, app: app); XCTAssertTrue(yield.exists, app.debugDescription)
        let confirm = app.buttons["recipe_restore_confirm"]
        reveal(confirm, app: app); assertControl(confirm, app: app); confirm.tap()
        let accepted = app.staticTexts["Restore accepted. The current library was refreshed."]
        XCTAssertTrue(accepted.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(confirm.label, "Done", app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Review version restore"].waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Recipe versions"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars["Recipe versions"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Recipe versions"].waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Recipe"].waitForExistence(timeout: 10), app.debugDescription)
        let restoredBasis = any(app, "recipe_detail").staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4 servings per recipe")).firstMatch
        reveal(restoredBasis, app: app); XCTAssertTrue(restoredBasis.exists, app.debugDescription)
        XCTAssertTrue(app.buttons["recipe_add_to_log"].exists, app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Recipe - reviewed version restore retains unknown origin and changes current yield"; shot.lifetime = .keepAlways; add(shot)
        let back = app.navigationBars["Recipe"].buttons.firstMatch
        XCTAssertTrue(back.exists && back.isHittable && app.frame.contains(back.frame), app.debugDescription); back.tap()
        XCTAssertTrue(app.navigationBars["My Recipes"].waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars["My Recipes"].buttons["Done"].tap()
    }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "recipes",
            "-disable-google-mobile-ads", "-ui-testing-reset-editor-drafts", "-ui-testing-recipe-version-history"]
        app.launch()
        let library = app.navigationBars["My Recipes"]
        if !library.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(library.waitForExistence(timeout: 15), app.debugDescription); return app
    }
    @MainActor private func openRecipe(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Four-serving rice batch")).firstMatch
        reveal(row, app: app); row.tap()
        if !app.navigationBars["Recipe"].waitForExistence(timeout: 5), app.navigationBars["My Recipes"].exists {
            reveal(row, app: app); row.tap()
        }
        XCTAssertTrue(app.navigationBars["Recipe"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func assertControl(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame), app.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, app.debugDescription, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, app.debugDescription, file: file, line: line)
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let destinations = [("Review version restore", "recipe_restore_list"), ("Recipe versions", "recipe_history_list"),
                            ("Recipe", "recipe_detail"), ("My Recipes", "recipe_library")]
        let destination = destinations.first { app.navigationBars[$0.0].exists && app.navigationBars[$0.0].isHittable }
        let region = destination.map { any(app, $0.1) } ?? app
        for attempt in 0..<14 {
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            let navBottom = destination.map { app.navigationBars[$0.0].frame.maxY } ?? 80
            let top = max(navBottom + 8, region.frame.minY + 8)
            var bottom = min(app.frame.maxY - 24, region.frame.maxY - 8)
            let footerID = destination?.0 == "Review version restore" ? "recipe_restore_confirm"
                : destination?.0 == "Recipe" ? "recipe_add_to_log" : nil
            if let footerID {
                let footer = app.buttons[footerID]
                if footer.exists, footer.isHittable { bottom = min(bottom, footer.frame.minY - 8) }
            }
            guard bottom - top > 70 else { break }
            let center = (top + bottom) / 2
            let translation: CGFloat
            if element.exists, element.frame.height > 0, element.frame.midY.isFinite {
                let needed = center - element.frame.midY
                translation = (needed < 0 ? -1 : 1) * min(180, max(40, abs(needed)))
            } else { translation = attempt < 9 ? -160 : 160 }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.88, dy: center))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: translation)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.exists && element.isHittable && app.frame.contains(element.frame), app.debugDescription, file: file, line: line)
    }
}
