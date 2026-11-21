import MyFitPlateShared
import XCTest

final class WorkoutActivitySessionRulesTests: XCTestCase {
    func testResumeReusesOnlyTheSameSessionAndRetiresDuplicates() {
        let result = WorkoutActivitySessionRules.reconcile(sessionID: "session-a", activities: [
            .init(id: "other-account", sessionID: "session-b"),
            .init(id: "same", sessionID: "session-a"),
            .init(id: "duplicate", sessionID: "session-a"),
            .init(id: "legacy", sessionID: nil)
        ])
        XCTAssertEqual(result.reusableID, "same")
        XCTAssertEqual(result.retiredIDs, ["other-account", "duplicate", "legacy"])
    }

    func testNewSessionCannotInheritAnOldWorkoutActivityOrItsRest() {
        let result = WorkoutActivitySessionRules.reconcile(sessionID: "new-session", activities: [
            .init(id: "previous-session", sessionID: "old-session"),
            .init(id: "legacy", sessionID: nil)
        ])
        XCTAssertNil(result.reusableID)
        XCTAssertEqual(result.retiredIDs, ["previous-session", "legacy"])
    }

    func testMissingIdentityNeverMatchesAnUnscopedLegacyActivity() {
        for identity in [nil, "", "  "] as [String?] {
            let result = WorkoutActivitySessionRules.reconcile(sessionID: identity, activities: [.init(id: "legacy", sessionID: nil)])
            XCTAssertNil(result.reusableID)
            XCTAssertEqual(result.retiredIDs, ["legacy"])
        }
    }
}
