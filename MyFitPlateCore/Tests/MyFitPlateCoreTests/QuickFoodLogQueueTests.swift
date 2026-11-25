import XCTest
@testable import MyFitPlateCore

@MainActor
final class QuickFoodLogQueueTests: XCTestCase {
    private var directory: URL!
    private var store: EditorDraftStore!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var oldAuth: AuthServiceProtocol!
    private var oldRepository: NutritionRepositoryProtocol!
    private let userID = "quick-log-owner"
    private let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))

    override func setUp() {
        oldAuth = DIContainer.shared.authService
        oldRepository = DIContainer.shared.nutritionRepository
        let auth = MockAuthService()
        auth.currentUserID = userID
        DIContainer.shared.authService = auth
        repository = MockNutritionRepository()
        repository.persistsDailyLogUpdates = true
        DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
        service = DailyLogService(undoStore: store)
        service.activateAccount(userID)
    }

    override func tearDown() {
        service.activateAccount(nil)
        service = nil
        DIContainer.shared.authService = oldAuth
        DIContainer.shared.nutritionRepository = oldRepository
        try? FileManager.default.removeItem(at: directory)
    }

    func testPreviewIsDurableBeforeHydrationAndRestoresExactDestination() throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Dinner", source: "quick_log", needsHydration: true))
        let restored = QuickFoodLogQueue(userID: userID, store: store)
        XCTAssertEqual(restored.operations.first?.id, pending.id)
        XCTAssertEqual(restored.operations.first?.draft.date, date)
        XCTAssertEqual(restored.operations.first?.draft.mealName, "Dinner")
        XCTAssertTrue(restored.operations.first?.draft.hasPendingHydration == true)
        XCTAssertTrue(restored.hydrate(id: pending.id, food: food(calories: 240)))
        XCTAssertEqual(restored.operations.first?.draft.entries.first?.id, pending.draft.entries.first?.id)
        XCTAssertEqual(restored.operations.first?.draft.foods.first?.calories, 240)
    }

    func testStaleFuelContextNeedsExplicitDetachAndKeepsTheOriginalQuickLog() async throws {
        let target = TrainingFuelTarget(planID: "stale", sessionTitle: "Earlier session", phase: .beforeTraining, proteinGrams: 20, carbGrams: 30)
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_macros",
            needsHydration: false, trainingFuelTarget: target))
        let failed = await save(queue, id: pending.id)
        XCTAssertFalse(failed); XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        let restored = QuickFoodLogQueue(userID: userID, store: store)
        XCTAssertEqual(restored.operations.first?.draft.trainingFuelTarget, target)
        XCTAssertEqual(restored.operations.first?.draft.foods.map(\.id), pending.draft.foods.map(\.id))
        XCTAssertTrue(restored.removeFuelContext(id: pending.id))
        let detached = QuickFoodLogQueue(userID: userID, store: store)
        XCTAssertNil(detached.operations.first?.draft.trainingFuelTarget)
        repository.updateLogSuccess = false
        let rejected = await save(detached, id: pending.id)
        XCTAssertFalse(rejected); XCTAssertFalse(detached.removeFuelContext(id: pending.id))
        repository.updateLogSuccess = true
        let accepted = await save(detached, id: pending.id)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), pending.draft.foods.map(\.id))
    }

    func testRejectedSaveRelaunchAndRetryUseSameFoodIDAndDay() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Dinner", source: "quick_log", needsHydration: false))
        repository.updateLogSuccess = false
        let rejected = await save(queue, id: pending.id)
        XCTAssertFalse(rejected)
        let restored = QuickFoodLogQueue(userID: userID, store: store)
        XCTAssertTrue(restored.operations.first?.draft.isSubmitted == true)
        XCTAssertFalse(restored.hydrate(id: pending.id, food: food(calories: 999)))
        service.activelyViewedDate = date.addingTimeInterval(3 * 86_400)
        repository.updateLogSuccess = true
        let accepted = await save(restored, id: pending.id)
        XCTAssertTrue(accepted)
        let saved = try await read(date)
        XCTAssertEqual(saved.meals.first?.name, "Dinner")
        XCTAssertEqual(saved.meals.flatMap(\.foodItems).map(\.id), pending.draft.foods.map(\.id))
        XCTAssertEqual(saved.meals.first?.foodItems.first?.calories, 180)
        XCTAssertTrue(restored.finish(id: pending.id))
    }

    func testAcceptedReceiptRestoresAndSkipsAnotherDiaryWrite() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: false))
        let accepted = await save(queue, id: pending.id)
        XCTAssertTrue(accepted)
        let count = repository.dailyLogUpdateUserIDs.count
        let restored = QuickFoodLogQueue(userID: userID, store: store)
        let replay = await save(restored, id: pending.id)
        XCTAssertTrue(replay)
        XCTAssertEqual(repository.dailyLogUpdateUserIDs.count, count)
        XCTAssertTrue(restored.finish(id: pending.id))
        XCTAssertTrue(QuickFoodLogQueue(userID: userID, store: store).operations.isEmpty)
    }

    func testCleanupFailureRetainsAcceptedIdentityForRetry() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: false))
        let accepted = await save(queue, id: pending.id)
        XCTAssertTrue(accepted)
        let backup = directory.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        XCTAssertFalse(queue.finish(id: pending.id))
        XCTAssertEqual(queue.operations.first?.id, pending.id)
        let writeCount = repository.dailyLogUpdateUserIDs.count
        let replay = await save(queue, id: pending.id)
        XCTAssertTrue(replay)
        XCTAssertEqual(repository.dailyLogUpdateUserIDs.count, writeCount)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        XCTAssertTrue(queue.finish(id: pending.id))
    }

    func testIndependentQuickLogsDoNotReplaceEachOther() throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let first = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Dinner", source: "quick_log", needsHydration: true))
        var secondFood = food(); secondFood.id = "other-food"
        let second = try XCTUnwrap(queue.begin(food: secondFood, date: date, mealName: "Dinner", source: "quick_log", needsHydration: true))
        let retry = try XCTUnwrap(queue.begin(food: food(calories: 999), date: date.addingTimeInterval(86_400), mealName: "Breakfast", source: "new_intent", needsHydration: true))
        XCTAssertEqual(retry.id, first.id)
        XCTAssertEqual(retry.draft.date, date)
        XCTAssertEqual(queue.operations.map(\.id), [first.id, second.id])
    }

    func testUnhydratedPreviewCannotPartiallySave() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: true))
        let saved = await save(queue, id: pending.id)
        XCTAssertFalse(saved)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
    }

    func testLaterIntentionalHelpingGetsAnotherConsumptionID() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let first = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: false))
        let saved = await save(queue, id: first.id)
        XCTAssertTrue(saved)
        XCTAssertTrue(queue.finish(id: first.id))
        let second = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: false))
        XCTAssertNotEqual(first.draft.entries.first?.id, second.draft.entries.first?.id)
        let savedSecond = await save(queue, id: second.id)
        XCTAssertTrue(savedSecond)
        let record = try await read(date)
        XCTAssertEqual(record.meals.flatMap(\.foodItems).count, 2)
    }

    func testOtherAccountCannotHydrateSubmitOrClearOldOperation() async throws {
        let queue = QuickFoodLogQueue(userID: userID, store: store)
        let pending = try XCTUnwrap(queue.begin(food: food(), date: date, mealName: "Lunch", source: "quick_log", needsHydration: false))
        (DIContainer.shared.authService as? MockAuthService)?.currentUserID = "other-account"
        XCTAssertFalse(queue.hydrate(id: pending.id, food: food()))
        let saved = await save(queue, id: pending.id)
        XCTAssertFalse(saved)
        XCTAssertFalse(queue.finish(id: pending.id))
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertEqual(queue.operations.count, 1)
    }

    func testQuickMacrosParseFullLocaleNumbersAndRejectInvalidValues() {
        let english = Locale(identifier: "en_US")
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(QuickMacroDraft.number("1,234.5", locale: english), 1234.5)
        XCTAssertEqual(QuickMacroDraft.number(".5", locale: english), 0.5)
        XCTAssertEqual(QuickMacroDraft.number("1,5", locale: french), 1.5)
        XCTAssertNil(QuickMacroDraft.number("1,5", locale: english))
        for value in ["inf", "NaN", "1e309", "-1", "12abc", "1.2.3"] { XCTAssertNil(QuickMacroDraft.number(value, locale: english)) }
    }

    func testMacroDraftKeepsLocaleAndCalculatesOnlyWhenCaloriesAreBlank() throws {
        var draft = QuickMacroDraft(date: date, mealName: "Dinner")
        draft.numberLocaleIdentifier = "fr_FR"
        draft.protein = "10,5"; draft.carbs = "20"; draft.fats = "4"
        XCTAssertEqual(draft.food?.calories, 158)
        draft.calories = "200"
        XCTAssertEqual(draft.food?.calories, 200)
        let restored = try JSONDecoder().decode(QuickMacroDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.food?.protein, 10.5)
        XCTAssertEqual(restored.food?.calories, 200)
        XCTAssertEqual(restored.foodID, draft.foodID)
        draft.calories = "inf"
        XCTAssertNil(draft.food)
    }

    private func food(calories: Double = 180) -> FoodItem {
        FoodItem(id: "provider-food", name: "Rice bowl", calories: calories, protein: 12, carbs: 24, fats: 4, servingSize: "150 g", servingWeight: 150)
    }

    private func save(_ queue: QuickFoodLogQueue, id: UUID) async -> Bool {
        await withCheckedContinuation { continuation in queue.save(id: id, using: service) { continuation.resume(returning: $0) } }
    }

    private func read(_ day: Date) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            repository.fetchLogInternal(userID: userID, date: day) { continuation.resume(with: $0) }
        }
    }
}
