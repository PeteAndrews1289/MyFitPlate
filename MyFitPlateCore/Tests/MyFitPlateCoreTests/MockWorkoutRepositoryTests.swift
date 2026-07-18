import XCTest
@testable import MyFitPlateCore

final class MockWorkoutRepositoryTests: XCTestCase {
    func testMissingSessionResultThrowsInsteadOfCrashing() async {
        let repository = MockWorkoutRepository()

        do {
            _ = try await repository.fetchWorkoutSessionLog(userID: "user", sessionID: "session")
            XCTFail("Expected an unconfigured mock result to throw")
        } catch {
            XCTAssertEqual(error as? MockWorkoutRepositoryError, .resultNotConfigured)
        }
    }
}
