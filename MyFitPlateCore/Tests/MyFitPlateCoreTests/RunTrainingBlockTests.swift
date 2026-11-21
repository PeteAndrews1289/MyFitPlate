import XCTest
@testable import MyFitPlateCore

final class RunTrainingBlockRulesTests: XCTestCase {
    private var start: Date {
        Calendar.current.startOfDay(for: Calendar.current.nextDate(after: Date(timeIntervalSince1970: 1_900_000_000),
            matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!)
    }
    private func date(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: start)! }
    private func brief(_ ability: RunBlockAbility = .returning) -> RunTrainingBlockBrief {
        .init(start: start, weeks: 4, ability: ability, recentWeeklyMinutes: 60, recentLongestMinutes: 30,
            weekdays: [2, 4, 7], preferredLongWeekday: 7, includeQuality: ability == .established)
    }
    func testAbilityCorpusProtectsStrengthAndBoundedLighterWeek() throws {
        let protected = Set([TrainingCalendarDay(start)])
        for ability in RunBlockAbility.allCases {
            let block = try RunTrainingBlockRules.make(brief: brief(ability), strengthDays: protected, now: start)
            XCTAssertTrue(block.slots.allSatisfy { !protected.contains($0.day) })
            XCTAssertEqual(block.slots.filter { $0.weekIndex == 0 }.count, 2)
            XCTAssertLessThanOrEqual(block.weeklyMinuteCeilings[1], 60 * 1.05 + 0.0001)
            XCTAssertLessThan(block.weeklyMinuteCeilings[3], block.weeklyMinuteCeilings[2])
            for week in 0..<4 {
                XCTAssertLessThanOrEqual(RunTrainingBlockRules.plannedMinutes(block, week: week), block.weeklyMinuteCeilings[week] + 0.001)
                XCTAssertLessThanOrEqual(block.slots.filter { $0.weekIndex == week && $0.role == .quality }.count, 1)
            }
            if ability == .starting {
                XCTAssertTrue(block.slots.allSatisfy { $0.role == .runWalk && $0.plan.steps.contains { $0.title == "Walk" } })
            }
            XCTAssertTrue(block.slots.allSatisfy { $0.plan.steps.first?.kind == .warmup && $0.plan.steps.last?.kind == .cooldown })
        }
    }
    func testUnavailableWeekAndContradictoryGoalDateFailWithoutMovingStrength() throws {
        let protected = Set((0..<7).map { TrainingCalendarDay(date($0)) })
        XCTAssertThrowsError(try RunTrainingBlockRules.make(brief: brief(), strengthDays: protected, now: start))
        var invalid = brief(); invalid.targetDay = TrainingCalendarDay(date(5))
        XCTAssertThrowsError(try RunTrainingBlockRules.make(brief: invalid, strengthDays: [], now: start))
        invalid = brief(); invalid.weekdays = [2, 2]
        XCTAssertThrowsError(try RunTrainingBlockRules.make(brief: invalid, strengthDays: [], now: start))
    }
    func testMissedRunRequiresReviewAndCannotOverloadAnotherWeek() throws {
        let block = try RunTrainingBlockRules.make(brief: brief(), strengthDays: [], now: start)
        let slot = block.slots[0]
        let frozen = try PlanFingerprint.make(block)
        let missedNow = date(8)
        XCTAssertNil(slot.outcome)
        let futureEasy = block.slots.first { $0.weekIndex == 1 && $0.role == .easy }!
        let opened = try RunTrainingBlockRules.review(block: block, slotID: futureEasy.id, adjustment: .skip,
            ownerID: "owner", strengthDays: [], now: missedNow).after
        let missedLong = block.slots.first { $0.weekIndex == 0 && $0.role == .long }!
        XCTAssertThrowsError(try RunTrainingBlockRules.review(block: opened, slotID: missedLong.id, adjustment: .move(futureEasy.day),
            ownerID: "owner", strengthDays: [], now: date(7))) { error in
            guard case RunTrainingBlockError.overload = error else { return XCTFail("Expected workload rejection, received \(error)") }
        }
        let skipped = try RunTrainingBlockRules.review(block: block, slotID: slot.id, adjustment: .skip,
            ownerID: "owner", strengthDays: [], now: missedNow)
        XCTAssertEqual(skipped.after.slots[0].outcome?.state, .skipped)
        XCTAssertEqual(skipped.after.slots.dropFirst(), block.slots.dropFirst())
        XCTAssertEqual(try PlanFingerprint.make(block), frozen)
    }
    func testMoveReviewsCollisionsAndShorteningKeepsOtherIdentities() throws {
        let block = try RunTrainingBlockRules.make(brief: brief(), strengthDays: [], now: start)
        let slot = block.slots[0]
        XCTAssertThrowsError(try RunTrainingBlockRules.review(block: block, slotID: slot.id, adjustment: .move(block.slots[1].day),
            ownerID: "owner", strengthDays: [], now: start))
        let shorter = try RunTrainingBlockRules.review(block: block, slotID: slot.id, adjustment: .shorten(minutes: 10),
            ownerID: "owner", strengthDays: [], now: start)
        XCTAssertEqual(shorter.after.slots[0].plannedMinutes, 10)
        XCTAssertEqual(shorter.after.slots.dropFirst(), block.slots.dropFirst())
        XCTAssertEqual(shorter.after.slots[0].id, slot.id)
        XCTAssertNotEqual(shorter.after.slots[0].revisionID, slot.revisionID)
        var stronger = shorter.after; stronger.weeklyMinuteCeilings[0] += 100
        XCTAssertThrowsError(try RunTrainingBlockRules.validateChange(from: block, to: stronger, strengthDays: [], otherCommitments: [], now: start))
    }
    func testLighterWeekPreservesRecordedAndStartedPrescriptions() throws {
        var block = try RunTrainingBlockRules.make(brief: brief(), strengthDays: [], now: start)
        block.slots[0].outcome = .init(state: .recorded, recordingID: "accepted", acceptedAt: start, movingSeconds: 900)
        let before = block.slots[0]
        let reviewed = try RunTrainingBlockRules.review(block: block, slotID: block.slots[1].id, adjustment: .lighterWeek(0),
            ownerID: "owner", strengthDays: [], now: start)
        XCTAssertEqual(reviewed.after.slots[0], before)
        XCTAssertLessThan(reviewed.after.slots[1].plannedMinutes, block.slots[1].plannedMinutes)
        XCTAssertThrowsError(try RunTrainingBlockRules.review(block: block, slotID: block.slots[0].id, adjustment: .skip,
            ownerID: "owner", strengthDays: [], now: start))
    }
}

