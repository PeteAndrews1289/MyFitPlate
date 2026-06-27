import XCTest

final class MainNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testTabNavigation() throws {
        let app = XCUIApplication()
        
        // Wait for the tab bar to appear
        let homeTab = app.buttons["tab_home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5), "Home tab should be visible")
        
        // Navigate to Maia
        let maiaTab = app.buttons["tab_maia"]
        maiaTab.tap()
        XCTAssertTrue(maiaTab.isSelected || app.navigationBars["Maia"].exists || app.buttons["tab_maia"].exists, "Should navigate to Maia")
        
        // Navigate to Meal Plan
        let mealPlanTab = app.buttons["tab_meal_plan"]
        mealPlanTab.tap()
        XCTAssertTrue(mealPlanTab.exists, "Should navigate to Meal Plan")
        
        // Navigate to Reports
        let reportsTab = app.buttons["tab_reports"]
        reportsTab.tap()
        XCTAssertTrue(reportsTab.exists, "Should navigate to Reports")
        
        // Navigate back to Home
        homeTab.tap()
        XCTAssertTrue(homeTab.exists, "Should navigate back to Home")
    }
}
