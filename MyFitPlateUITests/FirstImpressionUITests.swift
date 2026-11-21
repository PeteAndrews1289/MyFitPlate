import XCTest

final class FirstImpressionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(_ route: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", route,
                               "-ui-testing-reset-onboarding"] + extra
        if !extra.contains("-UIPreferredContentSizeCategoryName") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        app.launch()
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func enter(_ value: String, field: XCUIElement, app: XCUIApplication) {
        reveal(field, in: app)
        field.tap()
        field.typeText(value)
    }

    @MainActor func testQuizBuildsAPlanAndEmailSignupPreservesInput() {
        let app = launch("welcome")
        XCTAssertTrue(app.buttons["welcome_get_started"].waitForExistence(timeout: 15))
        let start = app.buttons["welcome_get_started"]
        let maintain = app.buttons["onboarding_goal_maintain"]
        start.press(forDuration: 0.1)
        if !maintain.waitForExistence(timeout: 5) {
            // Retry a dropped simulator touch only while the unchanged welcome remains.
            XCTAssertTrue(start.exists && start.isHittable, app.debugDescription)
            start.press(forDuration: 0.1)
        }
        XCTAssertTrue(maintain.waitForExistence(timeout: 5), app.debugDescription)
        reveal(app.buttons["onboarding_goal_maintain"], in: app)
        maintain.press(forDuration: 0.1)
        XCTAssertTrue(app.buttons["onboarding_next"].wait(for: \.isEnabled, toEqual: true, timeout: 5), app.debugDescription)
        app.buttons["onboarding_next"].tap()
        XCTAssertTrue(app.buttons["onboarding_sex_male"].waitForExistence(timeout: 5))
        app.buttons["onboarding_sex_male"].tap()
        enter("30", field: app.textFields["Age"], app: app)
        app.buttons["onboarding_next"].tap()
        app.segmentedControls["onboarding_units"].buttons["cm, kg"].tap()
        enter("178", field: app.textFields["Height"], app: app)
        app.buttons["onboarding_next"].tap()
        enter("80", field: app.textFields["Current weight"], app: app)
        app.buttons["onboarding_next"].tap()
        let activity = app.buttons["onboarding_activity_1"]
        reveal(activity, in: app)
        activity.tap()
        app.buttons["onboarding_next"].tap()
        XCTAssertTrue(app.staticTexts["Your plan is ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["plan_reveal_continue"].isHittable)
        app.buttons["plan_reveal_continue"].tap()
        XCTAssertTrue(app.buttons["create_account_email"].waitForExistence(timeout: 5))
        app.buttons["create_account_email"].tap()
        enter("member@example.com\n", field: app.textFields["create_account_email_field"], app: app)
        XCTAssertEqual(app.textFields["create_account_email_field"].value as? String, "member@example.com")
        // Choose manual entry when iOS offers password generation. Typing through that
        // system panel bypasses the keyboard and does not represent a user entering text.
        let suggestion = app.buttons["GenerateStrongPasswordButton"]
        if suggestion.waitForExistence(timeout: 5) {
            app.buttons["Close"].tap()
            XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        }
        let key = app.keyboards.keys["s"]
        XCTAssertTrue(key.waitForExistence(timeout: 5) && key.isHittable)
        key.tap()
        app.typeText("hort")
        XCTAssertTrue(app.secureTextFields["create_account_password"].exists)
        XCTAssertFalse(app.buttons["create_account_submit"].isEnabled)
        app.typeText("er")
        XCTAssertTrue(app.buttons["create_account_submit"].isEnabled, app.debugDescription)
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["create_account_password"].value as? String, "shorter", app.debugDescription)
        XCTAssertTrue(app.buttons["create_account_submit"].isEnabled, app.debugDescription)
    }

    @MainActor func testSignInFailureKeepsEmailPasswordAndRetry() {
        let app = launch("login", extra: ["-ui-testing-auth-failure"])
        XCTAssertTrue(app.textFields["login_email"].waitForExistence(timeout: 15))
        enter("member@example.com\n", field: app.textFields["login_email"], app: app)
        app.typeText("example-pass")
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["login_password"].value as? String, "example-pass")
        app.typeText("1")
        XCTAssertEqual(app.textFields["login_password"].value as? String, "example-pass1")
        app.buttons["Hide password"].tap()
        app.typeText("2")
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["login_password"].value as? String, "example-pass12")
        app.keyboards.buttons["Go"].tap()
        // The OS may offer to save after submission. Never store the test credentials.
        if app.sheets["Save Password?"].waitForExistence(timeout: 1) {
            app.sheets["Save Password?"].buttons["Not Now"].tap()
        }
        let error = app.staticTexts["auth_error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(error.label.contains("Couldn't connect"))
        XCTAssertTrue(app.buttons["login_submit"].isEnabled)
        XCTAssertEqual(app.textFields["login_email"].value as? String, "member@example.com")
        XCTAssertEqual(app.textFields["login_password"].value as? String, "example-pass12")
    }

    @MainActor func testSignupCanTypeAfterDismissingPasswordSuggestion() throws {
        let app = launch("create-account")
        let emailOption = app.buttons["create_account_email"]
        XCTAssertTrue(emailOption.waitForExistence(timeout: 15))
        let email = app.textFields["create_account_email_field"]
        emailOption.press(forDuration: 0.1)
        if !email.waitForExistence(timeout: 5) {
            XCTAssertTrue(emailOption.exists && emailOption.isHittable, app.debugDescription)
            emailOption.press(forDuration: 0.1)
        }
        XCTAssertTrue(email.waitForExistence(timeout: 5), app.debugDescription)
        enter("manual-entry@example.com\n", field: email, app: app)
        let suggestion = app.buttons["GenerateStrongPasswordButton"]
        guard suggestion.waitForExistence(timeout: 5) else {
            throw XCTSkip("This simulator did not offer a generated password.")
        }
        app.buttons["Close"].tap()

        // Use a visible keyboard key first: typeText alone can inject text even when
        // the password suggestion has taken over the user's normal keyboard path.
        let key = app.keyboards.keys["a"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertTrue(key.isHittable)
        key.tap()
        app.typeText("manual-pass")
        XCTAssertFalse(suggestion.exists)
        XCTAssertTrue(app.buttons["create_account_submit"].isEnabled)

        email.tap()
        let password = app.secureTextFields["create_account_password"]
        reveal(password, in: app)
        password.tap()
        XCTAssertFalse(suggestion.waitForExistence(timeout: 1))
        app.typeText("2")
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["create_account_password"].value as? String, "amanual-pass2")
        app.buttons["Hide password"].tap()
        app.typeText("3")
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["create_account_password"].value as? String, "amanual-pass23")

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Signup - manual entry after declining password suggestion"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor func testFirstSessionCanExploreWithoutASecondTour() {
        let app = launch("home", extra: ["-ui-testing-first-session", "-ui-testing-spotlights"])
        let explore = app.buttons["first_session_explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["spotlight_next"].exists)
        explore.tap()
        XCTAssertTrue(explore.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feature_tour_next"].exists)
        XCTAssertFalse(app.buttons["spotlight_next"].exists)
    }

    @MainActor func testOptionalFirstLookHasThreeStepsBackAndAnExit() {
        let app = launch("home", extra: ["-ui-testing-first-session", "-ui-testing-spotlights"])
        let tour = app.buttons["first_session_tour"]
        XCTAssertTrue(tour.waitForExistence(timeout: 15), app.debugDescription)
        tour.tap()
        XCTAssertTrue(app.staticTexts["Meet Maia"].waitForExistence(timeout: 5))
        app.buttons["feature_tour_next"].tap()
        XCTAssertTrue(app.staticTexts["Make every set count"].waitForExistence(timeout: 5))
        app.buttons["feature_tour_back"].tap()
        XCTAssertTrue(app.staticTexts["Meet Maia"].waitForExistence(timeout: 5))
        app.buttons["feature_tour_next"].tap()
        app.buttons["feature_tour_next"].tap()
        XCTAssertTrue(app.staticTexts["Life happens. Your plan adapts."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["feature_tour_next"].label, "Open MyFitPlate")
        app.buttons["feature_tour_next"].tap()
        XCTAssertTrue(app.buttons["feature_tour_next"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["spotlight_next"].exists)
    }

    @MainActor func testContextualSpotlightHasExplicitControlsAndBack() {
        let app = launch("home", extra: ["-ui-testing-spotlights"])
        let next = app.buttons["spotlight_next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(next.isHittable)
        let title = app.staticTexts["spotlight_title"]
        XCTAssertEqual(title.label, "Your day, at a glance")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.25)).tap()
        XCTAssertEqual(title.label, "Your day, at a glance")
        next.tap()
        XCTAssertTrue(app.buttons["spotlight_back"].waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Your log, your control")
        app.buttons["spotlight_back"].tap()
        XCTAssertEqual(title.label, "Your day, at a glance")
        let summary = app.staticTexts["home_calories_remaining"]
        XCTAssertTrue(summary.exists, "The spotlight still anchors the visible calorie summary.")
        XCTAssertGreaterThanOrEqual(summary.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(summary.frame.maxY, app.frame.maxY)
        app.buttons["spotlight_skip"].tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 5))
    }

    @MainActor func testSpotlightControlsFitLargestTextInDarkMode() {
        let app = launch("home", extra: ["-ui-testing-spotlights", "-screenshot-dark-mode",
                                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let next = app.buttons["spotlight_next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), app.debugDescription)
        for _ in 0..<3 {
            XCTAssertTrue(next.isHittable)
            XCTAssertTrue(app.buttons["spotlight_skip"].isHittable)
            XCTAssertGreaterThanOrEqual(next.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(next.frame.maxY, app.frame.maxY)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Spotlight at largest text"
            shot.lifetime = .keepAlways
            add(shot)
            next.tap()
        }
        XCTAssertTrue(next.waitForNonExistence(timeout: 5))
    }
}
