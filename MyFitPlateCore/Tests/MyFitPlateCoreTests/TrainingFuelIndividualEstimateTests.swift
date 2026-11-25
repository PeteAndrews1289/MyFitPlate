import XCTest
@testable import MyFitPlateCore

final class TrainingFuelIndividualEstimateTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 8))! }
    private func session(kind: TrainingFuelSession.Kind = .run, minutes: Int = 90, start: Date? = nil) -> TrainingFuelSession {
        .init(kind: kind, scheduledAt: start ?? now.addingTimeInterval(7_200), expectedDurationMinutes: minutes,
              intensity: .moderate, strengthFocus: .fullBody)
    }
    private func inputs(weight: Double = 75, during: Double? = nil) -> TrainingFuelPersonalInputs {
        .init(adultConfirmed: true, bodyMass: .init(kilograms: weight, measurementID: "measured-weight", measuredAt: now.addingTimeInterval(-86_400), confirmedAt: now),
              tolerance: during == nil ? .noPreference : .practicedDuringRun, duringCarbsPerHour: during)
    }
    private func estimate(_ values: TrainingFuelPersonalInputs, session proposed: TrainingFuelSession? = nil) -> TrainingFuelDemandPreview {
        TrainingFuelIndividualEstimateRules.preview(session: proposed ?? session(), inputs: values, now: now, calendar: calendar)
    }
    func testBodyweightReferenceStaysSeparateFromCommonServingAndRoundsInsideRange() throws {
        for (weight, lower, upper, chosen) in [(50.0, 12.5, 20.0, 13.0), (75, 18.75, 30, 19), (120, 30, 48, 30), (149, 37.25, 59.6, 38)] {
            let value = estimate(inputs(weight: weight))
            XCTAssertEqual(value.bodyMassProteinReference?.lower, lower)
            XCTAssertEqual(try XCTUnwrap(value.bodyMassProteinReference?.upper), upper, accuracy: 0.000001)
            XCTAssertEqual(value.requestedSessionProteinGrams, chosen)
            XCTAssertEqual(value.commonProteinServingReference.lower, 20); XCTAssertEqual(value.commonProteinServingReference.upper, 40)
            XCTAssertFalse(value.requiresReview)
        }
    }
    func testMissingWeightDoesNotUseProfileDefaultAndInvalidSpecifiedEvidenceNeedsReview() {
        let unknown = estimate(.init(adultConfirmed: true))
        XCTAssertNil(unknown.bodyMassProteinReference); XCTAssertNil(unknown.requestedSessionProteinGrams)
        XCTAssertTrue(unknown.rationale.contains(.weightUnknown)); XCTAssertFalse(unknown.requiresReview)
        let badInputs: [TrainingFuelPersonalInputs] = [
            .init(), inputs(weight: .nan), inputs(weight: 0), inputs(weight: 301),
            .init(adultConfirmed: true, bodyMass: .init(kilograms: 75, measurementID: "", measuredAt: now, confirmedAt: now)),
            .init(adultConfirmed: true, bodyMass: .init(kilograms: 75, measurementID: "future", measuredAt: now.addingTimeInterval(1), confirmedAt: now)),
            .init(adultConfirmed: true, bodyMass: .init(kilograms: 75, measurementID: "stale", measuredAt: now.addingTimeInterval(-31 * 86_400), confirmedAt: now)),
            .init(adultConfirmed: true, bodyMass: .init(kilograms: 75, measurementID: "confirmation", measuredAt: now.addingTimeInterval(-3 * 86_400), confirmedAt: now.addingTimeInterval(-2 * 86_400)))
        ]
        for input in badInputs { let value = estimate(input); XCTAssertTrue(value.requiresReview); XCTAssertNil(value.requestedSessionProteinGrams) }
    }
    func testMealTimingToleranceAndStrengthFocusDoNotInventProteinDoseMultipliers() {
        let original = inputs()
        var changed = original; changed.lastMealAt = now.addingTimeInterval(-3_600); changed.tolerance = .lighterFoods
        XCTAssertEqual(estimate(original).requestedSessionProteinGrams, estimate(changed, session: session(kind: .strength, minutes: 30)).requestedSessionProteinGrams)
        XCTAssertTrue(estimate(changed).rationale.contains(.recentMealReviewed))
        XCTAssertTrue(estimate(changed).rationale.contains(.lighterFoodPreference))
        var requested = original; requested.reviewedProteinGrams = 29
        XCTAssertEqual(estimate(requested).requestedSessionProteinGrams, 29)
        requested.reviewedProteinGrams = 99
        XCTAssertTrue(estimate(requested).requiresReview)
    }
    func testPracticedDuringRateUsesDurationAndNeverDefaultsToNinetyGramsPerHour() throws {
        for (rate, grams) in [(30.0, 45.0), (45, 67.5), (60, 90)] {
            let value = estimate(inputs(during: rate))
            XCTAssertEqual(value.requestedDuringCarbGrams, grams)
            XCTAssertEqual(value.duringHourlyReference?.lower, 30); XCTAssertEqual(value.duringHourlyReference?.upper, 60)
            XCTAssertFalse(value.requiresReview)
        }
        XCTAssertNil(estimate(inputs()).requestedDuringCarbGrams)
        for minutes in [74, 151, Int.max] {
            XCTAssertTrue(estimate(inputs(during: 30), session: session(minutes: minutes)).requiresReview)
        }
        for minutes in [75, 150] { XCTAssertNotNil(estimate(inputs(during: 30), session: session(minutes: minutes)).requestedDuringCarbGrams) }
        XCTAssertTrue(estimate(inputs(during: 90)).requiresReview)
        var unpracticed = inputs(during: 30); unpracticed.tolerance = .noPreference
        XCTAssertTrue(estimate(unpracticed).requiresReview)
        XCTAssertTrue(estimate(inputs(during: 30), session: session(kind: .strength)).requiresReview)
    }
    func testOvernightDuringChoiceRequiresSeparateDayEvidenceWithoutChangingBeforeAfter() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23))!
        let value = estimate(inputs(during: 45), session: session(start: late))
        XCTAssertTrue(value.requiresReview); XCTAssertNil(value.requestedDuringCarbGrams)
        XCTAssertEqual(value.requestedSessionProteinGrams, 19)
        XCTAssertTrue(value.rationale.contains(.duringNeedsSeparateDayEvidence))
    }
    func testBodyweightAndDuringBoundaryCorpusIsFiniteAndWithinReferences() throws {
        for mass in stride(from: 30.0, through: 300, by: 3.5) {
            for duration in [75, 90, 120, 150] {
                for rate in [30.0, 45, 60] {
                    let value = estimate(inputs(weight: mass, during: rate), session: session(minutes: duration))
                    let selected = try XCTUnwrap(value.requestedSessionProteinGrams), range = try XCTUnwrap(value.bodyMassProteinReference)
                    XCTAssertTrue(selected.isFinite); XCTAssertTrue((range.lower...range.upper).contains(selected))
                    XCTAssertEqual(try XCTUnwrap(value.requestedDuringCarbGrams), rate * Double(duration) / 60, accuracy: 0.000001)
                    XCTAssertFalse(value.requiresReview)
                }
            }
        }
    }
    func testWholePlanConservesOneChosenProteinAmountAndCarbsAcrossPhases() {
        let goals = TodayFuelPlanGoals(calories: 3_000, protein: 200, carbs: 400, fats: 100)
        for weight in [30.0, 50, 75, 120, 149] {
            let personal = inputs(weight: weight, during: 45)
            let plan = TrainingFuelPlannerRules.makePlan(session: session(), today: DailyLog(date: now, meals: []), goals: goals,
                preference: .init(personalInputs: personal), now: now, calendar: calendar)
            XCTAssertEqual(plan.allocatedProteinGrams, Int(ceil(0.25 * weight)))
            XCTAssertEqual(plan.allocation(for: .duringTraining)?.carbGrams, 67)
            XCTAssertTrue(plan.staysInsideDailyTargets)
            XCTAssertLessThanOrEqual(plan.allocatedCarbGrams, 68, "During carbs are a part of, not an addition to, the session estimate.")
        }
    }
    func testAllDailyBudgetsAreConservedAndReferencesRemainVisibleWhenAllocationShrinks() {
        let personal = inputs(weight: 75, during: 60)
        let demand = estimate(personal)
        for calories in [0.0, 60, 100, 200, 500, 1_000] {
            for protein in [0.0, 5, 15, 100] {
                for carbs in [0.0, 5, 25, 200] {
                    let plan = TrainingFuelPlannerRules.makePlan(session: session(), today: DailyLog(date: now, meals: []),
                        goals: .init(calories: calories, protein: protein, carbs: carbs, fats: 0), preference: .init(personalInputs: personal), now: now, calendar: calendar)
                    XCTAssertTrue(plan.staysInsideDailyTargets)
                    XCTAssertGreaterThanOrEqual(plan.allocatedCalories, 0)
                }
            }
        }
        XCTAssertEqual(demand.requestedDuringCarbGrams, 90)
        XCTAssertEqual(demand.requestedSessionProteinGrams, 19)
    }
    func testOvernightRecoverySharesOriginalDemandAcrossDaysWithoutASecondServing() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 30))!
        let draft = TrainingFuelPlanDraft(candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .run), scheduledAt: start,
            durationMinutes: 90, preference: .init(personalInputs: inputs()))
        let goals = TodayFuelPlanGoals(calories: 3_000, protein: 200, carbs: 400, fats: 100)
        let initial = TrainingFuelPlannerRules.makePlan(session: draft.session, today: DailyLog(date: now, meals: []),
            goals: goals, preference: draft.preference, now: now, calendar: calendar)
        XCTAssertEqual(initial.allocation(for: .beforeTraining)?.proteinGrams, 10)
        XCTAssertNil(initial.allocation(for: .afterTraining))
        let saved = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: initial, goals: goals, today: nil, confirmedAt: now, calendar: calendar)
        let end = start.addingTimeInterval(5_400), nextDay = calendar.startOfDay(for: end)
        let recovery = TrainingFuelDeferredRecoveryRules.makePlan(for: saved, today: DailyLog(date: nextDay, meals: []),
            goals: goals, completedAt: end, calendar: calendar)
        XCTAssertEqual(recovery.allocation(for: .afterTraining)?.proteinGrams, 9)
        XCTAssertEqual(initial.allocatedProteinGrams + recovery.allocatedProteinGrams, 19)
        XCTAssertLessThanOrEqual(Double(initial.allocatedCarbGrams + recovery.allocatedCarbGrams), try XCTUnwrap(saved.calculation?.individualEstimate?.appEstimatedCarbTotal))
        XCTAssertTrue(recovery.staysInsideDailyTargets)
    }

    func testLateActualEndDoesNotRepeatAlreadyPlannedDuringCarbohydrate() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 22))!
        let draft = TrainingFuelPlanDraft(candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .run), scheduledAt: start,
            durationMinutes: 90, preference: .init(personalInputs: inputs(during: 45)))
        let goals = TodayFuelPlanGoals(calories: 3_000, protein: 200, carbs: 400, fats: 100)
        let initial = TrainingFuelPlannerRules.makePlan(session: draft.session, today: DailyLog(date: now, meals: []),
            goals: goals, preference: draft.preference, now: now, calendar: calendar)
        let saved = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: initial, goals: goals, today: nil, confirmedAt: now, calendar: calendar)
        let actualEnd = start.addingTimeInterval(10_800)
        let recovery = TrainingFuelDeferredRecoveryRules.makePlan(for: saved, today: DailyLog(date: actualEnd, meals: []),
            goals: goals, completedAt: actualEnd, calendar: calendar)
        XCTAssertEqual(initial.allocation(for: .duringTraining)?.carbGrams, 67)
        XCTAssertEqual(recovery.allocatedCarbGrams, 0)
        XCTAssertEqual(recovery.allocatedProteinGrams, 9)
    }

    func testCalculationReceiptUsesTheReviewedCalendarForOvernightEligibility() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 30))!
        let draft = TrainingFuelPlanDraft(candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .run), scheduledAt: start,
            durationMinutes: 90, preference: .init(personalInputs: inputs(during: 45)))
        let goals = TodayFuelPlanGoals(calories: 3_000, protein: 200, carbs: 400, fats: 100)
        let preview = TrainingFuelPlannerRules.makePlan(session: draft.session, today: DailyLog(date: now, meals: []), goals: goals,
            preference: draft.preference, now: now, calendar: calendar)
        let receipt = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: preview, goals: goals, today: nil, confirmedAt: now, calendar: calendar)
        XCTAssertEqual(receipt.calculation?.calculationTimeZoneIdentifier, calendar.timeZone.identifier)
        XCTAssertTrue(receipt.calculation?.individualEstimate?.requiresReview == true)
        XCTAssertNil(receipt.calculation?.individualEstimate?.requestedDuringCarbGrams)
    }

    func testDuringPhaseOpensOnlyDuringAndLegacyPlanKeepsItsRuleVersion() throws {
        let candidate = TrainingFuelSessionAdapter.manualCandidate(kind: .run)
        let draft = TrainingFuelPlanDraft(candidate: candidate, scheduledAt: now.addingTimeInterval(7_200), durationMinutes: 90,
            preference: .init(personalInputs: inputs(during: 45)))
        let goals = TodayFuelPlanGoals(calories: 3_000, protein: 200, carbs: 400, fats: 100)
        let log = DailyLog(date: now, meals: [])
        let planner = TrainingFuelPlannerRules.makePlan(session: draft.session, today: log, goals: goals, preference: draft.preference, now: now, calendar: calendar)
        let saved = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: planner, goals: goals, today: log, confirmedAt: now)
        let before = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: now, calendar: calendar)
        XCTAssertNil(before.target(for: .duringTraining, plan: saved))
        let middle = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: draft.scheduledAt.addingTimeInterval(600), calendar: calendar)
        XCTAssertNotNil(middle.target(for: .duringTraining, plan: saved))
        let after = TrainingFuelPlanProgressRules.makeProgress(plan: saved, today: log, goals: goals, now: saved.estimatedEndAt.addingTimeInterval(1), calendar: calendar)
        XCTAssertNil(after.target(for: .duringTraining, plan: saved))
        XCTAssertEqual(after.phases.first { $0.allocation.phase == .duringTraining }?.remainingCarbGrams, 0)
        var old = draft; old.preference = .init()
        let legacyPlan = TrainingFuelPlannerRules.makePlan(session: old.session, today: log, goals: goals, now: now, calendar: calendar)
        let legacy = TrainingFuelConfirmedPlan(draft: old, plannerPlan: legacyPlan, goals: goals, today: log, confirmedAt: now)
        XCTAssertEqual(legacy.calculation?.ruleset, "bounded-daily-budget-v1")
        XCTAssertNil(legacy.calculation?.individualEstimate)
        XCTAssertNil(legacyPlan.allocation(for: .duringTraining))
        let restored = try JSONDecoder().decode(TrainingFuelConfirmedPlan.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(try PlanFingerprint.make(restored), try PlanFingerprint.make(legacy))
    }
}

