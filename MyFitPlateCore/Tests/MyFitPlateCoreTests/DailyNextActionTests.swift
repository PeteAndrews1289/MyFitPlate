import XCTest
@testable import MyFitPlateCore

final class DailyNextActionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var goals: TodayFuelPlanGoals {
        TodayFuelPlanGoals(calories: 2_000, protein: 120, carbs: 240, fats: 70)
    }

    func testUpcomingTrainingFuelTakesPriorityAndUsesExactTarget() {
        let now = date(hour: 9)
        let reviewFood = FoodItem(
            name: "Estimate",
            calories: 400,
            protein: 20,
            sourceMetadata: .aiEstimate(.aiText, sourceName: "Test")
        )
        let log = DailyLog(date: now, meals: [Meal(name: "Breakfast", foodItems: [reviewFood])])
        let plan = confirmedPlan(
            start: date(hour: 12),
            confirmedAt: date(hour: 8),
            baseline: log
        )

        let action = DailyNextActionRules.makeAction(
            plan: plan,
            today: log,
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .preWorkoutFuel)
        XCTAssertEqual(action.deepLink, "myfitplate://training-fuel")
        XCTAssertEqual(action.proteinGrams, 15)
        XCTAssertEqual(action.carbGrams, 35)
    }

    func testCompletedSessionProducesRecoveryAction() {
        var plan = confirmedPlan(start: date(hour: 12), confirmedAt: date(hour: 8))
        plan.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: .manualConfirmation,
            recordedAt: date(hour: 13),
            actualEndAt: date(hour: 13),
            diaryAtOutcome: TrainingFuelDiarySnapshot(log: nil),
            recoveryDiaryIsAuthoritative: true
        )

        let action = DailyNextActionRules.makeAction(
            plan: plan,
            today: DailyLog(date: date(hour: 13), meals: []),
            goals: goals,
            now: date(hour: 13, minute: 10),
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .recoveryMeal)
        XCTAssertEqual(action.proteinGrams, 25)
        XCTAssertEqual(action.carbGrams, 45)
    }

    func testTrustReviewWinsOverGeneralProteinCatchUp() {
        let reviewFood = FoodItem(
            name: "Estimate",
            calories: 500,
            protein: 10,
            sourceMetadata: .aiEstimate(.aiText, sourceName: "Test")
        )
        let log = DailyLog(date: date(hour: 16), meals: [Meal(name: "Lunch", foodItems: [reviewFood])])

        let action = DailyNextActionRules.makeAction(
            plan: nil,
            today: log,
            goals: goals,
            now: date(hour: 16),
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .trustReview)
        XCTAssertEqual(action.deepLink, "myfitplate://trust")
    }

    func testNutritionContradictionRoutesToTrustReview() {
        let invalidFood = FoodItem(
            name: "Broken label",
            calories: 150,
            protein: 2,
            carbs: 20,
            fats: 4,
            saturatedFat: 12,
            sourceMetadata: .database(.openFoodFacts, sourceName: "Open Food Facts", sourceID: "bad")
        )
        let log = DailyLog(date: date(hour: 16), meals: [Meal(name: "Snack", foodItems: [invalidFood])])

        let action = DailyNextActionRules.makeAction(
            plan: nil,
            today: log,
            goals: goals,
            now: date(hour: 16),
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .trustReview)
        XCTAssertEqual(action.detail, "1 entry needs your review")
    }

    func testMeaningfulProteinGapRoutesToFoodSearch() {
        let food = FoodItem(name: "Meal", calories: 1_400, protein: 75)
        let log = DailyLog(date: date(hour: 18), meals: [Meal(name: "Dinner", foodItems: [food])])

        let action = DailyNextActionRules.makeAction(
            plan: nil,
            today: log,
            goals: goals,
            now: date(hour: 18),
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .proteinCatchUp)
        XCTAssertEqual(action.proteinGrams, 45)
        XCTAssertEqual(action.deepLink, "myfitplate://food-search")
    }

    func testFractionalProteinGapUsesNearestDisplayedGram() {
        let action = DailyNextActionRules.makeAction(
            plan: nil,
            today: nil,
            goals: TodayFuelPlanGoals(calories: 2_000, protein: 146.4, carbs: 240, fats: 70),
            now: date(hour: 18),
            calendar: calendar
        )

        XCTAssertEqual(action.kind, .proteinCatchUp)
        XCTAssertEqual(action.proteinGrams, 146)
        XCTAssertEqual(action.detail, "146 g protein left today")
    }

    func testSmallGapAndInvalidDataFallBackToSteadyDay() {
        let nearlyThere = FoodItem(name: "Meal", calories: 1_900, protein: 110)
        let log = DailyLog(date: date(hour: 20), meals: [Meal(name: "Dinner", foodItems: [nearlyThere])])
        let smallGap = DailyNextActionRules.makeAction(
            plan: nil,
            today: log,
            goals: goals,
            now: date(hour: 20),
            calendar: calendar
        )
        XCTAssertEqual(smallGap.kind, .steadyDay)

        let invalid = TodayFuelPlanGoals(calories: .nan, protein: .infinity, carbs: 0, fats: 0)
        let invalidAction = DailyNextActionRules.makeAction(
            plan: nil,
            today: nil,
            goals: invalid,
            now: date(hour: 20),
            calendar: calendar
        )
        XCTAssertEqual(invalidAction.kind, .steadyDay)
    }

    func testMaiaAnnotationStaysBoundToEveryDeterministicAction() {
        for kind in DailyNextAction.Kind.allCases {
            let action = DailyNextAction(
                kind: kind,
                title: "Private presentation title",
                detail: "Private presentation detail",
                deepLink: "myfitplate://test/\(kind.rawValue)"
            )

            let annotation = DailyNextActionAnnotationRules.make(for: action)

            XCTAssertEqual(annotation.actionKind, kind)
            XCTAssertEqual(annotation.deepLink, action.deepLink)
            XCTAssertFalse(annotation.text.isEmpty)
            XCTAssertFalse(annotation.text.contains(action.title))
            XCTAssertFalse(annotation.text.contains(action.detail))
            XCTAssertLessThanOrEqual(annotation.text.count, 100)
        }
    }

    func testMaiaAnnotationUsesHumanLanguageWithoutMakingNewClaims() {
        let recovery = DailyNextAction(
            kind: .recoveryMeal,
            title: "Log recovery fuel",
            detail: "25 g protein + 45 g carbs",
            deepLink: "myfitplate://training-fuel"
        )
        let annotation = DailyNextActionAnnotationRules.make(for: recovery)

        XCTAssertEqual(
            annotation.text,
            "You've done the work. This target keeps recovery inside what is left today."
        )
        XCTAssertFalse(annotation.text.contains("45"))
        XCTAssertFalse(annotation.text.lowercased().contains("optimal"))
    }

    private func confirmedPlan(
        start: Date,
        confirmedAt: Date,
        baseline: DailyLog? = nil
    ) -> TrainingFuelConfirmedPlan {
        let candidate = TrainingFuelSessionAdapter.manualCandidate(kind: .strength)
        let draft = TrainingFuelPlanDraft(
            candidate: candidate,
            scheduledAt: start,
            durationMinutes: 60,
            intensity: .hard,
            strengthFocus: .lowerBody,
            preference: TrainingFuelPreference()
        )
        let plannerPlan = TrainingFuelPlannerPlan(
            status: .ready,
            normalizedDurationMinutes: 60,
            normalizedIntensity: .hard,
            minutesUntilSession: 180,
            remainingCalories: 1_200,
            remainingProteinGrams: 100,
            remainingCarbGrams: 160,
            allocations: [
                TrainingFuelAllocation(
                    phase: .beforeTraining,
                    timing: .thirtyTo120Minutes,
                    proteinGrams: 15,
                    carbGrams: 35
                ),
                TrainingFuelAllocation(
                    phase: .afterTraining,
                    timing: .afterSession,
                    proteinGrams: 25,
                    carbGrams: 45
                )
            ],
            notes: []
        )
        return TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: goals,
            today: baseline ?? DailyLog(date: start, meals: []),
            confirmedAt: confirmedAt
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 11,
            hour: hour,
            minute: minute
        ))!
    }
}
