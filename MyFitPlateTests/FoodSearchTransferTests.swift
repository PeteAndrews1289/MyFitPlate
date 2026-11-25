import Combine
import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class FoodSearchTransferTests: XCTestCase {
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var model: FoodSearchViewModel!
    private var directory: URL!
    private var source: DiaryDayContext!
    private var destination: DiaryDayContext!
    private var sourceLog: DailyLog!
    private var subscriptions = Set<AnyCancellable>()
    private var owner = ""

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        owner = "search-transfer-\(UUID().uuidString)"
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        service = DailyLogService(undoStore: EditorDraftStore(directory: directory)); service.activateAccount(owner)
        let zone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        destination = DiaryDayContext(userID: owner, date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!, timeZone: zone)
        source = destination.adding(days: -1)
        sourceLog = DailyLog(id: source.dayKey, date: source.originalDate, meals: [
            Meal(name: "Lunch", foodItems: [FoodItem(id: "rice", name: "Rice", calories: 200), FoodItem(id: "chicken", name: "Chicken", calories: 300)]),
            Meal(name: "Dinner", foodItems: [FoodItem(id: "salmon", name: "Salmon", calories: 400)])
        ])
        repository.mockLogsByDay = [sourceLog, DailyLog(id: destination.dayKey, date: destination.originalDate, meals: [])]
        model = FoodSearchViewModel(selectedMeal: "Lunch", draftStore: EditorDraftStore(directory: directory))
        model.setup(dailyLogService: service)
    }

    override func tearDown() {
        subscriptions = []
        service.activateAccount(nil)
        model = nil; service = nil
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        super.tearDown()
    }

    private func loadPreviousDay() async throws {
        let loaded: Result<DailyLog, Error> = await withCheckedContinuation { continuation in
            service.fetchLog(for: owner, day: destination) { continuation.resume(returning: $0) }
        }
        _ = try loaded.get()
        let ready = expectation(description: "Previous civil day fetched")
        model.$isFetchingYesterday.dropFirst().filter { !$0 }.prefix(1).sink { _ in ready.fulfill() }.store(in: &subscriptions)
        model.fetchYesterdayMeal(userID: owner)
        await fulfillment(of: [ready], timeout: 3)
    }

    func testMealShortcutCreatesUnsubmittedCheckedReviewWithExactSourceAndPinnedDays() async throws {
        try await loadPreviousDay()
        let session = try model.makePreviousDayTransfer(allMeals: false)
        let proposal = try XCTUnwrap(session.draft)
        XCTAssertEqual(proposal.source, source)
        XCTAssertEqual(proposal.destination, destination)
        XCTAssertEqual(proposal.source.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(destination.originalDate.timeIntervalSince(source.originalDate), 23 * 3_600, "Previous day follows the captured DST calendar")
        XCTAssertEqual(proposal.entries.map { $0.originalFood.id }, ["rice", "chicken"])
        XCTAssertTrue(proposal.entries.allSatisfy { $0.originalMealID == sourceLog.meals[0].id && $0.destinationMealName == "Lunch" })
        XCTAssertTrue(proposal.entries.allSatisfy { $0.destinationFoodID != $0.originalFood.id })
        XCTAssertNil(session.command, "Opening the review cannot submit or freeze a transfer")
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        XCTAssertTrue(repository.savedDailyLogs.isEmpty)
    }

    func testAllMealsReviewPreservesMappingAndSupportsExclusionAndPortionChangesWithoutWriting() async throws {
        try await loadPreviousDay()
        let session = try model.makePreviousDayTransfer(allMeals: true)
        XCTAssertEqual(session.draft?.entries.map(\.destinationMealName), ["Lunch", "Lunch", "Dinner"])
        XCTAssertTrue(session.updateDraft { draft in
            draft.entries[0].isIncluded = false
            draft.entries[1].multiplier = 1.5
            draft.entries[2].destinationMealName = "Snacks"
        })
        let frozen = try XCTUnwrap(session.draft).freeze()
        XCTAssertEqual(frozen.entries.map { $0.originalFood.id }, ["chicken", "salmon"])
        XCTAssertEqual(frozen.entries.map(\.destinationMealName), ["Lunch", "Snacks"])
        XCTAssertEqual(frozen.entries.first?.destinationFood.calories, 450)
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        XCTAssertEqual(sourceLog.meals[0].foodItems[0].calories, 200)
    }

    func testDestinationOrAccountChangeCannotReuseStalePreviousDaySnapshot() async throws {
        try await loadPreviousDay()
        service.activelyViewedDate = destination.adding(days: -2)!.originalDate
        XCTAssertThrowsError(try model.makePreviousDayTransfer(allMeals: true))
        service.activelyViewedDate = destination.originalDate
        auth.currentUserID = "other-account"
        XCTAssertThrowsError(try model.makePreviousDayTransfer(allMeals: false))
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
    }

    func testUnfinishedReviewIsResumedWithoutOverwritingItsStableFoodIdentitiesOrAmounts() async throws {
        try await loadPreviousDay()
        let first = try model.makePreviousDayTransfer(allMeals: false)
        XCTAssertTrue(first.updateDraft { $0.entries[0].multiplier = 0.5 })
        let original = try XCTUnwrap(first.draft)
        let resumed = try model.makePreviousDayTransfer(allMeals: true)
        XCTAssertEqual(resumed.draft?.id, original.id)
        XCTAssertEqual(resumed.draft?.entries.map(\.destinationFoodID), original.entries.map(\.destinationFoodID))
        XCTAssertEqual(resumed.draft?.entries.first?.multiplier, 0.5)
        XCTAssertEqual(resumed.draft?.entries.count, 2, "A new shortcut must not silently replace an unfinished review")
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
    }
}
