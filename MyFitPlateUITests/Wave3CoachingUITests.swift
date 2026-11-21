import XCTest

@MainActor
final class Wave3CoachingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHomeMealOverridesPreviouslyBrowsedWeekWithoutChangingTheMeal() {
        let app = launch("home")
        app.buttons["tab_meal_plan"].tap()
        let heading = app.buttons["planner_view_mode"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        heading.tap()
        let calendar = app.buttons["planner_choose_date"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        let today = calendar.value as? String
        app.buttons["planner_previous_week"].tap()
        XCTAssertNotEqual(calendar.value as? String, today)
        app.segmentedControls["planner_workspace"].buttons["Shop"].tap()
        app.buttons["tab_home"].tap()
        let guidance = app.buttons["home_guidance_disclosure"]
        reveal(guidance, app: app); guidance.tap()
        let allEvents = app.buttons["Show all day events"]
        reveal(allEvents, app: app)
        if allEvents.exists { allEvents.tap() }
        let planned = app.buttons.matching(identifier: "livingDayEvent")
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "planned")).firstMatch
        reveal(planned, app: app)
        XCTAssertTrue(planned.exists && planned.isHittable, app.debugDescription)
        planned.tap()
        let review = app.navigationBars["Edit meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), app.debugDescription)
        let nutrition = app.staticTexts["planner_portion_nutrition"].label
        let amount = app.buttons["planner_portions-Increment"].value as? String
        XCTAssertEqual(amount, "1")
        review.buttons["Cancel"].tap()
        XCTAssertEqual(heading.value as? String, today, "An explicit Home action overrides the old planning week.")
        XCTAssertTrue(app.segmentedControls["planner_workspace"].buttons["Plan"].isSelected)
        XCTAssertEqual(heading.label, "Show week")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "planner_edit_")).firstMatch
        reveal(edit, app: app); edit.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["planner_portion_nutrition"].label, nutrition)
        XCTAssertEqual(app.buttons["planner_portions-Increment"].value as? String, amount)
        attach(app, "Home meal opens its original day and reviewed amount")
    }

    func testLighterWeekReviewDoesNotApplyAdviceUntilExplicitlyAccepted() {
        let app = launch("coaching")
        let options = app.buttons.matching(NSPredicate(format: "label == %@", "Other training options")).firstMatch
        reveal(options, app: app); options.tap()
        let lighter = app.buttons["coaching_review_lighter_week"]
        reveal(lighter, app: app); lighter.tap()
        XCTAssertTrue(app.navigationBars["Rescue my week"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["rescue_primary"].label.contains("Preview"), "Advice must open choices before any change.")
        app.navigationBars["Rescue my week"].buttons["Done"].tap()
        let history = app.buttons["coaching_action_history"]
        reveal(history, app: app); history.tap()
        XCTAssertTrue(app.staticTexts["Lighter week · review closed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Lighter week · accepted change"].exists)
        attach(app, "Declined coaching records a closed review, not a saved change")
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen,
            "-ui-testing-wave2-phul", "-ui-testing-reset-editor-drafts", "-ui-testing-reset-workout-draft"]
        app.launch()
        let ready = screen == "coaching" ? app.buttons["coaching_primary_action"] : app.buttons["tab_home"]
        if !ready.waitForExistence(timeout: 15), app.buttons["welcome_get_started"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(ready.waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists, element.isHittable, element.frame.minY > 75,
               element.frame.maxY < app.frame.maxY - 75 { return }
            let scroll = app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
                ?? app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
            if element.exists, element.frame.minY < 75 { (scroll ?? app).swipeDown() } else { (scroll ?? app).swipeUp() }
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}
