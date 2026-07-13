//
//  MyFitPlateUITests.swift
//  MyFitPlateUITests
//
//  Created by Peter Andrews on 6/27/26.
//

import XCTest

final class MyFitPlateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    private func focusAndType(_ text: String, into field: XCUIElement) {
        var receivedFocus = false

        for _ in 0..<2 where !receivedFocus {
            field.tap()
            let focusExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                object: field
            )
            receivedFocus = XCTWaiter.wait(for: [focusExpectation], timeout: 3) == .completed
        }

        XCTAssertTrue(receivedFocus, "The text field should receive keyboard focus")
        field.typeText(text)
    }

    @MainActor
    func testHomeDashboardLoads() throws {
        let app = XCUIApplication()

        // Wait for the home dashboard to load
        let homeTitle = app.staticTexts["Home"]
        XCTAssertTrue(homeTitle.waitForExistence(timeout: 10), "Home dashboard should be visible")

        // Check for key elements like the weekly check-in or progress circles
        let progressElement = app.otherElements["MetabolismProgress"]
        if progressElement.exists {
            XCTAssertTrue(progressElement.isHittable)
        }
    }

    @MainActor
    func testFoodSearchNavigation() throws {
        let app = XCUIApplication()

        let quickLogButton = app.buttons["quick_log_button"]
        XCTAssertTrue(quickLogButton.waitForExistence(timeout: 5), "Quick log button should be visible")
        let quickLogHittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: quickLogButton)
        XCTAssertEqual(XCTWaiter.wait(for: [quickLogHittable], timeout: 5), .completed)
        let searchFoodButton = app.buttons["Search food"]
        quickLogButton.press(forDuration: 0.1)
        if !searchFoodButton.waitForExistence(timeout: 3) {
            XCTAssertTrue(quickLogButton.isHittable, "Quick Log should remain tappable after a dropped input event")
            quickLogButton.press(forDuration: 0.1)
        }
        XCTAssertTrue(searchFoodButton.waitForExistence(timeout: 5), "Search Food option should be visible")
        searchFoodButton.tap()

        let searchField = app.textFields["Search foods, meals, brands"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Food search field should appear")

        focusAndType("Apple", into: searchField)

        let firstResult = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Test Kitchen Apple"))
            .firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "Search results should populate")
    }

    @MainActor
    func testFoodSearchFailureOffersRetryAndManualFallback() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-search-failure",
            "-screenshot-mode",
            "-screenshot-screen",
            "food-search"
        ]
        app.launch()

        let searchField = app.textFields["Search foods, meals, brands"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        focusAndType("apple", into: searchField)

        XCTAssertTrue(app.staticTexts["Search could not load"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["We couldn't reach the food databases. Your saved and recent foods still work."].exists)
        XCTAssertTrue(app.buttons["Try again"].isHittable)
        XCTAssertTrue(app.buttons["Create food"].isHittable)
    }

    @MainActor
    func testHomeDarkAccessibilityTextIsNotClipped() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-dark-mode",
            "-screenshot-screen",
            "home",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["quick_log_button"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Review Food Trust"))
                .firstMatch
                .isHittable
        )
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testVisualSystemGalleryIsLegible() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "visual-system"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["visualSystemGallery"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["visualSystemHero"].exists)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Visual system gallery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testQuickLogSheetDarkAccessibilityLayout() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-dark-mode",
            "-screenshot-screen",
            "quick-log",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let searchFood = app.descendants(matching: .any)["quick_log_search_food"]
        XCTAssertTrue(
            searchFood.waitForExistence(timeout: 8),
            "Quick Log should expose its primary action at accessibility text sizes"
        )
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertGreaterThan(searchFood.frame.width, 0)
        XCTAssertGreaterThanOrEqual(searchFood.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(searchFood.frame.maxX, app.frame.maxX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick Log - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTrainUsesUnifiedActionHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "train"
        ]
        app.launch()

        let header = app.staticTexts["Train"]
        let nextStep = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Dumbbell Strength & Hypertrophy"))
            .firstMatch
        let programWeek = app.staticTexts["Program Week"]

        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(nextStep.waitForExistence(timeout: 5))
        XCTAssertTrue(programWeek.waitForExistence(timeout: 5))
        XCTAssertLessThan(nextStep.frame.minY, programWeek.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Train - unified hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMealPlanUsesUnifiedPlanningHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "meal-plan"
        ]
        app.launch()

        let header = app.staticTexts["Meal Plan"]
        let week = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "planned meals, selected"))
            .firstMatch
        let summary = app.staticTexts["Today's meal plan"]
        let day = app.staticTexts["Today's plan"]

        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertLessThan(week.frame.minY, summary.frame.minY)
        XCTAssertLessThan(summary.frame.minY, day.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Meal Plan - unified hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTrainAndMealPlanSupportDarkAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "train", label: "Dumbbell Strength & Hypertrophy", isButton: false),
            (name: "meal-plan", label: "planned meals, selected", isButton: true)
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-dark-mode",
                "-screenshot-screen",
                screen.name,
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let primarySurface: XCUIElement
            if screen.isButton {
                primarySurface = app.buttons
                    .matching(NSPredicate(format: "label CONTAINS %@", screen.label))
                    .firstMatch
            } else {
                primarySurface = app.staticTexts
                    .matching(NSPredicate(format: "label == %@", screen.label))
                    .firstMatch
            }
            XCTAssertTrue(primarySurface.waitForExistence(timeout: 12))
            XCTAssertGreaterThan(primarySurface.frame.width, 0)
            XCTAssertGreaterThanOrEqual(primarySurface.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(primarySurface.frame.maxX, app.frame.maxX + 1)
            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testLivingDayOrdersActionsAndOffersExplicitShareSelection() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "home",
            "-living-day-home"
        ]
        app.launch()

        let surface = app.staticTexts["Living Day"]
        let action = app.descendants(matching: .any)["livingDayCurrentAction"]
        let maia = app.descendants(matching: .any)["livingDayMaiaAnnotation"]
        let firstEvent = app.descendants(matching: .any)
            .matching(identifier: "livingDayEvent")
            .firstMatch
        let share = app.descendants(matching: .any)["livingDayShareButton"]
        let density = app.descendants(matching: .any)["livingDayDensityMenu"]

        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(maia.waitForExistence(timeout: 5))
        XCTAssertTrue(firstEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(density.isHittable)
        XCTAssertLessThan(action.frame.minY, maia.frame.minY)
        XCTAssertLessThan(maia.frame.minY, firstEvent.frame.minY)

        let detailedPath = app.buttons["Detailed path"]
        density.press(forDuration: 0.1)
        if !detailedPath.waitForExistence(timeout: 3), density.isHittable {
            density.press(forDuration: 0.1)
        }
        XCTAssertTrue(detailedPath.waitForExistence(timeout: 7))
        detailedPath.tap()

        try app.performAccessibilityAudit(for: [.textClipped])

        share.tap()
        XCTAssertTrue(app.navigationBars["Share Living Day"].waitForExistence(timeout: 5))

        let budget = app.switches["livingDayShareBudgetToggle"]
        let path = app.switches["livingDaySharePathToggle"]
        let trust = app.switches["livingDayShareTrustToggle"]
        let nextAction = app.switches["livingDayShareActionToggle"]
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        XCTAssertTrue(path.exists)
        XCTAssertTrue(trust.exists)
        XCTAssertTrue(nextAction.exists)

        trust.tap()
        budget.tap()
        XCTAssertTrue(path.isEnabled)
        XCTAssertTrue(nextAction.isEnabled)

        let commit = app.descendants(matching: .any)["livingDayShareCommitButton"]
        for _ in 0..<4 where !commit.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertTrue(commit.isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Living Day explicit share selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLivingDaySupportsLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "home",
            "-living-day-home",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let surface = app.staticTexts["Living Day"]
        let action = app.descendants(matching: .any)["livingDayCurrentAction"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX + 1)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Living Day accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLivingDaySurvivesReportsTabRoundTrip() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "home",
            "-living-day-home"
        ]
        app.launch()

        let livingDay = app.staticTexts["Living Day"]
        XCTAssertTrue(livingDay.waitForExistence(timeout: 10))

        app.buttons["tab_reports"].tap()
        XCTAssertTrue(app.navigationBars["Reports"].waitForExistence(timeout: 5))

        app.buttons["tab_home"].tap()
        XCTAssertTrue(
            livingDay.waitForExistence(timeout: 5),
            "Living Day should remain enabled when Home is rebuilt after a tab change"
        )
    }

    @MainActor
    func testSettingsFeedbackAndShareRowsAreReachable() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "settings"
        ]
        app.launch()

        let feedbackRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Feedback & support"))
            .firstMatch
        let shareRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Share MyFitPlate"))
            .firstMatch

        for _ in 0..<8 where !feedbackRow.isHittable || !shareRow.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 5), "Feedback row should be reachable in Settings")
        XCTAssertTrue(shareRow.waitForExistence(timeout: 5), "App Store sharing row should be reachable in Settings")
        XCTAssertTrue(feedbackRow.isHittable, "Feedback row should be visible and tappable")
        XCTAssertTrue(shareRow.isHittable, "App Store sharing row should be visible and tappable")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings feedback and sharing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTrainingFuelNotificationControlsAreReachableAndFit() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "settings",
            "-trainingFuelPreSessionNotificationsEnabled",
            "YES",
            "-trainingFuelEveningNotificationsEnabled",
            "YES"
        ]
        app.launch()

        let beforeTraining = app.switches["Before training"]
        let recovery = app.switches["Recovery target"]
        let evening = app.switches["Evening protein catch-up"]
        for _ in 0..<6 where !beforeTraining.isHittable || !evening.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(beforeTraining.waitForExistence(timeout: 5))
        XCTAssertTrue(recovery.exists)
        XCTAssertTrue(evening.exists)
        XCTAssertTrue(app.staticTexts["Quiet hours"].exists)
        XCTAssertTrue(app.staticTexts["Evening reminder"].exists)
        XCTAssertLessThanOrEqual(evening.frame.maxX, app.frame.maxX + 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Training fuel notification controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMaiaVoiceControlsAreReachableAndFit() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "settings"
        ]
        app.launch()

        let spokenVoice = app.staticTexts["Spoken voice"]
        let previewVoice = app.buttons["Preview Voice"]
        for _ in 0..<8 where !spokenVoice.isHittable || !previewVoice.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(spokenVoice.waitForExistence(timeout: 5))
        XCTAssertTrue(previewVoice.waitForExistence(timeout: 5))
        XCTAssertTrue(previewVoice.isHittable)
        XCTAssertLessThanOrEqual(previewVoice.frame.maxX, app.frame.maxX + 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Maia voice controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testHomeTrustHubHasNavigationAndInteractiveRows() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "home"
        ]
        app.launch()

        let trustButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Review Food Trust"))
            .firstMatch
        XCTAssertTrue(trustButton.waitForExistence(timeout: 8), "Home should expose the food trust review")
        XCTAssertTrue(
            app.staticTexts["Daily log"].waitForExistence(timeout: 8),
            "Home should finish loading the deterministic diary before interaction"
        )
        let trustHittable = expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: trustButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [trustHittable], timeout: 5), .completed)
        let doneButton = app.buttons["Done"]
        trustButton.press(forDuration: 0.1)
        if !doneButton.waitForExistence(timeout: 3), trustButton.isHittable {
            trustButton.press(forDuration: 0.1)
        }
        XCTAssertTrue(doneButton.waitForExistence(timeout: 7), "Trust Hub should always provide a visible dismissal")
        XCTAssertTrue(doneButton.isHittable, "Trust Hub dismissal should be tappable")

        let verifiedFood = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Greek Yogurt Parfait"))
            .firstMatch
        XCTAssertTrue(verifiedFood.waitForExistence(timeout: 5), "Verified foods should appear in Trust Hub")
        XCTAssertTrue(verifiedFood.isEnabled, "Trust Hub food rows should remain interactive")

        doneButton.tap()
        XCTAssertTrue(
            app.buttons["quick_log_button"].waitForExistence(timeout: 5),
            "Done should return to Home"
        )
    }

    @MainActor
    func testWeeklyTrainingFuelReportRendersPopulatedAndScrollable() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "weekly-report"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Training & Fuel"].waitForExistence(timeout: 10),
            "The unified weekly report should open directly in screenshot mode"
        )
        XCTAssertTrue(
            app.staticTexts["weekly_report_headline"].waitForExistence(timeout: 10),
            "The report should finish its deterministic data load"
        )
        XCTAssertTrue(app.otherElements["weekly_report_strength"].exists)

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "Unified Training and Fuel report - top"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        let fueling = app.otherElements["weekly_report_fueling"]
        for _ in 0..<6 where !fueling.exists || !fueling.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(fueling.waitForExistence(timeout: 5), "Fueling denominators should be reachable")

        let middleScreenshot = XCTAttachment(screenshot: app.screenshot())
        middleScreenshot.name = "Unified Training and Fuel report - running and fueling"
        middleScreenshot.lifetime = .keepAlways
        add(middleScreenshot)

        let share = app.descendants(matching: .any)["weekly_report_share"]
        for _ in 0..<8 where !share.exists || !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.otherElements["weekly_report_context"].exists, "Outcome context should be reachable")
        XCTAssertTrue(share.waitForExistence(timeout: 5), "The privacy-reviewed share menu should be reachable")

        let bottomScreenshot = XCTAttachment(screenshot: app.screenshot())
        bottomScreenshot.name = "Unified Training and Fuel report - context and share"
        bottomScreenshot.lifetime = .keepAlways
        add(bottomScreenshot)

        share.tap()
        let chooseImage = app.buttons["Choose summary image"]
        XCTAssertTrue(chooseImage.waitForExistence(timeout: 3))
        chooseImage.tap()
        XCTAssertTrue(app.navigationBars["Share Week in Motion"].waitForExistence(timeout: 5))

        let rhythm = app.switches["weeklyShareRhythmToggle"]
        let evidence = app.switches["weeklyShareEvidenceToggle"]
        let observation = app.switches["weeklyShareObservationToggle"]
        XCTAssertTrue(rhythm.waitForExistence(timeout: 5))
        XCTAssertTrue(evidence.exists)
        XCTAssertTrue(observation.exists)
        evidence.tap()

        let shareImage = app.descendants(matching: .any)["weeklyShareCommitButton"]
        for _ in 0..<4 where !shareImage.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(shareImage.waitForExistence(timeout: 5))
        XCTAssertTrue(shareImage.isHittable)
    }

    @MainActor
    func testWeeklyTrainingFuelReportSupportsLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "weekly-report",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let headline = app.staticTexts["weekly_report_headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertLessThanOrEqual(headline.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(headline.frame.minX, app.frame.minX - 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unified Training and Fuel report - accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCustomProductPageDeepLinksOpenExactDestinations() throws {
        let app = XCUIApplication()
        let destinations = [
            ("myfitplate://food-search", "Log food"),
            ("myfitplate://trust", "Trust Hub"),
            ("myfitplate://builder", "Fast Food"),
            ("myfitplate://runs", "Running"),
            ("myfitplate://meal-plan", "Meal plan"),
            ("myfitplate://training-fuel", "Training Fuel")
        ]

        for (url, title) in destinations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-deep-link-url",
                url
            ]
            app.launch()

            let navigationTitle = app.navigationBars[title]
            let visibleTitle = app.staticTexts[title]
            XCTAssertTrue(
                navigationTitle.waitForExistence(timeout: 8) || visibleTitle.waitForExistence(timeout: 3),
                "\(url) should open \(title), not a neighboring tab"
            )
        }
    }
}
