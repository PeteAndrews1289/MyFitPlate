import XCTest

final class WorkoutDashboardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
    }

    func testWorkoutDashboardNavigationAndButtons() throws {
        let app = XCUIApplication()
        
        // Ensure we're on Home View by checking for the Workouts quick action button
        // It might be nested inside scroll views, but XCUITest can find it by its label.
        let workoutsButton = app.buttons["Workouts"]
        XCTAssertTrue(workoutsButton.waitForExistence(timeout: 5), "Workouts button should be visible on Home View")
        workoutsButton.tap()
        
        // Now we should be on the WorkoutRoutinesView
        // Let's verify the hero card or one of our newly tagged buttons exists
        let prebuiltButton = app.buttons["prebuilt_programs_button"]
        XCTAssertTrue(prebuiltButton.waitForExistence(timeout: 2), "Pre-built programs button should be visible")
        
        let aiProgramButton = app.buttons["ai_program_button"]
        XCTAssertTrue(aiProgramButton.exists, "AI Program button should exist")
    }
}
