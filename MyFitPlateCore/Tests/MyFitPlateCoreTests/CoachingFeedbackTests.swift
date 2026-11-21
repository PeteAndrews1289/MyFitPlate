import XCTest
@testable import MyFitPlateCore

@MainActor
final class CoachingFeedbackTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan(_ kind: AdaptiveCoachingPlan.ActionKind = .reviewMeal) -> AdaptiveCoachingPlan {
        .init(title: "Plan", subtitle: "Evidence", primaryAction: "Review a meal",
              mealMove: "Original meal", trainingMove: "Original training", recoveryMove: "Original recovery",
              confidence: "Building signal", dataPoints: ["2 fully logged days"], actionKind: kind, generatedAt: now)
    }

    func testFeedbackRetryIsIdempotentAccountScopedAndNeverAChangeReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CoachingFeedbackStore(store: EditorDraftStore(directory: directory))
        let reviewID = UUID()
        let feedback = try CoachingFeedback(userID: "owner", plan: plan(), disposition: .declined,
            barrier: .time, actionReviewID: reviewID, now: now)
        try store.record(feedback, currentUserID: "owner")
        try store.record(feedback, currentUserID: "owner")
        XCTAssertEqual(try store.history(userID: "owner"), [feedback])
        XCTAssertTrue(try store.history(userID: "other").isEmpty)
        XCTAssertThrowsError(try store.record(feedback, currentUserID: "other"))
        let outcomes = try CoachingActionHistory(store: EditorDraftStore(directory: directory)).outcomes(userID: "owner")
        XCTAssertTrue(outcomes.isEmpty, "Self report must not fabricate an accepted operation.")
        let changed = try CoachingFeedback(id: feedback.id, userID: "owner", plan: plan(), disposition: .tried, now: now)
        XCTAssertThrowsError(try store.record(changed, currentUserID: "owner"))
        XCTAssertEqual(try store.history(userID: "owner"), [feedback])
    }

    func testBarrierChangesPracticalSuggestionButPreservesEvidenceAndTypedAction() throws {
        let original = plan()
        let feedback = try CoachingFeedback(userID: "owner", plan: original, disposition: .declined, barrier: .time, now: now)
        let changed = CoachingFeedbackRules.applying([feedback], to: original, userID: "owner", now: now)
        XCTAssertTrue(changed.primaryAction.contains("leftovers"))
        XCTAssertEqual(changed.actionKind, original.actionKind)
        XCTAssertEqual(changed.generatedAt, original.generatedAt)
        XCTAssertEqual(changed.trainingMove, original.trainingMove)
        XCTAssertEqual(changed.recoveryMove, original.recoveryMove)
        XCTAssertEqual(changed.confidence, original.confidence)
        XCTAssertEqual(changed.dataPoints.first, original.dataPoints.first)
        XCTAssertTrue(changed.dataPoints.last?.contains("Your feedback") == true)
    }

    func testOldFutureDifferentAccountAndDifferentActionFeedbackCannotPersonalizePlan() throws {
        let feedback = try CoachingFeedback(userID: "owner", plan: plan(), disposition: .declined, barrier: .foodAvailability, now: now)
        XCTAssertEqual(CoachingFeedbackRules.applying([feedback], to: plan(), userID: "owner", now: now.addingTimeInterval(8 * 86_400)), plan())
        XCTAssertEqual(CoachingFeedbackRules.applying([feedback], to: plan(), userID: "owner", now: now.addingTimeInterval(-1)), plan())
        XCTAssertEqual(CoachingFeedbackRules.applying([feedback], to: plan(), userID: "other", now: now), plan())
        XCTAssertEqual(CoachingFeedbackRules.applying([feedback], to: plan(.reviewTraining), userID: "owner", now: now), plan(.reviewTraining))
    }

    func testDeclinedAdviceCannotClaimResultAndNotesAreBounded() throws {
        XCTAssertThrowsError(try CoachingFeedback(userID: "owner", plan: plan(), disposition: .declined, result: .helpful, now: now))
        XCTAssertThrowsError(try CoachingFeedback(userID: "owner", plan: plan(), disposition: .tried, note: String(repeating: "a", count: 501), now: now))
        XCTAssertThrowsError(try CoachingFeedback(userID: "owner", plan: plan(), disposition: .tried, now: now.addingTimeInterval(15 * 86_400)))
    }
}
