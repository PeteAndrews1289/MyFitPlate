import XCTest
@testable import MyFitPlateCore

final class WorkoutLegacyMigrationTests: XCTestCase {
    private func legacy(progress: Int = 39) -> WorkoutProgram {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: "migration-user", name: "PHUL day \(index + 1)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [ExerciseSet(id: "set-\(index)", target: "8–12 reps")])])
        }
        var value = WorkoutProgram(id: "phul", userID: "migration-user", name: "PHUL", dateCreated: date,
            routines: routines, startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: progress, skippedIndices: [2, 5])
        value.progressEpoch = "existing-epoch"
        return value
    }
    private func adopted(_ source: WorkoutProgram) throws -> (WorkoutProgram, WorkoutLegacyMigrationRecord) {
        let block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        return (try WorkoutBlockRules.applying(block, to: source, expected: source),
            try WorkoutLegacyMigrationRecord(original: source, block: block))
    }

    func testOriginalSnapshotFreezesPHULIdentitiesAndRoundTripsIndependentlyOfEditor() throws {
        let source = legacy(), (accepted, record) = try adopted(legacy())
        let decoded = try JSONDecoder().decode(WorkoutLegacyMigrationRecord.self, from: JSONEncoder().encode(record))
        source.routines[0].name = "Another mutable reference"
        let original = try decoded.original()
        XCTAssertEqual(original.currentProgressIndex, 39); XCTAssertEqual(original.skippedIndices, [2, 5])
        XCTAssertEqual(original.progressEpoch, "existing-epoch"); XCTAssertNil(original.trainingBlock)
        XCTAssertEqual(original.routines[0].name, "PHUL day 1")
        for slot in 0..<48 {
            XCTAssertEqual(original.routine(forSlot: slot)?.id, accepted.routine(forSlot: slot)?.id)
            XCTAssertEqual(original.date(forSlot: slot), accepted.date(forSlot: slot))
        }
        XCTAssertEqual(try decoded.fingerprint, try record.fingerprint)
    }

    func testNewAdoptionReceiptCarriesOriginalButLegacyReceiptRemainsDecodable() throws {
        let source = legacy(), block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let receipt = try WorkoutBlockOperationReceipt(expected: source, block: block, status: .accepted)
        XCTAssertNotNil(receipt.legacyMigration)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        old.removeValue(forKey: "legacyMigration")
        let decoded = try JSONDecoder().decode(WorkoutBlockOperationReceipt.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.legacyMigration); XCTAssertNoThrow(try decoded.validate(expected: source, block: block))
        XCTAssertNil(try WorkoutBlockOperationReceipt(expected: source, block: block, status: .cancelled).legacyMigration)
        var authored = source; authored.trainingBlock = block
        XCTAssertNil(try WorkoutBlockOperationReceipt(expected: authored, block: block, status: .accepted).legacyMigration)
    }

    func testRollbackKeepsNewCompatibleProgressSkipsAndOriginalTargets() throws {
        var (current, record) = try adopted(legacy())
        current.currentProgressIndex = 40; current.skippedIndices = [2, 5, 39]; current.progressEpoch = "later-epoch"
        let command = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        let restored = try WorkoutMigrationRollbackRules.applying(command, to: current, record: record)
        XCTAssertNil(restored.trainingBlock); XCTAssertEqual(restored.currentProgressIndex, 40)
        XCTAssertEqual(restored.skippedIndices, [2, 5, 39]); XCTAssertEqual(restored.progressEpoch, "later-epoch")
        XCTAssertEqual(restored.id, current.id); XCTAssertEqual(restored.startDate, current.startDate)
        XCTAssertEqual(restored.routines[0].exercises[0].sets[0].id, "set-0")
    }

    func testLateProgressAndActiveWorkoutCannotBeOverwritten() throws {
        let (current, record) = try adopted(legacy())
        let command = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        var later = current; later.currentProgressIndex = 40; later.progressEpoch = "new"
        XCTAssertThrowsError(try WorkoutMigrationRollbackRules.applying(command, to: later, record: record)) { XCTAssertEqual($0 as? WorkoutMigrationError, .progressChanged) }
        XCTAssertThrowsError(try WorkoutMigrationRollbackRules.applying(command, to: current, record: record, protectedSlots: [39])) { XCTAssertEqual($0 as? WorkoutMigrationError, .activeWorkout) }
    }

    func testLaterAuthoredTargetsAndScheduleRejectRollbackWithoutChangingOriginal() throws {
        let (current, record) = try adopted(legacy())
        var later = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(current))
        later.trainingBlock?.revisionID = "later-edit"
        XCTAssertThrowsError(try WorkoutMigrationRollbackCommand(migration: record, expected: later))
        let copy = try WorkoutMigrationRollbackRules.independentCopy(of: record)
        XCTAssertEqual(copy.routines[0].exercises[0].sets[0].target, "8–12 reps")
        XCTAssertEqual(try record.original().currentProgressIndex, 39)
    }

    func testPerformedAuthoredVariationPreventsReturnToDifferentLegacyTargets() throws {
        let source = legacy(progress: 1)
        var block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let future = try XCTUnwrap(source.routine(forSlot: 2)?.deepCopy())
        future.exercises[0].sets[0].target = "5 reps"
        block.overrides = [WorkoutBlockSlotOverride(slotIndex: 2, routine: future)]
        var current = try WorkoutBlockRules.applying(block, to: source, expected: source)
        let record = try WorkoutLegacyMigrationRecord(original: source, block: block)
        current.currentProgressIndex = 3
        let command = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        XCTAssertThrowsError(try WorkoutMigrationRollbackRules.applying(command, to: current, record: record)) { XCTAssertEqual($0 as? WorkoutMigrationError, .progressChanged) }
    }

    func testIndependentCopyClearsPerformedValuesAndStartsSeparately() throws {
        let source = legacy(); source.routines[0].exercises[0].sets[0].isCompleted = true
        source.routines[0].exercises[0].sets[0].weight = 225
        let (_, record) = try adopted(source), now = Date(timeIntervalSince1970: 1_800_000_000)
        let copy = try WorkoutMigrationRollbackRules.independentCopy(of: record, now: now)
        XCTAssertNotEqual(copy.id, source.id); XCTAssertEqual(copy.currentProgressIndex, 0); XCTAssertNil(copy.skippedIndices)
        XCTAssertEqual(copy.startDate, now); XCTAssertNil(copy.trainingBlock)
        XCTAssertFalse(copy.routines[0].exercises[0].sets[0].isCompleted)
        XCTAssertEqual(copy.routines[0].exercises[0].sets[0].weight, 0)
        XCTAssertEqual(source.currentProgressIndex, 39); XCTAssertEqual(source.routines[0].exercises[0].sets[0].weight, 225)
    }

    func testDurableRequestRelaunchAccountIsolationAndExactCleanupCAS() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory), drafts = WorkoutMigrationRollbackDraftStore(store: store)
        let (current, record) = try adopted(legacy()), first = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        try drafts.freeze(first)
        let relaunched = WorkoutMigrationRollbackDraftStore(store: EditorDraftStore(directory: directory))
        XCTAssertEqual(try relaunched.load(userID: current.userID, programID: "phul"), first)
        XCTAssertNil(try relaunched.load(userID: "another-account", programID: "phul"))
        let newer = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        XCTAssertThrowsError(try relaunched.freeze(newer))
        try store.save(newer, userID: current.userID, scope: WorkoutMigrationRollbackDraftStore.scope(programID: "phul"))
        XCTAssertFalse(try drafts.removeIfUnchanged(first)); XCTAssertEqual(try drafts.load(userID: current.userID, programID: "phul"), newer)
        XCTAssertTrue(try drafts.removeIfUnchanged(newer))
    }

    func testAcceptedResponseLossResolvesAfterRelaunchAndDoesNotReapplyOverLaterChanges() async throws {
        let repository = MockWorkoutRepository(), source = legacy()
        let block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let saved = try await repository.commitProgramBlock(userID: source.userID, expected: source, block: block, protectedSlots: [])
        let current = try XCTUnwrap(saved)
        let records = try await repository.fetchLegacyMigrations(userID: source.userID, programID: "phul")
        let record = try XCTUnwrap(records.first), command = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        repository.migrationRollbackFailureAfterCommit = URLError(.networkConnectionLost)
        do { _ = try await repository.commitMigrationRollback(userID: source.userID, command: command, protectedSlots: []); XCTFail("Expected response loss") } catch {}
        var later = try XCTUnwrap(repository.committedBlockPrograms.first); later.currentProgressIndex = 41
        repository.committedBlockPrograms = [later]
        switch try await repository.resolveMigrationRollback(userID: source.userID, command: command, cancelPending: true) {
        case .accepted(let saved): XCTAssertEqual(saved?.currentProgressIndex, 41); XCTAssertNil(saved?.trainingBlock)
        default: XCTFail("An accepted request must resolve as accepted even when cancellation races")
        }
        let repeated = try await repository.commitMigrationRollback(userID: source.userID, command: command, protectedSlots: [])
        XCTAssertEqual(repeated?.currentProgressIndex, 41)
        repository.deletedProgramIDs.append("phul")
        let deleted = try await repository.commitMigrationRollback(userID: source.userID, command: command, protectedSlots: [])
        XCTAssertNil(deleted, "Receipt replay must not recreate a deliberately deleted program")
    }

    func testCancelledFenceAndDifferentInverseCannotRestoreAgain() async throws {
        let repository = MockWorkoutRepository(), source = legacy()
        let block = try WorkoutBlockRules.createRepeatingBlock(for: source)
        let saved = try await repository.commitProgramBlock(userID: source.userID, expected: source, block: block, protectedSlots: [])
        let current = try XCTUnwrap(saved)
        let records = try await repository.fetchLegacyMigrations(userID: source.userID, programID: "phul")
        let record = try XCTUnwrap(records.first), cancelled = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        _ = try await repository.resolveMigrationRollback(userID: source.userID, command: cancelled, cancelPending: true)
        do { _ = try await repository.commitMigrationRollback(userID: source.userID, command: cancelled, protectedSlots: []); XCTFail("Cancelled request applied") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .cancelled) }
        let first = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        _ = try await repository.commitMigrationRollback(userID: source.userID, command: first, protectedSlots: [])
        repository.committedBlockPrograms = [current]
        let second = try WorkoutMigrationRollbackCommand(migration: record, expected: current)
        do { _ = try await repository.commitMigrationRollback(userID: source.userID, command: second, protectedSlots: []); XCTFail("Original receipt was restored twice") } catch { XCTAssertEqual(error as? WorkoutMigrationError, .alreadyRestored) }
    }
}
