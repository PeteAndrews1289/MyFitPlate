import XCTest
import MyFitPlateCore
@testable import MyFitPlate

final class WorkoutTimerTests: XCTestCase {
    private let timerUserID = "workout-timer-tests"
    private var timerStorageKey: String {
        AccountScopedStorageKey.make(
            prefix: "totalWorkoutTimer_testRoutine",
            userID: timerUserID
        )!
    }

    override func setUpWithError() throws {
        // Clear UserDefaults state for tests
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
        UserDefaults.standard.removeObject(forKey: timerStorageKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
        UserDefaults.standard.removeObject(forKey: timerStorageKey)
    }

    @MainActor
    func testTotalWorkoutTimer_Formatting() throws {
        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        
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
        let timer1 = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        timer1.start()
        
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        // Given timer1 has started and saved state in UserDefaults
        XCTAssertTrue(timer1.totalTimeElapsed >= 1.0)
        
        // When timer2 is initialized with same routineId
        let timer2 = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        
        // Then it should load the state and resume
        XCTAssertTrue(timer2.totalTimeElapsed >= 1.0)
        
        timer1.stop()
        timer2.stop()
    }

    @MainActor
    func testTotalWorkoutTimer_DiscardsAbandonedWorkoutState() throws {
        let key = timerStorageKey
        UserDefaults.standard.set(
            Date().addingTimeInterval(-(TotalWorkoutTimer.maximumRestorableDuration + 60)),
            forKey: key
        )

        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)

        XCTAssertEqual(timer.totalTimeElapsed, 0)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    @MainActor
    func testTotalWorkoutTimer_DiscardsFutureStartTime() throws {
        let key = timerStorageKey
        UserDefaults.standard.set(Date().addingTimeInterval(60), forKey: key)

        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)

        XCTAssertEqual(timer.totalTimeElapsed, 0)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
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
