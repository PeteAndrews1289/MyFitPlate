import XCTest

/// Execute only against the real Release app on the disposable QA simulator.
/// No mock flags, authentication submission, account creation or account reset.
@MainActor
final class WaveFourReleaseEntryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSignedOutReleaseOpensSignInAndReturnsWithoutSubmitting() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let signIn = app.buttons["welcome_sign_in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20), "Use only the disposable signed-out QA simulator.")
        XCTAssertFalse(app.buttons["tab_home"].exists)
        signIn.tap()
        XCTAssertTrue(app.textFields["login_email"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.secureTextFields["login_password"].exists)
        XCTAssertFalse(app.buttons["login_submit"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Release - signed-out entry"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(signIn.waitForExistence(timeout: 15), "Browsing sign-in must not create or authenticate an account.")
    }
}
