import XCTest
@testable import MyFitPlateCore

@MainActor
final class WeeklyRecapEvidenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private func session(_ id: String, at date: Date, load: Double = 100,
                         equipment: StrengthEquipment? = nil) -> WorkoutSessionLog {
        var exercise = RoutineExercise(name: "Row", type: .strength, sets: [])
        exercise.loadEquipment = equipment
        let result = CompletedExercise(exerciseName: "Row", exercise: exercise,
            sets: [CompletedSet(reps: 8, weight: load, distance: 0, durationInSeconds: 0)])
        return WorkoutSessionLog(id: id, date: date, routineID: "r", completedExercises: [result])
    }
    private func recap(ending: Date? = nil, sessions: [WorkoutSessionLog] = [],
                       logs: [DailyLog] = [], targets: [WeeklyRecapTargetDay]? = nil) -> WeeklyRecap {
        WeeklyRecapBuilder.build(weekEnding: ending ?? date(7), calendar: calendar, dailyLogs: logs,
            sessionLogs: sessions, priorSessionLogs: sessions, weightHistory: [], calorieGoal: 2_000,
            proteinGoal: 100, dailyTargets: targets, now: date(20))
    }
    private func food(day: Int, complete: Bool, calories: Double = 2_000) -> DailyLog {
        DailyLog(date: date(day), meals: [Meal(name: "Lunch", foodItems: [
            FoodItem(name: "Meal", calories: calories, protein: 100)
        ])], nutritionDayStatus: complete ? .complete : .partial)
    }

    func testCalendarWindowsRemainDisjointAcrossDSTAndIncludeFractionalLastSecond() {
        let window = WeeklyRecapWindow(endingOn: date(7), calendar: calendar)
        let prior = window.preceding(calendar: calendar)
        XCTAssertEqual(prior.endExclusive, window.start)
        XCTAssertEqual(window.endExclusive.timeIntervalSince(window.start), 169 * 3_600, accuracy: 0.01)
        let edge = window.endExclusive.addingTimeInterval(-0.0001)
        XCTAssertTrue(window.contains(edge)); XCTAssertFalse(window.contains(window.endExclusive))
        let report = recap(sessions: [session("inside", at: edge), session("outside", at: window.endExclusive)])
        XCTAssertEqual(report.workoutsCompleted, 1)
        XCTAssertEqual(report.totalVolume, 800)
    }

    func testRecapUsesCanonicalLoadMeaningAndSeparatesDifferentEquipmentRecords() {
        let total = StrengthEquipment(loadingMeaning: .total, name: "Cable A", availableWeights: [80, 100])
        let other = StrengthEquipment(loadingMeaning: .total, name: "Cable B", availableWeights: [80, 100])
        let assist = StrengthEquipment(loadingMeaning: .assistance, name: "Assisted row", availableWeights: [80, 100])
        let older = session("older", at: date(1).addingTimeInterval(-7 * 86_400), load: 80, equipment: total)
        let current = session("current", at: date(3), equipment: other)
        let assisted = session("assisted", at: date(4), equipment: assist)
        let values = [older, current, assisted, current]
        let report = recap(sessions: values)
        XCTAssertEqual(report.workoutsCompleted, 2, "A replayed session cannot inflate the week")
        XCTAssertEqual(report.workingSetCount, 2)
        XCTAssertEqual(report.totalVolume, 800, "Assistance is not added load")
        XCTAssertEqual(report.personalRecords, 0, "A different implement cannot beat an incompatible baseline")
        XCTAssertEqual(recap(sessions: [older, session("matched", at: date(3), equipment: total)]).personalRecords, 1)
    }

    func testDailyTargetsExcludeUnknownAndPartialDaysWithoutChangingMeasuredIntake() {
        let report = recap(logs: [food(day: 2, complete: true), food(day: 3, complete: false), food(day: 4, complete: true)],
            targets: [WeeklyRecapTargetDay(date: calendar.startOfDay(for: date(4)), calories: 2_000, protein: 100)])
        XCTAssertEqual(report.daysLogged, 3)
        XCTAssertEqual(report.averageCalories, 2_000)
        XCTAssertEqual(report.calorieAdherence, .init(completed: 1, eligible: 1))
        XCTAssertEqual(report.proteinAdherence, .init(completed: 1, eligible: 1))
        let unknown = recap(logs: [food(day: 2, complete: true)], targets: [])
        XCTAssertEqual(unknown.calorieAdherence.eligible, 0)
        XCTAssertEqual(unknown.averageCalories, 2_000)
    }

    func testUnrecordedHardDayIsUnknownRatherThanNutritionFailure() {
        var hard = session("hard", at: date(3))
        hard.completedExercises[0].sets = Array(repeating: hard.completedExercises[0].sets[0], count: 8)
        let report = recap(sessions: [hard])
        XCTAssertEqual(report.demandingStrengthDays, 1)
        XCTAssertEqual(report.demandingStrengthDaysLogged, 0)
        XCTAssertEqual(report.demandingStrengthFuelAdherence.eligible, 0)
    }

    func testTargetReceiptsDoNotLeakBeforeDecisionAcrossAccountsOrThroughChangeDay() throws {
        let before = GoalEditorDraft(age: 30, gender: "Male", weight: 180, height: 178, activityLevel: 1.5,
            goal: "Maintain", targetWeight: nil, weeklyChangeLbs: 0, method: .custom, calories: 2_000,
            proteinPercentage: 25, carbsPercentage: 45, fatsPercentage: 30)
        let evidence = AdaptiveGoalService.ExpenditureSnapshot(recentWeighInCount: 21, recentLogCount: 21,
            last21DaysCalorieAverage: 2_200, weightChangeRatePerDay: 0, calculatedTDEE: 2_400,
            dataConfidence: .high, validLogCount: 21, recentWorkoutCount: 0, isActionable: true)
        let proposal = try WeeklyTargetProposal(userID: "owner", before: before, evidence: evidence,
            evidenceFingerprint: "supported", now: date(3), calendar: calendar)
        let decision = WeeklyTargetDecision(proposal: proposal, choice: .accept, now: date(3))
        let window = WeeklyRecapWindow(endingOn: date(7), calendar: calendar)
        let days = WeeklyRecapTargetRules.days(in: window, decisions: [decision], userID: "owner", now: date(7), calendar: calendar)
        XCTAssertEqual(days.map { calendar.component(.day, from: $0.date) }, [4, 5, 6, 7])
        XCTAssertTrue(WeeklyRecapTargetRules.days(in: window, decisions: [decision], userID: "other", now: date(7), calendar: calendar).isEmpty)
        XCTAssertTrue(WeeklyRecapTargetRules.days(in: window, decisions: [decision], userID: "owner", now: date(2), calendar: calendar).isEmpty)
        XCTAssertTrue(WeeklyRecapTargetRules.days(in: window, decisions: [WeeklyTargetDecision(proposal: proposal, choice: .deferReview, now: date(3))], userID: "owner", now: date(7), calendar: calendar).isEmpty)
    }

    func testRevisionsAreDeterministicAndRetainPreparedVersionAfterLateCorrection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WeeklyRecapJournal(store: EditorDraftStore(directory: directory))
        let window = WeeklyRecapWindow(endingOn: date(7), calendar: calendar)
        let initial = try WeeklyRecapRevision(ownerID: "owner", window: window, sourceFingerprint: "source1",
            recap: recap(sessions: [session("s", at: date(4))]), prior: recap(ending: date(1)), coverage: "Complete", now: date(8))
        let replay = try WeeklyRecapRevision(ownerID: "owner", window: window, sourceFingerprint: "source1",
            recap: initial.recap, prior: initial.prior, coverage: "Complete", now: date(9))
        XCTAssertEqual(initial.id, replay.id)
        try store.remember(initial, currentUserID: "owner")
        try store.prepareForSharing(initial, currentUserID: "owner", now: date(8))
        let corrected = try WeeklyRecapRevision(ownerID: "owner", window: window, sourceFingerprint: "source2",
            recap: recap(sessions: [session("s", at: date(4), load: 110)]), prior: initial.prior, coverage: "Complete", now: date(9))
        XCTAssertNotEqual(corrected.id, initial.id)
        try store.remember(corrected, currentUserID: "owner")
        let reopened = WeeklyRecapJournal(store: EditorDraftStore(directory: directory))
        let retained = try reopened.revisions(ownerID: "owner", window: window)
        XCTAssertEqual(retained.count, 2)
        XCTAssertEqual(retained[0].recap.totalVolume, 800)
        XCTAssertEqual(retained[1].recap.totalVolume, 880)
        XCTAssertTrue(try reopened.revisions(ownerID: "other", window: window).isEmpty)
        XCTAssertThrowsError(try reopened.remember(corrected, currentUserID: "other"))
        let csv = WeeklyRecapCSVExporter.csvString(for: retained[0].recap, metric: false,
            revisionID: retained[0].id, timeZoneID: window.timeZoneID)
        XCTAssertTrue(csv.contains(initial.id)); XCTAssertTrue(csv.contains("America/New_York"))
        XCTAssertFalse(csv.contains("owner")); XCTAssertFalse(csv.contains("source1"))
    }

    func testIntentionSurvivesRelaunchBelongsToFollowingWindowAndRejectsStaleReflection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WeeklyRecapJournal(store: EditorDraftStore(directory: directory))
        let window = WeeklyRecapWindow(endingOn: date(7), calendar: calendar)
        let revision = try WeeklyRecapRevision(ownerID: "owner", window: window, sourceFingerprint: "s",
            recap: recap(), prior: recap(ending: date(1)), coverage: "Complete", now: date(8))
        let pinned = try store.pin(text: "Log effort after each set", from: revision, currentUserID: "owner", now: date(8), calendar: calendar)
        XCTAssertEqual(pinned.targetWindow.start, window.endExclusive)
        let reopened = WeeklyRecapJournal(store: EditorDraftStore(directory: directory))
        XCTAssertEqual(try reopened.intention(ownerID: "owner", targetWindow: pinned.targetWindow), pinned)
        let reflected = try reopened.reflect(on: pinned, outcome: .partly, currentUserID: "owner", now: date(14))
        XCTAssertEqual(reflected.outcome, .partly)
        XCTAssertThrowsError(try reopened.reflect(on: pinned, outcome: .followedThrough, currentUserID: "owner"))
        XCTAssertThrowsError(try reopened.pin(text: "Another", from: revision, currentUserID: "other"))
        XCTAssertNil(try reopened.intention(ownerID: "other", targetWindow: pinned.targetWindow))
    }
    func testHistoricalRecoveryUsesOnlyWeightRecordedBeforeEachRunAndKeepsUnknownSeparate() {
        var run = Run(id: "r", source: .recorded, startDate: date(4), endDate: date(4).addingTimeInterval(1_800),
                      distanceMeters: 10_000, movingSeconds: 1_800)
        run.activeCalories = 500
        let food = FoodItem(name: "Recovery", calories: 450, protein: 40, carbs: 60,
                            timestamp: run.endDate.addingTimeInterval(600))
        let log = DailyLog(date: date(4), meals: [Meal(name: "Recovery", foodItems: [food])])
        func build(_ weights: [(id: String, date: Date, weight: Double)]) -> WeeklyRecap {
            WeeklyRecapBuilder.build(weekEnding: date(7), calendar: calendar, dailyLogs: [log], sessionLogs: [],
                priorSessionLogs: [], weightHistory: weights, runs: [run], calorieGoal: nil, bodyWeightLbs: 250,
                requireHistoricalRecoveryWeight: true, now: date(20))
        }
        let known = build([("before", date(3), 120), ("later", date(8), 250)])
        XCTAssertEqual(known.recoveryFuelAdherence, .init(completed: 1, eligible: 1))
        XCTAssertEqual(known.recoveryFuelUnknownRuns, 0)
        let unknown = build([("later", date(8), 250)])
        XCTAssertEqual(unknown.recoveryFuelAdherence.eligible, 0)
        XCTAssertEqual(unknown.recoveryFuelUnknownRuns, 1)
        XCTAssertEqual(known.runMeters, unknown.runMeters, "Missing target evidence does not remove the run itself")
    }

}