@MainActor final class RunTrainingBlockStoreTests: XCTestCase {
    private func setupStore() throws -> (RunTrainingBlockStore, EditorDraftStore, MockAuthService, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("run-block-test-" + UUID().uuidString)
        let auth = MockAuthService(); auth.currentUserID = "block-owner"
        DIContainer.shared.authService = auth
        let editor = EditorDraftStore(directory: directory)
        return (.init(store: editor, auth: auth), editor, auth, directory)
    }
    private var start: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000)) }
    private func adopt(_ store: RunTrainingBlockStore) throws -> (RunTrainingBlock, RunTrainingBlockChange) {
        let brief = RunTrainingBlockBrief(start: start, recentWeeklyMinutes: 60, recentLongestMinutes: 30)
        let block = try RunTrainingBlockRules.make(brief: brief, strengthDays: [], now: start)
        let review = RunTrainingBlockChange(ownerID: "block-owner", before: nil, after: block, explanation: "Reviewed fixture")
        try store.stage(review, userID: "block-owner")
        return (try store.accept(review, userID: "block-owner", strengthDays: [], now: start), review)
    }
    private func completedRun(context: RunScheduledContext, recordingID: String = "recording", id: String = "local-run") -> Run {
        var run = Run(id: id, source: .recorded, startDate: start, endDate: start.addingTimeInterval(900), distanceMeters: 2_000,
            movingSeconds: 900, recordingID: recordingID)
        run.scheduledContext = context; return run
    }
    func testAcceptedReplayCannotRevertCompletionAndHealthAliasDoesNotCompleteTwice() throws {
        let (store, _, _, directory) = try setupStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let (block, adoption) = try adopt(store)
        let context = RunScheduledContext(commitment: block.commitment(for: block.slots[0])!)
        try store.recordStarted(context: context, recordingID: "recording", userID: "block-owner", now: start)
        try store.recordCompleted(run: completedRun(context: context), userID: "block-owner", now: start.addingTimeInterval(900))
        let accepted = try store.library(userID: "block-owner").blocks[0]
        try store.recordCompleted(run: completedRun(context: context, id: "health-alias"), userID: "block-owner")
        XCTAssertEqual(try store.library(userID: "block-owner").blocks[0], accepted)
        XCTAssertEqual(try store.accept(adoption, userID: "block-owner", strengthDays: [], now: start), accepted)
        XCTAssertEqual(accepted.slots[0].outcome?.prescription?.plan, block.slots[0].plan)
        XCTAssertEqual(accepted.slots[0].outcome?.state, .recorded)
        XCTAssertFalse(try store.commitments(userID: "block-owner").contains { $0.id == block.slots[0].id })
    }
    func testStaleReviewCannotOverwriteStartedSessionAndExplicitAbandonKeepsAttempt() throws {
        let (store, _, _, directory) = try setupStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let (block, _) = try adopt(store)
        let slot = block.slots[0], context = RunScheduledContext(commitment: block.commitment(for: block.slots[0])!)
        let change = try RunTrainingBlockRules.review(block: block, slotID: slot.id, adjustment: .shorten(minutes: 10),
            ownerID: "block-owner", strengthDays: [], now: start)
        try store.stage(change, userID: "block-owner")
        try store.recordStarted(context: context, recordingID: "attempt", userID: "block-owner", now: start)
        XCTAssertThrowsError(try store.accept(change, userID: "block-owner", strengthDays: [], now: start))
        try store.recordAbandoned(context: context, recordingID: "attempt", userID: "block-owner", now: start)
        let value = try store.library(userID: "block-owner")
        XCTAssertNil(value.blocks[0].slots[0].outcome)
        XCTAssertEqual(value.blocks[0].slots[0].plan, slot.plan)
        XCTAssertEqual(value.abandonedAttempts.count, 1)
        XCTAssertEqual(value.abandonedAttempts[0].recordingID, "attempt")
    }
    func testAccountSwitchAndNewerLibraryPreserveData() throws {
        let (store, editor, auth, directory) = try setupStore(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try adopt(store)
        let original = try PlanFingerprint.make(store.library(userID: "block-owner"))
        auth.currentUserID = "other-owner"
        XCTAssertThrowsError(try store.library(userID: "block-owner"))
        XCTAssertTrue(try store.library(userID: "other-owner").blocks.isEmpty)
        auth.currentUserID = "block-owner"
        XCTAssertEqual(try PlanFingerprint.make(store.library(userID: "block-owner")), original)
        var newer = try store.library(userID: "block-owner"); newer.schemaVersion = 2
        try editor.save(newer, userID: "block-owner", scope: "run-training-block-library-v1")
        XCTAssertThrowsError(try store.saveBrief(.init(), userID: "block-owner"))
        XCTAssertEqual(try editor.load(RunTrainingBlockLibrary.self, userID: "block-owner", scope: "run-training-block-library-v1")?.value.schemaVersion, 2)
    }
    func testCalendarProjectionKeepsIndependentRunsAndBlocksGenericDeletion() throws {
        let (store, editor, _, directory) = try setupStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let (block, _) = try adopt(store)
        let commitments = TrainingRunCommitmentStore(store: editor)
        let independent = TrainingRunCommitment(id: "one-off", date: start, plan: RunWorkoutPlan.builtinTemplates(metric: true)[0])
        try commitments.save(independent, userID: "block-owner")
        XCTAssertEqual(try commitments.entries(userID: "block-owner").count, block.slots.count + 1)
        XCTAssertThrowsError(try commitments.remove(id: block.slots[0].id, userID: "block-owner"))
        try commitments.remove(id: independent.id, userID: "block-owner")
        XCTAssertEqual(try commitments.entries(userID: "block-owner").count, block.slots.count)
    }
}
