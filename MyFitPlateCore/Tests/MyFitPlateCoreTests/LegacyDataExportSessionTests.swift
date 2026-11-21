import XCTest
@testable import MyFitPlateCore

@MainActor
final class LegacyDataExportSessionTests: XCTestCase {
    private let owner = "export-owner"
    private var auth: MockAuthService!
    private var nutrition: MockNutritionRepository!
    private var workouts: MockWorkoutRepository!
    private var previousAuth: AuthServiceProtocol?
    private var previousNutrition: NutritionRepositoryProtocol?
    private var previousWorkouts: WorkoutRepositoryProtocol?
    private var directory: URL!

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousNutrition = DIContainer.shared.nutritionRepository
        previousWorkouts = DIContainer.shared.workoutRepository
        auth = MockAuthService(); auth.currentUserID = owner
        nutrition = MockNutritionRepository(); workouts = MockWorkoutRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = nutrition
        DIContainer.shared.workoutRepository = workouts
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousNutrition
        DIContainer.shared.workoutRepository = previousWorkouts
        super.tearDown()
    }

    func testConfirmedEmptySourcesProduceOnlyTheLegacyHeadersAndCleanupRemovesBothFiles() async throws {
        let session = LegacyDataExportSession(directory: directory)
        let accepted = await session.generate(for: owner)
        XCTAssertTrue(accepted)
        XCTAssertEqual(session.ownerID, owner)
        XCTAssertEqual(session.urls.count, 2)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(try String(contentsOf: session.urls[0]), "date,meal,food,calories,protein_g,carbs_g,fats_g,serving,serving_weight_g")
        XCTAssertEqual(try String(contentsOf: session.urls[1]), "date,exercise,set,weight_lbs,reps,distance_miles,duration_seconds")
        let files = session.urls
        session.cleanup()
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testPopulatedSourcesWriteMatchingValuesAndSpreadsheetSafeNames() async throws {
        let food = FoodItem(id: "food-1", name: "=SUM(A1:A3)", calories: 350, protein: 25, carbs: 40, fats: 10,
                            servingSize: "2 cups", servingWeight: 250)
        nutrition.mockFetchDailyHistoryResult = .success([DailyLog(date: Date(), meals: [Meal(name: "Lunch", foodItems: [food])])])
        let exercise = RoutineExercise(name: "@Exercise", type: .strength, sets: [])
        workouts.mockFetchRecentSessionLogsResult = [WorkoutSessionLog(date: Date(), routineID: "routine", completedExercises: [
            CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: [CompletedSet(reps: 8, weight: 125)])
        ])]
        let session = LegacyDataExportSession(directory: directory)
        let accepted = await session.generate(for: owner)
        XCTAssertTrue(accepted)
        XCTAssertTrue(try String(contentsOf: session.urls[0]).contains("Lunch,'=SUM(A1:A3),350,25,40,10,2 cups,250"))
        XCTAssertTrue(try String(contentsOf: session.urls[1]).contains("'@Exercise,1,125,8,0,0"))
    }

    func testFailedFoodReadCannotCreateHeaderOnlySuccessAndCanRetry() async {
        nutrition.mockFetchDailyHistoryResult = .failure(URLError(.notConnectedToInternet))
        let session = LegacyDataExportSession(directory: directory)
        let failed = await session.generate(for: owner)
        XCTAssertFalse(failed)
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertFalse(session.isExporting)
        XCTAssertTrue(session.errorMessage?.contains("food diary") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        nutrition.mockFetchDailyHistoryResult = .success([])
        let retried = await session.generate(for: owner)
        XCTAssertTrue(retried)
        XCTAssertEqual(session.urls.count, 2)
        XCTAssertNil(session.errorMessage)
    }

    func testFailedWorkoutReadDoesNotExportTheSuccessfulFoodHalf() async {
        nutrition.mockFetchDailyHistoryResult = .success([DailyLog(date: Date(), meals: [])])
        workouts.fetchRecentSessionLogsError = URLError(.cannotConnectToHost)
        let session = LegacyDataExportSession(directory: directory)
        let accepted = await session.generate(for: owner)
        XCTAssertFalse(accepted)
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertTrue(session.errorMessage?.contains("workout history") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testActualFileWriteFailureHasNoFilesOrSuccessThenRetriesAfterRepair() async throws {
        try Data("Not a directory".utf8).write(to: directory)
        let session = LegacyDataExportSession(directory: directory)
        let failed = await session.generate(for: owner)
        XCTAssertFalse(failed)
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertTrue(session.errorMessage?.contains("CSV files") == true)
        XCTAssertEqual(try String(contentsOf: directory), "Not a directory")
        try FileManager.default.removeItem(at: directory)
        let retried = await session.generate(for: owner)
        XCTAssertTrue(retried)
        XCTAssertEqual(session.urls.count, 2)
    }

    func testCancelDuringFetchPreventsLatePublicationAndAllowsFreshRetry() async {
        nutrition.fetchDailyHistoryDelayNanoseconds = 40_000_000
        let session = LegacyDataExportSession(directory: directory)
        let old = Task { await session.generate(for: owner) }
        await waitUntilExporting(session)
        session.cancel()
        XCTAssertFalse(session.isExporting)
        XCTAssertTrue(session.urls.isEmpty)
        nutrition.fetchDailyHistoryDelayNanoseconds = 0
        let retry = await session.generate(for: owner)
        XCTAssertTrue(retry)
        let retryURLs = session.urls
        let oldResult = await old.value
        XCTAssertFalse(oldResult)
        XCTAssertEqual(session.urls, retryURLs)
        XCTAssertNil(session.errorMessage)
    }

    func testAccountChangeBeforeOrDuringExportCannotPublishAnotherAccountsFiles() async {
        let session = LegacyDataExportSession(directory: directory)
        auth.currentUserID = "other"
        let before = await session.generate(for: owner)
        XCTAssertFalse(before)
        XCTAssertTrue(session.urls.isEmpty)
        auth.currentUserID = owner
        nutrition.fetchDailyHistoryDelayNanoseconds = 40_000_000
        let pending = Task { await session.generate(for: owner) }
        await waitUntilExporting(session)
        auth.currentUserID = "other"
        let during = await pending.value
        XCTAssertFalse(during)
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertTrue(session.errorMessage?.contains("account changed") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDoubleTapDoesNotCreateConcurrentExports() async {
        nutrition.fetchDailyHistoryDelayNanoseconds = 40_000_000
        let session = LegacyDataExportSession(directory: directory)
        let first = Task { await session.generate(for: owner) }
        await waitUntilExporting(session)
        let duplicate = await session.generate(for: owner)
        XCTAssertFalse(duplicate)
        let accepted = await first.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(session.urls.count, 2)
    }

    private func waitUntilExporting(_ session: LegacyDataExportSession) async {
        for _ in 0..<100 where !session.isExporting { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(session.isExporting)
    }
}
