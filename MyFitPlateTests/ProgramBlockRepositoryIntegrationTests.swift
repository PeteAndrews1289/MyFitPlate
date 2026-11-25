import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class ProgramBlockEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}

private final class ProgramBlockEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("program-block-test-") ? ProgramBlockEmulatorCheck() : nil
    }
}

/// Named synthetic Firebase apps and fixed localhost endpoints only. Opt in using
/// MYFITPLATE_EMULATOR_TESTS=YES; this never selects the production Firebase app.
@MainActor
final class ProgramBlockRepositoryIntegrationTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
    }
    private struct Fixture {
        let client: Client
        let uid: String
        let baseline: WorkoutProgram
        let reference: DocumentReference
        let history: DocumentReference
        let repository: FirestoreWorkoutRepository
    }
    private var clients: [Client] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(ProgramBlockEmulatorCheckFactory())
    }

    override func tearDown() {
        for client in clients {
            try? client.auth.signOut()
            client.app.delete { _ in }
            try? FileManager.default.removeItem(at: client.directory)
        }
        clients = []
        super.tearDown()
    }

    private func client() -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "program-block-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        let value = Client(app: app, auth: auth, db: db,
                           directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        clients.append(value)
        return value
    }

    private func fixture(pending: Bool = false) async throws -> Fixture {
        let client = client()
        let uid = try await client.auth.signInAnonymously().user.uid
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "phul-day-\(index)", userID: uid, name: "PHUL day \(index + 1)",
                dateCreated: Date(timeIntervalSince1970: 1_700_000_000.123456), exercises: [
                    RoutineExercise(id: "movement-\(index)", name: "Squat", sets: [
                        ExerciseSet(id: "set-\(index)", target: "8-12 reps")
                    ])
                ])
        }
        let program = WorkoutProgram(id: "active-phul", userID: uid, name: "PHUL",
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000.123456), routines: routines,
            startDate: Date(timeIntervalSince1970: 1_700_000_000.123456), daysOfWeek: [2, 3, 5, 6],
            currentProgressIndex: 39, skippedIndices: [2, 5])
        let user = client.db.collection("users").document(uid)
        let reference = user.collection("workoutPrograms").document("active-phul")
        var data = try Firestore.Encoder().encode(program)
        data["unrelatedLegacyField"] = "keep"
        try await reference.setData(data)
        let history = user.collection("workoutSessionLogs").document("existing-history")
        try await history.setData(["date": Timestamp(seconds: 1_700_000_000, nanoseconds: 123_456_789),
                                   "legacyTarget": "8-12 reps", "actualReps": 11, "actualWeight": 127.345])
        let baseline = try await read(reference)
        let outboxURL = client.directory.appendingPathComponent("outbox.json")
        if pending {
            try WorkoutOutbox(fileURL: outboxURL).append(WorkoutPendingWrite(userID: uid, collection: .programs,
                documentID: "active-phul", value: baseline))
        }
        // Disable only automatic network wake-up. The preseeded queue must remain
        // pending until the tested preflight inspects it; normal explicit retry works.
        let repository = FirestoreWorkoutRepository(db: client.db, outboxURL: outboxURL,
            currentUserID: { client.auth.currentUser?.uid }, monitorNetwork: false)
        return Fixture(client: client, uid: uid, baseline: baseline, reference: reference, history: history, repository: repository)
    }

    private func read(_ reference: DocumentReference) async throws -> WorkoutProgram {
        let snapshot = try await reference.getDocument(source: .server)
        var program = try snapshot.data(as: WorkoutProgram.self)
        program.id = reference.documentID
        return program
    }

    private func authored(_ fixture: Fixture, slot: Int = 40) throws -> WorkoutProgramBlock {
        var block = try WorkoutBlockRules.createRepeatingBlock(for: fixture.baseline)
        block.name = "Reviewed PHUL block"
        let routine = try XCTUnwrap(fixture.baseline.routine(forSlot: slot)?.deepCopy())
        routine.dateCreated = Date(timeIntervalSince1970: 1_700_000_000.123456789)
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rpe, value: 8), loadPercentage: 75,
            loadReference: .init(label: "Squat training max", weightPounds: 200,
                                 date: Date(timeIntervalSince1970: 1_700_000_001.987654321)))
        routine.exercises[0].sets[0].prescription = target
        routine.exercises[0].sets[0].target = target.targetText
        block.overrides = [WorkoutBlockSlotOverride(slotIndex: slot, routine: routine)]
        block.weeks[10].name = "Lighter week"
        block.weeks[10].isDeload = true
        return block
    }

    func testCheckedBlockSavePreservesCanonicalProgressSkipsDatesAndHistory() async throws {
        let fixture = try await fixture()
        let originalSnapshot = try await fixture.reference.getDocument(source: .server)
        let original = try XCTUnwrap(originalSnapshot.data())
        let historyBefore = try await fixture.history.getDocument(source: .server).data()
        let block = try authored(fixture)
        try await fixture.reference.setData(["currentProgressIndex": 40, "skippedIndices": [2, 5, 39]], merge: true)
        let result = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                   block: block, protectedSlots: [])
        let saved = try XCTUnwrap(result)
        XCTAssertEqual(saved.currentProgressIndex, 40)
        XCTAssertEqual(saved.skippedIndices, [2, 5, 39])
        XCTAssertEqual(saved.totalSlots, 48)
        let canonical = try await read(fixture.reference)
        XCTAssertEqual(canonical.currentProgressIndex, 40)
        XCTAssertEqual(canonical.trainingBlock?.revisionID, block.revisionID)
        XCTAssertEqual(canonical.routine(forSlot: 40)?.exercises[0].sets[0].prescription,
                       block.overrides[0].routine.exercises[0].sets[0].prescription)
        let afterSnapshot = try await fixture.reference.getDocument(source: .server)
        let after = try XCTUnwrap(afterSnapshot.data())
        XCTAssertEqual(after["unrelatedLegacyField"] as? String, "keep")
        for key in ["dateCreated", "startDate"] {
            let beforeDate = try XCTUnwrap(original[key] as? Timestamp)
            let afterDate = try XCTUnwrap(after[key] as? Timestamp)
            XCTAssertEqual(beforeDate.seconds, afterDate.seconds)
            XCTAssertEqual(beforeDate.nanoseconds, afterDate.nanoseconds)
        }
        let historyAfter = try await fixture.history.getDocument(source: .server).data()
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(historyBefore)).isEqual(to: try XCTUnwrap(historyAfter)))
    }

    func testLostAcknowledgementRetryKeepsExactFractionalOverrideDatesAndOneRevision() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        let restarted = FirestoreWorkoutRepository(db: fixture.client.db,
            outboxURL: fixture.client.directory.appendingPathComponent("restarted-outbox.json"),
            currentUserID: { fixture.client.auth.currentUser?.uid }, monitorNetwork: false)
        let replay = try await restarted.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        let canonical = try await read(fixture.reference)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(canonical.trainingBlock)),
                       try WorkoutBlockRules.fingerprint(block))
        XCTAssertEqual(replay?.trainingBlock?.revisionID, block.revisionID)
        XCTAssertEqual(canonical.trainingBlock?.overrides.count, 1)
        XCTAssertEqual(canonical.trainingBlock?.overrides[0].routine.dateCreated, block.overrides[0].routine.dateCreated)
        XCTAssertEqual(canonical.trainingBlock?.overrides[0].routine.exercises[0].sets[0].prescription?.loadReference?.date,
                       block.overrides[0].routine.exercises[0].sets[0].prescription?.loadReference?.date)
    }

    func testConcurrentProgramStructureChangeCannotBeOverwritten() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        try await fixture.reference.setData(["name": "Remote PHUL edit"], merge: true)
        do {
            _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                block: block, protectedSlots: [])
            XCTFail("A stale program proposal must be rejected")
        } catch { XCTAssertEqual(error.localizedDescription, WorkoutBlockError.changed.localizedDescription) }
        let canonical = try await read(fixture.reference)
        XCTAssertEqual(canonical.name, "Remote PHUL edit")
        XCTAssertNil(canonical.trainingBlock)
        XCTAssertEqual(canonical.currentProgressIndex, 39)
    }

    func testPendingOutboxBlocksAuthoringAndRetainsOriginalCommand() async throws {
        let fixture = try await fixture(pending: true)
        let block = try authored(fixture)
        let outbox = WorkoutOutbox(fileURL: fixture.client.directory.appendingPathComponent("outbox.json"))
        let original = try XCTUnwrap(outbox.pending(userID: fixture.uid).first)
        do {
            _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                block: block, protectedSlots: [])
            XCTFail("A locally pending program save must finish first")
        } catch { XCTAssertEqual(error.localizedDescription, WorkoutBlockError.pendingSync.localizedDescription) }
        XCTAssertEqual(try outbox.pending(userID: fixture.uid).map(\.id), [original.id])
        XCTAssertEqual(try outbox.pending(userID: fixture.uid).first?.payload, original.payload)
        let canonical = try await read(fixture.reference)
        XCTAssertNil(canonical.trainingBlock)
    }

    func testLaterOrdinaryProgressWriteCannotReplaceAuthoredBlock() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        var stale = fixture.baseline
        stale.currentProgressIndex = 40
        // A delayed older client does not know the authored block at all.
        _ = try await fixture.repository.saveProgram(userID: fixture.uid, program: stale)
        for _ in 0..<100 {
            if fixture.repository.workoutSyncState(userID: fixture.uid) == .synced { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(fixture.repository.workoutSyncState(userID: fixture.uid), .synced)
        let canonical = try await read(fixture.reference)
        XCTAssertEqual(canonical.currentProgressIndex, 40)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(canonical.trainingBlock)),
                       try WorkoutBlockRules.fingerprint(block))
    }

    func testPassedAndRecoveredActiveSlotsRejectChangedTargets() async throws {
        let fixture = try await fixture()
        for (slot, protected) in [(38, Set<Int>()), (40, Set([40]))] {
            let block = try authored(fixture, slot: slot)
            do {
                _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                    block: block, protectedSlots: protected)
                XCTFail("Passed and recovered sessions must keep their exact targets")
            } catch { XCTAssertEqual(error.localizedDescription, WorkoutBlockError.progressChanged.localizedDescription) }
        }
        let canonical = try await read(fixture.reference)
        XCTAssertNil(canonical.trainingBlock)
        XCTAssertEqual(canonical.currentProgressIndex, 39)
    }

    func testAcceptedRetryAfterLaterBlockEditReturnsCurrentProgramWithoutWriting() async throws {
        let fixture = try await fixture()
        let original = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: original, protectedSlots: [])
        let accepted = try await read(fixture.reference)
        var later = try XCTUnwrap(accepted.trainingBlock)
        later.revisionID = UUID().uuidString; later.name = "Later reviewed edit"
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: accepted, block: later, protectedSlots: [])
        let before = try await fixture.reference.getDocument(source: .server).data()
        let replay = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                     block: original, protectedSlots: [])
        XCTAssertEqual(replay?.trainingBlock?.revisionID, later.revisionID)
        let after = try await fixture.reference.getDocument(source: .server).data()
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(before)).isEqual(to: try XCTUnwrap(after)))
    }

    func testAcceptedRetryAndStatusAfterLaterDeletionNeverRecreateProgram() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        try await fixture.reference.delete()
        let replay = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                     block: block, protectedSlots: [])
        XCTAssertNil(replay)
        let status = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                      block: block, cancelPending: false)
        guard case .accepted(let removed)? = status else { return XCTFail("The permanent receipt must retain acceptance") }
        XCTAssertNil(removed)
        let snapshot = try await fixture.reference.getDocument(source: .server)
        XCTAssertFalse(snapshot.exists)
    }

    func testCancellationFenceRejectsLateSubmissionAndStatusIsReadOnly() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        let unknown = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                       block: block, cancelPending: false)
        XCTAssertNil(unknown)
        let result = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                      block: block, cancelPending: true)
        guard case .cancelled? = result else { return XCTFail("An unaccepted operation must be fenced before clearing local intent") }
        do {
            _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                block: block, protectedSlots: [])
            XCTFail("A late old command cannot bypass cancellation")
        } catch { XCTAssertEqual(error.localizedDescription, WorkoutBlockError.cancelled.localizedDescription) }
        let canonical = try await read(fixture.reference)
        XCTAssertNil(canonical.trainingBlock)
        XCTAssertEqual(canonical.currentProgressIndex, 39)
        let status = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                      block: block, cancelPending: false)
        guard case .cancelled? = status else { return XCTFail("Cancelled status must remain durable") }
    }

    func testCancelRacingAcceptanceHasOneDurableOutcome() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        let save = Task { () -> Result<WorkoutProgram?, Error> in
            do { return .success(try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                                block: block, protectedSlots: [])) } catch { return .failure(error) }
        }
        let cancel = Task {
            try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                             block: block, cancelPending: true)
        }
        _ = try await cancel.value
        let saveResult = await save.value
        let status = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                      block: block, cancelPending: false)
        let canonical = try await read(fixture.reference)
        switch status {
        case .accepted(let program)?:
            XCTAssertNotNil(program)
            XCTAssertEqual(canonical.trainingBlock?.revisionID, block.revisionID)
        case .cancelled?:
            XCTAssertNil(canonical.trainingBlock)
            if case .success = saveResult { XCTFail("A cancelled operation cannot also report acceptance") }
        case nil: XCTFail("The race must leave a permanent outcome")
        }
        XCTAssertEqual(canonical.currentProgressIndex, 39)
    }

    func testReceiptFingerprintCollisionCannotReuseRevisionForChangedProposal() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        var collision = block; collision.name = "Different command, reused UUID"
        do {
            _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                block: collision, protectedSlots: [])
            XCTFail("The same operation ID cannot authorize another reviewed payload")
        } catch { XCTAssertEqual(error.localizedDescription, WorkoutBlockError.changed.localizedDescription) }
        let canonical = try await read(fixture.reference)
        XCTAssertEqual(canonical.trainingBlock?.name, block.name)
    }

    func testAcceptedStatusPreservesNewerLocalOutboxFieldsWithoutRewritingBlock() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        var pending = fixture.baseline
        pending.currentProgressIndex = 41; pending.name = "Locally accepted rename"
        let write = try WorkoutPendingWrite(userID: fixture.uid, collection: .programs, documentID: "active-phul", value: pending)
        let outbox = WorkoutOutbox(fileURL: fixture.client.directory.appendingPathComponent("outbox.json"))
        try outbox.append(write)
        let status = try await fixture.repository.resolveProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                                      block: block, cancelPending: false)
        guard case .accepted(let visible)? = status else { return XCTFail("Accepted receipt should remain visible") }
        XCTAssertEqual(visible?.currentProgressIndex, 41)
        XCTAssertEqual(visible?.name, "Locally accepted rename")
        XCTAssertEqual(visible?.trainingBlock?.revisionID, block.revisionID)
        let remote = try await read(fixture.reference)
        XCTAssertEqual(remote.currentProgressIndex, 39)
        XCTAssertEqual(remote.name, "PHUL")
        XCTAssertEqual(try outbox.pending(userID: fixture.uid).map(\.id), [write.id])
    }

    func testLiveLibraryRetainsCanonicalBlockWhilePublishingPendingProgressOffline() async throws {
        let fixture = try await fixture()
        let block = try authored(fixture)
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.uid, expected: fixture.baseline,
                                                            block: block, protectedSlots: [])
        let initial = expectation(description: "Canonical block published and cached")
        let pendingPublished = expectation(description: "Pending pointer retains authored block")
        var didPublishInitial = false
        var didPublishPending = false
        let handle = fixture.repository.addProgramLibraryListener(userID: fixture.uid) { result in
            guard case .success(let snapshot) = result,
                  let program = snapshot.values.first(where: { $0.id == "active-phul" }) else { return }
            if program.currentProgressIndex == 39, program.trainingBlock?.revisionID == block.revisionID, !didPublishInitial {
                didPublishInitial = true; initial.fulfill()
            }
            if program.currentProgressIndex == 41, program.name == "Pending local schedule", !didPublishPending {
                didPublishPending = true
                XCTAssertEqual(program.trainingBlock?.revisionID, block.revisionID)
                XCTAssertEqual(program.routine(forSlot: 40)?.exercises[0].sets[0].target, "5–8 reps")
                pendingPublished.fulfill()
            }
        }
        var removedInitialListener = false
        defer { if !removedInitialListener { fixture.repository.removeListener(handle) } }
        await fulfillment(of: [initial], timeout: 10)
        try await fixture.client.db.disableNetwork()
        var pending = fixture.baseline
        pending.currentProgressIndex = 41; pending.name = "Pending local schedule"
        let write = try WorkoutPendingWrite(userID: fixture.uid, collection: .programs, documentID: "active-phul", value: pending)
        let outbox = WorkoutOutbox(fileURL: fixture.client.directory.appendingPathComponent("outbox.json"))
        try outbox.append(write)
        NotificationCenter.default.post(name: .workoutSyncStateChanged, object: fixture.uid, userInfo: ["changed": true])
        await fulfillment(of: [pendingPublished], timeout: 10)
        XCTAssertEqual(try outbox.pending(userID: fixture.uid).map(\.id), [write.id])
        fixture.repository.removeListener(handle)
        removedInitialListener = true
        let restarted = FirestoreWorkoutRepository(db: fixture.client.db,
            outboxURL: fixture.client.directory.appendingPathComponent("outbox.json"),
            currentUserID: { fixture.client.auth.currentUser?.uid }, monitorNetwork: false)
        let cached = expectation(description: "Restarted offline listener keeps last-good authored block")
        var didPublishCached = false
        let restartedHandle = restarted.addProgramLibraryListener(userID: fixture.uid) { result in
            guard case .success(let snapshot) = result,
                  let program = snapshot.values.first(where: { $0.id == "active-phul" }),
                  program.currentProgressIndex == 41, !didPublishCached else { return }
            didPublishCached = true
            XCTAssertTrue(snapshot.isFromCache)
            XCTAssertEqual(program.trainingBlock?.revisionID, block.revisionID)
            XCTAssertEqual(program.routine(forSlot: 40)?.exercises[0].sets[0].target, "5–8 reps")
            cached.fulfill()
        }
        await fulfillment(of: [cached], timeout: 10)
        XCTAssertEqual(try outbox.pending(userID: fixture.uid).map(\.id), [write.id])
        restarted.removeListener(restartedHandle)
        try await fixture.client.db.enableNetwork()
        for _ in 0..<100 {
            if restarted.workoutSyncState(userID: fixture.uid) == .synced { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(restarted.workoutSyncState(userID: fixture.uid), .synced)
    }
}
