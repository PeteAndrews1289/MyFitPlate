import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class BuffetSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var undoDirectory: URL!

    override func setUp() {
        super.setUp()
        suite = "buffet-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        auth = MockAuthService()
        auth.currentUserID = "buffet-test"
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repository
        DIContainer.shared.analyticsManager = MockAnalyticsManager()
        DIContainer.shared.crashManager = MockCrashManager()
        undoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("buffet-undo-\(UUID())")
        service = DailyLogService(undoStore: EditorDraftStore(directory: undoDirectory))
        service.activateAccount(auth.currentUserID)
    }

    override func tearDown() {
        service.activateAccount(nil)
        defaults.removePersistentDomain(forName: suite)
        service = nil
        try? FileManager.default.removeItem(at: undoDirectory)
        undoDirectory = nil
        repository = nil
        auth = nil
        defaults = nil
        super.tearDown()
    }

    private func manager(initial: AYCESession? = nil) -> AYCESessionManager {
        AYCESessionManager(initialSession: initial, managesLiveActivity: false, userDefaults: defaults, authService: auth)
    }

    func testRepeatRoundReviewIsSingleUseUndoableAndDurable() throws {
        let model = manager()
        let food = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        model.start(cuisine: .sushi, buffetPrice: 35, citySlug: nil)
        model.setQuantity(0.375, for: food)
        model.finishRound()
        let reviewed = try XCTUnwrap(model.session)
        model.repeatLastRound(reviewedSession: reviewed)
        XCTAssertEqual(model.count(for: food), 0.75)
        model.repeatLastRound(reviewedSession: reviewed)
        XCTAssertEqual(model.count(for: food), 0.75, "The same confirmation cannot apply twice")
        XCTAssertEqual(manager().count(for: food), 0.75)
        model.undoLastChange()
        XCTAssertEqual(model.count(for: food), 0.375)
        XCTAssertEqual(manager().session?.lastRound?.first?.count, 0.375)
    }

    func testRememberedCutOnlyAppliesToNamedRestaurantAndAccount() throws {
        let model = manager()
        let original = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        let cut = try XCTUnwrap(AYCEPortionRules.changingCut(of: original, pieces: 6))
        model.start(cuisine: .sushi, buffetPrice: 35, citySlug: nil, restaurantName: "Sushi Place")
        model.savePortion(0.5, item: cut, rememberCut: true)
        model.toggleFavorite(cut)
        XCTAssertTrue(manager().isFavorite(original))
        XCTAssertEqual(manager().resolvedItem(original).piecesPerUnit, 6)
        auth.currentUserID = "other"
        let other = manager()
        other.start(cuisine: .sushi, buffetPrice: 35, citySlug: nil, restaurantName: "Sushi Place")
        XCTAssertEqual(other.resolvedItem(original).piecesPerUnit, 8)
        XCTAssertFalse(other.isFavorite(original))
        model.savePortion(1, item: original, rememberCut: true)
        XCTAssertEqual(model.count(for: original), 0.5)
    }

    func testFractionalPortionUndoAndRelaunchKeepExactEntryIdentity() throws {
        let model = manager()
        let food = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        model.start(cuisine: .sushi, buffetPrice: 35, citySlug: "nyc")
        model.setQuantity(0.375, for: food)
        let entryID = model.session?.entries.first?.id
        model.add(food)
        XCTAssertEqual(model.count(for: food), 1.375)
        model.undoLastChange()
        XCTAssertEqual(model.count(for: food), 0.375)
        XCTAssertEqual(manager().session, model.session)
        XCTAssertEqual(manager().session?.entries.first?.id, entryID)
        model.remove(food)
        XCTAssertTrue(model.session?.entries.isEmpty == true)
        model.undoLastChange()
        XCTAssertEqual(model.count(for: food), 0.375)
        model.setQuantity(.nan, for: food)
        XCTAssertEqual(model.count(for: food), 0.375)
    }

    func testEndedSessionRecoversIntoReviewAndCanReturnToEditing() throws {
        let model = manager()
        model.start(cuisine: .kbbq, buffetPrice: 35, citySlug: nil)
        model.add(try XCTUnwrap(AYCECatalog.item(id: "kbbq_brisket")))
        let ended = try XCTUnwrap(model.end())
        XCTAssertNotNil(ended.endedAt)
        let restored = manager()
        XCTAssertEqual(restored.session, ended)
        XCTAssertNil(restored.scoreboardRecordLine, "Review alone must not count as a completed meal")
        restored.resume()
        XCTAssertNil(restored.session?.endedAt)
        XCTAssertEqual(restored.session?.entries, ended.entries)
        XCTAssertTrue(restored.discard())
        XCTAssertNil(manager().session)
    }

    func testFailedSaveRetainsFrozenSessionAndRetryKeepsOriginalDay() async throws {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let food = try XCTUnwrap(AYCECatalog.item(id: "kbbq_brisket"))
        let model = manager(initial: AYCESession(cuisine: .kbbq, buffetPrice: 35, startedAt: date,
                                                entries: [AYCESessionEntry(id: "brisket", item: food, count: 1.5)]))
        model.end()
        repository.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in
            model.logToDiary(using: service) { continuation.resume(returning: $0) }
            XCTAssertTrue(model.isSavingDiary)
            model.logToDiary(using: service) { XCTAssertFalse($0) }
        }
        XCTAssertFalse(rejected)
        XCTAssertNotNil(model.session?.submittedAt)
        XCTAssertTrue(model.message?.contains("Couldn't save") == true)
        let submitted = try XCTUnwrap(model.session)
        model.resume()
        model.add(food)
        XCTAssertFalse(model.discard())
        XCTAssertEqual(model.session, submitted, "A rejected submission keeps its exact payload")
        let restored = manager()
        XCTAssertEqual(restored.session, submitted)
        service.activelyViewedDate = Date()
        repository.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in
            restored.logToDiary(using: service) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertNil(manager().session)
        XCTAssertEqual(repository.lastUpdatedLog?.date, date)
        let entries = repository.lastUpdatedLog?.meals.flatMap(\.foodItems) ?? []
        XCTAssertEqual(entries.map(\.id), ["ayce_brisket"])
        XCTAssertEqual(entries.first?.calories, 525)
        // Simulate process death after cloud acceptance but before local draft cleanup.
        let replay = manager(initial: submitted)
        let replayAccepted = await withCheckedContinuation { continuation in
            replay.logToDiary(using: service) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(replayAccepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "ayceScoreboard", userID: auth.currentUserID))
        let records = try JSONDecoder().decode([AYCESessionRecord].self, from: XCTUnwrap(defaults.data(forKey: key)))
        XCTAssertEqual(records.count, 1)
    }

    func testAccountChangeCannotSaveOrModifyAnotherAccountsDraft() async throws {
        let model = manager()
        let food = try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri"))
        model.start(cuisine: .sushi, buffetPrice: 30, citySlug: nil)
        model.add(food)
        let original = model.session
        auth.currentUserID = "another-account"
        model.add(food)
        XCTAssertNil(model.end())
        XCTAssertFalse(model.discard())
        let accepted = await withCheckedContinuation { continuation in
            model.logToDiary(using: service) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(accepted)
        XCTAssertNil(manager().session)
        auth.currentUserID = "buffet-test"
        XCTAssertEqual(manager().session, original)
        XCTAssertNil(repository.lastUpdatedLog)
    }

    func testReviewedBuffetDestinationAndFoodsStayFrozenAcrossMidnightFailureAndRelaunch() async throws {
        repository.persistsDailyLogUpdates = true
        let reviewedDay = Calendar.current.startOfDay(for: Date())
        let started = reviewedDay.addingTimeInterval(-2 * 3_600)
        let item = try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri"))
        let model = manager(initial: AYCESession(cuisine: .sushi, buffetPrice: 30, startedAt: started,
            entries: [AYCESessionEntry(id: "reviewed-salmon", item: item, count: 2)]))
        model.end()
        XCTAssertTrue(model.updateDiaryDestination(date: reviewedDay, mealName: "Dinner"))
        repository.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in model.logToDiary(using: service) { continuation.resume(returning: $0) } }
        XCTAssertFalse(rejected)
        let submitted = try XCTUnwrap(model.session)
        let frozenFoods = try XCTUnwrap(submitted.diaryFoodItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let frozenBytes = try encoder.encode(frozenFoods)
        XCTAssertEqual(submitted.diaryDate, reviewedDay)
        XCTAssertEqual(submitted.diaryMealName, "Dinner")
        let restored = manager()
        XCTAssertEqual(try encoder.encode(restored.session?.diaryFoodItems), frozenBytes)
        XCTAssertFalse(restored.updateDiaryDestination(date: started, mealName: "Lunch"))
        restored.prepareDiaryDestination()
        XCTAssertEqual(restored.session, submitted)
        service.activelyViewedDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: reviewedDay))
        repository.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in restored.logToDiary(using: service) { continuation.resume(returning: $0) } }
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.date, reviewedDay)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.map(\.name), ["Dinner"])
        XCTAssertEqual(try encoder.encode(repository.lastUpdatedLog?.meals.flatMap(\.foodItems)), frozenBytes)
    }

    func testLegacySubmittedBuffetRetainsOriginalCuisineGroupAndDate() async throws {
        let originalDay = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let item = try XCTUnwrap(AYCECatalog.item(id: "kbbq_brisket"))
        let legacy = AYCESession(cuisine: .kbbq, buffetPrice: 35, startedAt: originalDay,
            entries: [AYCESessionEntry(id: "legacy-brisket", item: item, count: 1)],
            endedAt: originalDay.addingTimeInterval(3_600), submittedAt: originalDay.addingTimeInterval(3_610))
        let model = manager(initial: legacy)
        model.prepareDiaryDestination()
        XCTAssertNil(model.session?.diaryDate)
        XCTAssertNil(model.session?.diaryMealName)
        XCTAssertFalse(model.updateDiaryDestination(date: Date(), mealName: "Dinner"))
        let accepted = await withCheckedContinuation { continuation in model.logToDiary(using: service) { continuation.resume(returning: $0) } }
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.date, originalDay)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.map(\.name), [AYCERules.mealName(for: .kbbq)])
    }

    func testInvalidBuffetDestinationCannotAcknowledgeDiarySave() async throws {
        let item = try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri"))
        var invalid = AYCESession(cuisine: .sushi, buffetPrice: 30,
            entries: [AYCESessionEntry(id: "invalid-date", item: item, count: 1)], endedAt: Date())
        invalid.diaryDate = Date.distantFuture.addingTimeInterval(86_400)
        let model = manager(initial: invalid)
        // Initializing a legacy draft adds stable round boundaries without changing
        // its entries or destination. Validation must preserve that exact baseline.
        let baseline = try XCTUnwrap(model.session)
        XCTAssertEqual(baseline, AYCEStableRoundRules.migrated(invalid))
        XCTAssertEqual(baseline.entries, invalid.entries)
        XCTAssertEqual(baseline.diaryDate, invalid.diaryDate)
        XCTAssertFalse(model.updateDiaryDestination(date: Date(timeIntervalSinceReferenceDate: .nan), mealName: "Dinner"))
        let accepted = await withCheckedContinuation { continuation in model.logToDiary(using: service) { continuation.resume(returning: $0) } }
        XCTAssertFalse(accepted)
        XCTAssertNil(repository.lastUpdatedLog)
        XCTAssertEqual(model.session, baseline)
        XCTAssertNil(model.session?.submittedAt)
        XCTAssertNotNil(model.message)
    }

    func testInvalidReviewedFoodKeepsPreviousDraftAndShowsRecoveryError() throws {
        let model = manager()
        model.start(cuisine: .sushi, buffetPrice: 30, citySlug: nil)
        model.add(try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri")))
        let previous = model.session
        let bad = AYCECatalogItem(id: "invalid", cuisine: .sushi, name: "Invalid", emoji: "🍣", unit: "piece",
                                  calories: .nan, protein: 2, carbs: 2, fats: 2, restaurantPrice: 4, homeCost: 1)
        model.addReviewed([bad])
        XCTAssertEqual(model.session, previous)
        XCTAssertEqual(manager().session, previous)
        XCTAssertNotNil(model.message)
    }

    func testValueOnlySessionCanFinishWithoutWritingFood() throws {
        let model = manager()
        model.start(cuisine: .sushi, buffetPrice: 30, citySlug: nil)
        model.add(try XCTUnwrap(AYCECatalog.item(id: "sushi_salmon_nigiri")))
        XCTAssertFalse(model.finishWithoutLogging(), "Finish requires reviewing the session first")
        model.end()
        XCTAssertTrue(model.finishWithoutLogging())
        XCTAssertNil(manager().session)
        XCTAssertNotNil(manager().scoreboardRecordLine)
        XCTAssertNil(repository.lastUpdatedLog)
    }

    func testUnreadableDraftIsNotOverwrittenByStartingAgain() throws {
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "ayceSessionDraft", userID: auth.currentUserID))
        let original = Data("unreadable".utf8)
        defaults.set(original, forKey: key)
        let model = manager()
        XCTAssertNotNil(model.message)
        model.start(cuisine: .sushi, buffetPrice: 30, citySlug: nil)
        XCTAssertEqual(defaults.data(forKey: key), original)
        XCTAssertNil(model.session)
    }
}
