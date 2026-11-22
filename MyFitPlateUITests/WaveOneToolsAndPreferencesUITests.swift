import XCTest

final class WaveOneToolsAndPreferencesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testUnfinishedFoodPreferencesRestoreSelectionsAndRawFavoriteAfterTermination() {
        let app = launch("settings-food-preferences", flags: ["-ui-testing-reset-editor-drafts"])
        let tofu = app.buttons["food_preference_proteins_tofu"].firstMatch
        reveal(tofu, app: app); tofu.tap()
        let chosen = tofu.value as? String
        let custom = app.textFields["food_preference_custom_cuisines"]
        reveal(custom, app: app); custom.tap(); custom.typeText("Ethiop")
        app.terminate()
        let resumed = launch("settings-food-preferences")
        XCTAssertTrue(any(resumed, "food_preferences_restored").waitForExistence(timeout: 10))
        let restoredTofu = resumed.buttons["food_preference_proteins_tofu"].firstMatch
        reveal(restoredTofu, app: resumed); XCTAssertEqual(restoredTofu.value as? String, chosen)
        let restoredText = resumed.textFields["food_preference_custom_cuisines"]
        reveal(restoredText, app: resumed); XCTAssertEqual(restoredText.value as? String, "Ethiop")
        record(resumed, "Food preferences - unfinished selections and typing restored")
        resumed.buttons["food_preferences_cancel"].firstMatch.tap()
    }

    @MainActor
    func testTrackingOnlyAndMetricContainerPersist() {
        let app = XCUIApplication()
        func start(reset: Bool) {
            app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "settings-water", "-ui-testing-hydration-preferences"]
                + (reset ? ["-ui-testing-reset-editor-drafts"] : [])
            app.launch()
            XCTAssertTrue(app.switches["water_tracking_only"].waitForExistence(timeout: 15), app.debugDescription)
        }
        start(reset: true)
        let trackingOnly = app.switches["water_tracking_only"]
        if trackingOnly.value as? String != "1" {
            trackingOnly.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let trackingEnabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: trackingOnly)
        XCTAssertEqual(XCTWaiter.wait(for: [trackingEnabled], timeout: 4), .completed, app.debugDescription)
        let name = app.textFields["water_container_name"]
        revealForm(name, app: app); name.tap(); name.typeText("QA flask")
        let amount = app.textFields["water_container_amount"]
        amount.tap(); amount.typeText("450")
        app.buttons["Done"].firstMatch.tap()
        let unit = app.buttons["water_container_unit"]
        revealForm(unit, app: app); unit.tap()
        app.buttons["mL"].firstMatch.tap()
        app.buttons["water_add_container"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let container = app.staticTexts["QA flask · 450 mL"]
        revealForm(container, app: app); XCTAssertTrue(container.exists)
        app.buttons["settings_water_save"].tap()
        XCTAssertTrue(app.switches["water_tracking_only"].waitForNonExistence(timeout: 10))
        app.terminate(); start(reset: false)
        XCTAssertEqual(app.switches["water_tracking_only"].value as? String, "1")
        XCTAssertFalse(app.textFields["water_target_amount"].exists)
        revealForm(container, app: app); XCTAssertTrue(container.exists)
        record(app, "Hydration - tracking only and metric container restored")
        app.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor private func revealForm(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists, element.isHittable, element.frame.minY > 100, element.frame.maxY < app.frame.maxY - 100 { return }
            let down = element.exists && element.frame.minY < 100
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: down ? 0.30 : 0.72))
                .press(forDuration: 0.06, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: down ? 0.72 : 0.30)))
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    func testFoodPreferencesCancelNeverAppliesDraft() {
        let app = launch("settings-food-preferences")
        let tofu = app.buttons["food_preference_proteins_tofu"].firstMatch
        XCTAssertTrue(tofu.waitForExistence(timeout: 15))
        let original = tofu.value as? String
        tofu.tap()
        XCTAssertNotEqual(tofu.value as? String, original)
        app.buttons["food_preferences_cancel"].firstMatch.tap()
        let reopen = app.buttons["settings_food_preferences"].firstMatch
        reveal(reopen, app: app); reopen.tap()
        XCTAssertTrue(tofu.waitForExistence(timeout: 5))
        XCTAssertEqual(tofu.value as? String, original, "Cancel cannot publish preference changes")
        record(app, "Food preferences - independent draft")
    }

    @MainActor
    func testRejectedPreferencesSaveRetainsSelectionsAndEditor() {
        let app = launch("settings-food-preferences", flags: ["-ui-testing-food-preferences-save-failure"])
        let tofu = app.buttons["food_preference_proteins_tofu"].firstMatch
        XCTAssertTrue(tofu.waitForExistence(timeout: 15))
        tofu.tap()
        let chosen = tofu.value as? String
        let save = app.buttons["food_preferences_save"].firstMatch
        XCTAssertTrue(save.isHittable)
        save.tap()
        let error = app.staticTexts["food_preferences_error"]
        reveal(error, app: app)
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        reveal(tofu, app: app)
        XCTAssertEqual(tofu.value as? String, chosen)
        XCTAssertTrue(app.buttons["food_preferences_save"].firstMatch.exists)
        record(app, "Food preferences - failed save retained")
    }

    @MainActor
    func testToolsDirectoryOpensRealPreferenceDestinationAtLargestText() {
        let app = launch("home", flags: ["-deep-link-url", "myfitplate://tools", "-screenshot-dark-mode",
                                         "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let directory = any(app, "tool_directory")
        XCTAssertTrue(directory.waitForExistence(timeout: 15))
        let preference = app.buttons["tool_food-preferences"].firstMatch
        reveal(preference, app: app)
        XCTAssertTrue(preference.isHittable)
        XCTAssertGreaterThanOrEqual(preference.frame.height, 44)
        XCTAssertGreaterThanOrEqual(preference.frame.width, 44)
        record(app, "Tools - large text neutral directory")
        preference.tap()
        XCTAssertTrue(app.buttons["food_preferences_save"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["food_preferences_cancel"].firstMatch.isHittable)
        app.buttons["food_preferences_cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["food_preferences_save"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["home_scroll"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(_ screen: String, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags
        app.launch()
        let expected = screen == "home" ? any(app, "tool_directory") : app.buttons["food_preference_proteins_tofu"].firstMatch
        if !expected.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists, app.buttons["welcome_sign_in"].exists { app.terminate(); app.launch() }
        return app
    }

    @MainActor
    private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        var searchAbove = false
        var unknownSteps = 0
        for _ in 0..<32 {
            let directory = app.scrollViews["tool_directory"]
            let scroll = directory.exists ? directory : app.scrollViews.firstMatch
            let save = app.buttons["food_preferences_save"].firstMatch
            let cancel = app.buttons["food_preferences_cancel"].firstMatch
            let error = app.staticTexts["food_preferences_error"]
            let pinned = [save, cancel, error].filter { $0.exists && $0.frame.height > 0 }
            let top = scroll.exists ? max(scroll.frame.minY + 5, 110) : 110
            let bottom = pinned.map(\.frame.minY).min().map { $0 - 5 } ?? app.frame.maxY - 12
            if element.exists, element.isHittable {
                if pinned.contains(where: { $0.identifier == element.identifier }), app.frame.contains(element.frame) { return }
                if element.frame.minY >= top, element.frame.maxY <= bottom { return }
            }
            guard bottom - top > 60 else { break }
            let distance: CGFloat
            if element.exists, element.frame.height > 0 {
                searchAbove = element.frame.minY < top
                unknownSteps = 0
                let overflow = searchAbove ? top - element.frame.minY : element.frame.maxY - bottom
                distance = min(180, max(24, overflow + 12))
            } else {
                unknownSteps += 1
                if unknownSteps == 16 { searchAbove.toggle(); unknownSteps = 0 }
                distance = min(180, (bottom - top) * 0.4)
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let startY = top + (bottom - top) * 0.5
            let endY = min(bottom - 8, max(top + 8, startY + (searchAbove ? distance : -distance)))
            let start = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: startY))
            let end = origin.withOffset(CGVector(dx: app.frame.width * 0.03, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTFail("Couldn't reveal a complete target in the foreground tool/editor scroll view. \(app.debugDescription)")
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
