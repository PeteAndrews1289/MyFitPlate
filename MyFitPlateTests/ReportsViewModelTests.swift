import XCTest
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
            ]
        )
    }
}
