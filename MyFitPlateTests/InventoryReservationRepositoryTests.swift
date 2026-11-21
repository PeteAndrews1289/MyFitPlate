import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class ReservationEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3600)), nil)
    }
}
private final class ReservationEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? { app.name.hasPrefix("reservation-test-") ? ReservationEmulatorCheck() : nil }
}

@MainActor
final class InventoryReservationRepositoryTests: XCTestCase {
    private var app: FirebaseApp!
    private var auth: Auth!
    private var db: Firestore!
    private var directory: URL!
    private var owner: String!
    private var repository: FirestoreNutritionRepository!
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(ReservationEmulatorFactory())
    }
    override func tearDown() {
        try? auth?.signOut(); app?.delete { _ in }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        repository = nil; db = nil; auth = nil; app = nil; directory = nil; owner = nil
        super.tearDown()
    }
    private func connect() async throws {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "reservation-test-\(UUID().uuidString)"; FirebaseApp.configure(name: name, options: options)
        app = try XCTUnwrap(FirebaseApp.app(name: name)); auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        owner = try await auth.signInAnonymously().user.uid
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let capturedAuth = try XCTUnwrap(auth)
        repository = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"), currentUserID: { capturedAuth.currentUser?.uid })
    }
    private var plans: CollectionReference { db.collection("users").document(owner).collection("mealPlans") }
    func testReservationSourceFetchPaginatesPastOneHundredWithoutDroppingDates() async throws {
        try await connect()
        let start = Calendar.current.startOfDay(for: Date()), batch = db.batch()
        var keys: [String] = []
        for offset in 0..<101 {
            let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: offset, to: start))
            let key = MealPlanEditingRules.dayID(date); keys.append(key)
            batch.setData(["id": key, "date": Timestamp(date: date), "meals": []], forDocument: plans.document(key))
        }
        try await batch.commit()
        let loaded = try await repository.fetchMealPlansForStockReservations(userID: owner)
        XCTAssertEqual(loaded.count, 101); XCTAssertEqual(loaded.map(\.id), keys.sorted())
    }
    func testMalformedSavedPlanFailsInsteadOfReportingZeroReservations() async throws {
        try await connect()
        let date = Calendar.current.startOfDay(for: Date()), key = MealPlanEditingRules.dayID(Date())
        try await plans.document(key).setData(["id": key, "date": Timestamp(date: date), "meals": "unreadable source"])
        do { _ = try await repository.fetchMealPlansForStockReservations(userID: owner); XCTFail("Unreadable plans must not become an empty reservation source") } catch {}
    }
    func testAccountSwitchRefusesOriginalOwnersReservationSources() async throws {
        try await connect(); let originalOwner = try XCTUnwrap(owner)
        try auth.signOut()
        do { _ = try await repository.fetchMealPlansForStockReservations(userID: originalOwner); XCTFail("A signed-out client read the old account") } catch { XCTAssertEqual(error as? MealPlanChangeReceiptError, .accountChanged) }
    }
}
