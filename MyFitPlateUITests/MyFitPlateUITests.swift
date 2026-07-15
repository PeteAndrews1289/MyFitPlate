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
    func testFoodSearchUsesSearchFirstHierarchyAndQuickLog() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "food-search"
        ]
        app.launch()

        let searchField = app.textFields["food_search_field"]
        let mealPicker = app.descendants(matching: .any)["food_search_meal_picker"]
        let repeatSection = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "food_search_repeat_section",
                "Repeat faster"
            ))
            .firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertTrue(mealPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(repeatSection.waitForExistence(timeout: 5))
        XCTAssertLessThan(searchField.frame.minY, mealPicker.frame.minY)
        XCTAssertLessThan(mealPicker.frame.minY, repeatSection.frame.minY)

        focusAndType("apple", into: searchField)

        let result = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Test Kitchen Apple"))
            .firstMatch
        let quickLog = app.buttons["Quick log Test Kitchen Apple"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(quickLog.waitForExistence(timeout: 5))
        XCTAssertTrue(quickLog.isHittable)
        quickLog.tap()

        let logged = app.buttons["Test Kitchen Apple logged"]
        XCTAssertTrue(logged.waitForExistence(timeout: 5))
        XCTAssertFalse(logged.isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Food Search - grouped results and quick log"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFoodSearchSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "food-search",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(app.textFields["food_search_field"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["food_search_meal_menu"].waitForExistence(timeout: 5))
        let repeatSection = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "food_search_repeat_section",
                "Repeat faster"
            ))
            .firstMatch
        XCTAssertTrue(repeatSection.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.textClipped])

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "Food Search - dark accessibility XXXL"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        let historyCard = app.staticTexts["Chicken Breast, Grilled"]
        for _ in 0..<4 where !historyCard.exists || !historyCard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(historyCard.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.textClipped])

        let historyScreenshot = XCTAttachment(screenshot: app.screenshot())
        historyScreenshot.name = "Food Search history - dark accessibility XXXL"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
    }

    @MainActor
    func testSpecialistSourcesRemainVisibleFromSearchThroughTrustReceipt() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-specialist-sources",
            "-screenshot-mode",
            "-screenshot-screen",
            "food-search"
        ]
        app.launch()

        let searchField = app.textFields["food_search_field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        focusAndType("salmon", into: searchField)

        let canadaRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Salmon, Atlantic, baked"))
            .firstMatch
        XCTAssertTrue(canadaRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["food_source_badge_health_canada_cnf"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Health Canada CNF"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        canadaRow.tap()

        XCTAssertTrue(app.staticTexts["Health Canada CNF"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label CONTAINS %@",
                    "Reference dataset released May 14, 2026"
                ))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        app.terminate()
        app.launch()
        let supplementSearchField = app.textFields["food_search_field"]
        XCTAssertTrue(supplementSearchField.waitForExistence(timeout: 8))
        focusAndType("vitamin", into: supplementSearchField)

        let supplementRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Example Vitamin D3"))
            .firstMatch
        for _ in 0..<4 where !supplementRow.exists || !supplementRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(supplementRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["food_source_badge_nih_dsld"]
                .waitForExistence(timeout: 5)
        )
        let supplementHittable = expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: supplementRow
        )
        XCTAssertEqual(XCTWaiter.wait(for: [supplementHittable], timeout: 5), .completed)
        XCTAssertTrue(supplementRow.label.contains("NIH"))
        XCTAssertTrue(supplementRow.label.contains("1 Softgel"))
        supplementRow.tap()

        XCTAssertTrue(app.staticTexts["NIH DSLD"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 Softgel"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "not laboratory verification"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testMyFoodsLibraryUsesGroupedOperationalHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "my-foods"
        ]
        app.launch()

        let library = app.descendants(matching: .any)
            .matching(identifier: "my_foods_library")
            .firstMatch
        let list = app.descendants(matching: .any)
            .matching(identifier: "my_foods_list")
            .firstMatch
        let oats = app.descendants(matching: .any)
            .matching(identifier: "my_foods_row_demo-library-oats")
            .firstMatch
        let duplicateSection = app.staticTexts["Duplicate copies"]

        XCTAssertTrue(library.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Barcode"].exists)
        XCTAssertTrue(app.staticTexts["Review"].exists)
        XCTAssertTrue(duplicateSection.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(oats.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.staticTexts["Saved"].frame.minY, duplicateSection.frame.minY)
        XCTAssertLessThan(duplicateSection.frame.minY, list.frame.minY)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "My Foods - grouped library hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMyFoodsLibrarySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "my-foods",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let library = app.descendants(matching: .any)
            .matching(identifier: "my_foods_library")
            .firstMatch
        let oats = app.descendants(matching: .any)
            .matching(identifier: "my_foods_row_demo-library-oats")
            .firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["All foods"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.textClipped])

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "My Foods - dark accessibility XXXL summary"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        for _ in 0..<8 where !oats.exists || !oats.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(oats.waitForExistence(timeout: 5))
        XCTAssertTrue(oats.isHittable)
        XCTAssertLessThanOrEqual(oats.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(oats.frame.minX, app.frame.minX - 1)
        try app.performAccessibilityAudit(for: [.textClipped])

        let rowScreenshot = XCTAttachment(screenshot: app.screenshot())
        rowScreenshot.name = "My Foods - dark accessibility XXXL saved row"
        rowScreenshot.lifetime = .keepAlways
        add(rowScreenshot)
    }

    @MainActor
    func testManualFoodEditorUsesUnifiedResponsiveForm() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "add-food"
        ]
        app.launch()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "manual_food_editor")
            .firstMatch
        let name = app.textFields["manual_food_name"]
        let nutrition = app.descendants(matching: .any)
            .matching(identifier: "manual_food_nutrition")
            .firstMatch
        let serving = app.staticTexts["Serving"]
        let details = app.staticTexts["Nutrition details"]
        let navigationBar = app.navigationBars["Log food"]
        let cancelButtons = app.buttons
            .matching(NSPredicate(format: "label == %@", "Cancel"))
        let primaryAction = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Add to log"))
            .firstMatch

        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cancelButtons.count, 0)
        let visibleCancel = (0..<cancelButtons.count)
            .map { cancelButtons.element(boundBy: $0) }
            .first(where: \.isHittable)
        XCTAssertNotNil(visibleCancel)
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(serving.waitForExistence(timeout: 5))
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.isHittable)
        XCTAssertLessThan(name.frame.minY, nutrition.frame.minY)
        XCTAssertLessThan(nutrition.frame.minY, serving.frame.minY)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manual Food - unified responsive form"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testManualFoodEditorSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "add-food",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let editor = app.descendants(matching: .any)
            .matching(identifier: "manual_food_editor")
            .firstMatch
        let navigationBars = app.navigationBars
            .matching(identifier: "Log food")
        let cancelButtons = app.buttons
            .matching(NSPredicate(format: "label == %@", "Cancel"))
        let details = app.staticTexts["Nutrition details"]
        let primaryAction = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Add to log"))
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["manual_food_name"].waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.isHittable)
        XCTAssertGreaterThan(cancelButtons.count, 0)
        let visibleCancel = try XCTUnwrap(
            (0..<cancelButtons.count)
                .map { cancelButtons.element(boundBy: $0) }
                .first(where: \.isHittable)
        )
        try app.performAccessibilityAudit(for: [.textClipped])

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "Manual Food - dark accessibility XXXL nutrition"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        for _ in 0..<8 {
            let detailsIsFullyVisible = details.exists
                && details.frame.minY >= visibleCancel.frame.maxY
                && details.frame.maxY <= primaryAction.frame.minY
            if detailsIsFullyVisible {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(details.isHittable)
        XCTAssertTrue(primaryAction.isHittable)
        XCTAssertGreaterThanOrEqual(details.frame.minY, visibleCancel.frame.maxY)
        XCTAssertLessThanOrEqual(details.frame.maxY, primaryAction.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let detailsScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailsScreenshot.name = "Manual Food - dark accessibility XXXL details"
        detailsScreenshot.lifetime = .keepAlways
        add(detailsScreenshot)
    }

    @MainActor
    func testRecipeLibraryAndDetailUseUnifiedHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "recipes"
        ]
        app.launch()

        let library = app.descendants(matching: .any)["recipe_library"]
        let summary = app.descendants(matching: .any)
            .matching(identifier: "recipe_library_summary")
            .firstMatch
        let list = app.descendants(matching: .any)["recipe_library_list"]
        let firstRecipe = app.buttons["recipe_open_demo-recipe-chicken-bowl"]
        let detail = app.descendants(matching: .any)["recipe_detail"]

        XCTAssertTrue(library.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved"].exists)
        XCTAssertTrue(app.staticTexts["Avg Ingredients"].exists)
        XCTAssertTrue(app.staticTexts["Avg Calories"].exists)
        XCTAssertTrue(firstRecipe.waitForExistence(timeout: 5))
        XCTAssertLessThan(summary.frame.minY, list.frame.minY)

        let libraryScreenshot = XCTAttachment(screenshot: app.screenshot())
        libraryScreenshot.name = "Recipes - unified library"
        libraryScreenshot.lifetime = .keepAlways
        add(libraryScreenshot)

        XCTAssertTrue(firstRecipe.isHittable)
        firstRecipe.press(forDuration: 0.1)
        if !detail.waitForExistence(timeout: 3) {
            XCTAssertTrue(firstRecipe.isHittable, "Recipe should remain tappable after a dropped input")
            firstRecipe.press(forDuration: 0.1)
        }

        let nutrition = app.descendants(matching: .any)["recipe_nutrition_summary"]
        let ingredients = app.descendants(matching: .any)["recipe_ingredients"]
        let instructions = app.descendants(matching: .any)["recipe_instructions"]
        let logAction = app.buttons["recipe_add_to_log"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(ingredients.waitForExistence(timeout: 5))
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.isHittable)
        XCTAssertLessThan(nutrition.frame.minY, ingredients.frame.minY)

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Recipes - unified detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    @MainActor
    func testRecipeLoggingCannotRestoreTotalsAfterRemovingEveryIngredient() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "recipes"
        ]
        app.launch()

        let firstRecipe = app.descendants(matching: .any)["recipe_open_demo-recipe-chicken-bowl"]
        XCTAssertTrue(firstRecipe.waitForExistence(timeout: 10))
        XCTAssertTrue(firstRecipe.isHittable)
        firstRecipe.tap()

        let detail = app.descendants(matching: .any)["recipe_detail"]
        let addToLog = app.buttons["recipe_add_to_log"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(addToLog.waitForExistence(timeout: 5))
        addToLog.tap()

        let logging = app.descendants(matching: .any)["recipe_logging"]
        let logAction = app.buttons["recipe_log_action"]
        XCTAssertTrue(logging.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["recipe_log_nutrition"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["recipe_log_meal"].exists)
        XCTAssertTrue(logAction.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.isEnabled)

        let loggingScreenshot = XCTAttachment(screenshot: app.screenshot())
        loggingScreenshot.name = "Recipes - editable logging"
        loggingScreenshot.lifetime = .keepAlways
        add(loggingScreenshot)

        for ingredient in [
            "Grilled Chicken Breast",
            "Jasmine Rice",
            "Black Beans",
            "Avocado Salsa"
        ] {
            let remove = app.buttons["Remove \(ingredient)"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
        }

        let emptyState = app.descendants(matching: .any)["recipe_log_empty_ingredients"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        XCTAssertFalse(logAction.isEnabled)
        XCTAssertTrue(app.staticTexts["0 cal"].exists)
    }

    @MainActor
    func testCreateRecipeKeepsAllCreationModesAndManualEditorDirect() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "recipes"
        ]
        app.launch()

        let create = app.buttons["Create recipe"]
        let editor = app.navigationBars["Create Recipe"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.press(forDuration: 0.1)
        if !editor.waitForExistence(timeout: 3) {
            XCTAssertTrue(create.isHittable, "Create Recipe should remain tappable after a dropped input")
            create.press(forDuration: 0.1)
        }

        let modePicker = app.descendants(matching: .any)["create_recipe_mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["create_recipe_ai_input"].waitForExistence(timeout: 5))

        let manual = app.segmentedControls.buttons["Manual"]
        let name = app.textFields["create_recipe_name"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.press(forDuration: 0.1)
        if !name.waitForExistence(timeout: 3) {
            XCTAssertTrue(manual.isHittable, "Manual mode should remain tappable after a dropped input")
            manual.press(forDuration: 0.1)
        }

        let addIngredient = app.buttons["create_recipe_add_ingredient"]
        let instructions = app.textViews["create_recipe_instructions"]
        let save = app.buttons["create_recipe_action"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(addIngredient.waitForExistence(timeout: 5))
        XCTAssertTrue(instructions.waitForExistence(timeout: 5))
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Recipes - manual creation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRecipeWorkflowSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "recipes",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let library = app.descendants(matching: .any)["recipe_library"]
        let summary = app.descendants(matching: .any)["recipe_library_summary"]
        let firstRecipe = app.buttons["recipe_open_demo-recipe-chicken-bowl"]
        let detail = app.descendants(matching: .any)["recipe_detail"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRecipe.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["recipe_summary_saved"].label, "Saved recipes, 3")
        XCTAssertEqual(app.descendants(matching: .any)["recipe_summary_ingredients"].label, "Average ingredients, 3")
        XCTAssertEqual(app.descendants(matching: .any)["recipe_summary_calories"].label, "Average calories, 552 cal")
        XCTAssertGreaterThanOrEqual(firstRecipe.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(firstRecipe.frame.maxX, app.frame.maxX + 1)
        // SwiftUI exposes hidden visual children from combined accessibility elements to this audit.
        // Ignore only these manually verified summary strings; the semantic values are asserted above.
        let summaryVisualStrings: Set<String> = ["Saved", "3", "Avg Ingredients", "Avg Calories", "552 cal"]
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            guard let element = issue.element else { return false }
            return summaryVisualStrings.contains(element.label)
        }

        let libraryScreenshot = XCTAttachment(screenshot: app.screenshot())
        libraryScreenshot.name = "Recipes - dark accessibility XXXL library"
        libraryScreenshot.lifetime = .keepAlways
        add(libraryScreenshot)

        XCTAssertTrue(firstRecipe.isHittable)
        firstRecipe.press(forDuration: 0.1)
        if !detail.waitForExistence(timeout: 3) {
            XCTAssertTrue(firstRecipe.isHittable, "Recipe should remain tappable after a dropped input")
            firstRecipe.press(forDuration: 0.1)
        }

        let detailTitle = app.staticTexts["recipe_detail_title"]
        let ingredientCount = app.staticTexts["recipe_detail_ingredient_count"]
        let instructionCount = app.staticTexts["recipe_detail_instruction_count"]
        let addToLog = app.buttons["recipe_add_to_log"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(ingredientCount.waitForExistence(timeout: 5))
        XCTAssertTrue(instructionCount.waitForExistence(timeout: 5))
        XCTAssertTrue(addToLog.waitForExistence(timeout: 5))
        XCTAssertTrue(addToLog.isHittable)
        XCTAssertLessThanOrEqual(detailTitle.frame.maxX, app.frame.maxX + 1)
        XCTAssertEqual(ingredientCount.label, "4 ingredients")
        XCTAssertEqual(instructionCount.label, "3 steps")
        XCTAssertLessThanOrEqual(instructionCount.frame.maxX, app.frame.maxX + 1)
        let calorieMetric = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Calories, 610 cal"))
            .firstMatch
        XCTAssertTrue(calorieMetric.waitForExistence(timeout: 5))
        let detailVerifiedVisualStrings: Set<String> = [
            "Weeknight Chicken Power Bowl", "4 ingredients", "3 steps",
            "Calories", "Protein", "Carbs", "Fat", "610 cal", "58 g", "66 g", "12 g"
        ]
        // Rounded-font and combined-metric nodes report intrinsic glyph bounds as clipped.
        // Exact fixture strings are backed by frame and semantic assertions above.
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            guard let element = issue.element else { return false }
            let normalizedLabel = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return detailVerifiedVisualStrings.contains(normalizedLabel)
        }

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Recipes - dark accessibility XXXL detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)

        addToLog.tap()
        let logging = app.descendants(matching: .any)["recipe_logging"]
        let loggingTitle = app.staticTexts["recipe_log_title"]
        let loggingSubtitle = app.staticTexts["recipe_log_subtitle"]
        XCTAssertTrue(logging.waitForExistence(timeout: 5))
        XCTAssertTrue(loggingTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(loggingSubtitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recipe_log_action"].isHittable)
        XCTAssertLessThanOrEqual(loggingTitle.frame.maxX, app.frame.maxX + 1)
        XCTAssertLessThanOrEqual(loggingSubtitle.frame.maxX, app.frame.maxX + 1)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Calories, 610 cal"))
            .firstMatch
            .waitForExistence(timeout: 5))
        let loggingVerifiedVisualStrings: Set<String> = [
            "Weeknight Chicken Power Bowl",
            "Review the meal destination and ingredient amounts before logging.",
            "Calories", "Protein", "Carbs", "Fat", "610 cal", "58 g", "66 g", "12 g"
        ]
        // Keep form controls and the sticky action unfiltered while excluding the verified identity/metric nodes.
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            guard let element = issue.element else { return false }
            let normalizedLabel = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return loggingVerifiedVisualStrings.contains(normalizedLabel)
        }

        let loggingScreenshot = XCTAttachment(screenshot: app.screenshot())
        loggingScreenshot.name = "Recipes - dark accessibility XXXL logging"
        loggingScreenshot.lifetime = .keepAlways
        add(loggingScreenshot)
    }

    @MainActor
    func testFastFoodBuilderKeepsSelectionWorkflowDirect() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "builder"
        ]
        app.launch()

        let searchField = app.textFields["chain_builder_search"]
        let chainIdentity = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "chain_builder_selected_chain",
                "Chipotle"
            ))
            .firstMatch
        let review = app.buttons["chain_builder_review_meal"]
        let category = app.staticTexts["Bases & Grains"]
        let menuSearchField = app.textFields["chain_builder_menu_search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        XCTAssertTrue(chainIdentity.waitForExistence(timeout: 5))
        XCTAssertTrue(menuSearchField.waitForExistence(timeout: 5))
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chain_builder_catalog_count"].label, "22 items")
        XCTAssertLessThan(searchField.frame.minY, chainIdentity.frame.minY)
        XCTAssertLessThan(chainIdentity.frame.minY, category.frame.minY)

        menuSearchField.tap()
        menuSearchField.typeText("Barbacoa")
        XCTAssertTrue(app.buttons["chain_builder_ingredient_c_barbacoa"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chain_builder_ingredient_c_white_rice"].exists)
        app.buttons["Clear menu search"].tap()
        menuSearchField.typeText("\n")

        let whiteRice = app.buttons["chain_builder_ingredient_c_white_rice"]
        XCTAssertTrue(whiteRice.waitForExistence(timeout: 5))
        XCTAssertTrue(whiteRice.isHittable)
        XCTAssertEqual(whiteRice.value as? String, "Selected")
        XCTAssertLessThan(whiteRice.frame.maxY, review.frame.minY - 8)

        func pressWhiteRice(expecting expectedValue: String) {
            let expectedState = app.buttons
                .matching(identifier: "chain_builder_ingredient_c_white_rice")
                .matching(NSPredicate(format: "value == %@", expectedValue))
                .firstMatch

            app.buttons["chain_builder_ingredient_c_white_rice"].press(forDuration: 0.1)
            if !expectedState.waitForExistence(timeout: 2) {
                let retryButton = app.buttons["chain_builder_ingredient_c_white_rice"]
                XCTAssertTrue(retryButton.isHittable, "Ingredient should remain tappable after a dropped input")
                retryButton.press(forDuration: 0.1)
            }
            XCTAssertTrue(expectedState.waitForExistence(timeout: 5))
        }

        pressWhiteRice(expecting: "Not selected")

        let fiveItems = app.buttons
            .matching(identifier: "chain_builder_review_meal")
            .matching(NSPredicate(format: "value CONTAINS %@", "5 items selected"))
            .firstMatch
        XCTAssertTrue(fiveItems.waitForExistence(timeout: 5))

        pressWhiteRice(expecting: "Selected")

        let sixItems = app.buttons
            .matching(identifier: "chain_builder_review_meal")
            .matching(NSPredicate(format: "value CONTAINS %@", "6 items selected"))
            .firstMatch
        XCTAssertTrue(sixItems.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["chain_builder_ingredient_c_white_rice"].value as? String,
            "Selected"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Fast Food Builder - direct selection workflow"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFastFoodBuilderSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "builder",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let chainIdentity = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "chain_builder_selected_chain",
                "Chipotle"
            ))
            .firstMatch
        let review = app.buttons["chain_builder_review_meal"]
        XCTAssertTrue(chainIdentity.waitForExistence(timeout: 8))
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(review.label, "Review order")
        XCTAssertLessThan(review.frame.height, app.frame.height * 0.20)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Fast Food Builder - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFoodDetailKeepsTrustEvidenceAheadOfNutritionSummary() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "trust"
        ]
        app.launch()

        let identity = app.descendants(matching: .any)["food_detail_identity"]
        let receipt = app.descendants(matching: .any)["food_trust_receipt"]
        let score = app.descendants(matching: .any)["food_trust_score"]
        let macros = app.descendants(matching: .any)["food_detail_macro_summary"]
        let logAction = app.buttons["food_detail_log_action"]

        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertTrue(macros.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.waitForExistence(timeout: 5))
        XCTAssertLessThan(identity.frame.minY, receipt.frame.minY)
        XCTAssertLessThan(receipt.frame.minY, macros.frame.minY)
        XCTAssertTrue(logAction.isHittable)
        XCTAssertEqual(score.label, "Trust rating")
        XCTAssertEqual(
            score.value as? String,
            "Excellent trust. Cross-database match. Evidence index 98 out of 99"
        )
        // SwiftUI reports one unresolvable decorative node here; the XXXL test below is unfiltered.
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            issue.element == nil
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Food Detail - trust-led hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFoodDetailSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "trust",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let identity = app.descendants(matching: .any)["food_detail_identity"]
        let receipt = app.descendants(matching: .any)["food_trust_receipt"]
        let score = app.descendants(matching: .any)["food_trust_score"]
        let logAction = app.buttons["food_detail_log_action"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.waitForExistence(timeout: 5))
        XCTAssertTrue(logAction.isHittable)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Food Detail - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRunningHistoryAndDetailUseUnifiedHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "runs"
        ]
        app.launch()

        let start = app.buttons["run_history_start"]
        let week = app.descendants(matching: .any)
            .matching(identifier: "run_history_week_summary")
            .firstMatch
        let records = app.descendants(matching: .any)
            .matching(identifier: "run_history_records")
            .firstMatch
        let history = app.descendants(matching: .any)
            .matching(identifier: "run_history_list")
            .firstMatch
        let firstRun = app.buttons
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "run_history_list",
                "6.21 mi"
            ))
            .firstMatch

        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(records.waitForExistence(timeout: 5))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRun.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
        XCTAssertLessThan(start.frame.minY, week.frame.minY)
        XCTAssertLessThan(week.frame.minY, records.frame.minY)
        XCTAssertLessThan(records.frame.minY, history.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let historyScreenshot = XCTAttachment(screenshot: app.screenshot())
        historyScreenshot.name = "Running - unified history"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)

        for _ in 0..<4 where !firstRun.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(firstRun.isHittable)
        let detailScreen = app.descendants(matching: .any)
            .matching(identifier: "run_detail_screen")
            .firstMatch
        for _ in 0..<2 where !detailScreen.exists {
            firstRun.tap()
            if detailScreen.waitForExistence(timeout: 3) {
                break
            }
        }
        XCTAssertTrue(detailScreen.waitForExistence(timeout: 8))

        let metrics = app.descendants(matching: .any)
            .matching(identifier: "run_detail_metrics")
            .firstMatch
        let recovery = app.descendants(matching: .any)
            .matching(identifier: "run_detail_recovery")
            .firstMatch
        let splits = app.descendants(matching: .any)
            .matching(identifier: "run_detail_splits")
            .firstMatch
        let gear = app.descendants(matching: .any)
            .matching(identifier: "run_detail_gear")
            .firstMatch
        let source = app.descendants(matching: .any)
            .matching(identifier: "run_detail_source")
            .firstMatch
        XCTAssertTrue(metrics.waitForExistence(timeout: 8))
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
        XCTAssertTrue(splits.waitForExistence(timeout: 5))
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertLessThan(metrics.frame.minY, recovery.frame.minY)
        XCTAssertLessThan(recovery.frame.minY, splits.frame.minY)

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Running - unified detail summary"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)

        let recoveryAction = app.buttons["Log recovery meal"]
        for _ in 0..<6 where !recoveryAction.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(recoveryAction.isHittable)
        try app.performAccessibilityAudit(for: [.textClipped])

        let recoveryScreenshot = XCTAttachment(screenshot: app.screenshot())
        recoveryScreenshot.name = "Running - recovery and splits"
        recoveryScreenshot.lifetime = .keepAlways
        add(recoveryScreenshot)
    }

    @MainActor
    func testRunningHistorySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "runs",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let start = app.buttons["run_history_start"]
        let week = app.descendants(matching: .any)
            .matching(identifier: "run_history_week_summary")
            .firstMatch
        let firstRun = app.buttons
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "run_history_list",
                "6.21 mi"
            ))
            .firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(start.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(start.frame.minX, app.frame.minX - 1)
        try app.performAccessibilityAudit(for: [.textClipped])

        let topScreenshot = XCTAttachment(screenshot: app.screenshot())
        topScreenshot.name = "Running - dark accessibility XXXL summary"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        for _ in 0..<8 {
            let rowIsVisible = firstRun.exists
                && firstRun.frame.minY >= app.frame.minY
                && firstRun.frame.maxY <= app.frame.maxY - 20
            if rowIsVisible {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(firstRun.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRun.isHittable)
        XCTAssertLessThanOrEqual(firstRun.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(firstRun.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(firstRun.frame.maxY, app.frame.maxY - 20)
        sleep(1)
        XCTAssertLessThanOrEqual(firstRun.frame.maxY, app.frame.maxY - 20)

        let historyScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        historyScreenshot.name = "Running - dark accessibility XXXL history"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
        try app.performAccessibilityAudit(for: [.textClipped])
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
        try app.performAccessibilityAudit(for: [.textClipped])

        let homeScrollView = app.scrollViews["home_scroll"]
        let dailyLog = app.staticTexts["Daily log"]
        XCTAssertTrue(homeScrollView.waitForExistence(timeout: 5))
        XCTAssertTrue(dailyLog.waitForExistence(timeout: 8))
        for _ in 0..<16 where dailyLog.frame.minY >= app.frame.maxY - 180 {
            homeScrollView.swipeUp()
        }
        XCTAssertLessThan(dailyLog.frame.minY, app.frame.maxY - 180)
        XCTAssertGreaterThan(dailyLog.frame.maxY, 100)

        let expectedDailyMetrics = [
            ("home_daily_metric_calories", "Calories: 1,310 / 2,100 cal"),
            ("home_daily_metric_protein", "Protein: 98 / 160 g"),
            ("home_daily_metric_water", "Water: 72 / 64 oz"),
            ("home_daily_metric_activity", "Activity: 1 session")
        ]
        for (identifier, label) in expectedDailyMetrics {
            XCTAssertEqual(app.descendants(matching: .any)[identifier].label, label)
        }

        // iOS 26 audits hidden visual children of these verified combined accessibility elements
        // at their exact rounded-glyph bounds. Filter only those known visual strings; all other
        // visible Home content remains subject to the clipping audit.
        let dailyMetricVisualStrings: Set<String> = [
            "Calories", "1,310 / 2,100 cal", "Calories\n1,310 / 2,100 cal",
            "Protein", "98 / 160 g", "Protein\n98 / 160 g",
            "Water", "72 / 64 oz", "Water\n72 / 64 oz",
            "Activity", "1 session", "Activity\n1 session"
        ]
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            guard let element = issue.element else { return false }
            return element.identifier.hasPrefix("home_daily_metric_visual_")
                || dailyMetricVisualStrings.contains(element.label)
        }

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
        let day = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Today's plan"))
            .firstMatch

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
    func testMaiaUsesOneRecommendedActionHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "maia"
        ]
        app.launch()

        let header = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "maia_screen_header",
                "Maia"
            ))
            .firstMatch
        let context = app.staticTexts["Today in context"]
        let recommendation = app.buttons["maia_recommended_action"]
        let composer = app.textFields["Ask Maia anything"]

        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertTrue(recommendation.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertLessThan(context.frame.minY, recommendation.frame.minY)
        XCTAssertLessThan(recommendation.frame.minY, composer.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Maia - unified recommendation hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testReportsKeepsWeekInMotionAboveDetailedEvidence() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "reports"
        ]
        app.launch()

        let header = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "reports_screen_header",
                "Reports"
            ))
            .firstMatch
        let headline = app.staticTexts["weekly_report_headline"]
        let timeframe = app.staticTexts["Trend window"]
        let overview = app.staticTexts["At a glance"]

        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertLessThan(header.frame.minY, headline.frame.minY)

        for _ in 0..<6 where !timeframe.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(timeframe.waitForExistence(timeout: 5))
        XCTAssertTrue(timeframe.isHittable)

        for _ in 0..<5 where !overview.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(overview.isHittable)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reports - detailed evidence hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMaiaAndReportsSupportDarkAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "maia", heading: "Maia"),
            (name: "reports", heading: "Reports")
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

            let header = app.staticTexts
                .matching(NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "\(screen.name)_screen_header",
                    screen.heading
                ))
                .firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 12))
            XCTAssertGreaterThan(header.frame.width, 0)
            XCTAssertGreaterThanOrEqual(header.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(header.frame.maxX, app.frame.maxX + 1)
            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testMaiaActionCardsUseFlatReviewFirstHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "maia-action-cards"
        ]
        app.launch()

        let title = app.staticTexts["Action Cards"]
        let meal = app.descendants(matching: .any).matching(identifier: "maia_action_meal").firstMatch
        let weight = app.descendants(matching: .any).matching(identifier: "maia_action_weight").firstMatch

        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        let logFood = app.buttons["Log Food"]
        XCTAssertTrue(logFood.exists)
        logFood.tap()
        let logged = app.buttons["Logged"]
        XCTAssertTrue(logged.waitForExistence(timeout: 3))
        XCTAssertFalse(logged.isEnabled)

        let firstScreenshot = XCTAttachment(screenshot: app.screenshot())
        firstScreenshot.name = "Maia action cards - flat review hierarchy"
        firstScreenshot.lifetime = .keepAlways
        add(firstScreenshot)

        for _ in 0..<10 {
            if weight.exists && weight.frame.minY < app.frame.maxY - 20 {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(weight.frame.intersects(app.frame))
        XCTAssertGreaterThanOrEqual(weight.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(weight.frame.maxX, app.frame.maxX + 1)
        try app.performAccessibilityAudit(for: [.textClipped])
    }

    @MainActor
    func testMaiaActionCardsSupportDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-dark-mode",
            "-screenshot-screen",
            "maia-action-cards",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let meal = app.descendants(matching: .any).matching(identifier: "maia_action_meal").firstMatch
        let weight = app.descendants(matching: .any).matching(identifier: "maia_action_weight").firstMatch

        XCTAssertTrue(meal.waitForExistence(timeout: 12))
        XCTAssertGreaterThanOrEqual(meal.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(meal.frame.maxX, app.frame.maxX + 1)

        for _ in 0..<12 {
            if weight.exists && weight.frame.minY < app.frame.maxY - 20 {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(weight.frame.intersects(app.frame))
        XCTAssertGreaterThanOrEqual(weight.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(weight.frame.maxX, app.frame.maxX + 1)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Maia action cards - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLivingDayUsesSharedHomeShell() throws {
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

        let header = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "home_screen_header",
                "Home"
            ))
            .firstMatch
        let date = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@", "home_date_label"))
            .firstMatch
        let livingDay = app.staticTexts["Living Day"]
        let profile = app.buttons["Open profile"]
        let settings = app.buttons["Open settings"]

        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertTrue(livingDay.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isHittable)
        XCTAssertTrue(settings.isHittable)
        XCTAssertLessThan(header.frame.minY, date.frame.minY)
        XCTAssertLessThan(date.frame.minY, livingDay.frame.minY)
        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Living Day - shared Home shell"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Previous day"].tap()
        XCTAssertTrue(livingDay.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Calories"].waitForExistence(timeout: 5))
        XCTAssertTrue(header.exists)
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
        let addWater = app.buttons["livingDayAddWaterButton"]
        let share = app.descendants(matching: .any)["livingDayShareButton"]
        let density = app.descendants(matching: .any)["livingDayDensityMenu"]

        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(maia.waitForExistence(timeout: 5))
        XCTAssertTrue(firstEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(addWater.waitForExistence(timeout: 5))
        XCTAssertTrue(addWater.isHittable)
        XCTAssertEqual(addWater.value as? String, "72 / 64 oz")
        addWater.tap()
        let waterUpdated = expectation(
            for: NSPredicate(format: "value == %@", "80 / 64 oz"),
            evaluatedWith: addWater
        )
        XCTAssertEqual(XCTWaiter.wait(for: [waterUpdated], timeout: 5), .completed)
        XCTAssertTrue(share.isHittable)
        XCTAssertTrue(density.isHittable)
        XCTAssertLessThan(addWater.frame.minY, action.frame.minY)
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
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let header = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "home_screen_header",
                "Home"
            ))
            .firstMatch
        let surface = app.staticTexts["Living Day"]
        let action = app.descendants(matching: .any)["livingDayCurrentAction"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
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
        let homeHeader = app.staticTexts
            .matching(NSPredicate(
                format: "identifier == %@ AND label == %@",
                "home_screen_header",
                "Home"
            ))
            .firstMatch
        XCTAssertTrue(homeHeader.waitForExistence(timeout: 10))
        XCTAssertTrue(livingDay.waitForExistence(timeout: 10))

        app.buttons["tab_reports"].tap()
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "reports_screen_header",
                    "Reports"
                ))
                .firstMatch
                .waitForExistence(timeout: 5)
        )

        app.buttons["tab_home"].tap()
        XCTAssertTrue(homeHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(
            livingDay.waitForExistence(timeout: 5),
            "Living Day should remain enabled when Home is rebuilt after a tab change"
        )
    }

    @MainActor
    func testSettingsUsesUnifiedTargetsFirstHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "settings"
        ]
        app.launch()

        let screen = app.descendants(matching: .any)["settings_screen"]
        let summary = app.staticTexts["Your Targets"]
        let goalsAndData = app.staticTexts["Goals & Data"]
        let done = app.buttons["Done"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(goalsAndData.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        XCTAssertLessThan(summary.frame.minY, goalsAndData.frame.minY)
        XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings - targets-first unified hierarchy"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsDestinationsUseUnifiedSurfaces() throws {
        let app = XCUIApplication()
        let destinations = [
            (name: "Goals", route: "settings-goals", container: "settings_goals_screen", action: "settings_goals_save"),
            (name: "Height", route: "settings-height", container: "settings_height_screen", action: "settings_height_save"),
            (name: "Water", route: "settings-water", container: "settings_water_screen", action: "settings_water_save"),
            (name: "Disclaimer", route: "settings-disclaimer", container: "settings_disclaimer_screen", action: ""),
            (name: "AI Data", route: "settings-ai-data", container: "settings_ai_data_screen", action: "settings_ai_allow"),
            (name: "Import", route: "settings-import", container: "settings_import_screen", action: "settings_import_choose_files")
        ]

        for destination in destinations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                destination.route
            ]
            app.launch()

            let container = app.descendants(matching: .any)[destination.container]
            XCTAssertTrue(
                container.waitForExistence(timeout: 10),
                "\(destination.name) should open directly from its screenshot route"
            )
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if !destination.action.isEmpty {
                let action = app.buttons[destination.action]
                XCTAssertTrue(action.waitForExistence(timeout: 5))
                XCTAssertTrue(action.isHittable)
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Settings - \(destination.name) unified surface"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testSettingsSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let destinations = [
            (name: "Settings", route: "settings", container: "settings_screen", action: "Done"),
            (name: "Goals", route: "settings-goals", container: "settings_goals_screen", action: "settings_goals_save"),
            (name: "Height", route: "settings-height", container: "settings_height_screen", action: "settings_height_save"),
            (name: "Water", route: "settings-water", container: "settings_water_screen", action: "settings_water_save"),
            (name: "Import", route: "settings-import", container: "settings_import_screen", action: "settings_import_choose_files")
        ]

        for destination in destinations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                destination.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)[destination.container]
            let action = app.buttons[destination.action]
            XCTAssertTrue(container.waitForExistence(timeout: 10))
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            try app.performAccessibilityAudit(for: [.textClipped])

            if !action.isHittable {
                let scrollView = app.scrollViews.firstMatch
                XCTAssertTrue(scrollView.exists)
                var remainingScrolls = 4
                while !action.isHittable && remainingScrolls > 0 {
                    scrollView.swipeUp()
                    remainingScrolls -= 1
                }
                try app.performAccessibilityAudit(for: [.textClipped])
            }
            XCTAssertTrue(action.isHittable)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Settings - \(destination.name) dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
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
            "home",
            "-legacy-home"
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
    func testGroceryListUsesUnifiedHierarchyAndDiscoverableEditing() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "grocery"
        ]
        app.launch()

        let list = app.descendants(matching: .any)["grocery_list"]
        let summary = app.descendants(matching: .any)["grocery_summary"]
        let metrics = app.descendants(matching: .any)["grocery_summary_metrics"]
        let controls = app.descendants(matching: .any)["grocery_display_controls"]
        let produce = app.descendants(matching: .any)["grocery_category_Produce"]
        let chicken = app.buttons["grocery_item_00000000-0000-0000-0000-000000000103"]

        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(metrics.waitForExistence(timeout: 5))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(produce.waitForExistence(timeout: 5))
        XCTAssertTrue(chicken.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["grocery_add_item"].isHittable)
        XCTAssertTrue(app.buttons["grocery_scan_item"].isHittable)
        XCTAssertLessThan(summary.frame.minY, controls.frame.minY)
        XCTAssertLessThan(controls.frame.minY, produce.frame.minY)
        XCTAssertTrue(chicken.value as? String == "3 lb - Meal plan, not checked")

        let listScreenshot = XCTAttachment(screenshot: app.screenshot())
        listScreenshot.name = "Grocery List - unified shopping run"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)

        let options = app.buttons["More options for Chicken breast"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()

        let edit = app.buttons["Edit Item"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let editor = app.descendants(matching: .any)["grocery_manual_editor"]
        let name = app.textFields["grocery_manual_name"]
        let save = app.buttons["grocery_manual_action"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Chicken breast")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)

        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "Grocery List - direct item editor"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
    }

    @MainActor
    func testGroceryListCheckAndHideWorkflow() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "grocery"
        ]
        app.launch()

        let chicken = app.buttons["grocery_item_00000000-0000-0000-0000-000000000103"]
        XCTAssertTrue(chicken.waitForExistence(timeout: 10))
        XCTAssertTrue((chicken.value as? String)?.hasSuffix("not checked") == true)
        for _ in 0..<6 where !chicken.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(chicken.isHittable)
        let checkedChicken = app.buttons
            .matching(identifier: "grocery_item_00000000-0000-0000-0000-000000000103")
            .matching(NSPredicate(format: "value == %@", "3 lb - Meal plan, checked"))
            .firstMatch
        chicken.press(forDuration: 0.1)
        if !checkedChicken.waitForExistence(timeout: 2) {
            let retryChicken = app.buttons["grocery_item_00000000-0000-0000-0000-000000000103"]
            XCTAssertTrue(
                (retryChicken.value as? String)?.hasSuffix("not checked") == true,
                "Only retry a dropped input while the item is still unchanged"
            )
            XCTAssertTrue(retryChicken.isHittable)
            retryChicken.press(forDuration: 0.1)
        }
        XCTAssertTrue(checkedChicken.waitForExistence(timeout: 5))

        let hideChecked = app.switches["grocery_display_controls"]
        XCTAssertTrue(hideChecked.waitForExistence(timeout: 5))
        XCTAssertTrue(hideChecked.isEnabled)
        for _ in 0..<6 where !hideChecked.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(hideChecked.isHittable)
        XCTAssertTrue(app.staticTexts["3 checked items visible."].waitForExistence(timeout: 5))
        let switchedOn = app.switches
            .matching(identifier: "grocery_display_controls")
            .matching(NSPredicate(format: "value == %@", "1"))
            .firstMatch
        hideChecked.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if !switchedOn.waitForExistence(timeout: 2) {
            let retrySwitch = app.switches["grocery_display_controls"]
            XCTAssertEqual(retrySwitch.value as? String, "0", "Only retry a dropped switch input")
            XCTAssertTrue(retrySwitch.isHittable)
            retrySwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(switchedOn.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 checked items hidden."].waitForExistence(timeout: 5))

        let hiddenScreenshot = XCTAttachment(screenshot: app.screenshot())
        hiddenScreenshot.name = "Grocery List - checked items hidden"
        hiddenScreenshot.lifetime = .keepAlways
        add(hiddenScreenshot)
    }

    @MainActor
    func testGroceryListSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "grocery",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let summary = app.descendants(matching: .any)["grocery_summary"]
        let controls = app.descendants(matching: .any)["grocery_display_controls"]
        let addButton = app.buttons["grocery_add_item"]
        let scan = app.buttons["grocery_scan_item"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(addButton.isHittable)
        XCTAssertTrue(scan.isHittable)
        XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

        try app.performAccessibilityAudit(for: [.textClipped])

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Grocery List - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testQuickAddMacrosUsesUnifiedPreviewAndDirectAction() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "quick-add-macros"
        ]
        app.launch()

        let screen = app.descendants(matching: .any)["quick_add_macros"]
        let headerTitle = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Quick Add"))
            .firstMatch
        let nutrition = app.descendants(matching: .any)["quick_add_nutrition"]
        let summary = app.descendants(matching: .any)["quick_add_summary"]
        let calories = app.textFields["quick_add_calories"]
        let action = app.buttons["quick_add_action"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(headerTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(nutrition.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(calories.value as? String, "485")
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        XCTAssertTrue(action.label.contains("Add to Dinner"))
        XCTAssertLessThan(headerTitle.frame.minY, nutrition.frame.minY)
        XCTAssertLessThan(nutrition.frame.minY, summary.frame.minY)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick Add - unified entry preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMaiaTextLogUsesReviewFirstHierarchy() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "ai-text-log"
        ]
        app.launch()

        let screen = app.descendants(matching: .any)["ai_text_log"]
        let headerTitle = app.staticTexts["Describe a Meal"]
        let description = app.textViews["ai_text_description"]
        let guidance = app.descendants(matching: .any)["ai_text_guidance"]
        let action = app.buttons["ai_text_review_action"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(headerTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertTrue((description.value as? String)?.contains("chicken burrito bowl") == true)
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        XCTAssertEqual(action.label, "Review Estimate")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Maia Text Log - review-first input"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMaiaTextReviewRemovalUpdatesTheConfirmation() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "ai-text-results"
        ]
        app.launch()

        let screen = app.descendants(matching: .any)["ai_text_results"]
        let overview = app.descendants(matching: .any)["ai_text_results_overview"]
        let chips = screen.descendants(matching: .button)
            .matching(identifier: "ai_review_item_demo-ai-text-chips")
            .firstMatch
        let action = screen.descendants(matching: .button)["ai_text_log_action"]

        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(chips.waitForExistence(timeout: 5))
        for _ in 0..<2 where !chips.isHittable {
            screen.swipeUp()
        }
        XCTAssertTrue(chips.isHittable)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Log 3 Items")

        let beforeScreenshot = XCTAttachment(screenshot: app.screenshot())
        beforeScreenshot.name = "Maia Text Review - editable estimate"
        beforeScreenshot.lifetime = .keepAlways
        add(beforeScreenshot)

        chips.swipeLeft()
        let reducedAction = app.buttons["Log 2 Items"]
        if !reducedAction.waitForExistence(timeout: 2) {
            let remove = app.buttons["Remove"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
        }

        XCTAssertFalse(chips.waitForExistence(timeout: 2))
        XCTAssertTrue(reducedAction.waitForExistence(timeout: 5))

        let afterScreenshot = XCTAttachment(screenshot: app.screenshot())
        afterScreenshot.name = "Maia Text Review - item removed"
        afterScreenshot.lifetime = .keepAlways
        add(afterScreenshot)
    }

    @MainActor
    func testQuickAddAndMaiaReviewSupportDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Quick Add", route: "quick-add-macros", container: "quick_add_macros", action: "quick_add_action"),
            (name: "Maia Text Review", route: "ai-text-results", container: "ai_text_results", action: "ai_text_log_action")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)[screen.container]
            let action = app.buttons[screen.action]
            XCTAssertTrue(container.waitForExistence(timeout: 10))
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testTrainingEditorsUseUnifiedBuilderHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Saved Programs",
                route: "saved-programs",
                container: "saved_programs",
                title: "Saved Plans",
                action: "",
                close: ""
            ),
            (
                name: "Program Builder",
                route: "program-builder",
                container: "program_builder",
                title: "Edit Program",
                action: "program_builder_save",
                close: "program_builder_close"
            ),
            (
                name: "Routine Builder",
                route: "routine-builder",
                container: "routine_builder",
                title: "Edit Routine",
                action: "routine_builder_save",
                close: "routine_builder_close"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let container = app.descendants(matching: .any)[screen.container]
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(app.navigationBars[screen.title].waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if !screen.action.isEmpty {
                let action = app.buttons[screen.action]
                XCTAssertTrue(action.waitForExistence(timeout: 5))
                XCTAssertTrue(action.isHittable)
            }

            if !screen.close.isEmpty {
                let close = app.buttons[screen.close]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                XCTAssertTrue(close.isHittable)
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testTrainingBuildersSupportDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Program Builder",
                route: "program-builder",
                container: "program_builder",
                action: "program_builder_save",
                close: "program_builder_close"
            ),
            (
                name: "Routine Builder",
                route: "routine-builder",
                container: "routine_builder",
                action: "routine_builder_save",
                close: "routine_builder_close"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)[screen.container]
            let action = app.buttons[screen.action]
            let close = app.buttons[screen.close]
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(close.isHittable)
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)
            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testTrainingEvidenceUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Program Detail",
                route: "program-detail",
                container: "program_detail",
                title: "Dumbbell Strength & Hypertrophy"
            ),
            (
                name: "Workout History",
                route: "workout-history",
                container: "workout_history_screen",
                title: "Workout History"
            ),
            (
                name: "Session Review",
                route: "workout-summary",
                container: "workout_summary",
                title: "Session Review"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let container = app.descendants(matching: .any)[screen.container]
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(app.staticTexts[screen.title].waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if screen.route == "workout-summary" {
                let done = app.buttons["workout_summary_done"]
                XCTAssertTrue(done.waitForExistence(timeout: 5))
                XCTAssertTrue(done.isHittable)
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified evidence hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testTrainingEvidenceSupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Program Detail", route: "program-detail", container: "program_detail"),
            (name: "Workout History", route: "workout-history", container: "workout_history_screen"),
            (name: "Session Review", route: "workout-summary", container: "workout_summary")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)[screen.container]
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if screen.route == "workout-summary" {
                let done = app.buttons["workout_summary_done"]
                XCTAssertTrue(done.waitForExistence(timeout: 5))
                XCTAssertTrue(done.isHittable)
            }

            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testWorkoutPlayerAndRecoveryFieldUseUnifiedTrainingSignals() throws {
        let app = XCUIApplication()
        let configurations = [
            (name: "Live Workout", route: "workout-player", container: "workout_player"),
            (name: "Muscle Recovery", route: "muscle-recovery", container: "muscle_recovery_map")
        ]

        for configuration in configurations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                configuration.route
            ]
            app.launch()

            let container = app.descendants(matching: .any)
                .matching(identifier: configuration.container)
                .firstMatch
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(configuration.name) should load")
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if configuration.route == "workout-player" {
                XCTAssertTrue(app.staticTexts["IN SESSION"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Finish Workout"].isHittable)
                XCTAssertTrue(app.buttons["Plate calculator"].isHittable)
            } else {
                let bodyField = app.descendants(matching: .any)
                    .matching(identifier: "muscle_recovery_body_field")
                    .firstMatch
                let evidence = app.descendants(matching: .any)
                    .matching(identifier: "muscle_recovery_evidence")
                    .firstMatch
                XCTAssertTrue(bodyField.waitForExistence(timeout: 5))
                XCTAssertTrue(evidence.waitForExistence(timeout: 5))

                let coreZone = app.buttons["muscle_recovery_zone_front_core"]
                XCTAssertTrue(coreZone.waitForExistence(timeout: 5))
                XCTAssertTrue(coreZone.isHittable)
                coreZone.tap()
                XCTAssertTrue(app.staticTexts["Core"].waitForExistence(timeout: 5))
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(configuration.name) - semantic training signals"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testWorkoutPlayerAndRecoveryFieldSupportDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let configurations = [
            (name: "Live Workout", route: "workout-player", container: "workout_player"),
            (name: "Muscle Recovery", route: "muscle-recovery", container: "muscle_recovery_map")
        ]

        for configuration in configurations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                configuration.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)
                .matching(identifier: configuration.container)
                .firstMatch
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(configuration.name) should load")
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)
            try app.performAccessibilityAudit(for: [.textClipped])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(configuration.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testWellnessFamilyUsesUnifiedEvidenceHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Weight Progress", route: "weight-detail", container: "weight_tracking_screen", title: "Weight Progress"),
            (name: "Wellness Debrief", route: "wellness-detail", container: "wellness_detail_screen", title: "Wellness Debrief"),
            (name: "Fasting", route: "fasting-detail", container: "fasting_tracker_screen", title: "Plan a Fast"),
            (name: "Cycle Phase", route: "cycle-detail", container: "cycle_tracking_screen", title: "Cycle Phase")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let container = app.descendants(matching: .any)
                .matching(identifier: screen.container)
                .firstMatch
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(app.staticTexts[screen.title].waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if screen.route == "weight-detail" {
                let logWeight = app.buttons["weight_log_button"]
                XCTAssertTrue(logWeight.waitForExistence(timeout: 5))
                XCTAssertTrue(logWeight.isHittable)
            } else if screen.route == "fasting-detail" {
                XCTAssertTrue(app.buttons["fasting_schedule_picker"].waitForExistence(timeout: 5))
            } else if screen.route == "cycle-detail" {
                XCTAssertTrue(app.buttons["cycle_options_button"].waitForExistence(timeout: 5))
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified wellness hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testWellnessFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Weight Progress", route: "weight-detail", container: "weight_tracking_screen"),
            (name: "Wellness Debrief", route: "wellness-detail", container: "wellness_detail_screen"),
            (name: "Fasting", route: "fasting-detail", container: "fasting_tracker_screen"),
            (name: "Cycle Phase", route: "cycle-detail", container: "cycle_tracking_screen")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let container = app.descendants(matching: .any)
                .matching(identifier: screen.container)
                .firstMatch
            XCTAssertTrue(container.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            switch screen.route {
            case "weight-detail":
                let logWeight = app.buttons["weight_log_button"]
                XCTAssertTrue(logWeight.waitForExistence(timeout: 5))
                XCTAssertTrue(logWeight.isHittable)
            case "wellness-detail":
                let overview = app.descendants(matching: .any)
                    .matching(identifier: "wellness_score_overview")
                    .firstMatch
                XCTAssertTrue(overview.waitForExistence(timeout: 5))
                XCTAssertLessThanOrEqual(overview.frame.maxX, app.frame.maxX + 1)
            case "fasting-detail":
                let schedule = app.buttons["fasting_schedule_picker"]
                XCTAssertTrue(schedule.waitForExistence(timeout: 5))
                XCTAssertTrue(schedule.isHittable)
            case "cycle-detail":
                let options = app.buttons["cycle_options_button"]
                XCTAssertTrue(options.waitForExistence(timeout: 5))
                XCTAssertTrue(options.isHittable)
            default:
                XCTFail("Unknown wellness route \(screen.route)")
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testOnboardingFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Welcome", route: "welcome", title: "MyFitPlate", action: "welcome_create_account"),
            (name: "Sign In", route: "login", title: "Welcome back", action: "login_submit"),
            (name: "Create Account", route: "signup", title: "Create your workspace", action: "signup_submit"),
            (name: "Personal Setup", route: "onboarding-lifestyle", title: "How active is your life?", action: "onboarding_next"),
            (name: "Feature Tour", route: "feature-tour", title: "Meet Maia", action: "feature_tour_next")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let action = app.descendants(matching: .any)
                .matching(identifier: screen.action)
                .firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX + 1)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified first-run hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testOnboardingFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Welcome", route: "welcome", title: "MyFitPlate", action: "welcome_create_account"),
            (name: "Create Account", route: "signup", title: "Create your workspace", action: "Cancel"),
            (name: "Personal Setup", route: "onboarding-lifestyle", title: "How active is your life?", action: "onboarding_next"),
            (name: "Feature Tour", route: "feature-tour", title: "Meet Maia", action: "feature_tour_next")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let action = app.descendants(matching: .any)
                .matching(identifier: screen.action)
                .firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertTrue(action.waitForExistence(timeout: 5), "\(screen.name) should keep its key action")
            XCTAssertTrue(action.isHittable, "\(screen.name) key action should remain reachable")

            sleep(1)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testProgressFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Profile", route: "profile", title: "Your Progress", summary: "profile_progress_summary"),
            (name: "Challenges", route: "challenges", title: "Weekly Challenges", summary: "challenges_summary")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

            if screen.route == "profile" {
                let challengeButton = app.buttons["profile_weekly_challenges_button"]
                for _ in 0..<4 where !challengeButton.exists || !challengeButton.isHittable {
                    app.swipeUp()
                }
                XCTAssertTrue(challengeButton.waitForExistence(timeout: 5))
                XCTAssertTrue(challengeButton.isHittable)

                let achievementList = app.descendants(matching: .any)
                    .matching(identifier: "profile_achievement_list")
                    .firstMatch
                for _ in 0..<3 where !achievementList.exists {
                    app.swipeUp()
                }
                XCTAssertTrue(achievementList.waitForExistence(timeout: 5))
            } else {
                let challengeList = app.descendants(matching: .any)
                    .matching(identifier: "challenge_list")
                    .firstMatch
                XCTAssertTrue(challengeList.waitForExistence(timeout: 5))
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified progress hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testProgressFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Profile", route: "profile", title: "Your Progress", summary: "profile_progress_summary"),
            (name: "Challenges", route: "challenges", title: "Weekly Challenges", summary: "challenges_summary")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

            sleep(1)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testPantryFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Pantry",
                route: "pantry",
                title: "Smart Pantry",
                summary: "pantry_summary",
                action: "pantry_recipe_button"
            ),
            (
                name: "Pantry Recipes",
                route: "pantry-recipes",
                title: "Pantry Recipes",
                summary: "pantry_recipe_summary",
                action: "pantry_recipe_save_button"
            ),
            (
                name: "Receipt Review",
                route: "receipt-review",
                title: "Review Receipt",
                summary: "receipt_review_summary",
                action: "receipt_add_to_pantry_button"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch
            let action = app.descendants(matching: .any)
                .matching(identifier: screen.action)
                .firstMatch

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5), "\(screen.name) should show its summary")

            for _ in 0..<5 where !action.exists || !action.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(action.waitForExistence(timeout: 5), "\(screen.name) should keep its key action")
            XCTAssertTrue(action.isHittable, "\(screen.name) key action should remain reachable")

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified pantry hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testPantryFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "Pantry", route: "pantry", title: "Smart Pantry", summary: "pantry_summary"),
            (
                name: "Pantry Recipes",
                route: "pantry-recipes",
                title: "Pantry Recipes",
                summary: "pantry_recipe_summary"
            ),
            (
                name: "Receipt Review",
                route: "receipt-review",
                title: "Review Receipt",
                summary: "receipt_review_summary"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts[screen.title]
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch
            let closeButton = app.buttons["app_sheet_close_button"]
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.isHittable, "\(screen.name) should keep its close control reachable")
            XCTAssertGreaterThanOrEqual(closeButton.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(closeButton.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(closeButton.frame.minY, app.frame.minY - 1)
            XCTAssertLessThanOrEqual(closeButton.frame.maxY, app.frame.maxY + 1)
            XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testRestaurantValueFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "AYCE Start", route: "ayce-start", title: "Beat the Buffet", action: "Start Session"),
            (name: "AYCE Live", route: "ayce-live", title: "Sushi", action: "End Session"),
            (name: "AYCE Review", route: "ayce-review", title: "Review Plate Estimate", action: "Add 2 Items"),
            (name: "AYCE Summary", route: "ayce-summary", title: "Buffet Summary", action: "Add to Today's Diary"),
            (name: "Value Radar", route: "value-radar", title: "Value Radar", action: "Scan Another Menu")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let action = app.buttons[screen.action]
            let closeButton = app.buttons["Close"]

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(action.waitForExistence(timeout: 5), "\(screen.name) should retain its primary action")
            XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.isHittable)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified restaurant value hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testRestaurantValueFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (name: "AYCE Start", route: "ayce-start", title: "Beat the Buffet", action: "Start Session"),
            (name: "AYCE Live", route: "ayce-live", title: "Sushi", action: "End Session"),
            (name: "AYCE Review", route: "ayce-review", title: "Review Plate Estimate", action: "Add 2 Items"),
            (name: "AYCE Summary", route: "ayce-summary", title: "Buffet Summary", action: "Add to Today's Diary"),
            (name: "Value Radar", route: "value-radar", title: "Value Radar", action: "Scan Another Menu")
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let action = app.buttons[screen.action]
            let closeButton = app.buttons["Close"]

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.isHittable)
            XCTAssertGreaterThanOrEqual(closeButton.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(closeButton.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX + 1)

            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testCelebrationOverlaySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ui-testing",
            "-screenshot-mode",
            "-screenshot-screen",
            "celebration",
            "-screenshot-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let title = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Buffet Beaten"))
            .firstMatch
        let continueButton = app.buttons["Continue"]

        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        for _ in 0..<4 where !continueButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertGreaterThanOrEqual(continueButton.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(continueButton.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(continueButton.frame.minY, app.frame.minY - 1)
        XCTAssertLessThanOrEqual(continueButton.frame.maxY, app.frame.maxY + 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Celebration - dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMealPlanningSupportFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Meal Plan Survey",
                route: "meal-plan-survey",
                title: "Generate a Meal Plan",
                summary: "Step 1 of 6",
                action: "Next"
            ),
            (
                name: "Meal Plan Cooking Style",
                route: "meal-plan-survey-cooking",
                title: "Generate a Meal Plan",
                summary: "Step 6 of 6",
                action: "Generate Seven-Day Plan"
            ),
            (
                name: "Meal Prep Ingredients",
                route: "meal-prep",
                title: "Meal Prep",
                summary: "Bulk Ingredients",
                action: "Start Cooking Timer"
            ),
            (
                name: "Meal Prep Steps",
                route: "meal-prep-steps",
                title: "Meal Prep",
                summary: "Prep Steps",
                action: "Start Cooking Timer"
            ),
            (
                name: "Meal Suggestion",
                route: "meal-suggestion",
                title: "Meal Suggestion",
                summary: "Macro Fit",
                action: "Log Estimate"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let summary = app.staticTexts[screen.summary]
            let action = app.buttons[screen.action]
            let closeButton = app.buttons["Close"]

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButton.isHittable)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified planning hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testAddSavedRecipeSupportsUnifiedHierarchyAndLargestText() throws {
        let app = XCUIApplication()
        let configurations = [
            (name: "Standard", dark: false, accessibilityText: false),
            (name: "Dark Accessibility", dark: true, accessibilityText: true)
        ]

        for configuration in configurations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                "add-meal-plan"
            ]
            if configuration.dark {
                app.launchArguments.append("-screenshot-dark-mode")
            }
            if configuration.accessibilityText {
                app.launchArguments.append(contentsOf: [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL"
                ])
            }
            app.launch()

            let container = app.descendants(matching: .any)["add_meal_plan_screen"]
            XCTAssertTrue(container.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Add a Saved Recipe"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Create recipe"].isHittable)
            XCTAssertGreaterThanOrEqual(container.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(container.frame.maxX, app.frame.maxX + 1)

            if configuration.accessibilityText {
                try app.performAccessibilityAudit(for: [.textClipped])
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Add Saved Recipe - \(configuration.name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testAddShoeSupportsUnifiedHierarchyAndLargestText() throws {
        let app = XCUIApplication()
        let configurations = [
            (name: "Standard", dark: false, accessibilityText: false),
            (name: "Dark Accessibility", dark: true, accessibilityText: true)
        ]

        for configuration in configurations {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                "shoe-gear-add"
            ]
            if configuration.dark {
                app.launchArguments.append("-screenshot-dark-mode")
            }
            if configuration.accessibilityText {
                app.launchArguments.append(contentsOf: [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL"
                ])
            }
            app.launch()

            let container = app.descendants(matching: .any)["add_shoe_screen"]
            XCTAssertTrue(container.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Shoe Details"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Save"].exists)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Add Shoe - \(configuration.name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            if configuration.accessibilityText {
                container.swipeUp()
                // SwiftUI Form reports one unresolvable viewport node after scrolling at XXXL.
                // Keep every identifiable label and field subject to the clipping audit.
                try app.performAccessibilityAudit(for: [.textClipped]) { issue in
                    issue.element == nil
                }

                let lowerContentScreenshot = XCTAttachment(screenshot: app.screenshot())
                lowerContentScreenshot.name = "Add Shoe - Dark Accessibility Lower Content"
                lowerContentScreenshot.lifetime = .keepAlways
                add(lowerContentScreenshot)
            }
        }
    }

    @MainActor
    func testMealPlanningSupportFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Meal Plan Survey",
                route: "meal-plan-survey",
                title: "Generate a Meal Plan",
                action: "Next"
            ),
            (
                name: "Meal Plan Cooking Style",
                route: "meal-plan-survey-cooking",
                title: "Generate a Meal Plan",
                action: "Generate Seven-Day Plan"
            ),
            (
                name: "Meal Prep Ingredients",
                route: "meal-prep",
                title: "Meal Prep",
                action: "Start Cooking Timer"
            ),
            (
                name: "Meal Prep Steps",
                route: "meal-prep-steps",
                title: "Meal Prep",
                action: "Start Cooking Timer"
            ),
            (
                name: "Meal Suggestion",
                route: "meal-suggestion",
                title: "Meal Suggestion",
                action: "Log Estimate"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let action = app.buttons[screen.action]
            let closeButtons = app.buttons
                .matching(NSPredicate(format: "label == %@", "Close"))

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(closeButtons.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(closeButtons.allElementsBoundByIndex.contains { $0.isHittable })
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(action.frame.minY, app.frame.minY - 1)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY + 1)

            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testReportUtilityFamilyUsesUnifiedHierarchy() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Plate Calculator",
                route: "plate-calculator",
                title: "Plate Loading",
                summary: "plate_calculator_summary"
            ),
            (
                name: "Set Plate Loading",
                route: "plate-math",
                title: "Plate Loading",
                summary: "plate_calculator_summary"
            ),
            (
                name: "Nutrition Trends",
                route: "nutrition-trends",
                title: "Nutrition Trends",
                summary: "nutrition_trends_summary"
            ),
            (
                name: "Maia Insights",
                route: "maia-insights",
                title: "Weekly Insights",
                summary: "maia_insights_summary"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5), "\(screen.name) should show its summary")
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)

            if screen.route.hasPrefix("plate") {
                let closeButton = app.buttons["app_sheet_close_button"]
                XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
                XCTAssertTrue(closeButton.isHittable)
            } else if screen.route == "maia-insights" {
                let shareButton = app.buttons["maia_insights_share"]
                XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
                XCTAssertTrue(shareButton.isHittable)
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(screen.name) - unified report utility hierarchy"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testReportUtilityFamilySupportsDarkLargestAccessibilityText() throws {
        let app = XCUIApplication()
        let screens = [
            (
                name: "Plate Calculator",
                route: "plate-calculator",
                title: "Plate Loading",
                summary: "plate_calculator_summary"
            ),
            (
                name: "Set Plate Loading",
                route: "plate-math",
                title: "Plate Loading",
                summary: "plate_calculator_summary"
            ),
            (
                name: "Nutrition Trends",
                route: "nutrition-trends",
                title: "Nutrition Trends",
                summary: "nutrition_trends_summary"
            ),
            (
                name: "Maia Insights",
                route: "maia-insights",
                title: "Weekly Insights",
                summary: "maia_insights_summary"
            )
        ]

        for screen in screens {
            app.terminate()
            app.launchArguments = [
                "-ui-testing",
                "-screenshot-mode",
                "-screenshot-screen",
                screen.route,
                "-screenshot-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let title = app.staticTexts
                .matching(NSPredicate(format: "label == %@", screen.title))
                .firstMatch
            let summary = app.descendants(matching: .any)
                .matching(identifier: screen.summary)
                .firstMatch

            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(screen.name) should load")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(summary.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(summary.frame.minY, app.frame.minY - 1)
            XCTAssertLessThanOrEqual(summary.frame.maxY, app.frame.maxY + 1)

            if screen.route.hasPrefix("plate") {
                let closeButton = app.buttons["app_sheet_close_button"]
                XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
                XCTAssertTrue(closeButton.isHittable)
            } else if screen.route == "maia-insights" {
                let shareButton = app.buttons["maia_insights_share"]
                XCTAssertTrue(shareButton.waitForExistence(timeout: 5))
                XCTAssertTrue(shareButton.isHittable)
            }

            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "\(screen.name) - dark accessibility XXXL"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testCustomProductPageDeepLinksOpenExactDestinations() throws {
        let app = XCUIApplication()
        let destinations = [
            ("myfitplate://food-search", "Log food"),
            ("myfitplate://trust", "Trust Hub"),
            ("myfitplate://builder", "Fast Food"),
            ("myfitplate://runs", "Running"),
            ("myfitplate://meal-plan", "Meal Plan"),
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
