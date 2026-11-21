import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class IntakeEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class IntakeEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("inventory-intake-test-") ? IntakeEmulatorCheck() : nil
    }
}

/// Explicit localhost synthetic accounts only; all receipt/stock/diary assertions
/// execute against real Firestore transactions, not an owner account or simulator data.
@MainActor
final class InventoryIntakeLifecycleIntegrationTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
        let repository: FirestoreNutritionRepository
        var userID: String { auth.currentUser!.uid }
        var owner: DocumentReference { db.collection("users").document(userID) }
    }
    private struct Fixture {
        let client: Client
        let use: InventoryMutation
        let stock: PantryItem
        let day: DiaryDayContext
        let dayRef: DocumentReference
        let stockRef: DocumentReference
        let meal: Meal
        let food: FoodItem
    }
    private var clients: [Client] = []
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(IntakeEmulatorFactory())
    }
    override func tearDown() {
        for value in clients {
            try? value.auth.signOut(); value.app.delete { _ in }
            try? FileManager.default.removeItem(at: value.directory)
        }
        clients = []; super.tearDown()
    }
    private func client() async throws -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "inventory-intake-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name)), auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        _ = try await auth.signInAnonymously()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let repository = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"), currentUserID: { auth.currentUser?.uid })
        let value = Client(app: app, auth: auth, db: db, directory: directory, repository: repository)
        clients.append(value); return value
    }
    private func fixture(cooked: Bool = false) async throws -> Fixture {
        let client = try await client(), date = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        var stock = PantryItem(name: cooked ? "Cooked dinner" : "Identified chicken", quantity: cooked ? 4 : 1_000, unit: cooked ? "portion" : "g", dateAdded: date)
        stock.quantityVerified = true; stock.preparation = cooked ? "Cooked batch" : "Cooked"
        stock.portionFood = cooked ? FoodItem(name: "Dinner", calories: 400, servingSize: "1 serving", servingWeight: 300)
            : FoodItem(name: "Chicken", calories: 2, protein: 0.25, servingSize: "1 g", servingWeight: 1, quantityValue: 1, servingUnit: "g")
        if cooked { stock.cookedBatch = MealCookingBatch(id: "physical-batch", sourceMealID: "source", cookingDate: date, name: "Dinner", totalPortions: 4, ingredientsPerPortion: [], instructions: nil, allocations: []) }
        let stockRef = client.owner.collection("pantryItems").document(stock.id.uuidString)
        var raw = try Firestore.Encoder().encode(stock)
        raw["futureStockField"] = ["keep": true, "timestamp": Timestamp(seconds: 1_700_000_000, nanoseconds: 123_456_789)]
        try await stockRef.setData(raw)
        stock = try await stockRef.getDocument(source: .server).data(as: PantryItem.self)
        let use = try InventoryPlanningRules.reducing(item: stock, amount: cooked ? 1 : 200, reason: .consume, userID: client.userID, date: date, mealName: "Lunch", alsoLog: true)
        try await client.repository.applyInventoryMutation(userID: client.userID, mutation: use)
        let day = try XCTUnwrap(use.diary?.day), dayRef = client.owner.collection("dailyLogs").document(day.dayKey)
        try await dayRef.setData(["futureDayField": "keep"], merge: true)
        let loadedRawDay = try await rawData(dayRef)
        var rawDay = try XCTUnwrap(loadedRawDay)
        var meals = try XCTUnwrap(rawDay["meals"] as? [[String: Any]])
        var foods = try XCTUnwrap(meals[0]["foodItems"] as? [[String: Any]])
        foods[0]["futureFoodField"] = ["keep": 7, "timestamp": Timestamp(seconds: 1_700_000_000, nanoseconds: 987_654_321),
            "location": GeoPoint(latitude: 37.25, longitude: -122.125), "reference": client.owner.collection("providerEvidence").document("retained"),
            "blob": Data([0, 1, 2, 255]), "null": NSNull(), "boolean": true, "integer": Int64.max, "double": Double.pi]
        meals[0]["foodItems"] = foods; rawDay["meals"] = meals
        try await dayRef.setData(rawDay)
        let log = try await read(dayRef)
        return Fixture(client: client, use: use, stock: stock, day: day, dayRef: dayRef, stockRef: stockRef,
            meal: try XCTUnwrap(log.meals.first), food: try XCTUnwrap(log.meals.flatMap(\.foodItems).first))
    }
    private func rawData(_ ref: DocumentReference) async throws -> [String: Any]? { try await ref.getDocument(source: .server).data() }
    private func read(_ ref: DocumentReference) async throws -> DailyLog { try await ref.getDocument(source: .server).data(as: DailyLog.self) }
    private func changed(_ log: DailyLog, expected: FoodItem?, desired: FoodItem?, meal: Meal, id: String, checked: Bool = true) -> DailyLog {
        var value = log.rememberingMutationBase(); let foodID = desired?.id ?? expected!.id
        if let desired {
            if value.meals.flatMap(\.foodItems).contains(where: { $0.id == foodID }) { _ = DailyLogRules.updateFoodInLog(log: &value, updatedFoodItem: desired) } else if let index = value.meals.firstIndex(where: { $0.id == meal.id }) { value.meals[index].foodItems.append(desired) } else { value.meals.append(Meal(id: meal.id, name: meal.name, foodItems: [desired])) }
        } else { _ = DailyLogRules.deleteFoodFromLog(log: &value, foodItemID: foodID) }
        value.pendingMutationID = id
        if checked { value.pendingFoodEdits = [FoodEditPrecondition(foodID: foodID, expected: expected, desired: desired)] }
        return value
    }
    private func sync(_ client: Client) async throws {
        for _ in 0..<160 {
            if client.repository.dailyLogSyncState(userID: client.userID) == .synced { return }
            if client.repository.dailyLogSyncState(userID: client.userID) == .failed { throw InventoryIntakeError.changed }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Synthetic diary outbox did not finish"); throw InventoryError.unavailable
    }
    private func failure(_ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected checked rejection") } catch {}
    }

    private func milestoneCommand(_ client: Client, foodID: String = "accepted-food") throws -> AchievementAwardCommand {
        let definition = try XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "first_log" })
        return try AchievementAwardCommand(ownerID: client.userID, definition: definition,
            evidence: AchievementAwardEvidence(kind: "food_entry", sourceID: "2026-11-04", sourceFingerprint: "food:\(foodID)",
                recordedAt: Date().addingTimeInterval(-60), explanation: "Accepted food", facts: ["foodID": foodID]))
    }

    func testMilestoneAwardTransactionAcceptsStatusPointsEvidenceOnceAndRejectsLateRelock() async throws {
        let client = try await client()
        let repository = FirestoreAchievementRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        try await client.owner.setData(["totalAchievementPoints": 100, "userLevel": 2, "unrelatedPreference": "keep"])
        let day = client.owner.collection("dailyLogs").document("2026-11-04")
        let log = DailyLog(id: "2026-11-04", date: Date(), meals: [Meal(name: "Lunch", foodItems: [
            FoodItem(id: "accepted-food", name: "Rice", calories: 200), FoodItem(id: "later-food", name: "Beans", calories: 250)])])
        try await day.setData(try Firestore.Encoder().encode(log))
        let first = try milestoneCommand(client), second = try milestoneCommand(client, foodID: "later-food")
        async let one = repository.acceptAward(first, levelThresholds: AchievementRules.defaultLevelThresholds)
        async let two = repository.acceptAward(second, levelThresholds: AchievementRules.defaultLevelThresholds)
        let results = try await [one, two]
        XCTAssertEqual(results.filter(\.awardedNow).count, 1)
        let profile = try await client.owner.getDocument(source: .server)
        XCTAssertEqual(profile.data()?["totalAchievementPoints"] as? Int, 110)
        XCTAssertEqual(profile.data()?["unrelatedPreference"] as? String, "keep")
        let receipts = try await client.owner.collection("achievementAwardReceipts").getDocuments(source: .server)
        XCTAssertEqual(receipts.documents.count, 1)
        let receipt = try XCTUnwrap(receipts.documents.first).data(as: AchievementAwardReceipt.self)
        XCTAssertTrue(receipt.result.status.isUnlocked)
        XCTAssertEqual(receipt.result.status.awardEvidence, receipt.command.evidence)
        var stale = first.status; stale.isUnlocked = false; stale.currentProgress = 0
        stale.awardEvidence = nil; stale.awardRulesVersion = nil; stale.awardedPoints = nil
        try await repository.saveUserStatus(userID: client.userID, status: stale)
        let replay = try await repository.acceptAward(first, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertFalse(replay.awardedNow); XCTAssertEqual(replay.totalPoints, 110)
        XCTAssertTrue(replay.status.isUnlocked)
        XCTAssertEqual(replay.status.awardEvidence, receipt.command.evidence)
    }

    func testUndoneMilestoneSourceIsDefinitiveAndNewAcceptedFoodCanAwardOnce() async throws {
        let client = try await client()
        let repository = FirestoreAchievementRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        try await client.owner.setData(["totalAchievementPoints": 0, "userLevel": 1])
        let day = client.owner.collection("dailyLogs").document("2026-11-04")
        try await day.setData(try Firestore.Encoder().encode(DailyLog(id: "2026-11-04", date: Date(), meals: [])))
        let removed = try milestoneCommand(client, foodID: "undone-food")
        do {
            _ = try await repository.acceptAward(removed, levelThresholds: AchievementRules.defaultLevelThresholds)
            XCTFail("A server-confirmed removed food cannot unlock a milestone")
        } catch AchievementAwardError.evidenceNoLongerEligible { } catch { XCTFail("Expected definitive obsolete evidence, got \(error)") }
        let acceptedFood = FoodItem(id: "kept-food", name: "Rice", calories: 200)
        try await day.setData(try Firestore.Encoder().encode(DailyLog(id: "2026-11-04", date: Date(), meals: [Meal(name: "Lunch", foodItems: [acceptedFood])])))
        let accepted = try await repository.acceptAward(milestoneCommand(client, foodID: "kept-food"), levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertTrue(accepted.awardedNow); XCTAssertEqual(accepted.totalPoints, 10)
        let replay = try await repository.acceptAward(removed, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertFalse(replay.awardedNow); XCTAssertEqual(replay.totalPoints, 10)
        XCTAssertEqual(replay.status.awardEvidence?.facts?["foodID"], "kept-food")
    }

    func testMilestoneLoggingDaysUseCanonicalDiaryKeysAcrossTravelOffsets() async throws {
        let client = try await client()
        let repository = FirestoreAchievementRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        try await client.owner.setData(["totalAchievementPoints": 0, "userLevel": 1])
        var remote = Calendar(identifier: .gregorian)
        remote.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let today = Calendar.current.startOfDay(for: Date())
        var keys: [String] = []
        for offset in 0..<3 {
            let localDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -offset, to: today))
            let key = try XCTUnwrap(DiaryDayContext.dayKey(for: localDay)); keys.append(key)
            var components = Calendar.current.dateComponents([.year, .month, .day], from: localDay); components.hour = 0
            let remoteMidnight = try XCTUnwrap(remote.date(from: components))
            let log = DailyLog(id: key, date: offset == 2 ? localDay : remoteMidnight,
                meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "food-\(offset)", name: "Rice", calories: 200)])])
            try await client.owner.collection("dailyLogs").document(key).setData(try Firestore.Encoder().encode(log))
        }
        let definition = try XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "log_streak_3" })
        let command = try AchievementAwardCommand(ownerID: client.userID, definition: definition,
            evidence: AchievementAwardEvidence(kind: "logging_days", sourceID: keys[0], sourceFingerprint: try PlanFingerprint.make(keys),
                recordedAt: Date(), explanation: "Three confirmed diary days", facts: ["dayKeys": keys.joined(separator: ",")]))
        let result = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertTrue(result.awardedNow); XCTAssertEqual(result.totalPoints, 20)
    }

    func testMilestoneLegacyAliasPreservesHistoricalBalanceWithoutGrantingAgain() async throws {
        let client = try await client()
        let repository = FirestoreAchievementRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        try await client.owner.setData(["totalAchievementPoints": 987, "userLevel": 4])
        let command = try milestoneCommand(client)
        var legacy = command.status
        legacy.id = "legacy-random-id"; legacy.awardEvidence = nil; legacy.awardRulesVersion = nil; legacy.awardedPoints = nil
        try await client.owner.collection(FirestoreCollection.achievementStatus).document("legacy-random-id").setData(try Firestore.Encoder().encode(legacy))
        let accepted = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertFalse(accepted.awardedNow); XCTAssertEqual(accepted.totalPoints, 987)
        XCTAssertEqual(accepted.status.legacyAwardPreserved, true)
        XCTAssertNil(accepted.status.awardEvidence)
        let profile = try await client.owner.getDocument(source: .server)
        XCTAssertEqual(profile.data()?["totalAchievementPoints"] as? Int, 987)
    }

    func testMilestoneEmptyDiaryMalformedBalanceAndMalformedStatusNeverBecomeFreshAwards() async throws {
        let client = try await client()
        let repository = FirestoreAchievementRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        let command = try milestoneCommand(client)
        let day = client.owner.collection("dailyLogs").document("2026-11-04")
        try await day.setData(try Firestore.Encoder().encode(DailyLog(id: "2026-11-04", date: Date(), meals: [])))
        try await client.owner.setData(["totalAchievementPoints": 0, "userLevel": 1])
        await failure { _ = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds) }
        try await client.owner.updateData(["totalAchievementPoints": "unreadable historical points"])
        await failure { _ = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds) }
        try await client.owner.updateData(["totalAchievementPoints": 500])
        try await client.owner.collection(FirestoreCollection.achievementStatus).document("first_log").setData(["achievementID": "first_log", "isUnlocked": "unreadable"])
        await failure { _ = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds) }
        let receipts = try await client.owner.collection("achievementAwardReceipts").getDocuments(source: .server)
        XCTAssertTrue(receipts.documents.isEmpty)
        let profile = try await client.owner.getDocument(source: .server)
        XCTAssertEqual(profile.data()?["totalAchievementPoints"] as? Int, 500)
    }

    func testCheckedRunActivityRejectsStaleFieldsAndReplaysWithoutReplacingNewerDiaryTotals() async throws {
        let client = try await client()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let day = try XCTUnwrap(DiaryDayContext(userID: client.userID, date: date))
        let ref = client.owner.collection("dailyLogs").document(day.dayKey)
        let original = LoggedExercise(id: UUID().uuidString, name: "Running", durationMinutes: 30,
            caloriesBurned: 300, date: date, source: "HealthKit")
        let initial = DailyLog(id: day.dayKey, date: day.originalDate,
            meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "keep-food", name: "Rice", calories: 200)])], exercises: [original])
        var raw = try Firestore.Encoder().encode(initial); raw["futureDayField"] = "keep"
        try await ref.setData(raw)
        func proposal(_ base: DailyLog, expected: LoggedExercise, calories: Double, operation: String) -> DailyLog {
            var value = base.rememberingMutationBase(), desired = expected
            desired.caloriesBurned = calories; desired.durationMinutes = 32; desired.hasLocalHealthKitEdits = true
            value.exercises = [desired]; value.pendingMutationID = operation
            value.pendingActivityEdit = ActivityEditPrecondition(expected: expected, desired: desired)
            return value
        }
        func update(_ value: DailyLog) async -> Bool {
            await withCheckedContinuation { continuation in
                client.repository.updateDailyLog(userID: client.userID, log: value) { continuation.resume(returning: $0) }
            }
        }
        let stale = proposal(initial, expected: original, calories: 400, operation: "stale-run-correction")
        var independent = original; independent.caloriesBurned = 777; independent.hasLocalHealthKitEdits = true
        try await ref.updateData(["exercises": [try Firestore.Encoder().encode(independent)]])
        let rejected = await update(stale)
        XCTAssertFalse(rejected, "The activity-only marker must take the checked server transaction path")
        var current = try await read(ref)
        XCTAssertEqual(current.exercises?.first?.caloriesBurned, 777)
        let accepted = proposal(current, expected: independent, calories: 450, operation: "accepted-run-correction")
        let confirmed = await update(accepted)
        XCTAssertTrue(confirmed)
        current = try await read(ref)
        XCTAssertEqual(current.exercises?.first?.caloriesBurned, 450)
        var later = try XCTUnwrap(current.exercises?.first); later.caloriesBurned = 888
        try await ref.updateData(["exercises": [try Firestore.Encoder().encode(later)]])
        let replayed = await update(accepted)
        XCTAssertTrue(replayed, "The accepted operation is idempotent, and callers must inspect canonical current totals")
        let final = try await read(ref)
        XCTAssertEqual(final.exercises?.first?.caloriesBurned, 888)
        XCTAssertEqual(final.appliedMutationIDs?.filter { $0 == "accepted-run-correction" }.count, 1)
        XCTAssertEqual(final.meals.flatMap(\.foodItems).map(\.id), ["keep-food"])
        let finalRaw = try await rawData(ref)
        XCTAssertEqual(finalRaw?["futureDayField"] as? String, "keep")
    }

    func testEditDeleteAndDiaryUndoPreserveLaterPurchasesUnknownFieldsAndOriginalReceipt() async throws {
        let fixture = try await fixture(), client = fixture.client
        let eventRef = client.owner.collection("inventoryEvents").document(fixture.use.id.uuidString)
        let immutableBefore = try await rawData(eventRef)
        let stockBefore = try await rawData(fixture.stockRef)
        let dayBefore = try await rawData(fixture.dayRef)
        try await fixture.stockRef.updateData(["quantity": 1_200, "location": "Later purchase shelf"])
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 1.5))
        let original = try await read(fixture.dayRef)
        let edit = changed(original, expected: fixture.food, desired: updated, meal: fixture.meal, id: "checked-edit")
        try await client.repository.saveDailyLog(userID: client.userID, log: edit)
        var stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(stock.quantity, 1_100); XCTAssertEqual(stock.location, "Later purchase shelf")
        var current = try await read(fixture.dayRef)
        XCTAssertEqual(current.meals.flatMap(\.foodItems).first?.servingWeight, 300)
        let reviewedDay = try await rawData(fixture.dayRef)
        let reviewedMeals = try XCTUnwrap(reviewedDay?["meals"] as? [[String: Any]])
        let reviewedFoods = try XCTUnwrap(reviewedMeals.first?["foodItems"] as? [[String: Any]])
        let reviewedFood = try XCTUnwrap(reviewedFoods.first)
        let deletion = changed(current, expected: updated, desired: nil, meal: fixture.meal, id: "delete-intake", checked: false)
        try await client.repository.saveDailyLog(userID: client.userID, log: deletion); try await sync(client)
        current = try await read(fixture.dayRef); XCTAssertTrue(current.meals.flatMap(\.foodItems).isEmpty)
        stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self); XCTAssertEqual(stock.quantity, 1_400)
        let undo = changed(current, expected: nil, desired: updated, meal: fixture.meal, id: "undo-delete")
        try await client.repository.saveDailyLog(userID: client.userID, log: undo)
        try await client.repository.saveDailyLog(userID: client.userID, log: undo)
        stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self); XCTAssertEqual(stock.quantity, 1_100)
        let loadedStock = try await rawData(fixture.stockRef), loadedDay = try await rawData(fixture.dayRef)
        let finalStock = try XCTUnwrap(loadedStock), finalDay = try XCTUnwrap(loadedDay)
        XCTAssertEqual(finalStock["location"] as? String, "Later purchase shelf")
        XCTAssertTrue(NSDictionary(dictionary: ["value": finalStock["futureStockField"]!]).isEqual(to: ["value": stockBefore!["futureStockField"]!]))
        XCTAssertEqual(finalDay["futureDayField"] as? String, dayBefore?["futureDayField"] as? String)
        let restoredMeals = try XCTUnwrap(finalDay["meals"] as? [[String: Any]])
        let restoredFoods = try XCTUnwrap(restoredMeals.first?["foodItems"] as? [[String: Any]])
        let restoredFood = try XCTUnwrap(restoredFoods.first)
        XCTAssertTrue(NSDictionary(dictionary: reviewedFood).isEqual(to: restoredFood), "Checked deletion Undo must restore the full raw food, including provider extensions and nanosecond timestamps")
        let originalAfter = try await rawData(eventRef)
        XCTAssertTrue(NSDictionary(dictionary: immutableBefore!).isEqual(to: originalAfter!))
        let events = try await client.repository.fetchInventoryHistory(userID: client.userID)
        XCTAssertEqual(events.count, 4, "Original consumption plus edit/delete/Undo; retry never appends a fifth physical event")
    }

    func testConcurrentEditsHaveOneWinnerAndAcceptedReplayCannotOverwriteLaterFoodOrStock() async throws {
        let fixture = try await fixture(), client = fixture.client
        let original = try await read(fixture.dayRef)
        let large = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 1.5)), small = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 0.5))
        let first = changed(original, expected: fixture.food, desired: large, meal: fixture.meal, id: "first")
        let second = changed(original, expected: fixture.food, desired: small, meal: fixture.meal, id: "second")
        func attempt(_ value: DailyLog) async -> Bool { do { try await client.repository.saveDailyLog(userID: client.userID, log: value); return true } catch { return false } }
        async let firstResult = attempt(first); async let secondResult = attempt(second)
        let results = await [firstResult, secondResult]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let winner = results[0] ? first : second, winningFood = results[0] ? large : small
        let current = try await read(fixture.dayRef)
        let later = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 0.75))
        let latestEdit = changed(current, expected: winningFood, desired: later, meal: fixture.meal, id: "later")
        try await client.repository.saveDailyLog(userID: client.userID, log: latestEdit)
        try await client.repository.saveDailyLog(userID: client.userID, log: winner)
        let saved = try await read(fixture.dayRef), stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(saved.meals.flatMap(\.foodItems).first?.servingWeight, 150); XCTAssertEqual(stock.quantity, 850)
        var altered = winner; altered.pendingFoodEdits = [FoodEditPrecondition(original: fixture.food, desired: later)]
        await failure { try await client.repository.saveDailyLog(userID: client.userID, log: altered) }
        let tooMuch = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 10))
        let negative = changed(saved, expected: later, desired: tooMuch, meal: fixture.meal, id: "negative")
        await failure { try await client.repository.saveDailyLog(userID: client.userID, log: negative) }
        let unchanged = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self); XCTAssertEqual(unchanged.quantity, 850)
    }

    func testCookedIntakeLegacyLinkBackfillAndDeletionNeverRepeatRawCookingOrDoubleUndo() async throws {
        let fixture = try await fixture(cooked: true), client = fixture.client
        let rawRef = client.owner.collection("pantryItems").document(UUID().uuidString)
        let rawStock = PantryItem(name: "Ingredients already cooked", quantity: 600, unit: "g", dateAdded: Date(timeIntervalSince1970: 1_700_000_000))
        try await rawRef.setData(Firestore.Encoder().encode(rawStock))
        try await client.owner.collection("inventoryIntakeLinks").document(InventoryIntakeRules.key(foodID: fixture.food.id)).delete()
        let linked = try await client.repository.fetchInventoryIntakeLink(userID: client.userID, foodID: fixture.food.id)
        XCTAssertEqual(linked?.source.id, fixture.use.id)
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 2))
        let original = try await read(fixture.dayRef)
        try await client.repository.saveDailyLog(userID: client.userID, log: changed(original, expected: fixture.food, desired: updated, meal: fixture.meal, id: "two-portions"))
        let current = try await read(fixture.dayRef)
        try await client.repository.saveDailyLog(userID: client.userID, log: changed(current, expected: updated, desired: nil, meal: fixture.meal, id: "remove-portions"))
        let physical = try await client.repository.fetchInventory(userID: client.userID)
        XCTAssertEqual(physical.first { $0.id == fixture.stock.id }?.quantity, 4)
        let raw = try await rawRef.getDocument(source: .server).data(as: PantryItem.self); XCTAssertEqual(raw.quantity, 600)
        let oldUndo = try InventoryPlanningRules.undoing(fixture.use, current: physical)
        await failure { try await client.repository.applyInventoryMutation(userID: client.userID, mutation: oldUndo) }
        let stillCorrect = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self); XCTAssertEqual(stillCorrect.quantity, 4)
    }
    func testStockHistoryUndoOfIntakeCorrectionPreservesUnknownFoodFieldsAndPreciseTimestamp() async throws {
        let fixture = try await fixture(), client = fixture.client
        let originalRaw = try await rawData(fixture.dayRef)
        let originalMeals = try XCTUnwrap(originalRaw?["meals"] as? [[String: Any]])
        let originalFoods = try XCTUnwrap(originalMeals.first?["foodItems"] as? [[String: Any]])
        let originalFood = try XCTUnwrap(originalFoods.first)
        let original = try await read(fixture.dayRef)
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(fixture.food, by: 1.5))
        try await client.repository.saveDailyLog(userID: client.userID,
            log: changed(original, expected: fixture.food, desired: updated, meal: fixture.meal, id: "edit-for-stock-undo"))
        let history = try await client.repository.fetchInventoryHistory(userID: client.userID)
        let correction = try XCTUnwrap(history.first { $0.id != fixture.use.id })
        let currentStock = try await client.repository.fetchInventory(userID: client.userID)
        let undo = try InventoryPlanningRules.undoing(correction.mutation(), current: currentStock)
        try await client.repository.applyInventoryMutation(userID: client.userID, mutation: undo)
        let currentRaw = try await rawData(fixture.dayRef)
        let currentMeals = try XCTUnwrap(currentRaw?["meals"] as? [[String: Any]])
        let currentFoods = try XCTUnwrap(currentMeals.first?["foodItems"] as? [[String: Any]])
        let currentFood = try XCTUnwrap(currentFoods.first)
        for key in ["futureFoodField", "timestamp"] {
            XCTAssertTrue(NSDictionary(dictionary: ["value": originalFood[key]!]).isEqual(to: ["value": currentFood[key]!]), key)
        }
        let current = try await read(fixture.dayRef)
        XCTAssertEqual(current.meals.flatMap(\.foodItems).first?.servingWeight, 200)
        let stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(stock.quantity, 800)
        try await client.repository.applyInventoryMutation(userID: client.userID, mutation: undo)
        let replayStock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(replayStock.quantity, 800)
    }

    func testTamperedDeletedFoodBackupRejectsUndoWithoutChangingDiaryOrStock() async throws {
        let fixture = try await fixture(), client = fixture.client
        let original = try await read(fixture.dayRef)
        let operationID = "delete-with-backup"
        try await client.repository.saveDailyLog(userID: client.userID,
            log: changed(original, expected: fixture.food, desired: nil, meal: fixture.meal, id: operationID))
        let eventID = InventoryIntakeRules.eventID(userID: client.userID, operationID: operationID, foodID: fixture.food.id)
        let ref = client.owner.collection("inventoryEvents").document(eventID.uuidString)
        let deletedData = try await rawData(ref)
        let data = try XCTUnwrap(deletedData)
        var backup = try XCTUnwrap(data["beforeFoodBackup"] as? [String: Any])
        backup["unreviewedProviderField"] = "tampered"
        try await ref.updateData(["beforeFoodBackup": backup])
        let deleted = try await read(fixture.dayRef)
        let undo = changed(deleted, expected: nil, desired: fixture.food, meal: fixture.meal, id: "undo-tampered-deletion")
        await failure { try await client.repository.saveDailyLog(userID: client.userID, log: undo) }
        let current = try await read(fixture.dayRef)
        let stock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertTrue(current.meals.flatMap(\.foodItems).isEmpty)
        XCTAssertEqual(stock.quantity, 1_000)
    }

    func testStockHistoryDeletionThenCheckedDiaryUndoKeepsExactServerFractionalTimestamp() async throws {
        let fixture = try await fixture(), client = fixture.client
        let originalRaw = try await rawData(fixture.dayRef)
        let originalMeals = try XCTUnwrap(originalRaw?["meals"] as? [[String: Any]])
        let originalFoods = try XCTUnwrap(originalMeals.first?["foodItems"] as? [[String: Any]])
        let originalFood = try XCTUnwrap(originalFoods.first)
        let frozenSourceFood = try XCTUnwrap(fixture.use.diary?.desired)
        let stock = try await client.repository.fetchInventory(userID: client.userID)
        let deletion = try InventoryPlanningRules.undoing(fixture.use, current: stock)
        try await client.repository.applyInventoryMutation(userID: client.userID, mutation: deletion)
        let empty = try await read(fixture.dayRef)
        XCTAssertTrue(empty.meals.flatMap(\.foodItems).isEmpty)
        let restoration = changed(empty, expected: nil, desired: frozenSourceFood, meal: fixture.meal, id: "restore-frozen-source-after-stock-undo")
        try await client.repository.saveDailyLog(userID: client.userID, log: restoration)
        let restoredRaw = try await rawData(fixture.dayRef)
        let restoredMeals = try XCTUnwrap(restoredRaw?["meals"] as? [[String: Any]])
        let restoredFoods = try XCTUnwrap(restoredMeals.first?["foodItems"] as? [[String: Any]])
        let restoredFood = try XCTUnwrap(restoredFoods.first)
        XCTAssertTrue(NSDictionary(dictionary: originalFood).isEqual(to: restoredFood), "Typed frozen Date precision must never replace the exact server raw backup")
        let finalStock = try await fixture.stockRef.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(finalStock.quantity, 800)
    }

}
