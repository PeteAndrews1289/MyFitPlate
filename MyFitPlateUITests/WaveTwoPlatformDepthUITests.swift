import XCTest

final class WaveTwoPlatformDepthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testConsistencyReviewIsOptionalAndHidesHomeSummary() {
        let app = launch()
        let open = app.buttons["logging_habit_open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
        XCTAssertTrue(app.navigationBars["Logging consistency"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["logging_habit_rule"].exists)
        XCTAssertTrue(app.buttons["How days are counted"].exists)
        let save = app.navigationBars["Logging consistency"].buttons["Save"]
        waitEnabled(save, app: app)
        let hide = app.switches["Hide consistency on Home"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 5), app.debugDescription)
        let toggle = nativeSwitch(hide)
        XCTAssertEqual(toggle.value as? String, "0", app.debugDescription)
        toggle.tap()
        waitForValue("1", on: toggle, app: app)
        save.tap()
        XCTAssertTrue(app.navigationBars["Logging consistency"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(open.exists, app.debugDescription)
        open.tap()
        XCTAssertTrue(app.navigationBars["Logging consistency"].waitForExistence(timeout: 5), app.debugDescription)
        waitEnabled(save, app: app)
        XCTAssertTrue(hide.waitForExistence(timeout: 5), app.debugDescription)
        waitForValue("1", on: nativeSwitch(hide), app: app)
        record(app, "Consistency - optional rule review and calendar")
    }
    @MainActor func testDayShareStartsWithMinimumContentAndHasMatchingAccessibleText() {
        let app = launch()
        let guidance = app.buttons["home_guidance_disclosure"]
        if guidance.waitForExistence(timeout: 5) { guidance.tap() }
        let share = app.buttons["livingDayShareButton"]
        reveal(share, app: app); share.tap()
        XCTAssertTrue(app.navigationBars["Share my day"].waitForExistence(timeout: 6))
        for id in ["livingDayShareBudgetToggle", "livingDayShareFoodsToggle", "livingDayShareWeightToggle", "livingDayShareTrustToggle", "livingDayShareActionToggle"] {
            let toggle = app.switches[id]
            reveal(toggle, app: app); XCTAssertEqual(toggle.value as? String, "0", id)
        }
        let path = app.switches["livingDaySharePathToggle"]
        XCTAssertEqual(path.value as? String, "1")
        let text = app.buttons["livingDayShareText"]
        reveal(text, app: app); text.tap()
        let commit = app.buttons["livingDayShareCommitButton"]
        reveal(commit, app: app); XCTAssertTrue(commit.isEnabled)
        record(app, "Private day share - minimized content and accessible equivalent")
    }
    @MainActor func testNutrientDashboardOpensWithoutFeatureFlag() {
        let app = launch()
        let nutrient = app.descendants(matching: .any)["home_nutrient_dashboard"].firstMatch
        reveal(nutrient, app: app); nutrient.tap()
        let dashboard = app.navigationBars["Daily nutrients"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), app.debugDescription)
        let vitamin = app.buttons["daily_nutrient_vitaminA"]
        reveal(vitamin, app: app); vitamin.tap()
        let contributors = app.navigationBars["Vitamin A"]
        XCTAssertTrue(contributors.waitForExistence(timeout: 10), app.debugDescription)
        let explanation = app.staticTexts["Missing nutrient values are unknown. Open a food to inspect the exact snapshot recorded on this day."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), app.debugDescription)
        let food = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "nutrient_contributor_", "Grilled Chicken Power Bowl")).firstMatch
        reveal(food, app: app)
        XCTAssertTrue(food.exists && food.isHittable, app.debugDescription)
        XCTAssertTrue(food.label.contains("Lunch"), app.debugDescription)
        record(app, "Nutrients - dated Vitamin A contributors and frozen food evidence")
        contributors.buttons["Done"].tap()
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(contributors.waitForNonExistence(timeout: 5), app.debugDescription)
        dashboard.buttons["Done"].tap()
        XCTAssertTrue(dashboard.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["logging_habit_open"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home", "-living-day-home", "-ui-testing-reset-editor-drafts"]
        app.launch()
        if !app.buttons["logging_habit_open"].waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        return app
    }
    @MainActor private func nativeSwitch(_ element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
    }
    @MainActor private func waitEnabled(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, app.debugDescription)
    }
    @MainActor private func waitForValue(_ value: String, on element: XCUIElement, app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, app.debugDescription)
        XCTAssertEqual(element.value as? String, value, app.debugDescription)
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        let knownScrolls = ["daily_nutrient_dashboard", "home_scroll"].map { app.scrollViews[$0] }
        let scroll = knownScrolls.first { $0.exists && $0.isHittable }
            ?? app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
            ?? app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for index in 0..<25 {
            if target.exists, target.isHittable, app.frame.contains(target.frame) { return }
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(scroll?.frame.minY ?? 90, nav?.frame.maxY ?? 85) + 6
            let bottom = min(scroll?.frame.maxY ?? app.frame.maxY - 75, app.frame.maxY - 75) - 6
            guard bottom > top + 60 else { break }
            let above = target.exists && target.frame.height > 0 ? target.frame.minY < top : index > 16
            let center = top + (bottom - top) / 2
            let distance = min(CGFloat(130), (bottom - top) * 0.38)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: center)).press(forDuration: 0.03,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: center + (above ? distance : -distance))))
        }
        XCTAssertTrue(target.exists && target.isHittable && app.frame.contains(target.frame), "Expected reachable \(target.identifier)\n\(app.debugDescription)")
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
