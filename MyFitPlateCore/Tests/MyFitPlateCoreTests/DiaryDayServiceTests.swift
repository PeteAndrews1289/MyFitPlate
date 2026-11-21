import XCTest
@testable import MyFitPlateCore

@MainActor
final class DiaryDayServiceTests: XCTestCase {
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private var directory: URL!
    private let owner = "diary-day-service-tests"

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        service = DailyLogService(undoStore: EditorDraftStore(directory: directory)); service.activateAccount(owner)
    }

    override func tearDown() {
        service.activateAccount(nil)
        try? FileManager.default.removeItem(at: directory)
        try? EditorDraftStore().removeAll(userID: owner)
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        super.tearDown()
    }

    private func context(_ date: Date = Date(), key: String? = nil, zone: String = "America/New_York") throws -> DiaryDayContext {
        try XCTUnwrap(DiaryDayContext(userID: owner, date: date, timeZone: TimeZone(identifier: zone)!, dayKey: key))
    }

    private func load(_ day: DiaryDayContext) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            service.fetchLog(for: owner, day: day) { continuation.resume(with: $0) }
        }
    }

    func testExistingDocumentKeyAndCapturedZoneRemainAuthoritative() async throws {
        let day = try context(Date(timeIntervalSince1970: 1_700_000_000), key: "2023-11-12", zone: "Asia/Tokyo")
        repository.mockLogsByDay = [DailyLog(id: day.dayKey, date: day.originalDate, meals: [])]
        _ = try await load(day)
        let restored = try XCTUnwrap(service.diaryDayContext(for: owner, date: day.originalDate))
        XCTAssertEqual(restored, day)
        XCTAssertEqual(repository.logSnapshotListenerDayKeys, ["2023-11-12"])
        XCTAssertEqual(service.activelyViewedDayContext, day)
        XCTAssertNil(service.diaryDayContext(for: "different-owner", date: day.originalDate))
    }

    func testDelayedEarlierListenerCannotReplaceNewDay() async throws {
        let day = try context()
        let previous = try XCTUnwrap(day.adding(days: -1))
        repository.shouldDeferLogSnapshotCallbacks = true
        var oldRejected = false
        service.fetchLog(for: owner, day: previous) { if case .failure = $0 { oldRejected = true } }
        let stale = try XCTUnwrap(repository.logSnapshotCallbacks[owner])
        let accepted = expectation(description: "selected day accepted")
        service.fetchLog(for: owner, day: day) { result in
            XCTAssertEqual(try? result.get().id, day.dayKey); accepted.fulfill()
        }
        stale(.success(DailyLog(id: previous.dayKey, date: previous.originalDate, meals: [])))
        repository.emitLogSnapshot(.success(DailyLog(id: day.dayKey, date: day.originalDate, meals: [])), for: owner)
        await fulfillment(of: [accepted], timeout: 2)
        XCTAssertTrue(oldRejected)
        XCTAssertEqual(service.currentDailyLog?.id, day.dayKey)
    }

    func testWrongDayListenerResultFailsWithoutPublishingIt() async throws {
        let day = try context()
        repository.mockFetchLogResult = .success(DailyLog(id: "2020-01-01", date: day.originalDate, meals: []))
        do { _ = try await load(day); XCTFail("Wrong-day log must be rejected") } catch {}
        XCTAssertNil(service.currentDailyLog)
    }

    func testTransferPublishesOnlySelectedDayAndDoesNotCreateGenericUndo() async throws {
        let source = try context(Date().addingTimeInterval(-86_400))
        let destination = try XCTUnwrap(source.adding(days: -1))
        let food = FoodItem(id: "source", name: "Oats", calories: 200)
        let log = DailyLog(id: source.dayKey, date: source.originalDate, meals: [Meal(name: "Breakfast", foodItems: [food])])
        repository.mockLogsByDay = [log]
        _ = try await load(source)
        let draft = try DiaryTransferDraft(source: source, destination: destination, sourceLog: log, mode: .copy)
        let session = DiaryTransferSession(userID: owner, draft: draft, store: EditorDraftStore(directory: directory))
        let response = await service.performDiaryTransfer(session)
        let result = try XCTUnwrap(response)
        XCTAssertEqual(result.destinationLog.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(service.currentDailyLog?.id, source.dayKey)
        XCTAssertEqual(service.currentDailyLog?.meals.flatMap(\.foodItems).map(\.id), [food.id])
        XCTAssertFalse(service.canUndoDiaryChange, "Transfers use their exact durable receipt")
    }

    func testOrdinarySaveIsRejectedWhileTransferOwnsTheDayAndRetryKeepsIntent() async throws {
        let day = try context(Date().addingTimeInterval(-86_400))
        let food = FoodItem(id: "source", name: "Oats", calories: 200)
        let log = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Breakfast", foodItems: [food])])
        repository.mockLogsByDay = [log]; repository.diaryTransferDelayNanoseconds = 150_000_000
        _ = try await load(day)
        let draft = try DiaryTransferDraft(source: day, destination: day, sourceLog: log, mode: .copy)
        let session = DiaryTransferSession(userID: owner, draft: draft, store: EditorDraftStore(directory: directory))
        let transfer = Task { await service.performDiaryTransfer(session) }
        while !session.isSaving { await Task.yield() }
        let accepted = await withCheckedContinuation { continuation in
            service.addMealGroupsToLog(for: owner, date: day.originalDate, mealGroups: [("Lunch", [FoodItem(id: "new", name: "Milk", calories: 100)])], source: "test", dayContext: day) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(accepted)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        let result = await transfer.value
        XCTAssertNotNil(result)
        XCTAssertEqual(service.currentDailyLog?.meals.flatMap(\.foodItems).count, 2)
    }

    func testLateTransferResultCannotHideANewerPublishedListenerSnapshot() async throws {
        let day = try context(Date().addingTimeInterval(-86_400))
        let food = FoodItem(id: "source", name: "Oats", calories: 200)
        let log = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Breakfast", foodItems: [food])])
        repository.mockLogsByDay = [log]; repository.diaryTransferDelayNanoseconds = 150_000_000
        _ = try await load(day)
        let draft = try DiaryTransferDraft(source: day, destination: day, sourceLog: log, mode: .copy)
        let session = DiaryTransferSession(userID: owner, draft: draft, store: EditorDraftStore(directory: directory))
        let task = Task { await service.performDiaryTransfer(session) }
        while !session.isSaving { await Task.yield() }
        var newer = log
        newer.meals[0].foodItems.append(FoodItem(id: "remote-new", name: "New remote food", calories: 50))
        service.publishCurrentDailyLog(newer)
        let result = await task.value
        XCTAssertNotNil(result)
        XCTAssertEqual(service.currentDailyLog?.meals.flatMap(\.foodItems).map(\.id), ["source", "remote-new"])
    }

    func testStatusRefreshRetainsLocallyAcceptedFoodsThroughRepositoryOutboxOverlay() async throws {
        let day = try context(Date().addingTimeInterval(-86_400))
        let log = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "source", name: "Rice", calories: 100)])])
        repository.mockLogsByDay = [log]
        _ = try await load(day)
        let draft = try DiaryTransferDraft(source: day, destination: day, sourceLog: log, mode: .copy)
        let accepted = try await repository.applyDiaryTransfer(userID: owner, command: draft.freeze())
        var local = accepted.destinationLog
        local.meals[0].foodItems.append(FoodItem(id: "accepted-outbox-food", name: "Local accepted food", calories: 50))
        repository.mockFetchLogResult = .success(local)
        service.publishCurrentDailyLog(local)
        let session = DiaryTransferSession(userID: owner, store: EditorDraftStore(directory: directory))
        XCTAssertTrue(session.prepareUndo(of: accepted.receipt))
        _ = await service.resolveDiaryTransferStatus(session)
        XCTAssertEqual(service.currentDailyLog?.meals.flatMap(\.foodItems).map(\.id), local.meals.flatMap(\.foodItems).map(\.id))
        XCTAssertEqual(service.currentDailyLog?.totalCalories(), 250)
        XCTAssertFalse(service.canUndoDiaryChange)
    }

    func testHealthRetryCannotCreateAnAbsentTransferReceipt() async throws {
        let day = try context(Date().addingTimeInterval(-86_400))
        let log = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "food", name: "Rice", calories: 100)])])
        let draft = try DiaryTransferDraft(source: day, destination: day, sourceLog: log, mode: .copy)
        let localOnly = try DiaryTransferRules.apply(draft.freeze(), source: log, destination: log)
        await service.retryDiaryTransferHealth(localOnly.receipt)
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        XCTAssertNotNil(service.diaryTransferErrorMessage)
    }
}
