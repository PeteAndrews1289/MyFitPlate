import XCTest
@testable import MyFitPlateCore

@MainActor
final class ExerciseLogStoreTests: XCTestCase {
    private var service: DailyLogService!
    private var mockRepo: MockNutritionRepository!
    private var store: ExerciseLogStore!

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = MockAuthService()
        service = DailyLogService()
        store = ExerciseLogStore(dailyLogService: service)
    }

    override func tearDown() {
        store = nil
        service = nil
        mockRepo = nil
        super.tearDown()
    }

    private func fixedDay(_ dayOffset: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_725_235_200)
        return Calendar.current.startOfDay(for: base.addingTimeInterval(Double(dayOffset) * 86_400))
    }

    private func exercise(
        id: String,
        name: String,
        date: Date,
        source: String = "manual",
        calories: Double = 200
    ) -> LoggedExercise {
        LoggedExercise(
            id: id,
            name: name,
            durationMinutes: 30,
            caloriesBurned: calories,
            date: date,
            source: source
        )
    }

    func testAddExerciseAppendsToLogAndUsesViewedDate() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "log-1", date: viewedDate, meals: []))

        store.addExerciseToLog(
            for: "user-1",
            exercise: exercise(id: "exercise-1", name: "Rowing", date: fixedDay(-1), calories: 180)
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        let exercises = try XCTUnwrap(updatedLog.exercises)
        XCTAssertEqual(exercises.map(\.id), ["exercise-1"])
        XCTAssertEqual(exercises[0].name, "Rowing")
        XCTAssertEqual(exercises[0].caloriesBurned, 180)
        XCTAssertEqual(exercises[0].date, viewedDate)
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.id), ["exercise-1"])
    }

    func testAddExerciseInitializesMissingExerciseArray() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        var log = DailyLog(id: "log-1", date: viewedDate, meals: [])
        log.exercises = nil
        mockRepo.mockFetchLogResult = .success(log)

        store.addExerciseToLog(
            for: "user-1",
            exercise: exercise(id: "exercise-1", name: "Bike", date: viewedDate)
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.name), ["Bike"])
    }

    func testDeleteExerciseRemovesOnlyMatchingEntry() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let keep = exercise(id: "keep", name: "Run", date: viewedDate)
        let remove = exercise(id: "remove", name: "Swim", date: viewedDate)
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: "log-1", date: viewedDate, meals: [], exercises: [keep, remove])
        )

        store.deleteExerciseFromLog(for: "user-1", exerciseID: "remove")

        try await Task.sleep(nanoseconds: 50_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["keep"])
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.id), ["keep"])
    }

    func testDeleteExerciseSkipsUpdateWhenExerciseIsMissing() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let existing = exercise(id: "keep", name: "Run", date: viewedDate)
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: "log-1", date: viewedDate, meals: [], exercises: [existing])
        )

        store.deleteExerciseFromLog(for: "user-1", exerciseID: "missing")

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertNil(service.currentDailyLog)
    }

    func testHealthKitSyncReplacesPreviousHealthKitWorkoutsAndKeepsManualEntries() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let manual = exercise(id: "manual", name: "Strength", date: viewedDate, source: "routine")
        let oldHealthKit = exercise(id: "old-hk", name: "Old Walk", date: viewedDate, source: "HealthKit")
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: "log-1", date: viewedDate, meals: [], exercises: [manual, oldHealthKit])
        )

        let synced = [
            exercise(id: "new-hk-1", name: "Outdoor Run", date: viewedDate, source: "HealthKit", calories: 325),
            exercise(id: "new-hk-2", name: "Cooldown", date: viewedDate, source: "HealthKit", calories: 80)
        ]
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(for: "user-1", exercises: synced, date: viewedDate) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["manual", "new-hk-1", "new-hk-2"])
        XCTAssertEqual(updatedLog.exercises?.map(\.source), ["routine", "HealthKit", "HealthKit"])
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.id), ["manual", "new-hk-1", "new-hk-2"])
    }

    func testHealthKitSyncStillSavesWhenSyncedDateIsNotCurrentlyViewed() async throws {
        let viewedDate = fixedDay()
        let syncedDate = fixedDay(-1)
        service.activelyViewedDate = viewedDate
        mockRepo.mockFetchLogResult = .success(
            DailyLog(id: "log-1", date: syncedDate, meals: [], exercises: [])
        )
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(
            for: "user-1",
            exercises: [exercise(id: "new-hk", name: "Walk", date: syncedDate, source: "HealthKit")],
            date: syncedDate
        ) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.id), ["new-hk"])
        XCTAssertNil(service.currentDailyLog)
    }

    func testHealthKitSyncCallsCompletionWithoutSavingWhenFetchFails() async {
        service.activelyViewedDate = fixedDay()
        mockRepo.mockFetchLogResult = .failure(URLError(.notConnectedToInternet))
        let finished = expectation(description: "HealthKit sync completion")

        store.addOrUpdateHealthKitWorkouts(
            for: "user-1",
            exercises: [exercise(id: "new-hk", name: "Walk", date: fixedDay(), source: "HealthKit")],
            date: fixedDay()
        ) {
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }
}
