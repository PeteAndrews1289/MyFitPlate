import XCTest
@testable import MyFitPlateCore

final class TrainingFuelNotificationRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let goals = TodayFuelPlanGoals(calories: 2_000, protein: 120, carbs: 240, fats: 70)

    func testAllTypesDefaultOff() {
        let candidates = TrainingFuelNotificationRules.candidates(
            preferences: TrainingFuelNotificationPreferences(),
            plan: confirmedPlan(start: date(hour: 12), confirmedAt: date(hour: 8)),
            today: nil,
            goals: goals,
            now: date(hour: 8),
            calendar: calendar
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testPreSessionUsesAllocationTimingAndExactDeepLink() throws {
        let preferences = TrainingFuelNotificationPreferences(preSessionEnabled: true)
        let candidates = TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: confirmedPlan(start: date(hour: 12), confirmedAt: date(hour: 8)),
            today: nil,
            goals: goals,
            now: date(hour: 8),
            calendar: calendar
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.kind, .preSession)
        XCTAssertEqual(candidate.fireDate, date(hour: 10, minute: 45))
        XCTAssertEqual(candidate.deepLink, "myfitplate://training-fuel")
        XCTAssertTrue(candidate.body.contains("15 g protein + 35 g carbs"))
    }

    func testRecoveryRequiresExplicitCompletion() throws {
        let preferences = TrainingFuelNotificationPreferences(recoveryEnabled: true)
        let planWithoutOutcome = confirmedPlan(start: date(hour: 12), confirmedAt: date(hour: 8))
        XCTAssertTrue(TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: planWithoutOutcome,
            today: nil,
            goals: goals,
            now: date(hour: 13),
            calendar: calendar
        ).isEmpty)

        var completed = planWithoutOutcome
        completed.outcome = TrainingFuelSessionOutcome(
            status: .completed,
            source: .manualConfirmation,
            recordedAt: date(hour: 13),
            actualEndAt: date(hour: 13),
            recoveryDiaryIsAuthoritative: true
        )
        let candidate = try XCTUnwrap(TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: completed,
            today: nil,
            goals: goals,
            now: date(hour: 13, minute: 1),
            calendar: calendar
        ).first)

        XCTAssertEqual(candidate.kind, .recovery)
        XCTAssertEqual(candidate.fireDate, date(hour: 13, minute: 10))
    }

    func testEveningCatchUpRequiresMeaningfulGapAndRemainingCalories() {
        let preferences = TrainingFuelNotificationPreferences(eveningCatchUpEnabled: true)
        let meaningful = DailyLog(
            date: date(hour: 18),
            meals: [Meal(name: "Dinner", foodItems: [FoodItem(name: "Meal", calories: 1_300, protein: 70)])]
        )
        let candidate = TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: nil,
            today: meaningful,
            goals: goals,
            now: date(hour: 18),
            calendar: calendar
        ).first
        XCTAssertEqual(candidate?.kind, .eveningCatchUp)

        let nearlyComplete = DailyLog(
            date: date(hour: 18),
            meals: [Meal(name: "Dinner", foodItems: [FoodItem(name: "Meal", calories: 1_900, protein: 110)])]
        )
        XCTAssertTrue(TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: nil,
            today: nearlyComplete,
            goals: goals,
            now: date(hour: 18),
            calendar: calendar
        ).isEmpty)
    }

    func testQuietHoursSuppressInsteadOfMovingNotification() {
        let preferences = TrainingFuelNotificationPreferences(
            eveningCatchUpEnabled: true,
            quietStartMinutes: 19 * 60,
            quietEndMinutes: 7 * 60,
            eveningMinutes: 19 * 60 + 30
        )
        let log = DailyLog(
            date: date(hour: 18),
            meals: [Meal(name: "Dinner", foodItems: [FoodItem(name: "Meal", calories: 1_300, protein: 70)])]
        )

        XCTAssertTrue(TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: nil,
            today: log,
            goals: goals,
            now: date(hour: 18),
            calendar: calendar
        ).isEmpty)
    }

    func testPassedReminderMomentIsNotRecreated() {
        let preferences = TrainingFuelNotificationPreferences(preSessionEnabled: true)
        let plan = confirmedPlan(start: date(hour: 12), confirmedAt: date(hour: 8))

        XCTAssertTrue(TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: plan,
            today: nil,
            goals: goals,
            now: date(hour: 11),
            calendar: calendar
        ).isEmpty)
    }

    private func confirmedPlan(start: Date, confirmedAt: Date) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(
            candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
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
                TrainingFuelAllocation(phase: .beforeTraining, timing: .thirtyTo120Minutes, proteinGrams: 15, carbGrams: 35),
                TrainingFuelAllocation(phase: .afterTraining, timing: .afterSession, proteinGrams: 25, carbGrams: 45)
            ],
            notes: []
        )
        return TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: goals,
            today: DailyLog(date: start, meals: []),
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
