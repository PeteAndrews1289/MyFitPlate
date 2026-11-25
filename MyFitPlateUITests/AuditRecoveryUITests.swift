import XCTest

final class AuditRecoveryUITests: XCTestCase {
    @MainActor
    func testLargeTextActivityAnswerCanBeSelectedAndContinued() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "onboarding-lifestyle",
                               "-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["How active is your life?"].waitForExistence(timeout: 10))
        let answer = app.buttons["onboarding_activity_1"]
        for _ in 0..<8 where !answer.isHittable { app.swipeUp() }
        XCTAssertTrue(answer.isHittable)
        answer.tap()
        let next = app.buttons["onboarding_next"]
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Large text - activity answer selected"
        evidence.lifetime = .keepAlways
        add(evidence)
        next.tap()
        XCTAssertTrue(app.staticTexts["How fast do you want to lose?"].waitForExistence(timeout: 5))
    }
}
