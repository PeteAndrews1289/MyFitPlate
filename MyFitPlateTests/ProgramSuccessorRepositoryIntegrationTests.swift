import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class SuccessorEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class SuccessorEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("program-successor-test-") ? SuccessorEmulatorCheck() : nil
    }
}

/// Opt-in localhost emulator corpus. Named Firebase apps and anonymous synthetic
/// users keep all writes separate from production and owner simulator records.
@MainActor
final class ProgramSuccessorIntegrationTests: XCTestCase {
    private struct Fixture {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
        let userID: String
        let source: WorkoutProgram
        let sourceRef: DocumentReference
        let historyRef: DocumentReference
        let repository: FirestoreWorkoutRepository
        let outbox: WorkoutOutbox
    }
    private var fixtures: [Fixture] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(SuccessorEmulatorCheckFactory())
    }
    override func tearDown() {
        for fixture in fixtures {
            try? fixture.auth.signOut(); fixture.app.delete { _ in }
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        fixtures = []
        super.tearDown()
    }

    private func fixture() async throws -> Fixture {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "program-successor-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app); auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        let uid = try await auth.signInAnonymously().user.uid
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let outboxURL = directory.appendingPathComponent("outbox.json")
        let repository = FirestoreWorkoutRepository(db: db, outboxURL: outboxURL, currentUserID: { auth.currentUser?.uid }, monitorNetwork: false)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: uid, name: "PHUL day \(index + 1)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [ExerciseSet(id: "set-\(index)", target: "8-12 reps")])])
        }
        var source = WorkoutProgram(id: "existing-phul", userID: uid, name: "PHUL", dateCreated: date,
            routines: routines, startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39, skippedIndices: [2, 9, 20])
        source.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let user = db.collection("users").document(uid)
        let sourceRef = user.collection("workoutPrograms").document("existing-phul")
        var payload = try Firestore.Encoder().encode(source)
        payload["unrelatedOwnerField"] = ["keep": true, "originalTimestamp": Timestamp(seconds: 1_700_000_000, nanoseconds: 123_456_789)]
        try await sourceRef.setData(payload)
        let history = user.collection("workoutSessionLogs").document("existing-history")
        try await history.setData(["originalTimestamp": Timestamp(seconds: 1_700_000_000, nanoseconds: 987_654_321),
                                   "originalWeight": 127.345, "originalTarget": "8-12 reps"])
        var canonical = try await sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        canonical.id = sourceRef.documentID
        let fixture = Fixture(app: app, auth: auth, db: db, directory: directory, userID: uid, source: canonical,
            sourceRef: sourceRef, historyRef: history, repository: repository, outbox: WorkoutOutbox(fileURL: outboxURL))
        fixtures.append(fixture)
        return fixture
    }

    private func command(_ fixture: Fixture) throws -> WorkoutProgramSuccessorCommand {
        let destination = try WorkoutProgramSuccessorRules.prepare(from: fixture.source)
        return try WorkoutProgramSuccessorCommand(source: fixture.source, destination: destination)
    }
    private func destinationRef(_ fixture: Fixture, _ command: WorkoutProgramSuccessorCommand) -> DocumentReference {
        fixture.db.collection("users").document(fixture.userID).collection("workoutPrograms").document(command.destinationProgramID)
    }
    private func expectFailure(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected rejection", file: file, line: line) } catch {}
    }

    func testAtomicSuccessorCreatesNewIdentitiesAndPreservesEverySourceAndHistoryField() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        let beforeSnapshot = try await fixture.sourceRef.getDocument(source: .server)
        let before = try XCTUnwrap(beforeSnapshot.data())
        let historyBeforeSnapshot = try await fixture.historyRef.getDocument(source: .server)
        let historyBefore = try XCTUnwrap(historyBeforeSnapshot.data())
        let result = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        let created = try XCTUnwrap(result)
        XCTAssertEqual(created.currentProgressIndex, 0)
        XCTAssertNotEqual(created.id, fixture.source.id)
        XCTAssertNotEqual(created.trainingBlock?.id, fixture.source.trainingBlock?.id)
        XCTAssertTrue(Set(created.trainingBlock?.weeks.map(\.id) ?? []).isDisjoint(with: Set(fixture.source.trainingBlock?.weeks.map(\.id) ?? [])))
        XCTAssertEqual(created.lineage?.sourceProgramID, fixture.source.id)
        XCTAssertEqual(created.lineage?.sourceProgressIndex, 39)
        let afterSnapshot = try await fixture.sourceRef.getDocument(source: .server)
        let after = try XCTUnwrap(afterSnapshot.data())
        let historyAfterSnapshot = try await fixture.historyRef.getDocument(source: .server)
        let historyAfter = try XCTUnwrap(historyAfterSnapshot.data())
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: after))
        XCTAssertTrue(NSDictionary(dictionary: historyBefore).isEqual(to: historyAfter))
        let receiptRef = fixture.db.collection("users").document(fixture.userID).collection("programSuccessorOperations").document(command.operationID.uuidString)
        let receipt = try await receiptRef.getDocument(source: .server).data(as: WorkoutProgramSuccessorReceipt.self)
        try receipt.validate(command)
        XCTAssertEqual(receipt.status, .accepted)
    }

    func testAcceptedRetryIsReadOnlyAfterLaterSourceDestinationEditsAndDeletion() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        let destination = destinationRef(fixture, command)
        try await destination.setData(["name": "Later reviewed block", "currentProgressIndex": 2], merge: true)
        try await fixture.sourceRef.setData(["currentProgressIndex": 40], merge: true)
        let retry = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        XCTAssertEqual(retry?.name, "Later reviewed block")
        XCTAssertEqual(retry?.currentProgressIndex, 2)
        let status = try await fixture.repository.resolveProgramSuccessor(userID: fixture.userID, command: command, cancelPending: true)
        guard case .accepted(let current) = status else { return XCTFail("Cancellation cannot undo accepted creation") }
        XCTAssertEqual(current?.name, "Later reviewed block")
        try await destination.delete()
        let deletedRetry = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        XCTAssertNil(deletedRetry)
        let absent = try await destination.getDocument(source: .server)
        XCTAssertFalse(absent.exists)
    }

    func testPermanentCancellationFenceRejectsLateCreateWithoutChangingSource() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        guard case .pending = try await fixture.repository.resolveProgramSuccessor(userID: fixture.userID, command: command, cancelPending: false) else {
            return XCTFail("Absent receipt must be pending")
        }
        guard case .cancelled = try await fixture.repository.resolveProgramSuccessor(userID: fixture.userID, command: command, cancelPending: true) else {
            return XCTFail("Cancellation fence expected")
        }
        await expectFailure { _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command) }
        let absent = try await destinationRef(fixture, command).getDocument(source: .server)
        XCTAssertFalse(absent.exists)
        let source = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(source.currentProgressIndex, 39)
    }

    func testSourceCASAndDestinationCollisionFailWithoutReceiptOrOverwrite() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        try await fixture.sourceRef.setData(["currentProgressIndex": 40], merge: true)
        await expectFailure { _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command) }
        let absent = try await destinationRef(fixture, command).getDocument(source: .server)
        XCTAssertFalse(absent.exists)
        let receiptRef = fixture.db.collection("users").document(fixture.userID).collection("programSuccessorOperations").document(command.operationID.uuidString)
        let noReceipt = try await receiptRef.getDocument(source: .server)
        XCTAssertFalse(noReceipt.exists)
        try await fixture.sourceRef.setData(["currentProgressIndex": 39], merge: true)
        try await destinationRef(fixture, command).setData(["ownerValue": "retain"])
        await expectFailure { _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command) }
        let existing = try await destinationRef(fixture, command).getDocument(source: .server).data()
        XCTAssertEqual(existing?["ownerValue"] as? String, "retain")
    }

    func testAlteredPayloadAndWrongAccountCannotReuseAcceptedOperation() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        var changed = try command.destination(); changed.name = "Same operation different reviewed name"
        let reused = try WorkoutProgramSuccessorCommand(source: command.source(), destination: changed, operationID: command.operationID)
        await expectFailure { _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: reused) }
        await expectFailure { _ = try await fixture.repository.resolveProgramSuccessor(userID: fixture.userID, command: reused, cancelPending: true) }
        await expectFailure { _ = try await fixture.repository.resolveProgramSuccessor(userID: "other-account", command: command, cancelPending: true) }
        let current = try await destinationRef(fixture, command).getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.name, fixture.source.name)
    }

    func testPendingLocalSourceWritesBlockNewCreationButDoNotBlockAcceptedReceiptReplay() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        let pending = try WorkoutPendingWrite(userID: fixture.userID, collection: .programs,
            documentID: fixture.source.id!, value: fixture.source)
        try fixture.outbox.append(pending)
        await expectFailure { _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command) }
        try fixture.outbox.acknowledge(pending)
        _ = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        try fixture.outbox.append(pending)
        let replayed = try await fixture.repository.createProgramSuccessor(userID: fixture.userID, command: command)
        XCTAssertEqual(replayed?.id, command.destinationProgramID)
        XCTAssertEqual(try fixture.outbox.pending(userID: fixture.userID).map(\.id), [pending.id])
    }

    func testActivationRefusesRecoverableWorkoutAndPreservesItUntilExplicitCompletion() async throws {
        let fixture = try await fixture(); let command = try command(fixture)
        let auth = MockAuthService(); auth.currentUserID = fixture.userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = fixture.repository
        let suite = "successor-activation-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let service = WorkoutService(defaults: defaults)
        service.userPrograms = [fixture.source]; service.activeProgram = fixture.source
        _ = try await service.createProgramSuccessor(command)
        XCTAssertEqual(service.activeProgram?.id, fixture.source.id)
        let draftStore = WorkoutDraftStore(directory: fixture.directory.appendingPathComponent("active-draft"))
        let routine = try XCTUnwrap(fixture.source.routine(forSlot: 39))
        let draft = WorkoutSessionDraft(routine: routine, programContext: WorkoutRules.sessionContext(for: fixture.source, routineID: routine.id, slotIndex: 39))
        try draftStore.save(draft, userID: fixture.userID)
        let before = try WorkoutBlockRules.fingerprint(draft)
        await expectFailure { _ = try await service.activateProgramSuccessor(command, draftStore: draftStore) }
        let retained = try XCTUnwrap(draftStore.load(userID: fixture.userID))
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(retained), before)
        XCTAssertEqual(service.activeProgram?.id, fixture.source.id)
        try draftStore.remove(userID: fixture.userID)
        let active = try await service.activateProgramSuccessor(command, draftStore: draftStore)
        XCTAssertEqual(active.id, command.destinationProgramID)
        XCTAssertEqual(active.currentProgressIndex, 0)
        let source = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(source.currentProgressIndex, 39)
    }
    private func waitForSync(_ fixture: Fixture) async throws {
        for _ in 0..<120 {
            if case .synced = fixture.repository.workoutSyncState(userID: fixture.userID) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Synthetic workout outbox did not synchronize")
        throw WorkoutHistoryReadError.unavailable
    }

    func testExactTimestampCursorTraverses501SessionsIncludingNanosecondTies() async throws {
        let fixture = try await fixture()
        let collection = fixture.db.collection("users").document(fixture.userID).collection("workoutSessionLogs")
        for lower in stride(from: 0, to: 501, by: 450) {
            let batch = fixture.db.batch()
            for index in lower..<min(lower + 450, 501) {
                let id = String(format: "history-%04d", index)
                batch.setData(["id": id, "date": Timestamp(seconds: 1_700_000_000, nanoseconds: Int32(123_456_789 + (index % 3) * 1_000)),
                    "routineID": "routine", "completedExercises": []], forDocument: collection.document(id))
            }
            try await batch.commit()
        }
        let first = try await fixture.repository.fetchWorkoutHistoryPage(userID: fixture.userID, cursor: nil, pageSize: 50)
        let cursor = try XCTUnwrap(first.nextCursor)
        let boundaryDocument = try await collection.document(cursor.lastDocumentID).getDocument(source: .server)
        let storedBoundary = try XCTUnwrap(boundaryDocument.data()?["date"] as? Timestamp)
        XCTAssertEqual(cursor.lastSeconds, storedBoundary.seconds)
        XCTAssertEqual(cursor.lastNanoseconds, storedBoundary.nanoseconds,
            "The cursor retains the server's stored precision rather than round-tripping through Date")
        let all = try await fixture.repository.fetchCompleteWorkoutHistory(userID: fixture.userID, pageSize: 50)
        XCTAssertEqual(all.count, 501)
        XCTAssertEqual(Set(all.compactMap(\.id)).count, 501)
        XCTAssertTrue(all.contains { $0.id == "history-0000" })
        await expectFailure {
            _ = try await fixture.repository.fetchWorkoutHistoryPage(userID: "other-account", cursor: cursor, pageSize: 50)
        }
    }

    func testArchiveOnlyQueuedWritePreservesConcurrentProgressAndOrdinarySaveCannotUndoArchive() async throws {
        let fixture = try await fixture()
        let historyBefore = try await fixture.historyRef.getDocument(source: .server).data()
        try await fixture.sourceRef.setData(["currentProgressIndex": 40, "name": "Latest title"], merge: true)
        var stale = fixture.source; stale.archivedAt = Date()
        _ = try await fixture.repository.saveProgramArchive(userID: fixture.userID, program: stale)
        try await waitForSync(fixture)
        var current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.currentProgressIndex, 40)
        XCTAssertEqual(current.name, "Latest title")
        XCTAssertNotNil(current.archivedAt)
        _ = try await fixture.repository.saveProgram(userID: fixture.userID, program: fixture.source)
        try await waitForSync(fixture)
        current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.currentProgressIndex, 40)
        XCTAssertNotNil(current.archivedAt)
        current.id = fixture.source.id; current.archivedAt = nil
        _ = try await fixture.repository.saveProgramArchive(userID: fixture.userID, program: current)
        try await waitForSync(fixture)
        let restored = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertNil(restored.archivedAt)
        XCTAssertEqual(restored.currentProgressIndex, 40)
        let historyAfter = try await fixture.historyRef.getDocument(source: .server).data()
        XCTAssertTrue(NSDictionary(dictionary: historyBefore ?? [:]).isEqual(to: historyAfter ?? [:]))
    }

    func testDelayedScheduleWriteKeepsNewerCompletionAndEveryPassedDate() async throws {
        let fixture = try await fixture()
        var queued = fixture.source
        queued.startDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.source.startDate!))
        try await fixture.sourceRef.setData(["currentProgressIndex": 40, "skippedIndices": [2, 9, 20, 39]], merge: true)
        _ = try await fixture.repository.saveProgram(userID: fixture.userID, program: queued)
        try await waitForSync(fixture)
        let current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.currentProgressIndex, 40)
        XCTAssertTrue(current.skippedIndices?.contains(39) == true)
        XCTAssertEqual(current.slotDateSnapshots?.count, 40)
        for index in 0..<40 { XCTAssertEqual(current.date(forSlot: index), fixture.source.date(forSlot: index)) }
        XCTAssertNotEqual(current.date(forSlot: 40), fixture.source.date(forSlot: 40))
    }

    func testLegacyUseLastIgnoresFutureAndFindsPastExerciseBeyondTenUnrelatedSessions() async throws {
        let fixture = try await fixture()
        let collection = fixture.db.collection("users").document(fixture.userID).collection("workoutSessionLogs")
        let now = Date(); let exercise = RoutineExercise(id: "squat", name: "Squat")
        let old = WorkoutSessionLog(id: "eligible-past", date: now.addingTimeInterval(-45 * 86_400), routineID: "routine",
            completedExercises: [CompletedExercise(exerciseName: "Squat", exercise: exercise, sets: [CompletedSet(reps: 8, weight: 100)])])
        let future = WorkoutSessionLog(id: "future-mistake", date: now.addingTimeInterval(45 * 86_400), routineID: "routine",
            completedExercises: [CompletedExercise(exerciseName: "Squat", exercise: exercise, sets: [CompletedSet(reps: 8, weight: 9_999)])])
        let batch = fixture.db.batch()
        batch.setData(try Firestore.Encoder().encode(old), forDocument: collection.document(old.id!))
        batch.setData(try Firestore.Encoder().encode(future), forDocument: collection.document(future.id!))
        for index in 0..<20 {
            let unrelated = WorkoutSessionLog(id: "unrelated-\(index)", date: now.addingTimeInterval(-Double(index + 1) * 86_400),
                routineID: "other-routine", completedExercises: [])
            batch.setData(try Firestore.Encoder().encode(unrelated), forDocument: collection.document(unrelated.id!))
        }
        try await batch.commit()
        let previous = try await fixture.repository.fetchPreviousPerformance(userID: fixture.userID, exerciseName: "Squat")
        XCTAssertEqual(previous?.sets.first?.weight, 100)
    }

    func testCheckedProgramEditPreservesPHULProgressAuthoredBlockRawFieldsAndHistory() async throws {
        let fixture = try await fixture()
        let before = try await fixture.sourceRef.getDocument(source: .server).data() ?? [:]
        let historyBefore = try await fixture.historyRef.getDocument(source: .server).data() ?? [:]
        var proposed = fixture.source; proposed.name = "PHUL reviewed name"
        let command = try WorkoutProgramEditCommand(expected: fixture.source, proposed: proposed)
        try await fixture.sourceRef.setData(["currentProgressIndex": 40, "skippedIndices": [2, 9, 20, 39]], merge: true)
        let result = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        XCTAssertEqual(result?.currentProgressIndex, 40)
        XCTAssertEqual(result?.skippedIndices, [2, 9, 20, 39])
        let after = try await fixture.sourceRef.getDocument(source: .server).data() ?? [:]
        XCTAssertEqual(after["name"] as? String, "PHUL reviewed name")
        for key in ["dateCreated", "routines", "trainingBlock", "unrelatedOwnerField"] {
            let original = try XCTUnwrap(before[key]), retained = try XCTUnwrap(after[key])
            XCTAssertTrue(NSDictionary(dictionary: [key: original]).isEqual(to: [key: retained]), key)
        }
        let historyAfter = try await fixture.historyRef.getDocument(source: .server).data() ?? [:]
        XCTAssertTrue(NSDictionary(dictionary: historyBefore).isEqual(to: historyAfter))
    }

    func testProgramEditAcceptedReceiptDoesNotOverwriteLaterEditOrRecreateDeletedPlan() async throws {
        let fixture = try await fixture()
        var proposed = fixture.source; proposed.name = "Reviewed edit"
        let command = try WorkoutProgramEditCommand(expected: fixture.source, proposed: proposed)
        _ = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        try await fixture.sourceRef.setData(["name": "Later owner edit", "currentProgressIndex": 41], merge: true)
        let replay = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        XCTAssertEqual(replay?.name, "Later owner edit"); XCTAssertEqual(replay?.currentProgressIndex, 41)
        try await fixture.sourceRef.delete()
        let missingReplay = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        XCTAssertNil(missingReplay)
        guard case .accepted(let current) = try await fixture.repository.resolveProgramEdit(userID: fixture.userID, command: command, cancelPending: true) else { return XCTFail("Permanent accepted receipt expected") }
        XCTAssertNil(current)
        let document = try await fixture.sourceRef.getDocument(source: .server)
        XCTAssertFalse(document.exists)
    }

    func testProgramEditCancellationFencesLateCommitAndRejectsSameIDChangedPayload() async throws {
        let fixture = try await fixture()
        var proposed = fixture.source; proposed.name = "Not accepted"
        let command = try WorkoutProgramEditCommand(expected: fixture.source, proposed: proposed)
        guard case .pending = try await fixture.repository.resolveProgramEdit(userID: fixture.userID, command: command, cancelPending: false) else { return XCTFail("Pending expected") }
        guard case .cancelled = try await fixture.repository.resolveProgramEdit(userID: fixture.userID, command: command, cancelPending: true) else { return XCTFail("Cancellation fence expected") }
        await expectFailure { _ = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command) }
        var changed = proposed; changed.name = "Different payload"
        let reused = try WorkoutProgramEditCommand(expected: fixture.source, proposed: changed, id: command.id)
        await expectFailure { _ = try await fixture.repository.resolveProgramEdit(userID: fixture.userID, command: reused, cancelPending: false) }
        let saved = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(saved.name, fixture.source.name); XCTAssertEqual(saved.currentProgressIndex, 39)
    }

    func testProgramEditCASRejectsConcurrentMetadataAndKeepsReceiptPending() async throws {
        let fixture = try await fixture()
        var proposed = fixture.source; proposed.name = "Stale owner draft"
        let command = try WorkoutProgramEditCommand(expected: fixture.source, proposed: proposed)
        try await fixture.sourceRef.setData(["name": "Concurrent change"], merge: true)
        await expectFailure { _ = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command) }
        guard case .pending = try await fixture.repository.resolveProgramEdit(userID: fixture.userID, command: command, cancelPending: false) else { return XCTFail("Rejected CAS must not record acceptance") }
        let current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.name, "Concurrent change"); XCTAssertEqual(current.currentProgressIndex, 39)
    }

    func testProgramEditPendingOutboxIsProtectedButAcceptedReceiptReplayIsReadOnly() async throws {
        let fixture = try await fixture()
        var proposed = fixture.source; proposed.name = "Checked edit"
        let command = try WorkoutProgramEditCommand(expected: fixture.source, proposed: proposed)
        let pending = try WorkoutPendingWrite(userID: fixture.userID, collection: .programs,
            documentID: fixture.source.id!, value: fixture.source)
        try fixture.outbox.append(pending)
        await expectFailure { _ = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command) }
        try fixture.outbox.acknowledge(pending)
        _ = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        try fixture.outbox.append(pending)
        let replay = try await fixture.repository.commitProgramEdit(userID: fixture.userID, command: command)
        XCTAssertEqual(replay?.name, "Checked edit")
        XCTAssertEqual(try fixture.outbox.pending(userID: fixture.userID).map(\.id), [pending.id])
    }

    func testCheckedSkipAndUndoPatchOnlyProgressAndPermanentCancellationFencesLateRetry() async throws {
        let fixture = try await fixture()
        let rawBefore = try await fixture.sourceRef.getDocument(source: .server).data()
        let historyBefore = try await fixture.historyRef.getDocument(source: .server).data()
        let skip = try WorkoutProgramProgressCommand(program: fixture.source, kind: .skip, targetIndex: 41)
        _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: skip, locallyVerifiedLogs: [])
        try await waitForSync(fixture)
        var canonical = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        canonical.id = fixture.source.id
        XCTAssertEqual(canonical.currentProgressIndex, 41)
        XCTAssertEqual(canonical.skippedIndices, [2, 9, 20, 39, 40])
        let undo = try WorkoutProgramProgressCommand(program: canonical, kind: .undoSkip)
        _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: undo, locallyVerifiedLogs: [])
        try await waitForSync(fixture)
        let restored = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(restored.currentProgressIndex, 39); XCTAssertEqual(restored.skippedIndices, fixture.source.skippedIndices)
        let rawAfterSnapshot = try await fixture.sourceRef.getDocument(source: .server)
        var rawAfter = try XCTUnwrap(rawAfterSnapshot.data())
        var expected = try XCTUnwrap(rawBefore)
        for key in ["currentProgressIndex", "skippedIndices", "progressEpoch", "slotCompletionProofs", "lastSkipReceipt"] { rawAfter.removeValue(forKey: key); expected.removeValue(forKey: key) }
        XCTAssertEqual(rawAfter as NSDictionary, expected as NSDictionary)
        let historyAfter = try await fixture.historyRef.getDocument(source: .server).data()
        XCTAssertEqual(historyAfter as NSDictionary?, historyBefore as NSDictionary?)
        var nextSource = restored; nextSource.id = fixture.source.id
        let pending = try WorkoutProgramProgressCommand(program: nextSource, kind: .skip, targetIndex: 40)
        guard case .cancelled = try await fixture.repository.resolveProgramProgress(userID: fixture.userID, command: pending, cancelPending: true) else { return XCTFail("Cancellation fence expected") }
        await expectFailure { _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: pending, locallyVerifiedLogs: []) }
        XCTAssertEqual(try fixture.outbox.pending(userID: fixture.userID).count, 0)
    }

    func testDurableCompletionProgressReceiptSurvivesLaterMetadataAndProgramDeletion() async throws {
        let fixture = try await fixture()
        let routine = try XCTUnwrap(fixture.source.routine(forSlot: 39))
        let exercise = try XCTUnwrap(routine.exercises.first)
        let log = WorkoutSessionLog(id: "progress-completion", date: Date().addingTimeInterval(-5), routineID: routine.id,
            completedExercises: [CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: [CompletedSet(reps: 8, weight: 100)])],
            programContext: WorkoutProgramSessionContext(programID: fixture.source.id!, slotIndex: 39), programLinkDecision: .program)
        let collection = fixture.db.collection("users").document(fixture.userID).collection("workoutSessionLogs")
        try await fixture.repository.saveWorkoutSessionLog(userID: fixture.userID, log: log)
        try await waitForSync(fixture)
        var snapshotAfterHistory = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        snapshotAfterHistory.id = fixture.source.id
        XCTAssertEqual(snapshotAfterHistory.progressEpoch, try WorkoutProgramProgressCommand.historySaveEpoch(ownerID: fixture.userID, sessionID: log.id!))
        let command = try WorkoutProgramProgressCommand(program: fixture.source, kind: .completion, sessionID: log.id!)
        let pending = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: command, locallyVerifiedLogs: [log])
        XCTAssertEqual(try command.overlay(proposed: pending, on: snapshotAfterHistory).currentProgressIndex, 40)
        try await waitForSync(fixture)
        var current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.currentProgressIndex, 40)
        try await fixture.sourceRef.setData(["name": "Later edit", "currentProgressIndex": 44, "progressEpoch": "later"], merge: true)
        current = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: command, locallyVerifiedLogs: [log])
        XCTAssertEqual(current.name, "Later edit"); XCTAssertEqual(current.currentProgressIndex, 44)
        try await fixture.sourceRef.delete()
        guard case .accepted(let missing) = try await fixture.repository.resolveProgramProgress(userID: fixture.userID, command: command, cancelPending: false) else { return XCTFail("Permanent acceptance survives source deletion") }
        XCTAssertNil(missing)
        await expectFailure { _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: command, locallyVerifiedLogs: [log]) }
        let deleted = try await fixture.sourceRef.getDocument(source: .server)
        XCTAssertFalse(deleted.exists)
        let retainedLog = try await collection.document(log.id!).getDocument(source: .server)
        XCTAssertTrue(retainedLog.exists)
        XCTAssertEqual(try retainedLog.data(as: WorkoutSessionLog.self).completedExercises.first?.sets.first?.weight, 100)
    }

    func testSavedCompletionNotYetProjectedPreventsStaleSkipUndoOnServer() async throws {
        let fixture = try await fixture()
        let skip = try WorkoutProgramProgressCommand(program: fixture.source, kind: .skip, targetIndex: 40)
        _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: skip, locallyVerifiedLogs: [])
        try await waitForSync(fixture)
        var skipped = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self); skipped.id = fixture.source.id
        let log = WorkoutSessionLog(id: "new-unprojected-session", date: Date().addingTimeInterval(-5), routineID: fixture.source.routine(forSlot: 40)!.id,
            completedExercises: [], programContext: WorkoutProgramSessionContext(programID: fixture.source.id!, slotIndex: 40))
        try await fixture.repository.saveWorkoutSessionLog(userID: fixture.userID, log: log)
        try await waitForSync(fixture)
        let afterSave = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertNotEqual(afterSave.progressEpoch, skip.id)
        let undo = try WorkoutProgramProgressCommand(program: skipped, kind: .undoSkip)
        // A stale local review can be queued, but its server read must fence the saved receipt.
        _ = try await fixture.repository.enqueueProgramProgress(userID: fixture.userID, command: undo, locallyVerifiedLogs: [])
        for _ in 0..<120 {
            if fixture.repository.workoutSyncState(userID: fixture.userID) == .failed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(fixture.repository.workoutSyncState(userID: fixture.userID), .failed)
        let current = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(current.currentProgressIndex, 40); XCTAssertEqual(current.progressEpoch, afterSave.progressEpoch)
        guard case .cancelled = try await fixture.repository.resolveProgramProgress(userID: fixture.userID, command: undo, cancelPending: true) else { return XCTFail("Rejected pending Undo remains safely cancellable") }
        XCTAssertEqual(fixture.repository.workoutSyncState(userID: fixture.userID), .synced)
    }

    func testInitialCatalogBlockIsPersistedAndOrdinaryReplayCannotOverwriteLaterAuthoredWeeks() async throws {
        let fixture = try await fixture()
        var new = try WorkoutProgramSuccessorRules.prepare(from: fixture.source)
        new.id = "fresh-authored-program"; new.currentProgressIndex = 0
        let saved = try await fixture.repository.saveProgram(userID: fixture.userID, program: new)
        try await waitForSync(fixture)
        let reference = fixture.db.collection("users").document(fixture.userID).collection("workoutPrograms").document(saved.id!)
        var canonical = try await reference.getDocument(source: .server).data(as: WorkoutProgram.self); canonical.id = saved.id
        XCTAssertEqual(canonical.trainingBlock?.id, new.trainingBlock?.id)
        XCTAssertEqual(canonical.trainingBlock?.weeks.map(\.id), new.trainingBlock?.weeks.map(\.id))
        var reviewed = try XCTUnwrap(canonical.trainingBlock)
        reviewed.name = "Later checked block"; reviewed.revisionID = UUID().uuidString
        _ = try await fixture.repository.commitProgramBlock(userID: fixture.userID, expected: canonical, block: reviewed, protectedSlots: [])
        _ = try await fixture.repository.saveProgram(userID: fixture.userID, program: new)
        try await waitForSync(fixture)
        let result = try await reference.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(result.trainingBlock?.revisionID, reviewed.revisionID)
        XCTAssertEqual(result.trainingBlock?.name, "Later checked block")
        XCTAssertEqual(result.currentProgressIndex, 0)
        let source = try await fixture.sourceRef.getDocument(source: .server).data(as: WorkoutProgram.self)
        XCTAssertEqual(source.currentProgressIndex, 39)
    }

}
