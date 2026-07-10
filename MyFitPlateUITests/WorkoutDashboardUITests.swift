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
        let workoutsButton = app.buttons["home_workouts_button"]
        XCTAssertTrue(workoutsButton.waitForExistence(timeout: 5), "Workouts button should be visible on Home View")
        workoutsButton.tap()
        
        let startPlanButton = app.buttons["start_plan_button"]
        XCTAssertTrue(startPlanButton.waitForExistence(timeout: 2), "Start a Plan should be actionable")
        startPlanButton.tap()

        let prebuiltButton = app.buttons["prebuilt_programs_button"]
        XCTAssertTrue(prebuiltButton.waitForExistence(timeout: 5), "Pre-built programs button should be reachable")
        
        let aiProgramButton = app.buttons["ai_workout_generator_button"]
        XCTAssertTrue(aiProgramButton.exists, "AI Program button should exist")
    }
}
