import XCTest
@testable import MyFitPlateCore

final class RunFuelReviewRequestTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var run: Run { Run(id: "health-run", source: .recorded, startDate: start, endDate: start.addingTimeInterval(1800), distanceMeters: 5000, movingSeconds: 1700, recordingID: "recording") }
    private func revision(id: String = "head", owner: String = "owner", reference: String = "recording", archived: Bool = false) -> TrainingFuelRevision {
        let draft = TrainingFuelPlanDraft(id: "fuel", candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .run), scheduledAt: start, durationMinutes: 30)
        let goals = TodayFuelPlanGoals(calories: 2500, protein: 150, carbs: 300, fats: 80)
        let preview = TrainingFuelPlannerRules.makePlan(session: draft.session, today: nil, goals: goals, preference: draft.preference, now: start)
        var plan = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: preview, goals: goals, today: nil)
        plan.ownerID = owner; plan.revisionID = id
        plan.outcome = TrainingFuelSessionOutcome(status: .completed, source: .recordedRun, recordedAt: run.endDate,
            actualStartAt: run.startDate, actualEndAt: run.endDate, referenceID: reference)
        return TrainingFuelRevision(id: id, parents: [], plan: plan, archivedAt: archived ? run.endDate : nil, reason: "fixture")
    }
    func testOnlyExactAcceptedOutcomeOrItsRecordingAliasProducesReview() throws {
        let source = revision()
        let request = try XCTUnwrap(RunFuelReviewRequest.make(run: run, history: [source], conflictingPlanIDs: [], ownerID: "owner"))
        XCTAssertEqual(request.planID, "fuel"); XCTAssertEqual(request.revisionID, "head")
        XCTAssertTrue(request.isCurrent(history: [source], conflictingPlanIDs: [], currentUserID: "owner"))
        XCTAssertNil(RunFuelReviewRequest.make(run: run, history: [revision(reference: "unrelated-same-time")], conflictingPlanIDs: [], ownerID: "owner"))
        XCTAssertEqual(source.plan.outcome?.referenceID, "recording", "Review creates no allocation or rewritten receipt")
    }
    func testChangedConflictingClosedOrOtherAccountCannotOpenStalePlan() throws {
        let request = try XCTUnwrap(RunFuelReviewRequest.make(run: run, history: [revision()], conflictingPlanIDs: [], ownerID: "owner"))
        XCTAssertFalse(request.isCurrent(history: [revision(id: "new")], conflictingPlanIDs: [], currentUserID: "owner"))
        XCTAssertFalse(request.isCurrent(history: [revision()], conflictingPlanIDs: ["fuel"], currentUserID: "owner"))
        XCTAssertFalse(request.isCurrent(history: [revision()], conflictingPlanIDs: [], currentUserID: "other"))
        XCTAssertNil(RunFuelReviewRequest.make(run: run, history: [revision(archived: true)], conflictingPlanIDs: [], ownerID: "owner"))
        XCTAssertNil(RunFuelReviewRequest.make(run: run, history: [revision(), revision(id: "duplicate")], conflictingPlanIDs: [], ownerID: "owner"))
        XCTAssertNil(RunFuelReviewRequest.make(run: run, history: [revision(owner: "other")], conflictingPlanIDs: [], ownerID: "owner"))
    }
    func testReviewRetainsCapturedCivilDayAcrossTimezoneChangeAndEncoding() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let request = try XCTUnwrap(RunFuelReviewRequest.make(run: run, history: [revision()], conflictingPlanIDs: [], ownerID: "owner", calendar: calendar))
        let restored = try JSONDecoder().decode(RunFuelReviewRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(restored.day.dayKey, DiaryDayContext.dayKey(for: run.endDate, timeZone: calendar.timeZone))
        XCTAssertEqual(restored.day.timeZoneIdentifier, calendar.timeZone.identifier)
        XCTAssertEqual(restored, request)
    }
    func testUnlinkedPlannerRequestCreatesNoOutcomeAllocationOrChosenPlan() throws {
        let request = try XCTUnwrap(RunFuelReviewRequest.planning(ownerID: "owner", now: start))
        XCTAssertEqual(request.intent, .planner)
        XCTAssertNil(request.planID); XCTAssertNil(request.revisionID); XCTAssertNil(request.outcome)
        XCTAssertTrue(request.isCurrent(history: [revision()], conflictingPlanIDs: [], currentUserID: "owner"))
        XCTAssertFalse(request.isCurrent(history: [], conflictingPlanIDs: [], currentUserID: "other"))
        XCTAssertTrue(request.day.isToday(now: start))
    }

}
