import XCTest
@testable import MyFitPlateCore

@MainActor
final class FoodCheckpointDayContextTests: XCTestCase {
    private let owner = "captured-food-day-owner"
    private var directory: URL!
    private var store: EditorDraftStore!
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var previousAuth: AuthServiceProtocol!
    private var previousRepository: NutritionRepositoryProtocol!

    override func setUp() {
        previousAuth = DIContainer.shared.authService
        previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository(); repository.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("food-day-context-\(UUID())")
        store = EditorDraftStore(directory: directory)
        service = DailyLogService(undoStore: store); service.activateAccount(owner)
    }

    override func tearDown() {
        service.activateAccount(nil)
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.nutritionRepository = previousRepository
        try? FileManager.default.removeItem(at: directory)
    }

    func testQuickLogRetryKeepsCapturedDocumentAndConsumptionAfterAnotherDayOpens() async throws {
        let day = try capturedDay()
        let queue = QuickFoodLogQueue(userID: owner, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: day.originalDate, mealName: "Lunch", source: "test",
                                                needsHydration: false, dayContext: day))
        repository.updateLogSuccess = false
        let rejected = await save(queue, id: pending.id)
        XCTAssertFalse(rejected)
        XCTAssertEqual(repository.lastUpdatedLog?.id, day.dayKey)
        let restored = QuickFoodLogQueue(userID: owner, store: store)
        let reopened = try XCTUnwrap(restored.begin(food: food(), date: Date(), mealName: "Dinner", source: "other",
                                                    needsHydration: false, dayContext: otherDay()))
        XCTAssertEqual(reopened.id, pending.id)
        XCTAssertEqual(reopened.draft.dayContext, day)
        XCTAssertEqual(reopened.draft.foods.first?.id, pending.draft.foods.first?.id)
        service.activelyViewedDate = Date()
        repository.updateLogSuccess = true
        let accepted = await save(restored, id: pending.id)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.id, day.dayKey)
        XCTAssertEqual(repository.lastUpdatedLog?.date, day.startOfDay, "A newly created empty day follows the captured civil key; the frozen checkpoint retains its original anchor")
    }

    func testDetailEditAndAddPassCapturedKeyRatherThanRebuildingItFromAnchor() async throws {
        let day = try capturedDay()
        let original = food()
        let originalLog = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [original])])
        try await repository.saveDailyLog(userID: owner, log: originalLog)
        repository.mockFetchLogResult = .success(originalLog)
        let edit = FoodDetailSaveSession(food: original, userID: owner, date: day.originalDate, mealName: "Lunch",
                                        source: "log_edit", isEditing: true, dayContext: day, store: store)
        var changed = original; changed.calories = 240
        let edited = await save(edit, food: changed)
        XCTAssertTrue(edited)
        XCTAssertEqual(repository.lastUpdatedLog?.date, originalLog.date, "Editing an existing day must preserve its stored date anchor")
        XCTAssertEqual(repository.lastUpdatedLog?.id, day.dayKey)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.id, original.id)
        let add = FoodDetailSaveSession(food: FoodItem(id: "new-source", name: "Rice", calories: 150), userID: owner,
            date: day.originalDate, mealName: "Dinner", source: "search", isEditing: false, dayContext: day, store: store)
        let added = await save(add, food: add.checkpoint.food)
        XCTAssertTrue(added)
        XCTAssertEqual(repository.lastUpdatedLog?.id, day.dayKey)
        XCTAssertEqual(add.checkpoint.dayContext, day)
    }

    func testMealReviewRestoresCapturedDayAndOnlyAnExplicitDateChangeRecapturesIt() async throws {
        let day = try capturedDay()
        let review = MealReviewSaveSession(items: [food()], userID: owner, date: day.originalDate, mealName: "Lunch",
            source: "day-test", dayContext: day, store: store)
        XCTAssertTrue(review.updateDestination(date: review.date, mealName: "Dinner"))
        XCTAssertEqual(review.checkpoint.draft.dayContext, day, "Changing a meal cannot reinterpret its day")
        repository.updateLogSuccess = false
        let rejected = await save(review)
        XCTAssertFalse(rejected)
        let consumptionIDs = review.checkpoint.draft.foods.map(\.id)
        let restored = MealReviewSaveSession(items: [], userID: owner, date: Date(), mealName: "Breakfast",
            source: "day-test", dayContext: try otherDay(), store: store)
        XCTAssertEqual(restored.checkpoint.draft.dayContext, day)
        XCTAssertEqual(restored.checkpoint.draft.foods.map(\.id), consumptionIDs)
        repository.updateLogSuccess = true
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.id, day.dayKey)

        let editable = MealReviewSaveSession(items: [food()], userID: owner, date: day.originalDate, mealName: "Lunch",
            source: "explicit-date-test", dayContext: day, store: store)
        let next = try otherDay()
        XCTAssertTrue(editable.updateDestination(date: next.originalDate, mealName: "Lunch", dayContext: next))
        XCTAssertEqual(editable.checkpoint.draft.dayContext, next)
    }

    func testLegacySubmittedDetailQueueAndReviewRemainNilAndByteUnchangedOnRestore() throws {
        let day = try capturedDay()
        let original = food()
        let legacy = LegacyDetail(original: original, entryID: "legacy-consumption", date: day.originalDate,
            mealName: "Lunch", source: "legacy", isEditing: false, food: original, isSubmitted: true,
            operationID: "legacy-operation")
        try store.save(legacy, userID: owner, scope: "food-detail-add-legacy-\(original.id)")
        var draft = FoodLoggingDraft(date: day.originalDate, mealName: "Lunch")
        draft.date = day.originalDate; draft.entries = [FoodLoggingDraft.Entry(food: original)]; draft.isSubmitted = true
        let pending = PendingQuickFoodLog(id: UUID(), sourceFoodID: original.id, draft: draft, source: "legacy")
        try store.save([pending], userID: owner, scope: "legacy-queue")
        let review = MealReviewCheckpoint(draft: draft, selectedItemIDs: [original.id], source: "legacy")
        try store.save(review, userID: owner, scope: MealReviewSaveSession.scope(for: "legacy"))
        let before = try checkpointBytes()

        let detail = FoodDetailSaveSession(food: original, userID: owner, date: Date(), mealName: "Dinner", source: "legacy",
            isEditing: false, dayContext: try otherDay(), store: store)
        XCTAssertNil(detail.checkpoint.dayContext)
        XCTAssertEqual(detail.checkpoint.operationID, "legacy-operation")
        XCTAssertEqual(detail.checkpoint.entryID, "legacy-consumption")
        XCTAssertEqual(detail.checkpoint.date, day.originalDate)
        let queue = QuickFoodLogQueue(userID: owner, store: store, scope: "legacy-queue")
        let restored = try XCTUnwrap(queue.begin(food: original, date: Date(), mealName: "Dinner", source: "new",
            needsHydration: false, dayContext: otherDay()))
        XCTAssertNil(restored.draft.dayContext)
        XCTAssertEqual(restored.id, pending.id)
        let meal = MealReviewSaveSession(items: [], userID: owner, date: Date(), mealName: "Dinner", source: "legacy",
            dayContext: try otherDay(), store: store)
        XCTAssertNil(meal.checkpoint.draft.dayContext)
        XCTAssertEqual(meal.checkpoint.draft.id, draft.id)
        XCTAssertEqual(try checkpointBytes(), before, "Opening old checkpoints must not add metadata or rewrite frozen payloads")
    }

    func testWrongOwnerContextCannotCreateOrSendAnotherAccountsFood() async throws {
        let wrong = try XCTUnwrap(DiaryDayContext(userID: "another-owner", date: capturedDay().originalDate))
        let queue = QuickFoodLogQueue(userID: owner, store: store)
        XCTAssertNil(queue.begin(food: food(), date: wrong.originalDate, mealName: "Lunch", source: "test",
                                 needsHydration: false, dayContext: wrong))
        let detail = FoodDetailSaveSession(food: food(), userID: owner, date: wrong.originalDate, mealName: "Lunch",
            source: "wrong-owner", isEditing: false, dayContext: wrong, store: store)
        let accepted = await save(detail, food: food())
        XCTAssertFalse(accepted)
        XCTAssertNil(repository.lastUpdatedLog)
    }

    private func capturedDay() throws -> DiaryDayContext {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-03-01T02:00:00Z"))
        return try XCTUnwrap(DiaryDayContext(userID: owner, date: date,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!, dayKey: "2024-02-28"))
    }

    private func otherDay() throws -> DiaryDayContext { try XCTUnwrap(capturedDay().adding(days: 1)) }
    private func food() -> FoodItem { FoodItem(id: "source-oats", name: "Oats", calories: 180, protein: 8) }
    private func save(_ queue: QuickFoodLogQueue, id: UUID) async -> Bool {
        await withCheckedContinuation { continuation in queue.save(id: id, using: service) { continuation.resume(returning: $0) } }
    }
    private func save(_ detail: FoodDetailSaveSession, food: FoodItem) async -> Bool {
        await withCheckedContinuation { continuation in detail.save(food: food, using: service) { continuation.resume(returning: $0) } }
    }
    private func save(_ review: MealReviewSaveSession) async -> Bool {
        await withCheckedContinuation { continuation in review.save(using: service) { continuation.resume(returning: $0) } }
    }
    private func checkpointBytes() throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        var result: [String: Data] = [:]
        for case let url as URL in files where url.pathExtension == "json" { result[url.path] = try Data(contentsOf: url) }
        return result
    }
    private struct LegacyDetail: Codable {
        let original: FoodItem
        let entryID: String
        let date: Date
        let mealName: String
        let source: String
        let isEditing: Bool
        let food: FoodItem
        let isSubmitted: Bool
        let operationID: String?
    }
}
