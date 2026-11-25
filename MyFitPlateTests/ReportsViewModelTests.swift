import XCTest
import Combine
import HealthKit
@testable import MyFitPlate

@MainActor
final class ReportsViewModelTests: XCTestCase {
    private var repository: MockNutritionRepository!
    private var auth: MockAuthService!
    private var dailyLogService: DailyLogService!
    private var goals: GoalSettings!
    private var healthViewModel: HealthKitViewModel!
    private var healthManager: MockHealthKitManager!

    override func setUp() {
        super.setUp()
        repository = MockNutritionRepository()
        auth = MockAuthService()
        auth.currentUserID = "reports-user"
        DIContainer.shared.nutritionRepository = repository
        DIContainer.shared.authService = auth
        DIContainer.shared.reportsRepository = MockReportsRepository()

        dailyLogService = DailyLogService()
        dailyLogService.activateAccount("reports-user")
        goals = GoalSettings()
        goals.calories = 2_000
        healthManager = MockHealthKitManager()
        healthViewModel = HealthKitViewModel(manager: healthManager)
        healthViewModel.isAuthorized = false
    }

    func testNewerTimeframeCannotBeOverwrittenBySlowOlderRequest() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let weekStart = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -6, to: today))
        let monthStart = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -29, to: today))
        repository.mockFetchDailyHistoryResultsByStartDate[weekStart] = .success([
            log(id: "week", date: weekStart, calories: 1_100)
        ])
        repository.mockFetchDailyHistoryResultsByStartDate[monthStart] = .success([
            log(id: "month", date: monthStart, calories: 2_300)
        ])
        repository.fetchDailyHistoryDelayNanosecondsByStartDate[weekStart] = 300_000_000
        repository.fetchDailyHistoryDelayNanosecondsByStartDate[monthStart] = 10_000_000

        let viewModel = makeViewModel()
        viewModel.fetchData(for: .week)
        viewModel.fetchData(for: .month)

        try await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(viewModel.summary?.timeframe, ReportTimeframe.month.rawValue)
        XCTAssertEqual(viewModel.summary?.averageCalories ?? 0, 2_300, accuracy: 0.001)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAccountSwitchPreventsOldReportFromReappearing() async throws {
        repository.mockFetchDailyHistoryResultsByUserID["reports-user"] = .success([
            log(id: "old", date: Date(), calories: 1_100)
        ])
        repository.mockFetchDailyHistoryResultsByUserID["reports-user-2"] = .success([
            log(id: "new", date: Date(), calories: 2_400)
        ])
        repository.fetchDailyHistoryDelayNanoseconds = 250_000_000

        let viewModel = makeViewModel()
        viewModel.fetchData(for: .week)

        repository.fetchDailyHistoryDelayNanoseconds = 0
        auth.currentUserID = "reports-user-2"
        dailyLogService.activateAccount("reports-user-2")
        viewModel.fetchData(for: .week)

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(viewModel.summary?.averageCalories ?? 0, 2_400, accuracy: 0.001)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testIntakeAverageExcludesPartialUnknownAndDuplicateDays() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let older = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        var partial = log(id: "partial", date: yesterday, calories: 800)
        partial.nutritionDayStatus = .partial
        var unknown = log(id: "unknown", date: older, calories: 500)
        unknown.nutritionDayStatus = nil
        let complete = log(id: "complete", date: today, calories: 2_200)
        repository.mockFetchDailyHistoryResultsByUserID["reports-user"] = .success([complete, complete, partial, unknown])
        let viewModel = makeViewModel()
        viewModel.fetchData(for: .week)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(viewModel.summary?.averageCalories, 2_200)
        XCTAssertEqual(viewModel.summary?.daysLogged, 1)
        XCTAssertEqual(viewModel.calorieTrend.count, 3, "Partial days remain visible as recorded entries")
        XCTAssertTrue(viewModel.reportSpecificInsight?.message.contains("fully logged") == true)
    }

    func testNutritionTrendUsesCanonicalDiaryDaysAfterTravelWithoutCollapsingScopedCount() async throws {
        let calendar = Calendar.current
        let targetDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date())))
        // Choose a remote midnight that falls on another civil day in the current
        // test timezone, without changing the process timezone or any saved record.
        var remote = calendar
        let remoteOffset = calendar.timeZone.secondsFromGMT(for: targetDay) == 14 * 3600 ? -12 * 3600 : 14 * 3600
        remote.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: remoteOffset))
        let rawMidnight = try XCTUnwrap(remote.date(from: calendar.dateComponents([.year, .month, .day], from: targetDay)))
        let otherDay = calendar.startOfDay(for: rawMidnight)
        XCTAssertNotEqual(targetDay, otherDay)
        let canonicalKey = try XCTUnwrap(DiaryDayContext.dayKey(for: targetDay))
        let otherKey = try XCTUnwrap(DiaryDayContext.dayKey(for: otherDay))
        let traveler = log(id: canonicalKey, date: rawMidnight, calories: 2_100)
        let other = log(id: otherKey, date: otherDay, calories: 1_900)
        XCTAssertTrue(calendar.isDate(traveler.date, inSameDayAs: other.date))
        repository.mockFetchDailyHistoryResultsByUserID["reports-user"] = .success([traveler, other])
        let viewModel = makeViewModel()
        defer { viewModel.invalidateAccountProjection() }
        let loaded = expectation(description: "Requested nutrition range finished loading")
        let observation = viewModel.$isLoading.dropFirst().first { !$0 }.sink { _ in loaded.fulfill() }
        viewModel.fetchData(for: .custom, startDate: min(targetDay, otherDay), endDate: max(targetDay, otherDay))
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(observation) {}

        XCTAssertEqual(viewModel.summary?.daysLogged, 2, "Distinct canonical days must not collapse onto the old timestamp day")
        XCTAssertEqual(viewModel.summary?.averageCalories, 2_000)
        XCTAssertEqual(viewModel.calorieTrend.count, 2)
        XCTAssertEqual(Set(viewModel.calorieTrend.map(\.date)), Set([targetDay, otherDay]))
        let diaryDay = try XCTUnwrap(DiaryDayContext(userID: "reports-user", date: targetDay))
        XCTAssertEqual(viewModel.diaryEntry(for: diaryDay)?.id, canonicalKey)
        XCTAssertEqual(viewModel.diaryEntry(for: diaryDay)?.totalCalories(), 2_100)
        let otherOwner = try XCTUnwrap(DiaryDayContext(userID: "other-user", date: targetDay))
        XCTAssertNil(viewModel.diaryEntry(for: otherOwner))
        XCTAssertEqual(viewModel.calorieTrend.first { $0.date == targetDay }?.value, 2_100)
        XCTAssertEqual(viewModel.calorieTrend.first { $0.date == otherDay }?.value, 1_900)
        for trend in [viewModel.proteinTrend, viewModel.carbTrend, viewModel.fatTrend] {
            XCTAssertEqual(Set(trend.map(\.date)), Set([targetDay, otherDay]))
        }
        XCTAssertEqual(traveler.date, rawMidnight, "Display projection must not rewrite the saved source timestamp")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUnreviewedFoodKeepsTrendWithoutInventingAverageOrScore() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        var unknown = log(id: "unknown", date: yesterday, calories: 900)
        unknown.nutritionDayStatus = nil
        unknown.meals[0].name = "After lifting"
        let activityDate = Calendar.current.date(byAdding: .day, value: -1, to: yesterday)!
        let activityOnly = DailyLog(date: activityDate, meals: [], exercises: [
            LoggedExercise(name: "Walk", durationMinutes: 30, caloriesBurned: 100, date: activityDate)
        ])
        repository.mockFetchDailyHistoryResultsByUserID["reports-user"] = .success([unknown, activityOnly])
        let viewModel = makeViewModel()
        let loaded = expectation(description: "Unreviewed day and activity-only day loaded")
        let observation = viewModel.$isLoading.dropFirst().first { !$0 }.sink { _ in loaded.fulfill() }
        viewModel.fetchData(for: .week)
        await fulfillment(of: [loaded], timeout: 8)
        withExtendedLifetime(observation) {}
        XCTAssertNil(viewModel.summary)
        XCTAssertNil(viewModel.reportSpecificInsight)
        XCTAssertEqual(viewModel.calorieTrend.count, 1, "Activity-only days must not appear as zero food intake")
        XCTAssertTrue(viewModel.mealScore == nil || viewModel.mealScore?.grade == "N/A")
        XCTAssertEqual(viewModel.mealDistributionData.first?.mealName, "After lifting")
        XCTAssertEqual(viewModel.mealDistributionData.first?.totalCalories, unknown.totalCalories(),
                       "A day with only a workout must not lower the per-food-day meal average.")
        XCTAssertEqual(viewModel.weeklyWorkoutReport?.activeDays, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSleepHistoryPreservesSourceUnionAndCachedEvidenceAfterHealthFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SleepHistoryStore(store: EditorDraftStore(directory: directory))
        let day = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: Date()))!
        let start = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
        let end = start.addingTimeInterval(7 * 3600)
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        healthManager.sleepSamples = [
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start, end: end),
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: end)
        ]
        healthViewModel.isAuthorized = true
        let viewModel = ReportsViewModel(dailyLogService: dailyLogService, healthKitManager: healthManager, sleepHistoryStore: store)
        viewModel.setup(goals: goals, healthKitViewModel: healthViewModel)
        viewModel.fetchData(for: .custom, startDate: day, endDate: day)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.enhancedSleepReport?.averageTimeAsleep, 7 * 3600)
        XCTAssertEqual(viewModel.enhancedSleepReport?.nightEvidence.first?.sourceSampleIDs.count, 2)
        XCTAssertEqual(viewModel.enhancedSleepReport?.requestedDayCount, 1)
        XCTAssertEqual(healthManager.sleepRequestedRange?.start, Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        healthManager.sleepError = NSError(domain: "QA", code: 1)
        let restored = ReportsViewModel(dailyLogService: dailyLogService, healthKitManager: healthManager, sleepHistoryStore: store)
        restored.setup(goals: goals, healthKitViewModel: healthViewModel)
        restored.fetchData(for: .custom, startDate: day, endDate: day)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(restored.enhancedSleepReport?.averageTimeAsleep, 7 * 3600)
        XCTAssertTrue(restored.sleepHistoryNotice?.contains("saved snapshot") == true)
        XCTAssertEqual(restored.enhancedSleepReport?.nightEvidence, viewModel.enhancedSleepReport?.nightEvidence)
    }

    func testEmptyHealthReadDoesNotPretendCachedNightWasDeleted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SleepHistoryStore(store: EditorDraftStore(directory: directory))
        let day = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: Date()))!
        let start = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
        let sample = HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: start.addingTimeInterval(6 * 3600))
        let nights = SleepNightEvidence.normalize([sample])
        try store.save(SleepHistorySnapshot(ownerID: "reports-user", startDay: day, endDay: day,
            timeZoneIdentifier: Calendar.current.timeZone.identifier, nights: nights), currentUserID: "reports-user")
        healthViewModel.isAuthorized = true
        let viewModel = ReportsViewModel(dailyLogService: dailyLogService, healthKitManager: healthManager, sleepHistoryStore: store)
        viewModel.setup(goals: goals, healthKitViewModel: healthViewModel)
        viewModel.fetchData(for: .custom, startDate: day, endDate: day)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(viewModel.enhancedSleepReport?.averageTimeAsleep, 6 * 3600)
        XCTAssertTrue(viewModel.sleepHistoryNotice?.contains("may be stale") == true)
        auth.currentUserID = "different-owner"
        dailyLogService.activateAccount("different-owner")
        viewModel.fetchData(for: .custom, startDate: day, endDate: day)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(viewModel.enhancedSleepReport)
    }

    func testNoUserFetchClearsEveryReportProjectionAndCancelsLateWork() async throws {
        repository.mockFetchDailyHistoryResultsByUserID["reports-user"] = .success([log(id: "old", date: Date(), calories: 1200)])
        repository.fetchDailyHistoryDelayNanoseconds = 150_000_000
        let viewModel = makeViewModel()
        viewModel.mealScore = .noScore
        viewModel.mealScoreHistory = [DateValuePoint(date: Date(), value: 80)]
        viewModel.fetchData(for: .week)
        auth.currentUserID = nil
        viewModel.fetchData(for: .week)
        XCTAssertNil(viewModel.mealScore); XCTAssertTrue(viewModel.mealScoreHistory.isEmpty)
        XCTAssertNil(viewModel.enhancedSleepReport); XCTAssertNil(viewModel.wellnessScore)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(viewModel.summary); XCTAssertTrue(viewModel.calorieTrend.isEmpty)
    }

    private func makeViewModel() -> ReportsViewModel {
        let viewModel = ReportsViewModel(
            dailyLogService: dailyLogService,
            healthKitManager: healthManager
        )
        viewModel.setup(goals: goals, healthKitViewModel: healthViewModel)
        return viewModel
    }

    private func log(id: String, date: Date, calories: Double) -> DailyLog {
        DailyLog(
            id: id,
            date: date,
            meals: [
                Meal(
                    id: UUID(),
                    name: "Breakfast",
                    foodItems: [FoodItem(id: "\(id)-food", name: "Test food", calories: calories)]
                )
            ],
            nutritionDayStatus: .complete
        )
    }
}
