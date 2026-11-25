import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class MigrationEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3600)), nil)
    }
}
private final class MigrationEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? { app.name.hasPrefix("migration-test-") ? MigrationEmulatorCheck() : nil }
}

@MainActor
final class WorkoutMigrationRepositoryTests: XCTestCase {
    private var app: FirebaseApp!
    private var auth: Auth!
    private var db: Firestore!
    private var directory: URL!
    private var owner: String!
    private var repository: FirestoreWorkoutRepository!
    private var programRef: DocumentReference { db.collection("users").document(owner).collection("workoutPrograms").document("phul") }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(MigrationEmulatorFactory())
    }
    override func tearDown() {
        try? auth?.signOut(); app?.delete { _ in }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        repository = nil; db = nil; auth = nil; app = nil; directory = nil; owner = nil
        super.tearDown()
    }
    private func connect() async throws -> WorkoutProgram {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "migration-test-\(UUID().uuidString)"; FirebaseApp.configure(name: name, options: options)
        app = try XCTUnwrap(FirebaseApp.app(name: name)); auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        owner = try await auth.signInAnonymously().user.uid
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let capturedAuth = try XCTUnwrap(auth)
        repository = FirestoreWorkoutRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"), currentUserID: { capturedAuth.currentUser?.uid }, monitorNetwork: false)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: owner, name: "Day \(index + 1)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [ExerciseSet(id: "set-\(index)", target: "8–12 reps")])])
        }
        let program = WorkoutProgram(id: "phul", userID: owner, name: "PHUL", dateCreated: date, routines: routines,
            startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39, skippedIndices: [2, 5])
        var data = try Firestore.Encoder().encode(program); data["futureUnknownField"] = ["keep": true]
        try await programRef.setData(data)
        return try await programRef.getDocument(source: .server).data(as: WorkoutProgram.self)
    }
    private func adoption(_ source: WorkoutProgram) async throws -> (WorkoutProgram, WorkoutLegacyMigrationRecord) {
        let block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let saved = try await repository.commitProgramBlock(userID: owner, expected: source, block: block, protectedSlots: [])
        let records = try await repository.fetchLegacyMigrations(userID: owner, programID: "phul")
        return (try XCTUnwrap(saved), try XCTUnwrap(records.first))
    }

    func testDurableOriginalAfterRepositoryRelaunchAndRestorePreservesRawProgramAndLogs() async throws {
        let source = try await connect()
        let originalProgram = try await programRef.getDocument(source: .server)
        let originalProgramData = try XCTUnwrap(originalProgram.data())
        let history = db.collection("users").document(owner).collection("workoutSessionLogs").document("kept")
        try await history.setData(["originalWeight": 127.345, "date": Timestamp(seconds: 1_700_000_000, nanoseconds: 123_456_789)])
        // Firestore may canonicalize the input timestamp on its first write. Preserve
        // the exact stored baseline, including its precision and all unknown fields.
        let originalLog = try await history.getDocument(source: .server)
        let originalLogData = try XCTUnwrap(originalLog.data())
        let originalTimestamp = try XCTUnwrap(originalLogData["date"] as? Timestamp)
        let (adopted, record) = try await adoption(source)
        let capturedAuth = try XCTUnwrap(auth)
        repository = FirestoreWorkoutRepository(db: db, outboxURL: directory.appendingPathComponent("other-outbox.json"), currentUserID: { capturedAuth.currentUser?.uid }, monitorNetwork: false)
        let loaded = try await repository.fetchLegacyMigrations(userID: owner, programID: "phul")
        XCTAssertEqual(try loaded.first?.fingerprint, try record.fingerprint)
        let command = try WorkoutMigrationRollbackCommand(migration: record, expected: adopted)
        let restored = try await repository.commitMigrationRollback(userID: owner, command: command, protectedSlots: [])
        XCTAssertNil(restored?.trainingBlock); XCTAssertEqual(restored?.currentProgressIndex, 39); XCTAssertEqual(restored?.skippedIndices, [2, 5])
        let raw = try await programRef.getDocument(source: .server)
        let restoredProgramData = try XCTUnwrap(raw.data())
        XCTAssertNil(restoredProgramData["trainingBlock"])
        XCTAssertTrue(NSDictionary(dictionary: restoredProgramData).isEqual(to: originalProgramData), "Restoring must preserve the exact stored program fields and timestamp values")
        let log = try await history.getDocument(source: .server)
        let preservedLogData = try XCTUnwrap(log.data())
        XCTAssertTrue(NSDictionary(dictionary: preservedLogData).isEqual(to: originalLogData), "Migration and rollback must leave the complete stored history untouched")
        let preservedTimestamp = try XCTUnwrap(preservedLogData["date"] as? Timestamp)
        XCTAssertEqual(preservedTimestamp.seconds, originalTimestamp.seconds)
        XCTAssertEqual(preservedTimestamp.nanoseconds, originalTimestamp.nanoseconds)
        try await programRef.delete()
        let replay = try await repository.commitMigrationRollback(userID: owner, command: command, protectedSlots: [])
        XCTAssertNil(replay, "Accepted replay cannot recreate a deliberately deleted program")
    }

    func testProgressCASAndSingleUseMigrationReceipt() async throws {
        let source = try await connect(), (adopted, record) = try await adoption(source)
        let stale = try WorkoutMigrationRollbackCommand(migration: record, expected: adopted)
        try await programRef.updateData(["currentProgressIndex": 40])
        do { _ = try await repository.commitMigrationRollback(userID: owner, command: stale, protectedSlots: []); XCTFail("Late review rewound progress") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .progressChanged) }
        let current = try await programRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        let first = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        _ = try await repository.commitMigrationRollback(userID: owner, command: first, protectedSlots: [])
        try await programRef.updateData(["trainingBlock": try Firestore.Encoder().encode(XCTUnwrap(current.trainingBlock))])
        let second = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        do { _ = try await repository.commitMigrationRollback(userID: owner, command: second, protectedSlots: []); XCTFail("Migration inverse applied twice") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .alreadyRestored) }
    }

    func testCancellationFencesLateCommitAndStatusAfterSignoutRefusesOldAccount() async throws {
        let source = try await connect(), (adopted, record) = try await adoption(source)
        let command = try WorkoutMigrationRollbackCommand(migration: record, expected: adopted)
        if case .pending = try await repository.resolveMigrationRollback(userID: owner, command: command, cancelPending: false) {} else { XCTFail("Expected pending") }
        _ = try await repository.resolveMigrationRollback(userID: owner, command: command, cancelPending: true)
        do { _ = try await repository.commitMigrationRollback(userID: owner, command: command, protectedSlots: []); XCTFail("Cancelled restore applied") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .cancelled) }
        try auth.signOut()
        do { _ = try await repository.resolveMigrationRollback(userID: owner, command: command, cancelPending: false); XCTFail("Old account request resolved after signout") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .accountChanged) }
    }
}
