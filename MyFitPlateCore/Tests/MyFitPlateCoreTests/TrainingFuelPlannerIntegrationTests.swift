import XCTest
@testable import MyFitPlateCore

@MainActor
final class TrainingFuelPlannerIntegrationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testActiveProgramCandidateUsesCurrentRoutineAndSchedule() throws {
        let monday = date(2026, 7, 6, 0, 0)
        let upper = routine(
            id: "upper",
            name: "Upper Power",
            exercises: [
                RoutineExercise(name: "Barbell Bench Press", targetSets: 4),
                RoutineExercise(name: "Barbell Bent-over Row", targetSets: 4)
            ]
        )
        let lower = routine(
            id: "lower",
            name: "Lower Power",
            exercises: [
                RoutineExercise(name: "Barbell Back Squat", targetSets: 5),
                RoutineExercise(name: "Leg Press", targetSets: 3)
            ]
        )
        let program = WorkoutProgram(
            id: "program",
            userID: "user",
            name: "Power Split",
            routines: [upper, lower],
            startDate: monday,
            daysOfWeek: [2, 4, 6],
            currentProgressIndex: 1
        )

        let candidate = try XCTUnwrap(
            TrainingFuelSessionAdapter.activeStrengthCandidate(from: program, calendar: calendar)
        )

