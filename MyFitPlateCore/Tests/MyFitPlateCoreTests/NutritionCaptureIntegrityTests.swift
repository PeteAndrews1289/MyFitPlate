import XCTest
@testable import MyFitPlateCore

@MainActor
final class NutritionCaptureIntegrityTests: XCTestCase {
    private var directory: URL!
    private var store: EditorDraftStore!
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var previousAuth: AuthServiceProtocol!
    private var previousRepository: NutritionRepositoryProtocol!
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("capture-integrity-\(UUID())")
        store = EditorDraftStore(directory: directory)
        auth = MockAuthService(); auth.currentUserID = "capture-owner"
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
    }
    override func tearDown() {
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        try? FileManager.default.removeItem(at: directory)
    }
    private func grocery(_ name: String) -> GroceryListItem { GroceryListItem(name: name, quantity: 1, unit: "item") }
    private func pantry(_ name: String) -> PantryItem { PantryItem(name: name, quantity: 2, unit: "item") }
    private func product(_ code: String) -> FoodItem {
        FoodItem(id: "provider-\(code)", name: "Product \(code)", calories: 100, protein: 10, carbs: 10, fats: 2,
            sourceMetadata: .database(.openFoodFacts, sourceName: "Reference barcode", sourceID: code))
    }

    func testChecklistFailureRelaunchRetryPreservesUnrelatedRemoteRows() async throws {
        let apple = grocery("Apple"), oats = grocery("Oats")
        repository.mockFetchGroceryListResult = [apple, oats]
        let session = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.installRemote([apple, oats]))
        var checked = apple; checked.isCompleted = true
        XCTAssertTrue(session.stage([checked, oats]))
        repository.groceryMutationError = URLError(.notConnectedToInternet)
        await session.retry(using: repository)
        XCTAssertEqual(session.pendingItemIDs, [apple.id])
        XCTAssertNotNil(session.errorMessage)
        let restarted = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertEqual(restarted.items.first?.isCompleted, true)
        var remoteOats = oats; remoteOats.quantity = 3
        repository.mockFetchGroceryListResult = [apple, remoteOats, grocery("Milk")]
        repository.groceryMutationError = nil
        await restarted.retry(using: repository)
        XCTAssertEqual(restarted.pendingCount, 0)
        XCTAssertEqual(restarted.items.first { $0.id == oats.id }?.quantity, 3)
        XCTAssertEqual(restarted.items.count, 3)
        XCTAssertEqual(GroceryChecklistSession(userID: auth.currentUserID, store: store).items, restarted.items)
    }

    func testChecklistCompareAndSetRejectsSameItemConflictWithoutErasingEitherVersion() async {
        let apple = grocery("Apple")
        let session = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.installRemote([apple]))
        var checked = apple; checked.isCompleted = true
        XCTAssertTrue(session.stage([checked]))
        let exactStagedRows = session.items
        var changed = apple; changed.quantity = 4
        repository.mockFetchGroceryListResult = [changed]
        await session.retry(using: repository)
        XCTAssertEqual(repository.mockFetchGroceryListResult, [changed])
        XCTAssertEqual(session.items, exactStagedRows)
        XCTAssertEqual(session.pendingCount, 1)
        let reloaded = await session.reloadDiscardingPending(using: repository)
        XCTAssertTrue(reloaded)
        XCTAssertEqual(session.items, [changed])
    }

    func testChecklistReceiptReplayCannotOverwriteANewerEditAfterCommit() async throws {
        let apple = grocery("Apple")
        repository.mockFetchGroceryListResult = [apple]
        let session = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.installRemote([apple]))
        var checked = apple; checked.isCompleted = true
        XCTAssertTrue(session.stage([checked]))
        let beforeAcknowledgement = session.checkpoint
        _ = try await repository.applyGroceryMutation(userID: "capture-owner", mutation: beforeAcknowledgement.operations[0])
        var newer = checked; newer.quantity = 9
        repository.mockFetchGroceryListResult = [newer]
        // Simulates termination after the server transaction but before local receipt cleanup.
        let restarted = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        await restarted.retry(using: repository)
        XCTAssertEqual(restarted.items, [newer])
        XCTAssertEqual(repository.appliedGroceryMutationIDs.count, 1)
    }

    func testChecklistRapidChecksReplayInOrderAndAccountSwitchDoesNotWrite() async {
        let apple = grocery("Apple")
        repository.mockFetchGroceryListResult = [apple]
        let session = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.installRemote([apple]))
        var checked = apple; checked.isCompleted = true
        XCTAssertTrue(session.stage([checked])); XCTAssertTrue(session.stage([apple]))
        let exactStagedRows = session.items
        auth.currentUserID = "another-owner"
        await session.retry(using: repository)
        XCTAssertTrue(repository.appliedGroceryMutationIDs.isEmpty)
        XCTAssertFalse(session.stage([]))
        auth.currentUserID = "capture-owner"
        await session.retry(using: repository)
        XCTAssertEqual(repository.appliedGroceryMutationIDs.count, 2)
        XCTAssertEqual(repository.mockFetchGroceryListResult, exactStagedRows)
    }

    func testChecklistDiskFailureDoesNotAcceptAnUnrecoverableTap() throws {
        let apple = grocery("Apple"), session = GroceryChecklistSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.installRemote([apple]))
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        var checked = apple; checked.isCompleted = true
        XCTAssertFalse(session.stage([checked]))
        XCTAssertEqual(session.items, [apple]); XCTAssertEqual(session.pendingCount, 0)
    }

    func testLegacyReceiptPartialSaveRelaunchRetriesOnlyFailedRowsWithPurchaseDate() async throws {
        let apples = pantry("Apples"), milk = pantry("Milk"), rice = pantry("Rice")
        let originalStock = pantry("Apples")
        repository.mockPantryItemsByID[originalStock.id] = originalStock
        repository.pantryItemErrors[milk.id] = URLError(.timedOut)
        let purchaseDate = Calendar.current.startOfDay(for: day)
        var legacy = PantryReceiptCheckpoint(id: UUID(), purchaseDate: purchaseDate,
            rows: [apples, milk, rice].map { PantryReceiptRow(item: $0, status: .ready) }, isSubmitted: false)
        legacy.usesWholeReceiptLedger = nil
        try store.save(legacy, userID: auth.currentUserID!, scope: "pantry-receipt-import")
        let session = PantryReceiptImportSession(userID: auth.currentUserID, store: store)
        await session.save(using: repository)
        XCTAssertEqual(session.checkpoint.rows.map(\.status), [.accepted, .failed, .accepted])
        XCTAssertFalse(session.isComplete)
        let restarted = PantryReceiptImportSession(userID: auth.currentUserID, store: store)
        XCTAssertEqual(restarted.checkpoint.purchaseDate, purchaseDate)
        XCTAssertEqual(restarted.checkpoint.rows.map(\.id), [apples.id, milk.id, rice.id])
        repository.pantryItemErrors = [:]
        await restarted.save(using: repository)
        XCTAssertTrue(restarted.isComplete)
        XCTAssertEqual(repository.savedPantryItems.map(\.id), [apples.id, rice.id, milk.id])
        XCTAssertEqual(repository.mockPantryItemsByID[apples.id]?.dateAdded, purchaseDate)
        XCTAssertEqual(repository.mockPantryItemsByID[originalStock.id], originalStock, "Receipt import cannot alter existing stock by fuzzy name")
        XCTAssertTrue(restarted.finish())
        XCTAssertTrue(PantryReceiptImportSession(userID: auth.currentUserID, store: store).items.isEmpty)
    }

    func testReceiptAmbiguousCommitRetriesSameDocumentWithoutIncreasingStock() async {
        let apples = pantry("Apples")
        repository.pantryErrorAfterCommitIDs = [apples.id]
        let session = PantryReceiptImportSession(userID: auth.currentUserID, items: [apples], store: store)
        await session.save(using: repository)
        XCTAssertEqual(session.checkpoint.rows[0].status, .pending)
        XCTAssertEqual(repository.mockPantryItemsByID[apples.id]?.quantity, 2)
        var laterStock = apples; laterStock.quantity = 7
        repository.mockPantryItemsByID[apples.id] = laterStock
        repository.pantryErrorAfterCommitIDs = []
        await session.save(using: repository)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(repository.mockPantryItemsByID.count, 1)
        XCTAssertEqual(repository.mockPantryItemsByID[apples.id]?.quantity, 7, "A receipt replay cannot overwrite a later stock correction")
    }

    func testReceiptInvalidRowsAndAccountSwitchCannotPartiallySubmit() async {
        var invalid = pantry("Invalid"); invalid.quantity = 0
        let session = PantryReceiptImportSession(userID: auth.currentUserID, items: [pantry("Valid"), invalid], store: store)
        await session.save(using: repository)
        XCTAssertFalse(session.isSubmitted); XCTAssertTrue(repository.savedPantryItems.isEmpty)
        auth.currentUserID = "another-owner"
        XCTAssertFalse(session.update(items: [pantry("Other")], purchaseDate: Date()))
        await session.save(using: repository)
        XCTAssertTrue(repository.savedPantryItems.isEmpty)
    }

    func testReceiptDoubleTapWaitsForAcknowledgementAndCreatesOnePurchase() async {
        repository.pantrySaveDelayNanoseconds = 10_000_000
        let session = PantryReceiptImportSession(userID: auth.currentUserID, items: [pantry("Apples")], store: store)
        let first = Task { await session.save(using: repository) }
        for _ in 0..<100 where !session.isSaving { await Task.yield() }
        await session.save(using: repository)
        await first.value
        XCTAssertEqual(repository.savedPantryItems.count, 1)
        XCTAssertTrue(session.isComplete)
    }

    func testBarcodeTenScanReconciliationRetainsMissesAndRepeatedScansAcrossRelaunch() async {
        let session = RapidBarcodeBatchSession(userID: auth.currentUserID, date: day, mealName: "Lunch", store: store)
        let codes = ["012345678905", "012345678912", "012345678929", "012345678936", "012345678943",
                     "012345678950", "012345678967", "012345678974", "012345678981", "012345678905"]
        for code in codes { XCTAssertTrue(session.append(code)) }
        var calls = 0
        await session.resolve { code in calls += 1; return code == codes[2] ? nil : self.product(code) }
        XCTAssertEqual(calls, 10)
        XCTAssertEqual(session.checkpoint.entries.count, 10)
        XCTAssertEqual(session.includedFoods.count, 8)
        XCTAssertEqual(session.unresolvedCount, 1)
        XCTAssertEqual(session.leftOutCount, 1)
        let repeated = session.checkpoint.entries[9]
        XCTAssertTrue(repeated.isRepeatedScan); XCTAssertFalse(repeated.included)
        XCTAssertTrue(session.toggleIncluded(id: repeated.id))
        let restarted = RapidBarcodeBatchSession(userID: auth.currentUserID, date: Date(), mealName: "Dinner", store: store)
        XCTAssertEqual(restarted.checkpoint.date, Calendar.current.startOfDay(for: day))
        XCTAssertEqual(restarted.checkpoint.mealName, "Lunch")
        calls = 0
        await restarted.resolve { code in calls += 1; return self.product(code) }
        XCTAssertEqual(calls, 1, "Successful product decisions must not be looked up again")
        XCTAssertEqual(Set(restarted.includedFoods.map(\.id)).count, 10)
    }

    func testBarcodeFailedSubmissionFreezesAllOutcomesAndRetryLogsOnce() async throws {
        repository.persistsDailyLogUpdates = true
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        let session = RapidBarcodeBatchSession(userID: auth.currentUserID, date: day, mealName: "Lunch", store: store)
        XCTAssertTrue(session.append("012345678905")); XCTAssertTrue(session.append("012345678912"))
        await session.resolve { code in code == "012345678905" ? self.product(code) : nil }
        let notConfirmed = await save(session, service: service)
        XCTAssertFalse(notConfirmed); XCTAssertFalse(session.checkpoint.isSubmitted)
        repository.updateLogSuccess = false
        let failed = await save(session, service: service, leaveOut: true)
        XCTAssertFalse(failed); XCTAssertTrue(session.checkpoint.isSubmitted)
        XCTAssertEqual(session.unresolvedCount, 0); XCTAssertEqual(session.leftOutCount, 1)
        let payload = session.includedFoods
        XCTAssertFalse(session.append("012345678929")); XCTAssertFalse(session.clear())
        // The first write may have committed despite the timeout.
        repository.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: session.checkpoint.date),
            date: session.checkpoint.date, meals: [Meal(name: "Lunch", foodItems: payload)]))
        repository.updateLogSuccess = true
        let restarted = RapidBarcodeBatchSession(userID: auth.currentUserID, date: Date(), mealName: "Dinner", store: store)
        let accepted = await save(restarted, service: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), payload.map(\.id))
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Lunch")
        XCTAssertNotEqual(payload.first?.id, "provider-012345678905")
        XCTAssertTrue(restarted.clear())
        XCTAssertNil(RapidBarcodeBatchSession.pending(userID: auth.currentUserID, store: store))
    }

    func testBarcodeAccountSwitchCannotPublishOrOverwriteOriginalTray() async {
        let session = RapidBarcodeBatchSession(userID: auth.currentUserID, date: day, mealName: "Lunch", store: store)
        XCTAssertTrue(session.append("012345678905"))
        auth.currentUserID = "another-owner"
        XCTAssertFalse(session.append("012345678912"))
        await session.resolve { _ in XCTFail("Must not look up for a different account"); return nil }
        XCTAssertEqual(session.checkpoint.entries.count, 1)
        XCTAssertNil(RapidBarcodeBatchSession.pending(userID: auth.currentUserID, store: store))
    }

    func testMealDraftPendingHydrationAndInvalidMemberCannotBecomePartialSuccessfulMeal() throws {
        var draft = FoodLoggingDraft(date: day, mealName: "Lunch")
        var entry = FoodLoggingDraft.Entry(food: product("012345678905")); entry.hydrationPending = true
        draft.entries = [entry]
        try store.save(draft, userID: "capture-owner", scope: "meal")
        let restored = try XCTUnwrap(store.load(FoodLoggingDraft.self, userID: "capture-owner", scope: "meal")).value
        XCTAssertTrue(restored.hasPendingHydration); XCTAssertFalse(restored.isReadyToSubmit)
        XCTAssertEqual(restored.entries.first?.id, entry.id)
        draft.entries[0].hydrationPending = false
        XCTAssertTrue(draft.isReadyToSubmit)
        var invalid = FoodLoggingDraft.Entry(food: product("012345678912")); invalid.multiplier = 0
        draft.entries.append(invalid)
        XCTAssertFalse(draft.isReadyToSubmit)
        let legacy = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(FoodLoggingDraft.self, from: legacy).entries.count, 2)
    }

    func testFoodDetailBackdatedEditFailureRestoresPayloadAndAcceptsSameConsumptionOnce() async throws {
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        let original = product("012345678905")
        let originalLog = DailyLog(id: DiaryDayContext.dayKey(for: day), date: Calendar.current.startOfDay(for: day),
            meals: [Meal(name: "Lunch", foodItems: [original])])
        repository.mockFetchLogResult = .success(originalLog)
        repository.updateLogSuccess = false
        let session = FoodDetailSaveSession(food: original, userID: auth.currentUserID, date: day, mealName: "Lunch",
            source: "log_edit", isEditing: true, store: store)
        var changed = original; changed.calories = 150; changed.protein = 20
        let failed = await saveDetail(session, food: changed, service: service)
        XCTAssertFalse(failed); XCTAssertTrue(session.checkpoint.isSubmitted)
        let homeDate = service.activelyViewedDate
        let restored = FoodDetailSaveSession(food: original, userID: auth.currentUserID, date: Date(), mealName: "Dinner",
            source: "log_edit", isEditing: true, store: store)
        XCTAssertTrue(restored.restoredReview)
        XCTAssertEqual(restored.checkpoint.food.id, original.id)
        XCTAssertEqual(restored.checkpoint.food.calories, 150)
        XCTAssertEqual(restored.checkpoint.date, originalLog.date)
        XCTAssertEqual(restored.checkpoint.mealName, "Lunch")
        repository.updateLogSuccess = true
        let accepted = await saveDetail(restored, food: original, service: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.calories, 150)
        XCTAssertEqual(service.activelyViewedDate, homeDate)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.sourceMetadata, original.sourceMetadata)
    }

    func testFoodDetailRejectsChangedOriginalAndAcceptsAnIdenticalReplay() async {
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        let original = product("012345678905")
        var updated = original; updated.calories = 150
        var concurrent = original; concurrent.calories = 300
        repository.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: day), date: day,
            meals: [Meal(name: "Lunch", foodItems: [concurrent])]))
        let rejected = await withCheckedContinuation { continuation in
            service.updateFood(for: "capture-owner", date: day, original: original, updated: updated) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(rejected); XCTAssertNil(repository.lastUpdatedLog)
        let undoBeforeReplay = service.undoChangeID
        repository.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: day), date: day,
            meals: [Meal(name: "Lunch", foodItems: [updated])]))
        let replayed = await withCheckedContinuation { continuation in
            service.updateFood(for: "capture-owner", date: day, original: original, updated: updated) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(replayed)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.calories, updated.calories)
        XCTAssertNotNil(repository.lastUpdatedLog?.pendingFoodEdit, "A replay must verify server acceptance rather than trusting a cached snapshot")
        XCTAssertEqual(service.undoChangeID, undoBeforeReplay, "An accepted replay cannot create another Undo operation")
    }

    func testFoodDetailNewFoodRetryKeepsConsumptionIdentityAndEstimateLineage() async {
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        var original = product("012345678905")
        original.sourceMetadata = FoodSourceMetadata(sourceType: .aiText, confidence: .estimated, reviewStatus: .unreviewed, evidenceLineage: .modelEstimate)
        let session = FoodDetailSaveSession(food: original, userID: auth.currentUserID, date: day, mealName: "Lunch",
            source: "image_result", isEditing: false, store: store)
        repository.updateLogSuccess = false
        let failed = await saveDetail(session, food: original, service: service)
        XCTAssertFalse(failed)
        let payload = session.checkpoint.food
        XCTAssertNotEqual(payload.id, original.id)
        repository.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: session.checkpoint.date),
            date: session.checkpoint.date, meals: [Meal(name: "Lunch", foodItems: [payload])]))
        repository.updateLogSuccess = true
        let restored = FoodDetailSaveSession(food: original, userID: auth.currentUserID, date: Date(), mealName: "Dinner",
            source: "image_result", isEditing: false, store: store)
        let accepted = await saveDetail(restored, food: original, service: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), [payload.id])
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.sourceMetadata?.confidence, .estimated)
    }

    func testManualFoodScopeRecoversExactDestinationAndRejectsCompetingEditor() async throws {
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        let original = product("012345678905")
        let first = FoodDetailSaveSession(food: original, userID: auth.currentUserID, date: day, mealName: "Lunch",
            source: "manual", isEditing: false, store: store, draftScope: "manual-stable")
        let competing = FoodDetailSaveSession(food: product("012345678912"), userID: auth.currentUserID, date: Date(), mealName: "Dinner",
            source: "manual", isEditing: false, store: store, draftScope: "manual-stable")
        repository.updateLogSuccess = false
        let rejected = await saveDetail(first, food: original, service: service)
        XCTAssertFalse(rejected); XCTAssertTrue(first.checkpoint.isSubmitted)
        let writeCount = repository.dailyLogUpdateUserIDs.count
        let stale = await saveDetail(competing, food: product("012345678912"), service: service)
        XCTAssertFalse(stale); XCTAssertEqual(repository.dailyLogUpdateUserIDs.count, writeCount)
        let resumed = FoodDetailSaveSession(food: product("012345678929"), userID: auth.currentUserID, date: Date(), mealName: "Dinner",
            source: "manual", isEditing: false, store: store, draftScope: "manual-stable")
        XCTAssertEqual(resumed.checkpoint.entryID, first.checkpoint.entryID)
        XCTAssertEqual(resumed.checkpoint.food, first.checkpoint.food)
        XCTAssertEqual(resumed.checkpoint.date, Calendar.current.startOfDay(for: day))
        XCTAssertEqual(resumed.checkpoint.mealName, "Lunch")
        XCTAssertFalse(resumed.removeFuelContext(), "An uncertain submission stays immutable")
        repository.updateLogSuccess = true
        let accepted = await saveDetail(resumed, food: product("ignored"), service: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), [first.checkpoint.entryID])
    }

    func testBarcodeContextRestoresOriginalAndExplicitDetachPersistsWithoutChangingFoods() async throws {
        let original = TrainingFuelTarget(planID: "first", sessionTitle: "First", phase: .beforeTraining, proteinGrams: 20, carbGrams: 30)
        let replacement = TrainingFuelTarget(planID: "second", sessionTitle: "Second", phase: .afterTraining, proteinGrams: 30, carbGrams: 40)
        let session = RapidBarcodeBatchSession(userID: auth.currentUserID, date: day, mealName: "Lunch", store: store, trainingFuelTarget: original)
        XCTAssertTrue(session.append("012345678905")); await session.resolve { self.product($0) }
        let foods = session.includedFoods
        let resumed = RapidBarcodeBatchSession(userID: auth.currentUserID, date: Date(), mealName: "Dinner", store: store, trainingFuelTarget: replacement)
        XCTAssertEqual(resumed.checkpoint.trainingFuelTarget, original)
        XCTAssertEqual(resumed.includedFoods, foods)
        XCTAssertTrue(resumed.removeFuelContext())
        let again = RapidBarcodeBatchSession(userID: auth.currentUserID, date: Date(), mealName: "Snack", store: store, trainingFuelTarget: replacement)
        XCTAssertNil(again.checkpoint.trainingFuelTarget)
        XCTAssertEqual(again.includedFoods, foods)
        XCTAssertEqual(again.checkpoint.mealName, "Lunch")
        auth.currentUserID = "another-owner"
        XCTAssertFalse(again.removeFuelContext())
    }

    private func saveDetail(_ session: FoodDetailSaveSession, food: FoodItem, service: DailyLogService) async -> Bool {
        await withCheckedContinuation { continuation in
            session.save(food: food, using: service) { continuation.resume(returning: $0) }
        }
    }

    func testPlannedMealRetryRestoresFrozenFoodsDespitePlanChangesAndLogsOccurrenceOnce() async throws {
        let service = DailyLogService(undoStore: store); service.activateAccount(auth.currentUserID)
        defer { service.activateAccount(nil) }
        let planned = PlannedMeal(id: "planned-lunch", mealType: "Lunch", foodItem: product("012345678905"))
        let food = try XCTUnwrap(PlannedMealLoggingRules.food(for: planned, date: day))
        let session = PlannedMealSaveSession(userID: auth.currentUserID, date: day,
            meals: [Meal(name: "Lunch", foodItems: [food])], store: store)
        repository.updateLogSuccess = false
        let failed = await savePlan(session, service: service)
        XCTAssertFalse(failed); XCTAssertTrue(session.checkpoint.isSubmitted)
        var revised = food; revised.calories = 400
        let restored = PlannedMealSaveSession(userID: auth.currentUserID, date: day,
            meals: [Meal(name: "Dinner", foodItems: [revised])], store: store)
        XCTAssertTrue(restored.restoredReview)
        XCTAssertEqual(restored.checkpoint.meals.first?.name, "Lunch")
        XCTAssertEqual(restored.checkpoint.meals.first?.foodItems.first, food)
        repository.mockFetchLogResult = .success(DailyLog(id: DiaryDayContext.dayKey(for: day),
            date: Calendar.current.startOfDay(for: day), meals: [Meal(name: "Lunch", foodItems: [food])]))
        repository.updateLogSuccess = true
        let accepted = await savePlan(restored, service: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.id, food.id)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.calories, food.calories)
    }

    func testPlannedFuelFoodFailureAndRetryKeepTheSameContextAndOnlyLinkAcceptedFood() async throws {
        let owner = try XCTUnwrap(auth.currentUserID)
        let logDay = Calendar.current.startOfDay(for: day)
        let now = logDay.addingTimeInterval(10 * 3_600)
        let empty = DailyLog(date: logDay, meals: [])
        repository.mockFetchLogResult = .success(empty)
        let service = DailyLogService(undoStore: store); service.activateAccount(owner)
        defer { service.activateAccount(nil) }
        let settings = GoalSettings(isEditingPreview: true)
        settings.calories = 2_500; settings.protein = 150; settings.carbs = 300; settings.fats = 80
        service.goalSettings = settings; service.publishCurrentDailyLog(empty)
        let suite = "planned-fuel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let fuel = TrainingFuelPlanStore(userDefaults: defaults, draftStore: store, auth: auth)
        let goals = TodayFuelPlanGoals(calories: 2_500, protein: 150, carbs: 300, fats: 80)
        let draft = TrainingFuelPlanDraft(id: "exact-session", candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            scheduledAt: now.addingTimeInterval(2 * 3_600), durationMinutes: 45)
        let preview = TrainingFuelPlannerRules.makePlan(session: draft.session, today: empty, goals: goals,
            preference: draft.preference, now: now)
        let plan = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: preview, goals: goals, today: empty, confirmedAt: now)
        XCTAssertTrue(fuel.confirm(plan, for: owner))
        let target = try fuel.makeTarget(planID: plan.id, phase: .beforeTraining, today: empty, goals: goals, now: now)
        let food = FoodItem(id: "exact-planned-food", name: "Yogurt", calories: 180, protein: 20, carbs: 20, fats: 2)
        let review = PlannedMealSaveSession(userID: owner, date: logDay,
            meals: [Meal(name: "Lunch", foodItems: [food])], trainingFuelTarget: target, store: store)
        repository.updateLogSuccess = false
        let failed = await withCheckedContinuation { continuation in
            review.save(using: service, fuelStore: fuel, now: now) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(failed)
        XCTAssertTrue(review.checkpoint.isSubmitted)
        XCTAssertTrue(fuel.history.first?.plan.foodLinks?.isEmpty ?? true)
        let resumed = PlannedMealSaveSession(userID: owner, date: logDay, meals: [], store: store)
        XCTAssertEqual(resumed.checkpoint.trainingFuelTarget, target)
        repository.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in
            resumed.save(using: service, fuelStore: fuel, now: now.addingTimeInterval(60)) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(fuel.history.first?.plan.foodLinks?.map(\.foodID), [food.id])
        XCTAssertEqual(fuel.history.first?.plan.foodLinks?.first?.requestID, target.context?.requestID)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), [food.id])
    }

    private func savePlan(_ session: PlannedMealSaveSession, service: DailyLogService) async -> Bool {
        await withCheckedContinuation { continuation in session.save(using: service) { continuation.resume(returning: $0) } }
    }

    private func save(_ session: RapidBarcodeBatchSession, service: DailyLogService, leaveOut: Bool = false) async -> Bool {
        await withCheckedContinuation { continuation in
            session.save(using: service, leavingUnresolvedOut: leaveOut) { continuation.resume(returning: $0) }
        }
    }
}
