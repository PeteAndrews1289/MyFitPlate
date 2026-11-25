import XCTest

/// Read-only journeys against the mock screenshot account. No save, authorization,
/// import/export, workout, deletion or reminder action is performed here.
@MainActor
final class SupportingDesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompactHydrationRespectsTrackingOnlyAndPreferredContainerWithoutLogging() {
        let app = launch("home-water-tracking", flags: ["-ui-testing-reset-editor-drafts"])
        defer {
            app.terminate()
            let clean = launch("home", flags: ["-ui-testing-reset-editor-drafts"])
            _ = element("home_screen_header", in: clean).waitForExistence(timeout: 15)
            clean.terminate()
        }
        let progress = element("livingDayWaterProgress", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(progress.label.contains("mL"), progress.label)
        XCTAssertTrue(progress.label.contains("tracking only"), progress.label)
        XCTAssertFalse(progress.label.contains("/"), "Tracking-only must not invent a target.")
        XCTAssertFalse(progress.label.contains("oz"), "Visible units must match the chosen preference.")
        let add = app.buttons["livingDayAddWaterButton"]
        XCTAssertTrue(add.isHittable)
        XCTAssertTrue(add.label.contains("500 mL"), add.label)
        record(app, "Home - tracking-only water uses the reviewed unit and container")
    }

    func testHomeKeepsOneNextActionAndSecondaryToolsReachable() {
        let app = launch("home")
        let nextAction = app.buttons["livingDayCurrentAction"]
        XCTAssertTrue(nextAction.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(nextAction.isHittable, "The next action should not require opening guidance.")
        XCTAssertEqual(app.buttons.matching(identifier: "livingDayCurrentAction").count, 1)
        record(app, "Home - one next action")

        let guidance = app.buttons["home_guidance_disclosure"]
        reveal(guidance, in: app)
        guidance.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "livingDayCurrentAction").count, 1,
                       "Expanding the explanation must not duplicate the primary action.")
        XCTAssertTrue(element("livingDayMaiaAnnotation", in: app).exists)
        guidance.tap()

