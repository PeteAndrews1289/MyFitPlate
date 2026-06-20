import XCTest
@testable import MyFitPlate

final class WorkoutTimerTests: XCTestCase {

    override func setUpWithError() throws {
        // Clear UserDefaults state for tests
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
    }

    @MainActor
    func testTotalWorkoutTimer_Formatting() throws {
        let timer = TotalWorkoutTimer(routineId: "testRoutine")
        
        // Given
        timer.totalTimeElapsed = 45
        XCTAssertEqual(timer.formattedTime(), "00:45")
        
        timer.totalTimeElapsed = 65
        XCTAssertEqual(timer.formattedTime(), "01:05")
        
        timer.totalTimeElapsed = 3665
        XCTAssertEqual(timer.formattedTime(), "1:01:05")
    }
    
    @MainActor
    func testTotalWorkoutTimer_StatePersistence() async throws {
        let timer1 = TotalWorkoutTimer(routineId: "testRoutine")
        timer1.start()
        
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        // Given timer1 has started and saved state in UserDefaults
        XCTAssertTrue(timer1.totalTimeElapsed >= 1.0)
        
        // When timer2 is initialized with same routineId
        let timer2 = TotalWorkoutTimer(routineId: "testRoutine")
        
        // Then it should load the state and resume
        XCTAssertTrue(timer2.totalTimeElapsed >= 1.0)
        
        timer1.stop()
        timer2.stop()
    }
    
    @MainActor
    func testRestTimer_StartsAndStops() throws {
        let restTimer = RestTimer()
        
        // Given
        XCTAssertEqual(restTimer.timeRemaining, 0)
        
        // When
        restTimer.start(duration: 60, routineName: "Test Routine")
        
        // Then
        XCTAssertEqual(restTimer.timeRemaining, 60)
        
        // Stop
        restTimer.stop()
        XCTAssertEqual(restTimer.timeRemaining, 0)
    }
}