@MainActor final class TrainingFuelIndividualPersistenceTests: XCTestCase {
    private var directory: URL!
    private var disk: EditorDraftStore!
    private var defaults: UserDefaults!
    private var defaultsName: String!
    private var auth: MockAuthService!
    private let owner = "individual-fuel-owner"
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 8))! }
    private var goals: TodayFuelPlanGoals { .init(calories: 3_000, protein: 200, carbs: 400, fats: 100) }
    private var diary: DailyLog { .init(date: now, meals: []) }
    override func setUp() {
        super.setUp(); directory = FileManager.default.temporaryDirectory.appendingPathComponent("fuel-individual-\(UUID())")
        disk = EditorDraftStore(directory: directory); defaultsName = "fuel-individual-\(UUID())"; defaults = UserDefaults(suiteName: defaultsName)
        auth = MockAuthService(); auth.currentUserID = owner
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: defaultsName)
        super.tearDown()
    }
    private func store() -> TrainingFuelPlanStore {
        let result = TrainingFuelPlanStore(userDefaults: defaults, draftStore: disk, auth: auth)
        result.load(for: owner, now: now, calendar: calendar); return result
    }
    private func input(weight: Double = 75, adult: Bool = true) -> TrainingFuelPersonalInputs {
        .init(adultConfirmed: adult, bodyMass: .init(kilograms: weight, measurementID: "weight-source", measuredAt: now.addingTimeInterval(-86_400), confirmedAt: now),
              tolerance: .practicedDuringRun, duringCarbsPerHour: 45)
    }
    private func plan(id: String, personal: TrainingFuelPersonalInputs?, existing: TrainingFuelConfirmedPlan? = nil) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(id: id, candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .run),
            scheduledAt: now.addingTimeInterval(7_200), durationMinutes: 90, preference: .init(personalInputs: personal))
        let preview = TrainingFuelPlannerRules.makePlan(session: draft.session, today: diary, goals: goals, preference: draft.preference, now: now, calendar: calendar)
        return TrainingFuelConfirmedPlan(draft: draft, plannerPlan: preview, goals: goals, today: diary, existingPlan: existing, confirmedAt: now)
    }
    func testV2IntroductionVersionsContainerAndRetainsEveryLegacyRevisionAfterReload() throws {
        let library = store()
        XCTAssertTrue(library.confirm(plan(id: "legacy", personal: nil), for: owner))
        let old = try XCTUnwrap(library.history.first), oldFingerprint = try PlanFingerprint.make(old)
        let initial = try XCTUnwrap(disk.load(TrainingFuelLibraryCheckpoint.self, userID: owner, scope: "training-fuel-library-v1"))
        XCTAssertEqual(initial.value.schemaVersion, 1)
        XCTAssertTrue(library.confirm(plan(id: "individual", personal: input()), for: owner))
        let current = try XCTUnwrap(disk.load(TrainingFuelLibraryCheckpoint.self, userID: owner, scope: "training-fuel-library-v1"))
        XCTAssertEqual(current.value.schemaVersion, 2); XCTAssertEqual(current.value.state.schemaVersion, 2)
        XCTAssertEqual(try PlanFingerprint.make(current.value.state.revisions[old.id]), oldFingerprint)
        let restored = store()
        XCTAssertEqual(restored.history.count, 2)
        XCTAssertEqual(restored.history.first { $0.plan.id == "legacy" }?.plan.calculation?.ruleset, "bounded-daily-budget-v1")
        XCTAssertEqual(restored.history.first { $0.plan.id == "individual" }?.plan.calculation?.individualEstimate?.requestedSessionProteinGrams, 19)
        XCTAssertEqual(try current.value.state.merging(initial.value.state).schemaVersion, 2)
    }
    func testMissingReviewCannotReplaceAcceptedPlanAndAccountSwitchCannotAdopt() throws {
        let library = store()
        XCTAssertTrue(library.confirm(plan(id: "kept", personal: nil), for: owner))
        let before = try PlanFingerprint.make(library.history)
        XCTAssertFalse(library.confirm(plan(id: "bad", personal: input(adult: false)), for: owner))
        XCTAssertEqual(try PlanFingerprint.make(library.history), before)
        auth.currentUserID = "other"
        XCTAssertFalse(library.confirm(plan(id: "other", personal: input()), for: owner))
        auth.currentUserID = owner
        XCTAssertEqual(try PlanFingerprint.make(store().history), before)
    }
    func testDuringHandoffPreservesExactPhaseDayAndReceiptThroughReviewedRecalculation() throws {
        let library = store(), current = now.addingTimeInterval(7_800)
        XCTAssertTrue(library.confirm(plan(id: "run", personal: input()), for: owner))
        let accepted = try XCTUnwrap(library.history.first?.plan)
        let target = try library.makeTarget(planID: "run", phase: .duringTraining, today: diary, goals: goals, now: current, calendar: calendar)
        XCTAssertEqual(target.context?.day, TrainingCalendarDay(now, calendar: calendar))
        XCTAssertEqual(target.context?.foodTolerance, .practicedDuringRun)
        let food = FoodItem(id: "reviewed-during-food", name: "Practiced carbohydrate", calories: 240, carbs: 60)
        try library.stageFoodLink(target: target, foods: [food], date: now, today: diary, goals: goals, userID: owner, now: current, requiresSubmissionAuthorization: true)
        try library.authorizeFoodLink(target: target, foods: [food], userID: owner)
        XCTAssertTrue(library.acceptFoodLink(target: target, foods: [food], userID: owner))
        let linked = try XCTUnwrap(library.history.first?.plan)
        XCTAssertEqual(linked.foodLinks?.first?.phase, .duringTraining)
        XCTAssertEqual(linked.foodLinks?.first?.foodID, food.id)
        let prior = try XCTUnwrap(library.checkpoint.state.revisions[try XCTUnwrap(accepted.revisionID)])
        let fingerprint = try PlanFingerprint.make(prior)
        XCTAssertTrue(library.confirm(plan(id: "run", personal: input(weight: 50), existing: linked), for: owner))
        XCTAssertEqual(try PlanFingerprint.make(library.checkpoint.state.revisions[prior.id]), fingerprint)
        XCTAssertEqual(library.history.first?.plan.foodLinks, linked.foodLinks)
        XCTAssertEqual(library.history.first?.plan.calculation?.individualEstimate?.requestedSessionProteinGrams, 13)
        XCTAssertThrowsError(try library.validateTarget(target, day: now, today: diary, goals: goals, userID: owner, now: current, calendar: calendar))
    }
}