        let support = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label BEGINSWITH %@",
            "home_supporting_insights", "Fuel, health & trends"
        )).firstMatch
        reveal(support, in: app)
        support.tap()
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Training & Fuel")).firstMatch
        reveal(review, in: app)
        XCTAssertTrue(review.isHittable, "The weekly review remains reachable in supporting insights.")
        record(app, "Home - secondary insights remain available")
    }

    func testCompactHydrationHonorsUnitsTrackingOnlyAndExplicitIncrement() {
        let app = launch("home-hydration-design")
        let progress = element("livingDayWaterProgress", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(progress.label.contains("mL"))
        XCTAssertTrue(progress.label.contains("tracking only"))
        XCTAssertFalse(progress.label.contains("/"), "Tracking-only must not display a target.")
        let add = app.buttons["livingDayAddWaterButton"]
        XCTAssertTrue(add.label.contains("500 mL"), "The button must state its actual increment.")
        XCTAssertTrue(add.isHittable)
        let tracking = app.switches["hydration_design_tracking_only"]
        tracking.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let target = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "/ 2,000 mL", "/ 2000 mL"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [target], timeout: 5), .completed)
        app.segmentedControls["hydration_design_unit"].buttons["oz"].tap()
        XCTAssertTrue(progress.label.contains("oz"))
        XCTAssertFalse(progress.label.contains("mL"))
        XCTAssertTrue(add.label.contains("16.9 oz"))
        record(app, "Compact hydration - correct unit and exact increment")
    }

    func testSettingsCategoriesKeepExistingDestinationsWithoutInlineControls() {
        let app = launch("settings")
        XCTAssertTrue(element("settings_screen", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings_export_start"].exists)
        XCTAssertEqual(app.switches.count, 0, "The directory should show destinations, not every setting at once.")
        record(app, "Settings - focused directory")

        let categories: [(name: String, content: String)] = [
            ("goals", "settings_goals_data"),
            ("appearance", "settings_display_units"),
            ("health", "settings_integrations"),
            ("notifications", "settings_notifications"),
            ("training", "settings_training"),
            ("maia", "settings_maia"),
            ("data", "settings_goals_data"),
            ("support", "settings_help_support")
        ]
        for category in categories {
            let row = app.buttons["settings_open_\(category.name)"]
            // A partially visible row can still report hittable behind iOS's bottom search field.
            // Put the entire control between the navigation bar and search before tapping it.
            let search = app.searchFields.firstMatch
            for _ in 0..<6 {
                let top = app.navigationBars.firstMatch.frame.maxY + 8
                let bottom = search.exists ? search.frame.minY - 8 : app.frame.maxY - 90
                if row.exists && row.isHittable && row.frame.minY >= top && row.frame.maxY <= bottom { break }
                if row.exists && row.frame.minY < top { app.swipeDown() } else { app.swipeUp() }
            }
            XCTAssertTrue(row.exists && row.isHittable, app.debugDescription)
            XCTAssertGreaterThanOrEqual(row.frame.minY, app.navigationBars.firstMatch.frame.maxY + 8)
            XCTAssertLessThanOrEqual(row.frame.maxY, search.exists ? search.frame.minY - 8 : app.frame.maxY - 90)
            row.tap()
            XCTAssertTrue(element("settings_category_\(category.name)", in: app).waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(element(category.content, in: app).exists, app.debugDescription)
            if category.name == "goals" {
                XCTAssertEqual(app.buttons.matching(identifier: "settings_calorie_goals").count, 1)
                XCTAssertFalse(app.buttons["Calorie goal method"].exists, "One goal editor entry is enough.")
                XCTAssertFalse(app.buttons["settings_export_start"].exists)
            }
            if category.name == "data" {
                XCTAssertTrue(app.buttons["settings_export_start"].exists)
                XCTAssertFalse(app.buttons["settings_calorie_goals"].exists)
            }
            record(app, "Settings - \(category.name)")
            let back = app.navigationBars.buttons["Settings"]
            XCTAssertTrue(back.isHittable, app.debugDescription)
            back.tap()
        }
    }

    func testReportsShowPartialIntakeAndKeepDatesInStrengthDetail() {
        let app = launch("reports")
        let metric = app.buttons["reports_intake_metric"]
        XCTAssertTrue(metric.waitForExistence(timeout: 15))
        let caption = app.staticTexts["reports_intake_caption"]
        XCTAssertGreaterThan(app.staticTexts["reports_screen_header"].frame.width, 60)
        XCTAssertTrue(caption.label.contains("Latest logged"))
        let chart = app.otherElements.matching(NSPredicate(format: "label == %@", "Daily recorded calories")).firstMatch
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.6)).tap()
        XCTAssertTrue(caption.label.contains("Recorded intake"))
        let chartDay = caption.label
        app.buttons["reports_open_diary_day"].tap()
        XCTAssertTrue(app.navigationBars["Food diary"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Edit in diary"].waitForExistence(timeout: 8))
        record(app, "Chart diary day")
        XCTAssertTrue(app.staticTexts["diary_review_totals"].label.contains("g protein"))
        let breakfast = app.buttons["diary_toggle_Breakfast"]
        let foodID = firstDiaryFood(in: app).identifier
        let food = element(foodID, in: app)
        XCTAssertTrue(food.label.contains("grams protein"))
        XCTAssertFalse(app.buttons["diary_add_Breakfast"].exists)
        breakfast.tap()
        XCTAssertEqual(breakfast.value as? String, "Collapsed")
        XCTAssertFalse(food.exists)
        breakfast.tap()
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertEqual(caption.label, chartDay)
        app.buttons["Reset"].tap()
        XCTAssertTrue(caption.label.contains("Latest logged"))
        metric.tap()
        app.buttons["Protein"].tap()
        XCTAssertTrue(app.staticTexts["reports_nutrition_evidence"].label.contains("Partial days"))
        record(app, "Reports - protein for the latest logged day")
        app.segmentedControls["reports_focus"].buttons["Training"].tap()
        let strength = app.buttons["reports_strength_performance"]
        revealReportContent(strength, in: app)
        strength.tap()
        let period = app.buttons["report_period"]
        XCTAssertTrue(period.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Strength comparison"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Previous"].exists)
        record(app, "Strength period comparison")
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now))!
        let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: now))!
        let expectedPeriod = (start..<end).formatted(.interval.year().month(.abbreviated).day())
        XCTAssertTrue(period.label.contains(expectedPeriod) || period.staticTexts[expectedPeriod].exists, period.debugDescription)
        let duration = app.staticTexts["report_session_duration"]
        revealReportContent(duration, in: app)
        XCTAssertEqual(duration.label, "Duration unavailable")
        record(app, "Strength duration from untimed sessions")
    }

    func testIntakeChartOpensFullDiaryForTheSameHistoricalDay() {
        let app = launch("reports")
        let chart = app.otherElements.matching(NSPredicate(format: "label == %@", "Daily recorded calories")).firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 12))
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.6)).tap()
        app.buttons["reports_open_diary_day"].tap()
        let fullDate = app.staticTexts["diary_review_full_date"]
        XCTAssertTrue(fullDate.waitForExistence(timeout: 8))
        let dateLabel = fullDate.label
        let reportFood = firstDiaryFood(in: app)
        let foodID = reportFood.identifier
        let foodLabel = reportFood.label
        app.buttons["Edit in diary"].tap()
        let calendar = app.buttons["home_diary_calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 12))
        XCTAssertTrue(calendar.label.contains(dateLabel))
        XCTAssertEqual(calendar.value as? String, "Historical day")
        app.buttons["home_diary_index"].tap()
        app.buttons["Breakfast"].tap()
        let diaryFood = app.buttons[foodID]
        XCTAssertTrue(diaryFood.waitForExistence(timeout: 8))
        XCTAssertEqual(diaryFood.label, foodLabel)
    }

    private func firstDiaryFood(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH 'diary_food_' AND NOT identifier BEGINSWITH 'diary_food_options_'")).firstMatch
    }

    func testStrengthDurationShowsHowManySessionsWereTimed() {
        let app = launch("reports", flags: ["-ui-testing-partially-timed-workouts"])
        let focus = app.segmentedControls["reports_focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 10))
        focus.buttons["Training"].tap()
        let strength = app.buttons["reports_strength_performance"]
        revealReportContent(strength, in: app)
        strength.tap()
        let duration = app.staticTexts["report_session_duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 10))
        revealReportContent(duration, in: app)
        XCTAssertEqual(duration.label, "45 min recorded · 1 of 2 sessions timed")
        record(app, "Strength duration with partial timing")
    }

    func testNutritionAndWeightOpenOnTheSameReportDates() {
        let app = launch("reports")
        let period = app.segmentedControls["reports_timeframe"]
        XCTAssertTrue(period.waitForExistence(timeout: 12))
        period.buttons["7 days"].tap()
        let nutrition = app.buttons["reports_nutrition_detail"]
        revealReportContent(nutrition, in: app)
        nutrition.tap()
        let dates = app.staticTexts["nutrition_trends_dates"]
        XCTAssertTrue(dates.waitForExistence(timeout: 10))
        let selected = dates.label
        XCTAssertTrue(selected.contains(" – "))
        app.navigationBars.buttons.firstMatch.tap()
        let weight = app.buttons["reports_weight_detail"]
        revealReportContent(weight, in: app)
        weight.tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 8), app.debugDescription)
        let scope = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                          selected + " · ", "measurement")).firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 8), app.debugDescription)
    }

    func testReportsSeparateSelectedPeriodFromRecentRecoveryAndWeeklyReview() {
        let app = launch("reports")
        let focus = app.segmentedControls["reports_focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(focus.isHittable, "Report focus must be available without scrolling.")
        XCTAssertGreaterThanOrEqual(focus.frame.minY, app.scrollViews.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(focus.frame.maxY, element("main_navigation_dock", in: app).frame.minY)
        record(app, "Reports - compact trend and immediate focus")
        XCTAssertTrue(element("reports_nutrition_content", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(element("reports_recovery_content", in: app).exists)
        let calorieDetail = app.buttons["reports_nutrition_detail"]
        revealReportContent(calorieDetail, in: app)
        record(app, "Reports - nutrition focus")

        revealReportContent(focus, in: app)
        focus.buttons["Training"].tap()
        XCTAssertTrue(element("reports_training_content", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("reports_nutrition_content", in: app).exists)
        XCTAssertTrue(app.staticTexts["Last 7 days · independent of the selected dates"].exists)
        let workoutDetail = app.buttons["reports_strength_performance"]
        revealReportContent(workoutDetail, in: app)
        record(app, "Reports - training and weekly scope")

        revealReportContent(focus, in: app)
        focus.buttons["Recovery"].tap()
        XCTAssertTrue(element("reports_recovery_content", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Recent evidence · independent of the selected dates"].exists)
        XCTAssertTrue(app.staticTexts["Apple Health snapshot · last 7 days"].exists)
        XCTAssertFalse(app.staticTexts["Recorded habits"].exists, "A week without habit scores should show the measured Health data directly.")
        XCTAssertFalse(element("reports_training_content", in: app).exists)
        let healthMetric = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Heart rate variability,")).firstMatch
        revealReportContent(healthMetric, in: app)
        record(app, "Reports - honest recovery scope")
    }

    func testReceiptShowsAllNamedItemsBeforeEditingAndRestoresTheCorrectProduct() {
        let app = launch("receipt-review", flags: ["-ui-testing-reset-editor-drafts"])
        let names = ["Greek Yogurt", "Baby Spinach", "Jasmine Rice"]
        let save = app.buttons["receipt_add_to_pantry_button"]
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        for (index, name) in names.enumerated() {
            let row = app.buttons["receipt_product_\(index)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains(name))
            XCTAssertTrue(row.isHittable)
            XCTAssertLessThan(row.frame.maxY, save.frame.minY)
        }
        XCTAssertFalse(app.textFields["Item name"].exists)
        record(app, "Receipt - all three products above the pantry action")
        app.buttons["receipt_product_1"].tap()
        let name = app.textFields["Item name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.replaceContents(with: "Baby Spinach QA", in: app)
        name.typeText("\n")
        app.buttons["receipt_product_1"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-testing-reset-editor-drafts" }
        app.launch()
        let edited = app.buttons["receipt_product_1"]
        XCTAssertTrue(edited.waitForExistence(timeout: 10))
        XCTAssertTrue(edited.label.contains("Baby Spinach QA"))
        XCTAssertTrue(app.buttons["receipt_product_0"].label.contains("Greek Yogurt"))
        XCTAssertTrue(app.buttons["receipt_product_2"].label.contains("Jasmine Rice"))
        XCTAssertTrue(save.isEnabled)
    }

    private func revealReportContent(_ target: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        let dock = element("main_navigation_dock", in: app)
        for _ in 0..<12 {
            let top = scroll.frame.minY + 8
            let bottom = dock.frame.minY - 8
            if target.exists, target.isHittable, target.frame.minY >= top, target.frame.maxY <= bottom { return }
            // A full swipe can jump from below the dock to above the navigation bar.
            // Move only the missing distance so the complete selected card can settle in view.
            let translation: CGFloat
            if target.exists, target.frame.minY < top {
                translation = min(180, max(36, top - target.frame.minY))
            } else if target.exists {
                translation = -min(180, max(36, target.frame.maxY - bottom))
            } else {
                translation = -180
            }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: scroll.frame.midX, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: translation)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        record(app, "Reports - content visibility failure")
        XCTAssertTrue(target.isHittable, app.debugDescription)
        XCTAssertGreaterThanOrEqual(target.frame.minY, scroll.frame.minY + 8)
        XCTAssertLessThanOrEqual(target.frame.maxY, dock.frame.minY - 8)
    }

    func testWeightEntryShowsMeasurementDateAndSaveWithoutChangingRecords() {
        let app = launch("weight-detail")
        let logWeight = app.buttons["weight_log_button"]
        XCTAssertTrue(logWeight.waitForExistence(timeout: 10), app.debugDescription)
        logWeight.tap()
        let field = app.textFields["weight_entry_value"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        let save = app.buttons["weight_entry_save"]
        let saveReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard save.exists, save.isHittable else { return false }
            let frame = save.frame
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
                  frame.width >= 44, frame.height >= 44, app.frame.contains(frame) else { return false }
            let keyboard = app.keyboards.firstMatch
            return !keyboard.exists || frame.maxY <= keyboard.frame.minY + 1
        }, object: save)
        let readiness = XCTWaiter.wait(for: [saveReady], timeout: 8)
        // Retain the actual keyboard/layout evidence even if the bounded readiness check fails.
        record(app, "Weight - compact measurement with keyboard")
        XCTAssertEqual(readiness, .completed, "Save must settle fully on screen above the keyboard.")
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(field.isHittable)
        XCTAssertTrue(element("weight_entry_date", in: app).isHittable)
        XCTAssertFalse(app.staticTexts["Entry Date"].exists, "The date belongs alongside the measurement.")
        app.navigationBars["Log weight"].buttons["Cancel"].tap()
        XCTAssertTrue(element("weight_tracking_screen", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("weight_entry_screen", in: app).exists)
    }

    func testSelectedPeriodFailureKeepsIndependentReportDestinationsReachable() {
        // This existing fixture fails mock daily-history reads; it does not perform an export.
        let app = launch("reports", flags: ["-ui-testing-export-failure"])
        let error = element("reports_period_error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(element("reports_overview", in: app).exists,
                       "A failed period must not look like a loaded nutrition summary.")
        XCTAssertFalse(app.staticTexts["Daily calories"].exists)
        XCTAssertFalse(app.staticTexts["By meal"].exists)
        // SwiftUI propagates the workspace's identifier to this NavigationLink;
        // its combined semantic label still identifies the actual visible control.
        let metabolism = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Adaptive metabolism,"
        )).firstMatch
        reveal(metabolism, in: app)
        XCTAssertTrue(metabolism.isHittable)
        record(app, "Reports - period failure retains metabolism")
        metabolism.tap()
        XCTAssertTrue(element("adaptive_tdee_screen", in: app).waitForExistence(timeout: 10))
        let back = app.navigationBars["Adaptive metabolism"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10))

        let focus = app.segmentedControls["reports_focus"]
        reveal(focus, in: app, direction: .down)
        focus.buttons["Training"].tap()
        XCTAssertTrue(error.exists)
        XCTAssertTrue(app.buttons["reports_strength_performance"].exists)
        XCTAssertFalse(app.staticTexts["Workout summary"].exists)
        let weeklyReview = app.staticTexts["Last 7 days · independent of the selected dates"]
        reveal(weeklyReview, in: app)
        XCTAssertTrue(weeklyReview.isHittable)
        // The same fixture also fails the independent weekly fetch. Its own retry must survive.
        let weeklyRetry = app.buttons["Try again"]
        reveal(weeklyRetry, in: app)
        XCTAssertTrue(weeklyRetry.isHittable)
        record(app, "Reports - weekly retry remains available")

        reveal(focus, in: app, direction: .down)
        focus.buttons["Recovery"].tap()
        XCTAssertTrue(error.exists)
        let health = app.staticTexts["Apple Health snapshot · last 7 days"]
        reveal(health, in: app)
        XCTAssertTrue(health.isHittable)
        XCTAssertTrue(element("reports_recovery_content", in: app).exists)
        record(app, "Reports - diary failure does not hide Health")
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        for _ in 0..<10 {
            if target.exists && target.isHittable { return }
            if direction == .up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(target.exists && target.isHittable, app.debugDescription)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launch(_ screen: String, flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-screenshot-mode", "-screenshot-screen", screen,
            "-living-day-home", "-ui-testing-wave2-phul",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ] + flags
        app.launch()
        if app.buttons["welcome_get_started"].waitForExistence(timeout: 2) {
            app.terminate()
            app.launch()
        }
        return app
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) - accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
