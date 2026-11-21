import XCTest

final class EliteLoggingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNutritionTrendsExplainsConfirmedDayCoverage() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "nutrition-trends"]
        app.launch()
        let coverage = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Charts show recorded entries.'")).firstMatch
        XCTAssertTrue(coverage.waitForExistence(timeout: 15))
        XCTAssertTrue(coverage.label.contains("0 fully logged days"))
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Nutrition trends - confirmed day coverage"; evidence.lifetime = .keepAlways; add(evidence)
    }

    @MainActor
    func testHomeDayReviewSavesAndSecondaryGuidanceCanExpand() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "home", "-ui-testing-day-review-persistence"]
        app.launch()
        let guidance = app.buttons["home_guidance_disclosure"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["home_next_workout"].exists)
        let review = app.buttons["nutrition_day_review"]
        revealHomeControl(review, in: app)
        review.tap()
        app.buttons["Fully logged"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Fully logged'"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Home - confirmed food-log day"; image.lifetime = .keepAlways; add(image)
        revealHomeControl(guidance, in: app)
        guidance.press(forDuration: 0.1)
        let annotation = app.buttons["livingDayMaiaAnnotation"]
        XCTAssertTrue(annotation.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func revealHomeControl(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let top = 170.0, bottom = app.frame.maxY - 150
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let distance = element.exists && element.frame.midY < top ? 150.0 : -150.0
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("Couldn't reach \(element.identifier): \(app.debugDescription)")
    }

    @MainActor
    func testCompactSearchKeepsFoodDestinationAndSecondaryToolsAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search",
                               "-ui-testing-reset-editor-drafts"]
        app.launch()
        let meal = app.buttons["food_search_meal_menu"]
        XCTAssertTrue(meal.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["repeat_food_add_0"].isHittable)
        XCTAssertTrue(app.buttons["repeat_food_add_1"].isHittable)
        XCTAssertEqual(app.segmentedControls.count, 0)
        meal.tap()
        app.buttons["Lunch"].tap()
        XCTAssertTrue(meal.label.contains("Lunch"))
        app.buttons["food_search_repeat_scope"].tap()
        app.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["food_search_repeat_scope"].label.contains("Saved"))
        app.buttons["food_search_more_actions"].tap()
        XCTAssertTrue(app.buttons["Describe food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enter manually"].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Food search - secondary tools"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testUnavailableBarcodeScannerReturnsToFoodSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search",
                               "-ui-testing-reset-editor-drafts"]
        app.launch()
        let barcode = app.buttons["food_search_action_barcode"]
        XCTAssertTrue(barcode.waitForExistence(timeout: 10))
        barcode.tap()
        let back = app.buttons["Use another logging method"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["food_search_field"].isHittable)
        XCTAssertFalse(app.buttons["food_search_undo"].exists)
    }

    @MainActor
    func testFoodReviewCanCancelWithoutLogging() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search",
                               "-ui-testing-reset-editor-drafts"]
        app.launch()
        let review = app.buttons["repeat_food_review_0"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()

        let cancel = app.buttons["food_detail_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.buttons["food_detail_saved"].isHittable)
        XCTAssertTrue(app.buttons["food_detail_log_action"].exists)
        cancel.tap()

        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 5))
        XCTAssertTrue(review.isHittable)
        XCTAssertFalse(app.buttons["food_search_undo"].exists)
        XCTAssertFalse(app.buttons["food_detail_log_action"].exists)
    }

    @MainActor
    func testMealDraftFoodReviewCanCancelWithoutChangingDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search",
                               "-ui-testing-reset-editor-drafts"]
        app.launch()
        let mode = app.buttons["food_search_mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.tap()
        let add = app.buttons["repeat_food_add_0"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let total = app.staticTexts["meal_draft_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let originalTotal = total.label
        app.buttons["meal_draft_edit_0"].tap()

        let cancel = app.buttons["food_detail_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()

        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, originalTotal)
        XCTAssertTrue(app.buttons["meal_draft_log"].isEnabled)
        XCTAssertFalse(app.buttons["food_search_undo"].exists)
    }

    @MainActor
    func testMaiaFoodActionFailedSaveRemainsAvailableToRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "maia-action-cards",
                               "-ui-testing-food-save-failure"]
        app.launch()
        let log = app.buttons["maia_meal_log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.tap()
        let alert = app.alerts["Maia"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS \"Couldn't save\"")).firstMatch.exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(log.label, "Log food")
        log.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMealSuggestionFailedSaveKeepsReviewOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-suggestion",
                               "-ui-testing-food-save-failure"]
        app.launch()
        let log = app.buttons["meal_suggestion_log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.tap()
        XCTAssertTrue(app.staticTexts["meal_suggestion_save_error"].waitForExistence(timeout: 5))
        XCTAssertTrue(log.isEnabled)
        XCTAssertTrue(app.otherElements["meal_suggestion_detail_screen"].exists)
    }

    @MainActor
    func testPantryRecipeFailedSaveKeepsRecipeForRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "pantry-photo-recipes",
                               "-ui-testing-food-save-failure"]
        app.launch()
        let idea = app.buttons["Chicken rice bowl"]
        XCTAssertTrue(idea.waitForExistence(timeout: 10))
        idea.tap()
        let review = app.buttons["Review food log"]
        for _ in 0..<6 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isEnabled)
        review.tap()
        let log = app.buttons["recipe_log_action"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        log.tap()
        let error = app.staticTexts["recipe_log_error"]
        for _ in 0..<5 where !error.exists { app.swipeUp() }
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(log.isEnabled)
        XCTAssertTrue(app.navigationBars["Log recipe"].exists)
        XCTAssertTrue(log.label.contains("Retry logging"))
        log.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(log.isEnabled)
    }

    @MainActor
    func testMealDraftSurvivesRelaunchAndLogsAsOneAction() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let modeLoaded = app.buttons["food_search_mode"].waitForExistence(timeout: 10)
        if !modeLoaded {
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.lifetime = .keepAlways
            add(screen)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(modeLoaded)
        waitForStableFrame(app.buttons["food_search_mode"])
        app.buttons["food_search_mode"].tap()
        XCTAssertTrue(app.buttons["food_search_mode"].label.contains("Quick add"))
        app.buttons["food_search_meal_menu"].tap()
        let breakfast = app.buttons["Breakfast"]
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        breakfast.tap()
        let first = app.buttons["repeat_food_add_0"]
        let second = app.buttons["repeat_food_add_1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        second.tap()
        let review = app.buttons["food_search_review_meal"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        XCTAssertTrue(app.staticTexts["meal_draft_total"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["meal_draft_total"].label.hasPrefix("2 foods"))
        let stepper = app.steppers["meal_draft_serving_0"]
        stepper.buttons["meal_draft_serving_0-Increment"].tap()
        let total = app.staticTexts["meal_draft_total"].label
        let reviewEvidence = XCTAttachment(screenshot: app.screenshot())
        reviewEvidence.name = "Meal draft - portions and destination"
        reviewEvidence.lifetime = .keepAlways
        add(reviewEvidence)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "food-search"]
        app.launch()
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["food_search_meal_menu"].label.contains("Breakfast"))
        XCTAssertTrue(review.label.contains("Breakfast"))
        waitForStableFrame(review)
        review.tap()
        XCTAssertTrue(app.staticTexts["meal_draft_total"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meal_draft_total"].label, total)
        app.buttons["meal_draft_log"].tap()
        XCTAssertTrue(app.buttons["food_search_undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(review.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Meal draft - accepted with one undo"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMealPlanFailedSaveDoesNotClaimTheMealWasLogged() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan",
                               "-ui-testing-reset-editor-drafts", "-ui-testing-food-save-failure"]
        app.launch()
        let log = app.buttons["meal_plan_log_planned-0-0"]
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        let previouslyLogged = app.buttons.matching(NSPredicate(format: "label == 'Logged'")).count
        for _ in 0..<6 where !log.isHittable { app.swipeUp() }
        log.tap()
        let status = app.staticTexts["planned_log_error"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Could not log"))
        XCTAssertTrue(app.buttons["planned_log_action"].label.contains("Retry"))
        app.buttons["Close"].tap()
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(log.label, "Log my portion")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Logged'")).count, previouslyLogged)
        log.tap()
        XCTAssertTrue(app.buttons["planned_log_action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["planned_log_action"].label.contains("Retry"))
    }

    @MainActor
    private func waitForStableFrame(_ element: XCUIElement) {
        var previous = CGRect.null
        var stableSince = ProcessInfo.processInfo.systemUptime
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            let now = ProcessInfo.processInfo.systemUptime
            guard frame == previous else {
                previous = frame
                stableSince = now
                return false
            }
            return now - stableSince >= 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
    }
}
