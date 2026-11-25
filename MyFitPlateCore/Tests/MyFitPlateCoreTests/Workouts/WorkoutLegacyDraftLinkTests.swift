import XCTest
@testable import MyFitPlateCore

final class WorkoutLegacyDraftLinkTests: XCTestCase {
    private let owner = "legacy-owner"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func program(index: Int = 38) -> WorkoutProgram {
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "phul-\(index)", userID: owner, name: "PHUL routine \(index)",
                           dateCreated: now.addingTimeInterval(-100_000), exercises: [
                            RoutineExercise(id: "exercise-\(index)", name: "Bench Press", sets: [
                                ExerciseSet(id: "set-\(index)", isCompleted: true, reps: 8, weight: 165)
                            ])
                           ])
        }
        return WorkoutProgram(id: "existing-phul", userID: owner, name: "PHUL",
                              dateCreated: now.addingTimeInterval(-100_000), routines: routines,
                              startDate: now.addingTimeInterval(-90_000), daysOfWeek: [2, 3, 5, 6],
                              currentProgressIndex: index, skippedIndices: [2, 7])
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func legacyDraft(in program: WorkoutProgram, frozen: Bool = false) throws -> WorkoutSessionDraft {
        let routine = try XCTUnwrap(program.routine(forSlot: program.currentProgressIndex ?? 0)?.deepCopy())
        var draft = WorkoutSessionDraft(routine: routine, now: now.addingTimeInterval(-600))
        draft.elapsed = 600
        draft.rest = WorkoutRestState(duration: 120, routineName: routine.name, exerciseID: routine.exercises[0].id,
                                      setID: routine.exercises[0].sets[0].id, now: now.addingTimeInterval(-30))
        if frozen { XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: now)) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(draft)) as? [String: Any])
        object.removeValue(forKey: "programLinkDecision")
        if var completion = object["completion"] as? [String: Any] {
            completion.removeValue(forKey: "programLinkDecision")
            object["completion"] = completion
        }
        return try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testNewStandaloneSessionNeverRequestsLegacyReview() {
        let draft = WorkoutSessionDraft(routine: program().routines[2], now: now)
        XCTAssertEqual(draft.programLinkDecision, .standalone)
        XCTAssertNil(draft.programContext)
        XCTAssertFalse(draft.needsProgramLinkReview)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: program(), userID: owner, now: now))
    }

    func testNewProgramSessionRecordsItsOriginImmediately() {
        let context = WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38)
        let draft = WorkoutSessionDraft(routine: program().routines[2], now: now, programContext: context)
        XCTAssertEqual(draft.programLinkDecision, .program)
        XCTAssertEqual(draft.programContext, context)
        XCTAssertFalse(draft.needsProgramLinkReview)
    }

    func testLegacyDraftRoundTripAddsNoDecisionAndKeepsRecoveryState() throws {
        let draft = try legacyDraft(in: program())
        let before = try encoded(draft)
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: before)
        XCTAssertTrue(restored.needsProgramLinkReview)
        XCTAssertNil(restored.programLinkDecision)
        XCTAssertEqual(try encoded(restored), before)
        XCTAssertEqual(restored.rest, draft.rest)
        XCTAssertEqual(restored.elapsed, 600)
        XCTAssertEqual(restored.routine.exercises[0].sets[0].weight, 165)
        XCTAssertTrue(restored.routine.exercises[0].sets[0].isCompleted)
    }

    func testExistingExplicitContextWithoutNewMarkerDoesNotRequireReview() throws {
        var draft = try legacyDraft(in: program())
        draft.programContext = WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38)
        XCTAssertNil(draft.programLinkDecision)
        XCTAssertFalse(draft.needsProgramLinkReview)
    }

    func testUnknownOptionalDraftDecisionStillRecoversSetsForExplicitReview() throws {
        let draft = try legacyDraft(in: program())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(draft)) as? [String: Any])
        object["programLinkDecision"] = "future-unrecognized-value"
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.needsProgramLinkReview)
        XCTAssertEqual(restored.sessionID, draft.sessionID)
        XCTAssertEqual(restored.rest, draft.rest)
        XCTAssertEqual(try encoded(restored.routine), try encoded(draft.routine))
    }

    func testExactCurrentCandidateIsOnlyASuggestionAndDoesNotMutateDraftOrPlan() throws {
        let plan = program()
        let draft = try legacyDraft(in: plan)
        let draftBefore = try encoded(draft), planBefore = try encoded(plan)
        let candidate = WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now)
        XCTAssertEqual(candidate, WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38))
        XCTAssertTrue(draft.needsProgramLinkReview)
        XCTAssertNil(draft.programContext)
        XCTAssertEqual(try encoded(draft), draftBefore)
        XCTAssertEqual(try encoded(plan), planBefore)
    }

    func testMatchingExerciseNamesCannotCreateALegacyCandidate() throws {
        let plan = program()
        var draft = try legacyDraft(in: plan)
        draft.routine = try XCTUnwrap(draft.routine.deepCopy())
        draft.routine.id = "unrelated-routine"
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
    }

    func testCandidateNeverSearchesAheadOrBackForRecurringRoutine() throws {
        let plan = program()
        let draft = try legacyDraft(in: plan)
        var later = plan
        later.currentProgressIndex = 39
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: later, userID: owner, now: now))
        var earlier = plan
        earlier.currentProgressIndex = 37
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: earlier, userID: owner, now: now))
    }

    func testCandidateRequiresTheSameAccountInBothDraftAndProgram() throws {
        let plan = program()
        let draft = try legacyDraft(in: plan)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: "other", now: now))
        var foreign = plan
        foreign.userID = "other"
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: foreign, userID: owner, now: now))
    }

    func testDraftPredatingFreshProgramOrFutureDraftCannotBeSuggested() throws {
        var plan = program()
        var draft = try legacyDraft(in: plan)
        plan.dateCreated = draft.startedAt.addingTimeInterval(1)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        plan = program()
        draft.startedAt = now.addingTimeInterval(1)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
    }

    func testInvalidSkippedCompletedAndUnsavedProgramSlotsCannotBeSuggested() throws {
        var plan = program()
        let draft = try legacyDraft(in: plan)
        plan.skippedIndices?.append(38)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        plan = program(index: 48)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        plan = program(index: -1)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        plan = program()
        plan.id = nil
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
    }

    func testEarlyDraftCanBeReviewedWithoutRequiringItsScheduledDay() throws {
        var plan = program()
        let draft = try legacyDraft(in: plan)
        plan.startDate = now.addingTimeInterval(86_400)
        XCTAssertNotNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
    }

    func testExplicitProgramChoicePersistsBeforeFreezeAndPreservesRecoveryFields() throws {
        let plan = program()
        let draft = try legacyDraft(in: plan)
        let context = try XCTUnwrap(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutDraftStore(directory: directory)
        try store.save(draft, userID: owner)
        let resolved = try XCTUnwrap(store.saveLegacyProgramLinkDecision(in: draft, context: context, userID: owner))
        XCTAssertNil(resolved.completion)
        XCTAssertEqual(resolved.sessionID, draft.sessionID)
        XCTAssertEqual(resolved.startedAt, draft.startedAt)
        XCTAssertEqual(resolved.updatedAt, draft.updatedAt)
        XCTAssertEqual(resolved.rest, draft.rest)
        XCTAssertEqual(resolved.elapsed, draft.elapsed)
        XCTAssertEqual(try encoded(resolved.routine), try encoded(draft.routine))
        var recovered = try XCTUnwrap(store.load(userID: owner))
        XCTAssertEqual(recovered.programContext, context)
        XCTAssertEqual(recovered.programLinkDecision, .program)
        XCTAssertTrue(recovered.prepareCompletion(weightPounds: 180, now: now))
        let completion = try XCTUnwrap(recovered.completion)
        XCTAssertEqual(completion.id, draft.sessionID)
        XCTAssertEqual(completion.programContext, context)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: plan, sessionLogs: [completion]).currentProgressIndex, 39)
        XCTAssertEqual(plan.currentProgressIndex, 38, "The seeded original is preserved until an accepted completion save")
    }

    func testStandaloneChoiceNeverCreatesProgramProvenanceEvenWithExactCandidate() throws {
        let plan = program()
        var draft = try legacyDraft(in: plan)
        XCTAssertNotNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        XCTAssertTrue(draft.resolveLegacyProgramLink(nil))
        XCTAssertFalse(draft.needsProgramLinkReview)
        XCTAssertEqual(draft.programLinkDecision, .standalone)
        XCTAssertNil(draft.programContext)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: now))
        XCTAssertNil(draft.completion?.programContext)
        XCTAssertEqual(draft.completion?.programLinkDecision, .standalone)
        XCTAssertFalse(WorkoutRules.logBelongsToProgram(try XCTUnwrap(draft.completion), program: plan))
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: plan, sessionLogs: [try XCTUnwrap(draft.completion)]).isEmpty)
    }

    func testProgramDecisionIsIdempotentAndCannotRetargetOnRetry() throws {
        var draft = try legacyDraft(in: program())
        let context = WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38)
        XCTAssertTrue(draft.resolveLegacyProgramLink(context))
        let decided = try encoded(draft)
        XCTAssertFalse(draft.resolveLegacyProgramLink(context))
        XCTAssertFalse(draft.resolveLegacyProgramLink(nil))
        XCTAssertFalse(draft.resolveLegacyProgramLink(WorkoutProgramSessionContext(programID: "new-phul", slotIndex: 0)))
        XCTAssertEqual(try encoded(draft), decided)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: now))
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 200, now: now.addingTimeInterval(600)))
        XCTAssertEqual(draft.completion?.programContext, context)
        XCTAssertEqual(draft.completion?.date, now)
    }

    func testFailedDecisionWriteLeavesOriginalDraftUndecidedAndRecoverable() throws {
        let draft = try legacyDraft(in: program())
        let before = try encoded(draft)
        let blockedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sentinel = Data("existing data".utf8)
        try sentinel.write(to: blockedDirectory)
        defer { try? FileManager.default.removeItem(at: blockedDirectory) }
        let store = WorkoutDraftStore(directory: blockedDirectory)
        XCTAssertThrowsError(try store.saveLegacyProgramLinkDecision(in: draft,
            context: WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38), userID: owner))
        XCTAssertEqual(try encoded(draft), before)
        XCTAssertTrue(draft.needsProgramLinkReview)
        XCTAssertEqual(try Data(contentsOf: blockedDirectory), sentinel)
    }

    func testFrozenLegacyCompletionCannotAcquireProgramProvenanceOrChangePayload() throws {
        let plan = program()
        var draft = try legacyDraft(in: plan, frozen: true)
        let before = try encoded(draft)
        XCTAssertTrue(draft.needsProgramLinkReview)
        XCTAssertNil(WorkoutRules.legacyProgramContextCandidate(for: draft, in: plan, userID: owner, now: now))
        XCTAssertFalse(draft.resolveLegacyProgramLink(WorkoutProgramSessionContext(programID: "existing-phul", slotIndex: 38)))
        XCTAssertEqual(try encoded(draft), before)
    }

    func testFrozenLegacyStandaloneAcknowledgmentKeepsHistoryAndDiaryBytesUnchanged() throws {
        var draft = try legacyDraft(in: program(), frozen: true)
        let completion = try encoded(draft.completion), diary = try encoded(draft.diaryExercise)
        let sessionID = draft.sessionID
        XCTAssertTrue(draft.resolveLegacyProgramLink(nil))
        XCTAssertFalse(draft.needsProgramLinkReview)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 220, now: now.addingTimeInterval(600)))
        XCTAssertEqual(try encoded(draft.completion), completion)
        XCTAssertEqual(try encoded(draft.diaryExercise), diary)
        XCTAssertEqual(draft.sessionID, sessionID)
        XCTAssertNil(draft.completion?.programContext)
    }

    func testFrozenLegacyReceiptOnCurrentScheduledDayCannotAdvanceOrPretendToCompleteCurrentSlot() throws {
        var plan = program(index: 0)
        plan.startDate = Calendar.current.startOfDay(for: now)
        plan.daysOfWeek = [Calendar.current.component(.weekday, from: now)]
        var draft = try legacyDraft(in: plan, frozen: true)
        let receipt = try XCTUnwrap(draft.completion)
        XCTAssertNil(receipt.programLinkDecision)
        XCTAssertTrue(Calendar.current.isDate(receipt.date, inSameDayAs: try XCTUnwrap(plan.date(forSlot: 0))))
        XCTAssertTrue(draft.resolveLegacyProgramLink(nil))
        XCTAssertEqual(try encoded(draft.completion), try encoded(receipt))
        XCTAssertTrue(WorkoutRules.sessionLogsBySlot(in: plan, sessionLogs: [receipt]).isEmpty)
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: plan, sessionLogs: [receipt]).currentProgressIndex, 0)
        plan.currentProgressIndex = 1
        XCTAssertEqual(WorkoutRules.sessionLogsBySlot(in: plan, sessionLogs: [receipt])[0]?.id, receipt.id,
                       "Legacy linkage may review a position already passed, but cannot create that progress")
    }
}
