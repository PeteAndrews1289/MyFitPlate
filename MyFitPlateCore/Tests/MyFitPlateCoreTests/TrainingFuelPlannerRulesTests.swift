import XCTest
@testable import MyFitPlateCore

final class TrainingFuelPlannerRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 7, day: 7, hour: 14).date!
    }

    private let goals = TodayFuelPlanGoals(calories: 2_000, protein: 160, carbs: 250, fats: 70)

    func testHardLowerBodySessionReceivesMoreCarbsThanEasyUpperBodySession() {
        let hard = makePlan(session: session(
            kind: .strength,
            duration: 90,
            intensity: .hard,
            focus: .lowerBody
        ))
        let easy = makePlan(session: session(
            kind: .strength,
            duration: 90,
            intensity: .easy,
            focus: .upperBody
        ))

        XCTAssertEqual(hard.status, .ready)
        XCTAssertEqual(easy.status, .ready)
        XCTAssertGreaterThan(hard.allocatedCarbGrams, easy.allocatedCarbGrams)
        XCTAssertGreaterThan(hard.allocatedProteinGrams, easy.allocatedProteinGrams)
        XCTAssertTrue(hard.staysInsideDailyTargets)
        XCTAssertTrue(easy.staysInsideDailyTargets)
    }

    func testLongHardRunReceivesMoreFuelThanShortEasyRun() {
        let longRun = makePlan(session: session(kind: .run, duration: 120, intensity: .hard))
        let shortRun = makePlan(session: session(kind: .run, duration: 25, intensity: .easy))

        XCTAssertEqual(longRun.status, .ready)
        XCTAssertEqual(shortRun.status, .ready)
        XCTAssertGreaterThan(longRun.allocatedCarbGrams, shortRun.allocatedCarbGrams)
        XCTAssertGreaterThan(longRun.allocatedCalories, shortRun.allocatedCalories)
    }

    func testHardLongRunIsReducedToRemainingCaloriesAndMacros() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 150, intensity: .hard),
            today: log(calories: 1_720, protein: 120, carbs: 180, fats: 60),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.remainingCalories, 280)
        XCTAssertLessThanOrEqual(plan.allocatedCalories, 280)
        XCTAssertLessThanOrEqual(plan.allocatedProteinGrams, 40)
        XCTAssertLessThanOrEqual(plan.allocatedCarbGrams, 70)
        XCTAssertTrue(plan.notes.contains(.calorieBudgetLimited))
        XCTAssertTrue(plan.notes.contains(.carbBudgetLimited))
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testOverTargetDayReturnsNeutralReviewWithoutFuelAllocation() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .strength, duration: 60, intensity: .hard),
            today: log(calories: 2_125, protein: 145, carbs: 240, fats: 75),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .overTargetReview)
        XCTAssertLessThan(plan.remainingCalories, 0)
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertEqual(plan.allocatedCalories, 0)
    }

    func testTinyRemainingBudgetDoesNotCreateTokenTargets() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .strength, duration: 60, intensity: .moderate),
            today: log(calories: 1_955, protein: 120, carbs: 180, fats: 65),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .insufficientBudget)
        XCTAssertEqual(plan.remainingCalories, 45)
        XCTAssertTrue(plan.allocations.isEmpty)
    }

    func testFastedDayStillProducesABoundedPlanInsteadOfSpendingTheWholeDay() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 75, intensity: .moderate),
            today: nil,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertGreaterThan(plan.allocatedCalories, 0)
        XCTAssertLessThan(plan.allocatedCalories, plan.remainingCalories)
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testMissingSessionTimeRequestsInputWithoutInventingATime() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: TrainingFuelSession(
                kind: .strength,
                scheduledAt: nil,
                expectedDurationMinutes: 60,
                intensity: .moderate
            ),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .needsSessionTime)
        XCTAssertNil(plan.minutesUntilSession)
        XCTAssertTrue(plan.allocations.isEmpty)
    }

    func testLogFromAnotherDayIsIgnoredAndDisclosed() {
        var previousLog = baselineLog
        previousLog.date = calendar.date(byAdding: .day, value: -1, to: now)!
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 60, intensity: .moderate),
            today: previousLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.remainingCalories, 2_000)
        XCTAssertEqual(plan.remainingProteinGrams, 160)
        XCTAssertEqual(plan.remainingCarbGrams, 250)
        XCTAssertTrue(plan.notes.contains(.nonTodayLogIgnored))
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testMissingDurationAndIntensityUseVisibleConservativeDefaults() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: TrainingFuelSession(
                kind: .strength,
                scheduledAt: now.addingTimeInterval(2 * 60 * 60),
                expectedDurationMinutes: nil,
                intensity: nil
            ),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.normalizedDurationMinutes, 45)
        XCTAssertEqual(plan.normalizedIntensity, .moderate)
        XCTAssertTrue(plan.notes.contains(.durationDefaulted))
        XCTAssertTrue(plan.notes.contains(.intensityDefaulted))
    }

    func testAbsurdDurationIsClampedAndDisclosed() {
        let plan = makePlan(session: session(kind: .run, duration: 9_999, intensity: .hard))

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.normalizedDurationMinutes, 240)
        XCTAssertTrue(plan.notes.contains(.durationClamped))
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testStaleWorkoutProducesNoFuelRecommendation() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(
                kind: .strength,
                start: now.addingTimeInterval(-3 * 60 * 60),
                duration: 60,
                intensity: .hard
            ),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .staleSession)
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertLessThan(plan.minutesUntilSession ?? 0, 0)
    }

    func testTomorrowSessionDoesNotSpendTodaysBudget() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, start: tomorrow, duration: 45, intensity: .moderate),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .outsideToday)
        XCTAssertTrue(plan.allocations.isEmpty)
    }

    func testLateNightSessionKeepsNextDayRecoveryOutOfTodaysBudget() throws {
        let lateStart = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 7,
            hour: 23,
            minute: 30
        ).date!
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, start: lateStart, duration: 90, intensity: .hard),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertNotNil(plan.allocation(for: .beforeTraining))
        XCTAssertNil(plan.allocation(for: .afterTraining))
        XCTAssertTrue(plan.notes.contains(.postSessionFallsNextDay))
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testPostOnlyLateNightPreferenceSavesDeferredRecoveryWithoutTodaysBudget() {
        let lateStart = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 7,
            hour: 23,
            minute: 30
        ).date!
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, start: lateStart, duration: 90, intensity: .hard),
            today: baselineLog,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: true
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .deferredRecovery)
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertTrue(plan.notes.contains(.postSessionFallsNextDay))
    }

    func testDeferredRecoveryIntentCanBeSavedAfterTodaysBudgetIsExhausted() {
        let lateStart = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 7,
            hour: 23,
            minute: 45
        ).date!
        let exhaustedLog = DailyLog(
            date: now,
            meals: [Meal(name: "Dinner", foodItems: [
                FoodItem(name: "Dinner", calories: 2_200, protein: 100, carbs: 200)
            ])]
        )

        let plan = TrainingFuelPlannerRules.makePlan(
            session: TrainingFuelSession(
                kind: .strength,
                scheduledAt: lateStart,
                expectedDurationMinutes: 60,
                intensity: .hard,
                strengthFocus: .lowerBody
            ),
            today: exhaustedLog,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: true
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .deferredRecovery)
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertTrue(plan.notes.contains(.postSessionFallsNextDay))
    }

    func testUserCanChooseOnlyBeforeOrOnlyAfterTraining() {
        let upcoming = session(kind: .strength, duration: 60, intensity: .moderate)
        let beforeOnly = TrainingFuelPlannerRules.makePlan(
            session: upcoming,
            today: baselineLog,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: true,
                wantsPostSessionFuel: false
            ),
            now: now,
            calendar: calendar
        )
        let afterOnly = TrainingFuelPlannerRules.makePlan(
            session: upcoming,
            today: baselineLog,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: true
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertNotNil(beforeOnly.allocation(for: .beforeTraining))
        XCTAssertNil(beforeOnly.allocation(for: .afterTraining))
        XCTAssertNil(afterOnly.allocation(for: .beforeTraining))
        XCTAssertNotNil(afterOnly.allocation(for: .afterTraining))
    }

    func testNoFuelPreferenceReturnsNoAction() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .strength, duration: 60, intensity: .moderate),
            today: baselineLog,
            goals: goals,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: false,
                wantsPostSessionFuel: false
            ),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .noFuelRequested)
        XCTAssertTrue(plan.allocations.isEmpty)
    }

    func testExhaustedMacroTargetsDoNotCreateMisleadingTinyAllocations() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .strength, duration: 60, intensity: .hard),
            today: log(calories: 1_000, protein: 155, carbs: 245, fats: 25),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .insufficientBudget)
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertTrue(plan.notes.contains(.proteinBudgetLimited))
        XCTAssertTrue(plan.notes.contains(.carbBudgetLimited))
    }

    func testInvalidLoggedValuesStopPlanningInsteadOfOverstatingTheBudget() {
        let invalidLog = log(
            calories: .nan,
            protein: -.infinity,
            carbs: .nan,
            fats: 0
        )
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 45, intensity: .moderate),
            today: invalidLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .invalidDiaryData)
        XCTAssertTrue(plan.notes.contains(.invalidLoggedValue))
        XCTAssertTrue(plan.allocations.isEmpty)
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testInvalidCalorieTargetStopsPlanning() {
        let invalidGoals = TodayFuelPlanGoals(
            calories: .nan,
            protein: 160,
            carbs: 250,
            fats: 70
        )
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 45, intensity: .moderate),
            today: baselineLog,
            goals: invalidGoals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .invalidCalorieTarget)
        XCTAssertTrue(plan.allocations.isEmpty)
    }

    func testSlightlyLateSessionUsesGraceWithoutProducingUnboundedFuel() {
        let plan = TrainingFuelPlannerRules.makePlan(
            session: session(
                kind: .run,
                start: now.addingTimeInterval(-10 * 60),
                duration: 60,
                intensity: .moderate
            ),
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.status, .ready)
        XCTAssertEqual(plan.minutesUntilSession, 0)
        XCTAssertTrue(plan.notes.contains(.sessionStartGrace))
        XCTAssertLessThanOrEqual(
            plan.allocation(for: .beforeTraining)?.carbGrams ?? 0,
            25
        )
        XCTAssertTrue(plan.staysInsideDailyTargets)
    }

    func testAdversarialGridAlwaysPreservesBudgetAndActionabilityInvariants() {
        let kinds: [TrainingFuelSession.Kind] = [.strength, .run]
        let durations: [Int?] = [nil, -20, 15, 30, 60, 120, 300]
        let intensities: [TrainingFuelSession.Intensity?] = [nil, .easy, .moderate, .hard]
        let preferences = [
            TrainingFuelPreference(wantsPreSessionFuel: true, wantsPostSessionFuel: true),
            TrainingFuelPreference(wantsPreSessionFuel: true, wantsPostSessionFuel: false),
            TrainingFuelPreference(wantsPreSessionFuel: false, wantsPostSessionFuel: true),
            TrainingFuelPreference(wantsPreSessionFuel: false, wantsPostSessionFuel: false)
        ]
        let logs: [DailyLog?] = [
            nil,
            log(calories: 0, protein: 0, carbs: 0, fats: 0),
            baselineLog,
            log(calories: 1_850, protein: 155, carbs: 245, fats: 65),
            log(calories: 1_940, protein: 100, carbs: 100, fats: 60),
            log(calories: 2_100, protein: 170, carbs: 260, fats: 75)
        ]

        for kind in kinds {
            for duration in durations {
                for intensity in intensities {
                    for today in logs {
                        for preference in preferences {
                            let plan = TrainingFuelPlannerRules.makePlan(
                                session: session(
                                    kind: kind,
                                    duration: duration,
                                    intensity: intensity,
                                    focus: .lowerBody
                                ),
                                today: today,
                                goals: goals,
                                preference: preference,
                                now: now,
                                calendar: calendar
                            )
                            let context = "\(kind.rawValue), \(duration ?? -1)m, " +
                                "\(intensity?.rawValue ?? "default")"

                            XCTAssertTrue(plan.staysInsideDailyTargets, context)
                            XCTAssertEqual(plan.status == .ready, !plan.allocations.isEmpty, context)
                            XCTAssertEqual(
                                Set(plan.allocations.map(\.phase.rawValue)).count,
                                plan.allocations.count,
                                context
                            )
                            for allocation in plan.allocations {
                                XCTAssertGreaterThanOrEqual(allocation.calories, 60, context)
                                XCTAssertTrue(
                                    allocation.proteinGrams == 0 || allocation.proteinGrams >= 10,
                                    context
                                )
                                XCTAssertTrue(
                                    allocation.carbGrams == 0 || allocation.carbGrams >= 10,
                                    context
                                )
                                if allocation.phase == .beforeTraining {
                                    XCTAssertTrue(preference.wantsPreSessionFuel, context)
                                } else {
                                    XCTAssertTrue(preference.wantsPostSessionFuel, context)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testExtremeFiniteNutritionValuesAreRejectedWithoutIntegerOverflow() {
        let corruptedAllocation = TrainingFuelAllocation(
            phase: .beforeTraining,
            timing: .within30Minutes,
            proteinGrams: .max,
            carbGrams: .min
        )
        XCTAssertEqual(corruptedAllocation.proteinGrams, 100_000)
        XCTAssertEqual(corruptedAllocation.carbGrams, 0)
        XCTAssertEqual(corruptedAllocation.calories, 400_000)

        let impossibleGoals = TodayFuelPlanGoals(
            calories: .greatestFiniteMagnitude,
            protein: 160,
            carbs: 250,
            fats: 70
        )
        let invalidGoalPlan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .run, duration: 45, intensity: .moderate),
            today: nil,
            goals: impossibleGoals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(invalidGoalPlan.status, .invalidCalorieTarget)
        XCTAssertTrue(invalidGoalPlan.allocations.isEmpty)

        let corruptedLogPlan = TrainingFuelPlannerRules.makePlan(
            session: session(kind: .strength, duration: 60, intensity: .moderate),
            today: log(
                calories: .greatestFiniteMagnitude,
                protein: .greatestFiniteMagnitude,
                carbs: .greatestFiniteMagnitude,
                fats: 0
            ),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(corruptedLogPlan.status, .invalidDiaryData)
        XCTAssertEqual(corruptedLogPlan.remainingCalories, 0)
        XCTAssertEqual(corruptedLogPlan.remainingProteinGrams, 0)
        XCTAssertEqual(corruptedLogPlan.remainingCarbGrams, 0)
        XCTAssertTrue(corruptedLogPlan.notes.contains(.invalidLoggedValue))
        XCTAssertTrue(corruptedLogPlan.allocations.isEmpty)
        XCTAssertTrue(corruptedLogPlan.staysInsideDailyTargets)
    }

    private var baselineLog: DailyLog {
        log(calories: 900, protein: 55, carbs: 95, fats: 30)
    }

    private func makePlan(session: TrainingFuelSession) -> TrainingFuelPlannerPlan {
        TrainingFuelPlannerRules.makePlan(
            session: session,
            today: baselineLog,
            goals: goals,
            now: now,
            calendar: calendar
        )
    }

    private func session(
        kind: TrainingFuelSession.Kind,
        start: Date? = nil,
        duration: Int?,
        intensity: TrainingFuelSession.Intensity?,
        focus: TrainingFuelSession.StrengthFocus = .unknown
    ) -> TrainingFuelSession {
        TrainingFuelSession(
            kind: kind,
            scheduledAt: start ?? now.addingTimeInterval(2 * 60 * 60),
            expectedDurationMinutes: duration,
            intensity: intensity,
            strengthFocus: focus
        )
    }

    private func log(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double
    ) -> DailyLog {
        DailyLog(
            date: calendar.startOfDay(for: now),
            meals: [
                Meal(
                    name: "Logged",
                    foodItems: [
                        FoodItem(
                            name: "Logged food",
                            calories: calories,
                            protein: protein,
                            carbs: carbs,
                            fats: fats
                        )
                    ]
                )
            ]
        )
    }
}
