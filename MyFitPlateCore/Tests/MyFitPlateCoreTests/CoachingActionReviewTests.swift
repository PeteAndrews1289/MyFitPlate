import XCTest
@testable import MyFitPlateCore

final class CoachingActionReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_800_000)

    private func review() throws -> CoachingActionReview {
        let day = try XCTUnwrap(DiaryDayContext(userID: "owner", date: now, timeZone: TimeZone(secondsFromGMT: 0)!))
        return CoachingActionReview(kind: .sessionTargets, day: day, targetID: "phul",
                                    targetFingerprint: "original", evidence: ["Recorded set"], now: now)
    }

    func testExactContextRejectsOtherAccountsChangedProgramsAndOldAdvice() throws {
        let action = try review()
        XCTAssertNoThrow(try action.validate(userID: "owner", now: now, currentTargetID: "phul", currentFingerprint: "original"))
        XCTAssertThrowsError(try action.validate(userID: "other", now: now, currentTargetID: "phul", currentFingerprint: "original"))
        XCTAssertThrowsError(try action.validate(userID: "owner", now: now, currentTargetID: "replacement", currentFingerprint: "original"))
        XCTAssertThrowsError(try action.validate(userID: "owner", now: now, currentTargetID: "phul", currentFingerprint: "edited"))
        XCTAssertThrowsError(try action.validate(userID: "owner", now: now.addingTimeInterval(1_801), currentTargetID: "phul", currentFingerprint: "original"))
    }

    func testOpeningOrClosingDoesNotClaimAnAcceptedWriteAndAcceptedReceiptSurvivesDismissal() throws {
        var outcome = CoachingActionOutcome(review: try review(), now: now)
        XCTAssertEqual(outcome.state, .opened)
        XCTAssertNil(outcome.operationID)
        outcome.close(now: now)
        XCTAssertEqual(outcome.state, .closed)
        XCTAssertThrowsError(try outcome.accept(operationID: " "))
        try outcome.accept(operationID: "actual-program-change", now: now)
        outcome.close(now: now.addingTimeInterval(1))
        XCTAssertEqual(outcome.state, .accepted)
        XCTAssertEqual(outcome.operationID, "actual-program-change")
        XCTAssertNoThrow(try outcome.accept(operationID: "actual-program-change"))
        XCTAssertThrowsError(try outcome.accept(operationID: "unrelated-change"))
    }

    @MainActor func testHistoryRecoversAndCannotCrossAccountsOrOverwriteAcceptedResult() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let history = CoachingActionHistory(store: store)
        var outcome = CoachingActionOutcome(review: try review(), now: now)
        let opened = outcome
        XCTAssertThrowsError(try history.record(outcome, currentUserID: "other"))
        try history.record(outcome, currentUserID: "owner")
        try outcome.accept(operationID: "stored-change", now: now)
        try history.record(outcome, currentUserID: "owner")
        try history.record(opened, currentUserID: "owner")
        let recovered = try CoachingActionHistory(store: store).outcomes(userID: "owner")
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.operationID, "stored-change")
        XCTAssertTrue(try history.outcomes(userID: "other").isEmpty)
    }

    func testAdviceCopyCannotChangeTheDeclaredDestination() {
        let plan = AdaptiveCoachingPlan(title: "Workout run/walk scheduled baseline protein",
            subtitle: "Words are presentation", primaryAction: "Different wording", mealMove: "", trainingMove: "",
            recoveryMove: "", confidence: "", dataPoints: [], actionKind: .reviewMeal, generatedAt: now)
        XCTAssertEqual(plan.actionKind, .reviewMeal)
        XCTAssertEqual(plan.generatedAt, now)
    }
}
