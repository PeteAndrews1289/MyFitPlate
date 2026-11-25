import XCTest
@testable import MyFitPlateCore

@MainActor final class TrainingFuelLibraryTests: XCTestCase {
    private var directories: [URL] = []
    private var defaultsSuites: [String] = []
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))! }
    private var now: Date { day.addingTimeInterval(12 * 3_600) }
    private var goals: TodayFuelPlanGoals { .init(calories: 2_500, protein: 150, carbs: 300, fats: 80) }
    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        defaultsSuites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    func testMultipleSessionsPreserveHistoryAndReserveOneDailyBudget() throws {
        let (store, _, _) = fixture()
        let first = plan(id: "morning", hour: 15)
        let second = plan(id: "evening", hour: 19)
        XCTAssertTrue(store.confirm(first, for: "owner"))
        let adjusted = store.availableGoals(for: second.draft, today: DailyLog(date: day, meals: []), goals: goals, now: now, calendar: calendar)
        XCTAssertLessThan(adjusted.calories, goals.calories)
        XCTAssertLessThan(adjusted.protein, goals.protein)
        XCTAssertTrue(store.confirm(second, for: "owner"))
        XCTAssertEqual(Set(store.history.map { $0.plan.id }), ["morning", "evening"])
        try store.select(planID: first.id, for: "owner")
        XCTAssertTrue(store.clear(for: "owner"))
        XCTAssertEqual(store.history.count, 2)
        XCTAssertNotNil(store.history.first { $0.plan.id == first.id }?.archivedAt)
        XCTAssertEqual(store.history.first { $0.plan.id == second.id }?.plan.allocations, second.allocations)
    }

    func testShrinkingBudgetPrioritizesEarlierSessionWithoutCircularReservations() throws {
        let (store, _, _) = fixture()
        let first = plan(id: "earlier", hour: 15)
        let second = plan(id: "later", hour: 19)
        XCTAssertTrue(store.confirm(second, for: "owner")); XCTAssertTrue(store.confirm(first, for: "owner"))
        let log = DailyLog(date: day, meals: [.init(name: "Lunch", foodItems: [.init(name: "Unrelated meal", calories: 2_200)])])
        let earlierGoals = store.availableGoals(for: first.draft, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertEqual(earlierGoals, goals, "A later plan never blocks the earlier session")
        let early = store.progress(for: first, today: log, goals: goals, now: now, calendar: calendar)
        let late = store.progress(for: second, today: log, goals: goals, now: now, calendar: calendar)
        let earlyCalories = early.phases.reduce(0) { $0 + ($1.actionableProteinGrams + $1.actionableCarbGrams) * 4 }
        let lateCalories = late.phases.reduce(0) { $0 + ($1.actionableProteinGrams + $1.actionableCarbGrams) * 4 }
        XCTAssertGreaterThan(earlyCalories, 0)
        XCTAssertLessThanOrEqual(earlyCalories + lateCalories, 300)
        let target = try store.makeTarget(planID: first.id, phase: .beforeTraining, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertGreaterThan(target.calories, 0)
    }

    func testHistoricalAttributionCorrectionDoesNotReopenClosedPlan() throws {
        let (store, _, _) = fixture()
        var original = plan(id: "closed", hour: 15)
        let food = FoodItem(id: "kept-diary-food", name: "Rice", protein: 5, carbs: 30)
        let link = TrainingFuelFoodLink(requestID: "reviewed", food: food, day: TrainingCalendarDay(day, calendar: calendar), phase: .beforeTraining, at: now)
        original.foodLinks = [link]
        XCTAssertTrue(store.confirm(original, for: "owner")); XCTAssertTrue(store.clear(for: "owner"))
        let closedAt = try XCTUnwrap(store.history.first?.archivedAt)
        try store.unlinkFood(planID: original.id, linkID: link.id, for: "owner")
        XCTAssertEqual(store.history.first?.archivedAt, closedAt)
        XCTAssertEqual(store.history.first?.plan.foodLinks, [])
        XCTAssertNil(store.confirmedPlan, "A reporting correction cannot reactivate guidance")
    }

    func testMigrationKeepsExactPlanAndFoodIDsAndDoesNotReimportAfterClosure() throws {
        let (store, disk, defaults) = fixture()
        var original = plan(id: "legacy", hour: 15)
        let food = FoodItem(id: "old-food", name: "Rice", protein: 3, carbs: 30)
        original.foodLinks = [.init(requestID: "old-request", food: food, day: TrainingCalendarDay(day, calendar: calendar), phase: .beforeTraining, at: now)]
        try disk.save(original, userID: "owner", scope: "training-fuel-confirmed-plan")
        store.load(for: "owner", now: now, calendar: calendar)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history[0].plan.id, original.id)
        XCTAssertEqual(store.history[0].plan.foodLinks, original.foodLinks)
        try store.select(planID: original.id, for: "owner")
        XCTAssertTrue(store.clear(for: "owner"))
        let reopened = TrainingFuelPlanStore(userDefaults: defaults, draftStore: disk)
        reopened.load(for: "owner", now: now, calendar: calendar)
        XCTAssertNil(reopened.confirmedPlan)
        XCTAssertEqual(reopened.history.count, 1)
        XCTAssertNotNil(reopened.history[0].archivedAt)
        XCTAssertNotNil(try disk.load(TrainingFuelConfirmedPlan.self, userID: "owner", scope: "training-fuel-confirmed-plan"))
    }

    func testExplicitFoodReceiptsIgnoreUnrelatedFoodAndTrackCorrectionAndDeletion() throws {
        let (store, _, _) = fixture()
        XCTAssertTrue(store.confirm(plan(id: "session", hour: 15), for: "owner"))
        let empty = DailyLog(date: day, meals: [])
        let target = try store.makeTarget(planID: "session", phase: .beforeTraining, today: empty, goals: goals, now: now, calendar: calendar)
        let linked = FoodItem(id: "accepted-food", name: "Yogurt", calories: 160, protein: 15, carbs: 25, timestamp: now)
        let unrelated = FoodItem(id: "unrelated-food", name: "Lunch", calories: 400, protein: 40, carbs: 60, timestamp: now)
        try store.stageFoodLink(target: target, foods: [linked], date: day, today: empty, goals: goals, userID: "owner", now: now)
        XCTAssertTrue(store.acceptFoodLink(target: target, foods: [linked], userID: "owner"))
        XCTAssertTrue(store.acceptFoodLink(target: target, foods: [linked], userID: "owner"))
        let saved = try XCTUnwrap(store.history.first?.plan)
        XCTAssertEqual(saved.foodLinks?.count, 1)
        var log = DailyLog(date: day, meals: [Meal(name: "Lunch", foodItems: [linked, unrelated])])
        var progress = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertEqual(progress.phases.first?.loggedProteinGrams, 10, "Progress stops at the original 10g phase allocation; the receipt retains the actual 15g")
        log.meals[0].foodItems[0].protein = 5
        progress = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertEqual(progress.phases.first?.loggedProteinGrams, 5)
        log.meals[0].foodItems.removeFirst()
        progress = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertEqual(progress.phases.first?.loggedProteinGrams, 0)
        XCTAssertEqual(saved.foodLinks?.first?.protein, 15)
    }

    func testHandoffRejectsAccountDayAndChangedBudgetWithoutCreatingLinks() throws {
        let (store, _, _) = fixture()
        XCTAssertTrue(store.confirm(plan(id: "session", hour: 15), for: "owner"))
        let log = DailyLog(date: day, meals: [])
        let target = try store.makeTarget(planID: "session", phase: .beforeTraining, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertThrowsError(try store.validateTarget(target, day: day, today: log, goals: goals, userID: "other", now: now, calendar: calendar))
        XCTAssertThrowsError(try store.validateTarget(target, day: day.addingTimeInterval(86_400), today: log, goals: goals, userID: "owner", now: now, calendar: calendar))
        let crowded = DailyLog(date: day, meals: [.init(name: "Dinner", foodItems: [.init(name: "Food", calories: 2_490, protein: 149, carbs: 299)])])
        XCTAssertThrowsError(try store.validateTarget(target, day: day, today: crowded, goals: goals, userID: "owner", now: now, calendar: calendar))
        XCTAssertEqual(store.history[0].plan.foodLinks?.count, 0)
    }

    func testAcceptedReceiptAfterInterveningEditReplaysWithoutChangingFoodIDs() throws {
        let (store, disk, defaults) = fixture()
        XCTAssertTrue(store.confirm(plan(id: "session", hour: 15), for: "owner"))
        let log = DailyLog(date: day, meals: [])
        let target = try store.makeTarget(planID: "session", phase: .beforeTraining, today: log, goals: goals, now: now, calendar: calendar)
        let food = FoodItem(id: "receipt", name: "Meal", calories: 160, protein: 15, carbs: 25)
        try store.stageFoodLink(target: target, foods: [food], date: day, today: log, goals: goals, userID: "owner", now: now)
        var latest = try XCTUnwrap(store.history.first?.plan); latest.feedback = .init(energy: 3, comfort: 4, practicality: 4)
        XCTAssertTrue(store.confirm(latest, for: "owner"))
        XCTAssertTrue(store.acceptFoodLink(target: target, foods: [food], userID: "owner"))
        let reopened = TrainingFuelPlanStore(userDefaults: defaults, draftStore: disk)
        reopened.load(for: "owner", now: now, calendar: calendar)
        XCTAssertTrue(reopened.acceptFoodLink(target: target, foods: [food], userID: "owner"))
        XCTAssertEqual(reopened.history[0].plan.foodLinks?.map(\.foodID), [food.id])
        XCTAssertEqual(reopened.history[0].plan.feedback?.comfort, 4)
    }

    func testExactStrengthSlotDisambiguatesSameRoutineAndWrongProgram() throws {
        let (store, _, _) = fixture()
        func candidate(_ slot: Int) -> TrainingFuelSessionCandidate {
            TrainingFuelSessionCandidate(id: "strength\(slot)", source: .activeStrengthProgram, sourceID: "program", sessionReferenceID: "repeat",
                title: "Repeat", detail: "Scheduled", kind: .strength, scheduledDay: day, suggestedDurationMinutes: 45,
                suggestedIntensity: .moderate, suggestedStrengthFocus: .fullBody, assumptions: [], identity: .init(programID: "program", programSlot: slot))
        }
        let first = plan(id: "slot4", hour: 15, candidate: candidate(4))
        let second = plan(id: "slot5", hour: 17, candidate: candidate(5))
        XCTAssertTrue(store.confirm(first, for: "owner")); XCTAssertTrue(store.confirm(second, for: "owner"))
        let end = day.addingTimeInterval(16 * 3_600)
        var session = WorkoutSessionLog(id: "accepted", date: end, routineID: "repeat", completedExercises: [], programContext: .init(programID: "wrong", slotIndex: 4))
        XCTAssertFalse(store.recordStrengthCompletion(routineID: "repeat", routineName: "Repeat", completedAt: end, today: nil, goals: goals, for: "owner", calendar: calendar, session: session))
        session.programContext = .init(programID: "program", slotIndex: 4)
        XCTAssertTrue(store.recordStrengthCompletion(routineID: "repeat", routineName: "Repeat", completedAt: end, today: nil, goals: goals, for: "owner", calendar: calendar, session: session))
        XCTAssertNotNil(store.history.first { $0.plan.id == first.id }?.plan.outcome)
        XCTAssertNil(store.history.first { $0.plan.id == second.id }?.plan.outcome)
        XCTAssertFalse(store.recordStrengthCompletion(routineID: "repeat", routineName: "Repeat", completedAt: end, today: nil, goals: goals, for: "owner", calendar: calendar, session: session))
    }

    func testManualUndoIsConditionalAndDoesNotRewriteFoodLinks() throws {
        let (store, _, _) = fixture()
        XCTAssertTrue(store.confirm(plan(id: "manual", hour: 15), for: "owner"))
        let end = day.addingTimeInterval(16 * 3_600)
        XCTAssertTrue(store.markCurrentPlanCompleted(at: end, today: DailyLog(date: day, meals: []), goals: goals, for: "owner", calendar: calendar))
        let revision = try XCTUnwrap(store.history.first)
        try store.undoManualOutcome(planID: revision.plan.id, revisionID: revision.id, for: "owner")
        XCTAssertNil(store.history.first?.plan.outcome)
        XCTAssertThrowsError(try store.undoManualOutcome(planID: revision.plan.id, revisionID: revision.id, for: "owner"))
        XCTAssertEqual(store.history.first?.plan.foodLinks, revision.plan.foodLinks)
    }

    func testConcurrentOfflineOutcomesRemainConflictUntilReviewed() async throws {
        let repository = FuelTestRepository()
        let (first, _, _) = fixture(repository: repository)
        let (second, _, _) = fixture(repository: repository)
        XCTAssertTrue(first.confirm(plan(id: "shared", hour: 15), for: "owner"))
        await first.synchronize()
        second.load(for: "owner", now: now, calendar: calendar); await second.synchronize()
        repository.offline = true
        let end = day.addingTimeInterval(16 * 3_600)
        XCTAssertTrue(first.markCurrentPlanCompleted(at: end, today: nil, goals: goals, for: "owner", calendar: calendar))
        XCTAssertTrue(second.markCurrentPlanSkipped(at: end, today: nil, for: "owner", calendar: calendar))
        repository.offline = false
        await first.synchronize(); await second.synchronize(); await first.synchronize()
        XCTAssertEqual(first.conflictingPlanIDs, ["shared"])
        XCTAssertEqual(first.revisions(planID: "shared").count, 2)
        XCTAssertEqual(first.revisions(planID: "shared"), second.revisions(planID: "shared"))
        let chosen = try XCTUnwrap(first.revisions(planID: "shared").first { $0.plan.outcome?.status == .completed })
        try first.resolve(planID: "shared", choosing: chosen.id, for: "owner")
        await first.synchronize(); await second.synchronize()
        XCTAssertTrue(second.conflictingPlanIDs.isEmpty)
        XCTAssertEqual(second.history.first?.plan.outcome?.status, .completed)
        XCTAssertGreaterThan(repository.state.revisions.count, 3)
    }

    func testNewerLibraryCannotBeOverwritten() throws {
        let (store, disk, _) = fixture()
        var checkpoint = TrainingFuelLibraryCheckpoint(); checkpoint.schemaVersion = 99
        try disk.save(checkpoint, userID: "owner", scope: "training-fuel-library-v1")
        store.load(for: "owner", now: now, calendar: calendar)
        XCTAssertFalse(store.confirm(plan(id: "new", hour: 15), for: "owner"))
        XCTAssertEqual(try disk.load(TrainingFuelLibraryCheckpoint.self, userID: "owner", scope: "training-fuel-library-v1")?.value.schemaVersion, 99)
    }

    func testAbandonedPreflightCannotAcquireFuelAttributionFromIndependentFoodSave() throws {
        let (store, _, _) = fixture()
        let original = plan(id: "staged-only", hour: 15)
        XCTAssertTrue(store.confirm(original, for: "owner"))
        let target = try store.makeTarget(planID: original.id, phase: .beforeTraining, today: DailyLog(date: day, meals: []), goals: goals, now: now, calendar: calendar)
        let food = FoodItem(id: "same-food-id", name: "Rice", calories: 200, protein: 4, carbs: 40, fats: 2)
        try store.stageFoodLink(target: target, foods: [food], date: day, today: DailyLog(date: day, meals: []), goals: goals,
            userID: "owner", now: now, requiresSubmissionAuthorization: true)
        // The diary editor fails to checkpoint submission, then the user detaches Fuel.
        // Logging that exact food independently must not complete the abandoned preflight.
        let acceptedDiary = DailyLog(date: day, meals: [.init(name: "Lunch", foodItems: [food])])
        store.reconcileFoodLinks(with: acceptedDiary, for: "owner")
        XCTAssertTrue(store.history.first?.plan.foodLinks?.isEmpty ?? true)
        XCTAssertEqual(store.checkpoint.pendingLinks?.values.first?.submissionAuthorized, false)
    }

    func testDurableSubmissionAuthorizesExactOriginalPayloadDespiteLaterBudgetChange() throws {
        let (store, _, _) = fixture()
        let original = plan(id: "submitted", hour: 15)
        XCTAssertTrue(store.confirm(original, for: "owner"))
        let target = try store.makeTarget(planID: original.id, phase: .beforeTraining, today: DailyLog(date: day, meals: []), goals: goals, now: now, calendar: calendar)
        let food = FoodItem(id: "frozen-food", name: "Rice", calories: 200, protein: 4, carbs: 40, fats: 2)
        try store.stageFoodLink(target: target, foods: [food], date: day, today: DailyLog(date: day, meals: []), goals: goals,
            userID: "owner", now: now, requiresSubmissionAuthorization: true)
        var revised = food; revised.calories = 999
        XCTAssertThrowsError(try store.authorizeFoodLink(target: target, foods: [revised], userID: "owner"))
        XCTAssertThrowsError(try store.authorizeFoodLink(target: target, foods: [food], userID: "another-owner"))
        XCTAssertTrue(store.markCurrentPlanSkipped(at: now, today: nil, for: "owner", calendar: calendar))
        try store.authorizeFoodLink(target: target, foods: [food], userID: "owner")
        try store.authorizeFoodLink(target: target, foods: [food], userID: "owner")
        store.reconcileFoodLinks(with: DailyLog(date: day, meals: [.init(name: "Lunch", foodItems: [food])]), for: "owner")
        XCTAssertEqual(store.history.first?.plan.foodLinks?.map(\.foodID), [food.id])
        XCTAssertEqual(store.history.first?.plan.foodLinks?.first?.requestID, target.context?.requestID)
        XCTAssertEqual(store.history.first?.plan.outcome?.status, .skipped)
    }

    private func fixture(repository: TrainingFuelRepository? = nil) -> (TrainingFuelPlanStore, EditorDraftStore, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fuel-library-\(UUID().uuidString)")
        directories.append(directory)
        let suite = "fuel-library-\(UUID().uuidString)"; defaultsSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        let disk = EditorDraftStore(directory: directory)
        return (TrainingFuelPlanStore(userDefaults: defaults, draftStore: disk, repository: repository), disk, defaults)
    }
    private func plan(id: String, hour: Int, candidate: TrainingFuelSessionCandidate? = nil) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(id: id, candidate: candidate ?? TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            scheduledAt: day.addingTimeInterval(Double(hour) * 3_600), durationMinutes: 45)
        let preview = TrainingFuelPlannerRules.makePlan(session: draft.session, today: DailyLog(date: day, meals: []), goals: goals,
            preference: draft.preference, now: now, calendar: calendar)
        return TrainingFuelConfirmedPlan(draft: draft, plannerPlan: preview, goals: goals, today: DailyLog(date: day, meals: []), confirmedAt: now)
    }
}

@MainActor private final class FuelTestRepository: TrainingFuelRepository {
    var state = TrainingFuelCloudState()
    var offline = false
    func merge(_ state: TrainingFuelCloudState, userID: String) async throws -> TrainingFuelCloudState {
        if offline { throw CocoaError(.fileReadNoPermission) }
        self.state = try self.state.merging(state)
        return self.state
    }
}