        XCTAssertEqual(candidate.title, "Lower Power")
        XCTAssertEqual(candidate.sessionReferenceID, "lower")
        XCTAssertEqual(candidate.detail, "Power Split - Week 1, Day 2")
        XCTAssertEqual(candidate.suggestedStrengthFocus, .lowerBody)
        XCTAssertEqual(candidate.scheduledDay, date(2026, 7, 8, 0, 0))
        XCTAssertGreaterThanOrEqual(candidate.suggestedDurationMinutes ?? 0, 20)
        XCTAssertTrue(candidate.assumptions.contains(.sessionTimeRequired))
    }

    func testActiveProgramCandidateStopsAfterFinalSlot() {
        let program = WorkoutProgram(
            id: "program",
            userID: "user",
            name: "Short Plan",
            routines: [routine(id: "one", name: "One")],
            daysOfWeek: nil,
            currentProgressIndex: 1
        )

        XCTAssertNil(TrainingFuelSessionAdapter.activeStrengthCandidate(from: program))
    }

    func testStrengthFocusRecognizesFullBodyFromCatalogCategories() throws {
        let program = WorkoutProgram(
            id: "program",
            userID: "user",
            name: "Mixed",
            routines: [
                routine(
                    id: "mixed",
                    name: "Full Body",
                    exercises: [
                        RoutineExercise(name: "Barbell Back Squat"),
                        RoutineExercise(name: "Dumbbell Bench Press")
                    ]
                )
            ],
            daysOfWeek: [2],
            currentProgressIndex: 0
        )

        let candidate = try XCTUnwrap(TrainingFuelSessionAdapter.activeStrengthCandidate(from: program))
        XCTAssertEqual(candidate.suggestedStrengthFocus, .fullBody)
    }

    func testTimedRunPlanSuppliesDurationAndHardIntensity() {
        let plan = RunWorkoutPlan(
            id: "tempo",
            name: "Tempo",
            subtitle: "Controlled",
            steps: [
                RunWorkoutStep(kind: .warmup, title: "Warm up", goal: .duration(seconds: 600)),
                RunWorkoutStep(kind: .hard, title: "Tempo", goal: .duration(seconds: 1_200)),
                RunWorkoutStep(kind: .cooldown, title: "Cool down", goal: .duration(seconds: 300))
            ]
        )

        let candidate = TrainingFuelSessionAdapter.runCandidate(from: plan)

        XCTAssertEqual(candidate.suggestedDurationMinutes, 35)
        XCTAssertEqual(candidate.sessionReferenceID, "tempo")
        XCTAssertEqual(candidate.suggestedIntensity, .hard)
        XCTAssertTrue(candidate.assumptions.contains(.durationEstimated))
    }

    func testDistanceRunPlanRequiresDurationReview() {
        let plan = RunWorkoutPlan(
            id: "distance",
            name: "Repeats",
            subtitle: "Track",
            steps: [
                RunWorkoutStep(kind: .hard, title: "400 m", goal: .distance(meters: 400))
            ]
        )

        let candidate = TrainingFuelSessionAdapter.runCandidate(from: plan)

        XCTAssertNil(candidate.suggestedDurationMinutes)
        XCTAssertTrue(candidate.assumptions.contains(.durationNeedsReview))
    }

    func testDraftConvertsVisibleEditsToPlannerSession() {
        let start = date(2026, 7, 11, 18, 30)
        let candidate = TrainingFuelSessionAdapter.manualCandidate(kind: .strength)
        let draft = TrainingFuelPlanDraft(
            candidate: candidate,
            scheduledAt: start,
            durationMinutes: 75,
            intensity: .hard,
            strengthFocus: .lowerBody,
            preference: TrainingFuelPreference(wantsPreSessionFuel: true, wantsPostSessionFuel: false)
        )

        XCTAssertEqual(draft.session.scheduledAt, start)
        XCTAssertEqual(draft.session.expectedDurationMinutes, 75)
        XCTAssertEqual(draft.session.intensity, .hard)
        XCTAssertEqual(draft.session.strengthFocus, .lowerBody)
        XCTAssertTrue(draft.preference.wantsPreSessionFuel)
        XCTAssertFalse(draft.preference.wantsPostSessionFuel)
    }

    func testEditingSamePlanPreservesOriginalReconciliationBaseline() {
        let start = date(2026, 7, 11, 18, 0)
        let baseline = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [food(protein: 20, carbs: 30, timestamp: nil)])]
        )
        let original = confirmedPlan(
            start: start,
            confirmedAt: date(2026, 7, 11, 14, 0),
            baseline: baseline
        )
        let current = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [
                food(protein: 20, carbs: 30, timestamp: nil),
                food(protein: 5, carbs: 10, timestamp: nil)
            ])]
        )
        var editedDraft = original.draft
        editedDraft.durationMinutes = 75
        let replanned = TrainingFuelPlannerRules.makePlan(
            session: editedDraft.session,
            today: current,
            goals: TodayFuelPlanGoals(calories: 2_000, protein: 100, carbs: 200, fats: 70),
            now: date(2026, 7, 11, 14, 30),
            calendar: calendar
        )

        let updated = TrainingFuelConfirmedPlan(
            draft: editedDraft,
            plannerPlan: replanned,
            goals: TodayFuelPlanGoals(calories: 2_000, protein: 100, carbs: 200, fats: 70),
            today: current,
            existingPlan: original,
            confirmedAt: date(2026, 7, 11, 15, 0)
        )

        XCTAssertEqual(updated.confirmedAt, original.confirmedAt)
        XCTAssertEqual(updated.diaryAtConfirmation, original.diaryAtConfirmation)
        XCTAssertEqual(updated.goalsAtConfirmation, original.goalsAtConfirmation)
        XCTAssertEqual(updated.draft.durationMinutes, 75)
    }

    func testProgressSeparatesFoodsLoggedBeforeAndAfterSession() throws {
        let now = date(2026, 7, 11, 20, 0)
        let start = date(2026, 7, 11, 18, 0)
        let confirmedAt = date(2026, 7, 11, 14, 0)
        var plan = confirmedPlan(start: start, confirmedAt: confirmedAt)
        plan.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: .manualConfirmation,
            recordedAt: date(2026, 7, 11, 19, 0),
            actualStartAt: start,
            actualEndAt: date(2026, 7, 11, 19, 0)
        )
        let log = DailyLog(
            date: start,
            meals: [
                Meal(name: "Snacks", foodItems: [
                    food(protein: 8, carbs: 24, timestamp: date(2026, 7, 11, 16, 0)),
                    food(protein: 22, carbs: 28, timestamp: date(2026, 7, 11, 19, 30))
                ])
            ]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: now,
            calendar: calendar
        )
        let before = try XCTUnwrap(progress.phases.first { $0.allocation.phase == .beforeTraining })
        let after = try XCTUnwrap(progress.phases.first { $0.allocation.phase == .afterTraining })

        XCTAssertEqual(before.loggedProteinGrams, 8)
        XCTAssertEqual(before.loggedCarbGrams, 24)
        XCTAssertEqual(after.loggedProteinGrams, 22)
        XCTAssertEqual(after.loggedCarbGrams, 28)
        XCTAssertEqual(progress.status, .recovery)
    }

    func testElapsedSessionAwaitsOutcomeInsteadOfInferringRecovery() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            now: date(2026, 7, 11, 19, 15),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .awaitingOutcome)
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testSkippedSessionClosesTargetsEvenWhenDiaryIsInvalid() {
        let start = date(2026, 7, 11, 18, 0)
        var plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        plan.outcome = TrainingFuelSessionOutcome(
            status: .skipped,
            source: .manualConfirmation,
            recordedAt: date(2026, 7, 11, 17, 0)
        )
        let invalidLog = DailyLog(
            date: start,
            meals: [Meal(name: "Invalid", foodItems: [
                FoodItem(name: "Invalid", calories: .nan, protein: .infinity, carbs: 1)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: invalidLog,
            now: date(2026, 7, 11, 17, 1),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .skipped)
        XCTAssertTrue(progress.phases.allSatisfy { !$0.hasActionableTarget })
    }

    func testCompletedPreOnlyPlanDoesNotWaitForMissedPreWorkoutFuel() {
        let start = date(2026, 7, 11, 18, 0)
        var plan = confirmedPlan(
            start: start,
            confirmedAt: date(2026, 7, 11, 14, 0),
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: true,
                wantsPostSessionFuel: false
            ),
            allocations: [
                TrainingFuelAllocation(
                    phase: .beforeTraining,
                    timing: .overTwoHours,
                    proteinGrams: 10,
                    carbGrams: 30
                )
            ]
        )
        plan.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: .manualConfirmation,
            recordedAt: date(2026, 7, 11, 19, 0),
            actualEndAt: date(2026, 7, 11, 19, 0)
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            now: date(2026, 7, 11, 19, 10),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .complete)
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
    }

    func testProgressDoesNotCountInSessionFoodAsRecovery() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "During run", foodItems: [
                food(protein: 10, carbs: 30, timestamp: date(2026, 7, 11, 18, 30))
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 18, 45),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .inSession)
        XCTAssertTrue(progress.phases.allSatisfy { $0.loggedProteinGrams == 0 })
        XCTAssertTrue(progress.phases.allSatisfy { $0.loggedCarbGrams == 0 })
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testUpcomingProgressOnlyExposesBeforeTrainingTarget() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .upcoming)
        XCTAssertNotNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testProgressFallsBackToDiaryDeltaForLegacyUntimestampedFood() throws {
        let start = date(2026, 7, 11, 18, 0)
        let baseline = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [food(protein: 20, carbs: 30, timestamp: nil)])]
        )
        let plan = confirmedPlan(
            start: start,
            confirmedAt: date(2026, 7, 11, 14, 0),
            baseline: baseline
        )
        let current = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [
                food(protein: 20, carbs: 30, timestamp: nil),
                food(protein: 5, carbs: 12, timestamp: nil)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: current,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )
        let before = try XCTUnwrap(progress.phases.first { $0.allocation.phase == .beforeTraining })

        XCTAssertEqual(before.loggedProteinGrams, 5)
        XCTAssertEqual(before.loggedCarbGrams, 12)
    }

    func testProgressBecomesNeutralWhenDayMovesOverCalorieGoal() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "Dinner", foodItems: [
                FoodItem(name: "Large meal", calories: 2_100, protein: 10, carbs: 10)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .overTarget)
    }

    func testProgressFailsClosedWithoutConvertingNonFiniteDiaryValues() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "Corrupt", foodItems: [
                FoodItem(name: "Corrupt", calories: .nan, protein: .infinity, carbs: 10)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .invalidDiary)
        XCTAssertEqual(progress.phases.map(\.loggedProteinGrams), [0, 0])
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testProgressPausesTargetWhenUnrelatedFoodUsesDailyBudget() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [
                FoodItem(name: "High-fat lunch", calories: 1_960, protein: 0, carbs: 0, fats: 218)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .budgetUsedElsewhere)
        XCTAssertTrue(progress.phases.allSatisfy { !$0.hasActionableTarget })
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testProgressCapsRemainingProteinAcrossPhasesToLiveDailyGoal() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [
                FoodItem(name: "Protein", calories: 360, protein: 90, carbs: 0, timestamp: nil)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )
        let actionableProtein = progress.phases.reduce(0) { $0 + $1.actionableProteinGrams }

        XCTAssertLessThanOrEqual(actionableProtein, 10)
    }

    func testProgressNeverOffersMoreThanLiveDailyBudget() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))
        let log = DailyLog(
            date: start,
            meals: [Meal(name: "Lunch", foodItems: [
                FoodItem(name: "Late lunch", calories: 1_840, protein: 88, carbs: 185)
            ])]
        )

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: log,
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )
        let protein = progress.phases.reduce(0) { $0 + $1.actionableProteinGrams }
        let carbs = progress.phases.reduce(0) { $0 + $1.actionableCarbGrams }

        XCTAssertLessThanOrEqual(protein, 12)
        XCTAssertLessThanOrEqual(carbs, 15)
        XCTAssertLessThanOrEqual((protein + carbs) * 4, 160)
    }

    func testProgressRecapsToCurrentLowerGoals() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            goals: TodayFuelPlanGoals(calories: 160, protein: 20, carbs: 20, fats: 10),
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )
        let protein = progress.phases.reduce(0) { $0 + $1.actionableProteinGrams }
        let carbs = progress.phases.reduce(0) { $0 + $1.actionableCarbGrams }

        XCTAssertLessThanOrEqual(protein, 20)
        XCTAssertLessThanOrEqual(carbs, 20)
        XCTAssertLessThanOrEqual((protein + carbs) * 4, 160)
    }

    func testProgressFailsClosedWhenCurrentGoalsAreInvalid() {
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            goals: TodayFuelPlanGoals(calories: .nan, protein: 100, carbs: 200, fats: 70),
            now: date(2026, 7, 11, 16, 0),
            calendar: calendar
        )

        XCTAssertEqual(progress.status, .invalidTargets)
        XCTAssertNil(progress.target(for: .beforeTraining, plan: plan))
        XCTAssertNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testStoreScopesPlansByUserAndExpiresOldDay() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 18, 0)
        let plan = confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0))

        store.confirm(plan, for: "user-a")
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.joined().contains("user-a"))
        store.load(for: "user-b", now: start, calendar: calendar)
        XCTAssertNil(store.confirmedPlan)

        store.load(for: "user-a", now: start, calendar: calendar)
        XCTAssertEqual(store.confirmedPlan?.id, plan.id)

        store.load(for: "user-a", now: date(2026, 7, 12, 9, 0), calendar: calendar)
        XCTAssertNil(store.confirmedPlan)
    }

    func testStrengthCompletionRequiresExactProgramRoutine() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 18, 0)
        let candidate = TrainingFuelSessionCandidate(
            id: "strength:program:lower:1",
            source: .activeStrengthProgram,
            sourceID: "program",
            sessionReferenceID: "lower",
            title: "Lower Power",
            detail: "Power Split",
            kind: .strength,
            scheduledDay: calendar.startOfDay(for: start),
            suggestedDurationMinutes: 60,
            suggestedIntensity: .hard,
            suggestedStrengthFocus: .lowerBody,
            assumptions: []
        )
        store.confirm(
            confirmedPlan(
                start: start,
                confirmedAt: date(2026, 7, 11, 14, 0),
                candidate: candidate
            ),
            for: "user"
        )

        XCTAssertFalse(store.recordStrengthCompletion(
            routineID: "upper",
            routineName: "Upper Power",
            completedAt: date(2026, 7, 11, 19, 0),
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        XCTAssertNil(store.confirmedPlan?.outcome)

        XCTAssertTrue(store.recordStrengthCompletion(
            routineID: "lower",
            routineName: "Lower Power",
            completedAt: date(2026, 7, 11, 19, 0),
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        XCTAssertEqual(store.confirmedPlan?.outcome?.status, .completed)
        XCTAssertEqual(store.confirmedPlan?.outcome?.source, .strengthWorkout)
    }

    func testSelectedRunCompletionRequiresExactPlanIdentity() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 18, 0)
        let selected = RunWorkoutPlan(
            id: "tempo",
            name: "Tempo",
            subtitle: "Controlled",
            steps: [RunWorkoutStep(kind: .hard, title: "Tempo", goal: .duration(seconds: 3_600))]
        )
        store.confirm(
            confirmedPlan(
                start: start,
                confirmedAt: date(2026, 7, 11, 14, 0),
                candidate: TrainingFuelSessionAdapter.runCandidate(from: selected)
            ),
            for: "user"
        )
        let run = Run(
            id: "run",
            source: .recorded,
            startDate: start,
            endDate: date(2026, 7, 11, 19, 0),
            distanceMeters: 10_000,
            movingSeconds: 3_600
        )

        XCTAssertFalse(store.recordRunCompletion(
            run,
            selectedPlanID: "easy-run",
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        XCTAssertNil(store.confirmedPlan?.outcome)

        XCTAssertTrue(store.recordRunCompletion(
            run,
            selectedPlanID: "tempo",
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        XCTAssertEqual(store.confirmedPlan?.outcome?.actualStartAt, start)
        XCTAssertEqual(store.confirmedPlan?.outcome?.actualEndAt, run.endDate)
    }

    func testManualCompletionStartsRecoveryAtActualEnd() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 18, 0)
        store.confirm(
            confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 14, 0)),
            for: "user"
        )
        let completedAt = date(2026, 7, 11, 18, 35)

        XCTAssertTrue(store.markCurrentPlanCompleted(
            at: completedAt,
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        let plan = try XCTUnwrap(store.confirmedPlan)
        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: nil,
            goals: defaultGoals,
            now: date(2026, 7, 11, 18, 40),
            calendar: calendar
        )

        XCTAssertEqual(plan.outcome?.actualEndAt, completedAt)
        XCTAssertEqual(progress.status, .recovery)
        XCTAssertNotNil(progress.target(for: .afterTraining, plan: plan))
    }

    func testDeferredRecoveryUsesNextDayDiaryAndGoals() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 23, 30)
        let preference = TrainingFuelPreference(
            wantsPreSessionFuel: false,
            wantsPostSessionFuel: true
        )
        let draft = TrainingFuelPlanDraft(
            candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            scheduledAt: start,
            durationMinutes: 60,
            intensity: .hard,
            strengthFocus: .lowerBody,
            preference: preference
        )
        let plannerPlan = TrainingFuelPlannerRules.makePlan(
            session: draft.session,
            today: nil,
            goals: defaultGoals,
            preference: preference,
            now: date(2026, 7, 11, 20, 0),
            calendar: calendar
        )
        XCTAssertEqual(plannerPlan.status, .deferredRecovery)
        let plan = TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: defaultGoals,
            today: nil,
            confirmedAt: date(2026, 7, 11, 20, 0)
        )
        store.confirm(plan, for: "user")
        let completedAt = date(2026, 7, 12, 0, 35)
        let nextDayLog = DailyLog(
            date: completedAt,
            meals: [Meal(name: "Late snack", foodItems: [
                FoodItem(name: "Snack", calories: 400, protein: 20, carbs: 40)
            ])]
        )
        let nextDayGoals = TodayFuelPlanGoals(
            calories: 1_800,
            protein: 100,
            carbs: 200,
            fats: 60
        )

        XCTAssertTrue(store.markCurrentPlanCompleted(
            at: completedAt,
            today: nextDayLog,
            goals: nextDayGoals,
            for: "user",
            calendar: calendar
        ))
        let completedPlan = try XCTUnwrap(store.confirmedPlan)
        let recoveryPlan = try XCTUnwrap(completedPlan.outcome?.recoveryPlan)
        XCTAssertEqual(completedPlan.outcome?.diaryAtOutcome, TrainingFuelDiarySnapshot(log: nextDayLog))
        XCTAssertEqual(recoveryPlan.status, .ready)
        XCTAssertTrue(recoveryPlan.allocations.allSatisfy { $0.phase == .afterTraining })

        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: completedPlan,
            today: nextDayLog,
            goals: nextDayGoals,
            now: date(2026, 7, 12, 0, 45),
            calendar: calendar
        )
        let target = try XCTUnwrap(progress.target(for: .afterTraining, plan: completedPlan))
        XCTAssertEqual(progress.status, .recovery)
        XCTAssertLessThanOrEqual(Double(target.calories) + nextDayLog.totalCalories(), nextDayGoals.calories)

        store.load(for: "user", now: date(2026, 7, 12, 2, 34), calendar: calendar)
        XCTAssertNotNil(store.confirmedPlan)
        store.load(for: "user", now: date(2026, 7, 12, 2, 36), calendar: calendar)
        XCTAssertNil(store.confirmedPlan)
    }

    func testActualOverrunIntoNextDayCreatesFreshRecoveryPlan() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingFuelPlanStore(userDefaults: defaults)
        let start = date(2026, 7, 11, 22, 30)
        store.confirm(
            confirmedPlan(start: start, confirmedAt: date(2026, 7, 11, 18, 0)),
            for: "user"
        )

        XCTAssertTrue(store.markCurrentPlanCompleted(
            at: date(2026, 7, 12, 0, 10),
            today: nil,
            goals: defaultGoals,
            for: "user",
            calendar: calendar
        ))
        let pendingPlan = try XCTUnwrap(store.confirmedPlan)
        XCTAssertNil(pendingPlan.outcome?.recoveryPlan)
        XCTAssertEqual(
            TrainingFuelPlanProgressRules.makeProgress(
                plan: pendingPlan,
                today: nil,
                goals: defaultGoals,
                now: date(2026, 7, 12, 0, 15),
                calendar: calendar
            ).status,
            .awaitingRecoveryData
        )
        XCTAssertEqual(
            TrainingFuelPlanProgressRules.makeProgress(
                plan: pendingPlan,
                today: nil,
                goals: defaultGoals,
                now: date(2026, 7, 12, 2, 11),
                calendar: calendar
            ).status,
            .stale
        )

        XCTAssertTrue(store.refreshDeferredRecovery(
            today: DailyLog(date: date(2026, 7, 12, 0, 0), meals: []),
            goals: defaultGoals,
            at: date(2026, 7, 12, 0, 15),
            for: "user",
            calendar: calendar
        ))
        XCTAssertNotNil(store.confirmedPlan?.outcome?.recoveryPlan)
    }

    func testStoreDiscardsUnreadablePlanData() throws {
        let suite = "TrainingFuelPlannerIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "myfitplate.training_fuel_plan.user-a"
        let hashedKey = try XCTUnwrap(
            AccountScopedStorageKey.make(prefix: "myfitplate.training_fuel_plan", userID: "user-a")
        )
        defaults.set(Data("not-json".utf8), forKey: key)

        let store = TrainingFuelPlanStore(userDefaults: defaults)
        store.load(for: "user-a", now: date(2026, 7, 11, 9, 0), calendar: calendar)

        XCTAssertNil(store.confirmedPlan)
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertNil(defaults.data(forKey: hashedKey))
    }

    func testSavedPlanDecodesWhenNewIdentityAndOutcomeKeysAreAbsent() throws {
        let start = date(2026, 7, 11, 18, 0)
        let candidate = TrainingFuelSessionCandidate(
            id: "strength:program:lower:1",
            source: .activeStrengthProgram,
            sourceID: "program",
            sessionReferenceID: "lower",
            title: "Lower Power",
            detail: "Power Split",
            kind: .strength,
            scheduledDay: calendar.startOfDay(for: start),
            suggestedDurationMinutes: 60,
            suggestedIntensity: .hard,
            suggestedStrengthFocus: .lowerBody,
            assumptions: []
        )
        var plan = confirmedPlan(
            start: start,
            confirmedAt: date(2026, 7, 11, 14, 0),
            candidate: candidate
        )
        plan.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: .strengthWorkout,
            recordedAt: date(2026, 7, 11, 19, 0),
            actualEndAt: date(2026, 7, 11, 19, 0),
            recoveryPlan: TrainingFuelDeferredRecoveryRules.makePlan(
                for: plan,
                today: nil,
                goals: defaultGoals,
                completedAt: date(2026, 7, 11, 19, 0),
                calendar: calendar
            ),
            recoveryDiaryIsAuthoritative: true
        )

        let encoded = try JSONEncoder().encode(plan)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var draft = try XCTUnwrap(object["draft"] as? [String: Any])
        draft.removeValue(forKey: "sessionReferenceID")
        object["draft"] = draft
        var outcome = try XCTUnwrap(object["outcome"] as? [String: Any])
        outcome.removeValue(forKey: "recoveryDiaryIsAuthoritative")
        object["outcome"] = outcome

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TrainingFuelConfirmedPlan.self, from: legacyData)

        XCTAssertNil(decoded.draft.sessionReferenceID)
        XCTAssertEqual(decoded.outcome?.status, .completed)
        XCTAssertTrue(decoded.outcome?.hasAuthoritativeRecoveryDiary == true)
    }

    private func confirmedPlan(
        start: Date,
        confirmedAt: Date,
        baseline: DailyLog? = nil,
        candidate: TrainingFuelSessionCandidate = TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
        preference: TrainingFuelPreference = TrainingFuelPreference(),
        allocations: [TrainingFuelAllocation]? = nil
    ) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(
            candidate: candidate,
            scheduledAt: start,
            durationMinutes: 60,
            intensity: .hard,
            strengthFocus: .lowerBody,
            preference: preference
        )
        let resolvedAllocations = allocations ?? [
            TrainingFuelAllocation(
                phase: .beforeTraining,
                timing: .overTwoHours,
                proteinGrams: 10,
                carbGrams: 30
            ),
            TrainingFuelAllocation(
                phase: .afterTraining,
                timing: .afterSession,
                proteinGrams: 25,
                carbGrams: 35
            )
        ]
        let plannerPlan = TrainingFuelPlannerPlan(
            status: .ready,
            normalizedDurationMinutes: 60,
            normalizedIntensity: .hard,
            minutesUntilSession: 240,
            remainingCalories: 1_200,
            remainingProteinGrams: 100,
            remainingCarbGrams: 160,
            allocations: resolvedAllocations,
            notes: []
        )
        return TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: defaultGoals,
            today: baseline,
            confirmedAt: confirmedAt
        )
    }

    private var defaultGoals: TodayFuelPlanGoals {
        TodayFuelPlanGoals(calories: 2_000, protein: 100, carbs: 200, fats: 70)
    }

    private func routine(
        id: String,
        name: String,
        exercises: [RoutineExercise] = [RoutineExercise(name: "Barbell Bench Press")]
    ) -> WorkoutRoutine {
        WorkoutRoutine(
            id: id,
            userID: "user",
            name: name,
            dateCreated: date(2026, 1, 1, 0, 0),
            exercises: exercises
        )
    }

    private func food(protein: Double, carbs: Double, timestamp: Date?) -> FoodItem {
        FoodItem(
            name: "Fuel",
            calories: (protein + carbs) * 4,
            protein: protein,
            carbs: carbs,
            timestamp: timestamp
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
