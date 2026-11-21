import XCTest

@MainActor
final class PersonalReportContinuityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSleepWindowPreferenceSurvivesRelaunchAndSparseCoverageIsExplicit() {
        let app = launch("sleep-history", reset: true)
        XCTAssertTrue(app.staticTexts["Recorded nights, 1 of 3"].waitForExistence(timeout: 15), app.debugDescription)
        let toggle = app.switches["Compare with a preferred sleep window"]
        reveal(toggle, app: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let save = app.buttons["sleep_history_save_notes"]
        reveal(save, app: app); save.tap()
        XCTAssertTrue(app.buttons["Saved on this device"].waitForExistence(timeout: 5), app.debugDescription)
        app.terminate()
        let restored = launch("sleep-history", reset: false)
        let restoredToggle = restored.switches["Compare with a preferred sleep window"]
        reveal(restoredToggle, app: restored)
        XCTAssertEqual(restoredToggle.value as? String, "1")
        let attachment = XCTAttachment(screenshot: restored.screenshot())
        attachment.name = "Sleep history - sparse coverage and saved local routine"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testProfileCanHideGamificationAndKeepOrdinaryProgress() {
        let app = launch("profile", reset: true)
        let preferences = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Display preferences")).firstMatch
        reveal(preferences, app: app); preferences.tap()
        let toggle = app.switches["profile_show_gamification"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), app.debugDescription)
        reveal(toggle, app: app); XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        app.terminate()
        let restored = launch("profile", reset: false)
        let restoredPreferences = restored.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Display preferences")).firstMatch
        reveal(restoredPreferences, app: restored); restoredPreferences.tap()
        let restoredToggle = restored.switches["profile_show_gamification"]
        XCTAssertTrue(restoredToggle.waitForExistence(timeout: 3), restored.debugDescription)
        reveal(restoredToggle, app: restored)
        XCTAssertEqual(restoredToggle.value as? String, "0")
        XCTAssertFalse(restored.descendants(matching: .any)["profile_progress_summary"].exists)
        XCTAssertTrue(restored.staticTexts["Current targets"].exists)
        let attachment = XCTAttachment(screenshot: restored.screenshot())
        attachment.name = "Profile - ordinary progress with points hidden"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testInsightPDFShowsRenderedPagesBeforeSharing() {
        let app = launch("maia-insights", reset: true)
        let share = app.buttons["maia_insights_share"]
        XCTAssertTrue(share.waitForExistence(timeout: 15)); share.tap()
        let create = app.buttons["maia_insights_create_pdf"]
        reveal(create, app: app); create.tap()
        let pages = app.descendants(matching: .any)["maia_insights_pdf_pages"].firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.navigationBars["PDF preview"].exists)
        XCTAssertTrue(app.buttons["maia_insights_pdf_share"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Rendered insight PDF pages before sharing"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testRunningCloudSheetKeepsSimulatorDemoOffline() {
        let app = launch("runs", reset: true)
        let options = app.buttons["run_history_options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15), app.debugDescription); options.tap()
        let cloud = app.buttons["run_cloud_sync"]
        XCTAssertTrue(cloud.waitForExistence(timeout: 15), app.debugDescription); cloud.tap()
        XCTAssertTrue(app.staticTexts["run_cloud_demo_notice"].waitForExistence(timeout: 5), app.debugDescription)
        let sync = app.buttons["run_cloud_sync_now"]
        XCTAssertTrue(sync.exists); XCTAssertFalse(sync.isEnabled)
        XCTAssertTrue(app.staticTexts["Running workouts"].exists)
        XCTAssertTrue(app.staticTexts["Training blocks"].exists)
        XCTAssertTrue(app.staticTexts["Run reviews"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Running sync - simulator demo remains offline"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func launch(_ screen: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen]
        if reset { app.launchArguments += ["-ui-testing-reset-editor-drafts"] }
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable && element.frame.minY >= 85 && element.frame.maxY <= app.frame.maxY - 90 { return }
            if element.exists && element.frame.minY < 85 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Control not reachable. \(app.debugDescription)", file: file, line: line)
    }
}
