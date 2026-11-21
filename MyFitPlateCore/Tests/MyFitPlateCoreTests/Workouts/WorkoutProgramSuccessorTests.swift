import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutProgramSuccessorTests: XCTestCase {
    private let userID = "successor-user"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func source(progress: Int = 39, authored: Bool = true) throws -> WorkoutProgram {
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: userID, name: "Day \(index + 1)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [
                    ExerciseSet(id: "set-\(index)", isCompleted: true, target: "8 reps", reps: 8, weight: 100)
                ])])
        }
        var program = WorkoutProgram(id: "owner-phul", userID: userID, name: "PHUL", dateCreated: date,
            routines: routines, startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: progress,
            skippedIndices: [2, 9, 20])
        if authored { program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program) }
        return program
    }

    private func command(from source: WorkoutProgram? = nil) throws -> WorkoutProgramSuccessorCommand {
        let original = try source ?? self.source()
        let next = try WorkoutProgramSuccessorRules.prepare(from: original, startDate: date.addingTimeInterval(100 * 86_400), now: date.addingTimeInterval(99 * 86_400))
        return try WorkoutProgramSuccessorCommand(source: original, destination: next)
    }

    private func expectFailure(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected rejection", file: file, line: line) } catch {}
    }

    func testFreshProgramBlockAndWeekIdentitiesPreservePHUL39Of48AndAllOriginalData() throws {
        let original = try source(); let before = try WorkoutBlockRules.fingerprint(original)
        let next = try WorkoutProgramSuccessorRules.prepare(from: original, now: date.addingTimeInterval(100))
        XCTAssertNotEqual(next.id, original.id)
        XCTAssertNotEqual(next.trainingBlock?.id, original.trainingBlock?.id)
        XCTAssertNotEqual(next.trainingBlock?.revisionID, original.trainingBlock?.revisionID)
        XCTAssertTrue(Set(next.trainingBlock?.weeks.map(\.id) ?? []).isDisjoint(with: Set(original.trainingBlock?.weeks.map(\.id) ?? [])))
        XCTAssertEqual(next.currentProgressIndex, 0)
        XCTAssertTrue((next.skippedIndices ?? []).isEmpty)
        XCTAssertNil(next.weekRescue)
        XCTAssertEqual(next.lineage?.sourceProgramID, original.id)
        XCTAssertEqual(next.lineage?.sourceProgressIndex, 39)
        XCTAssertEqual(next.lineage?.sourceFingerprint, before)
        XCTAssertEqual(next.routines.map(\.id), original.routines.map(\.id), "Compatible equipment/exercise references remain reusable")
        XCTAssertFalse(try XCTUnwrap(next.routines.first?.exercises.first?.sets.first?.isCompleted))
        XCTAssertEqual(next.routines.first?.exercises.first?.sets.first?.weight, 0)
        next.routines[0].exercises[0].sets[0].target = "Changed future target"
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(original), before)
        XCTAssertEqual(original.currentProgressIndex, 39)
        XCTAssertEqual(original.totalSlots, 48)
    }

    func testLegacyProgramGetsSeparateAuthoredSuccessorWithoutMigratingItsOriginalRotation() throws {
        let original = try source(authored: false)
        let next = try WorkoutProgramSuccessorRules.prepare(from: original)
        XCTAssertNil(original.trainingBlock)
        XCTAssertEqual(original.currentProgressIndex, 39)
        XCTAssertEqual(next.trainingBlock?.weeks.count, 12)
        XCTAssertNil(next.lineage?.sourceBlockID)
        XCTAssertEqual(next.currentProgressIndex, 0)
    }

    func testFrozenCommandRoundTripCannotBeMutatedThroughSourceOrDestinationReferences() throws {
        let original = try source(); let next = try WorkoutProgramSuccessorRules.prepare(from: original)
        let command = try WorkoutProgramSuccessorCommand(source: original, destination: next)
        let expected = try command.fingerprint
        original.routines[0].name = "Later source edit"
        next.routines[0].name = "Later local proposal edit"
        XCTAssertEqual(try command.fingerprint, expected)
        XCTAssertEqual(try command.source().routines[0].name, "Day 1")
        XCTAssertEqual(try command.destination().routines[0].name, "Day 1")
        let restored = try JSONDecoder().decode(WorkoutProgramSuccessorCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(restored, command)
        try WorkoutProgramSuccessorRules.validate(restored)
    }

    func testAdjustedBlockRetainsReviewedPercentageTargetsAndDoesNotBorrowOldCompletions() throws {
        let original = try source()
        var next = try WorkoutProgramSuccessorRules.prepare(from: original, mode: .adjusted, weekCount: 4)
        let routine = try XCTUnwrap(next.routine(forSlot: 8)?.deepCopy())
        let target = WorkoutPrescription(kind: .repetitions, lowerBound: 5, upperBound: 8,
            effort: SetEffort(scale: .rpe, value: 8), loadPercentage: 75,
            loadReference: .init(label: "Training max", weightPounds: 200, date: date))
        routine.exercises[0].sets[0].prescription = target
        next.trainingBlock?.overrides = [WorkoutBlockSlotOverride(slotIndex: 8, routine: routine)]
        let command = try WorkoutProgramSuccessorCommand(source: original, destination: next)
        let saved = try command.destination()
        XCTAssertEqual(saved.totalSlots, 16)
        XCTAssertEqual(saved.routine(forSlot: 8)?.exercises[0].sets[0].prescription, target)
        let oldRoutine = try XCTUnwrap(original.routine(forSlot: 0))
        let oldLog = WorkoutSessionLog(id: "old-completion", date: date.addingTimeInterval(100), routineID: oldRoutine.id,
            completedExercises: [], programContext: WorkoutRules.sessionContext(for: original, routineID: oldRoutine.id, slotIndex: 0))
        XCTAssertFalse(WorkoutRules.logBelongsToProgram(oldLog, program: saved))
        XCTAssertEqual(WorkoutRules.reconcileProgressFromSessionLogs(in: saved, sessionLogs: [oldLog]).currentProgressIndex, 0)
    }

    func testAtomicCreatePreservesSourceAndAcceptanceReplayReturnsCurrentNewerDestination() async throws {
        let repository = MockWorkoutRepository(); let original = try source(); repository.committedBlockPrograms = [original]
        let before = try WorkoutBlockRules.fingerprint(original); let command = try command(from: original)
        _ = try await repository.createProgramSuccessor(userID: userID, command: command)
        let index = try XCTUnwrap(repository.committedBlockPrograms.firstIndex { $0.id == command.destinationProgramID })
        repository.committedBlockPrograms[index].name = "Edited later"
        let retried = try await repository.createProgramSuccessor(userID: userID, command: command)
        XCTAssertEqual(retried?.name, "Edited later")
        XCTAssertEqual(repository.createdSuccessorIDs, [command.destinationProgramID])
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(repository.committedBlockPrograms.first { $0.id == original.id })), before)
        repository.deletedProgramIDs.append(command.destinationProgramID)
        let afterDeletion = try await repository.createProgramSuccessor(userID: userID, command: command)
        XCTAssertNil(afterDeletion)
        XCTAssertEqual(repository.createdSuccessorIDs.count, 1)
    }

    func testLostAcknowledgementThenSourceChangesStillResolvesWithoutRecreatingAnything() async throws {
        let repository = MockWorkoutRepository(); let original = try source(); repository.committedBlockPrograms = [original]
        let command = try command(from: original)
        repository.successorFailureAfterCommit = APIError.apiError("Lost acknowledgement")
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: command) }
        repository.committedBlockPrograms[0].currentProgressIndex = 40
        let status = try await repository.resolveProgramSuccessor(userID: userID, command: command, cancelPending: false)
        guard case .accepted(let current) = status else { return XCTFail("Receipt must survive a later source edit") }
        XCTAssertEqual(current?.id, command.destinationProgramID)
        _ = try await repository.createProgramSuccessor(userID: userID, command: command)
        XCTAssertEqual(repository.createdSuccessorIDs.count, 1)
        XCTAssertEqual(repository.committedBlockPrograms[0].currentProgressIndex, 40)
    }

    func testSourceProgressScheduleOrStructureChangeAndDestinationCollisionRejectCreation() async throws {
        for mutation in 0..<3 {
            let repository = MockWorkoutRepository(); let original = try source(); let command = try command(from: original)
            var latest = try command.source()
            if mutation == 0 { latest.currentProgressIndex = 40 }
            if mutation == 1 { latest.startDate = date.addingTimeInterval(86_400) }
            if mutation == 2 { latest.name = "Changed source" }
            repository.committedBlockPrograms = [latest]
            await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: command) }
            XCTAssertTrue(repository.createdSuccessorIDs.isEmpty)
            XCTAssertTrue(repository.successorReceipts.isEmpty)
        }
        let repository = MockWorkoutRepository(); let command = try command()
        repository.committedBlockPrograms = [try command.source(), try command.destination()]
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: command) }
        XCTAssertTrue(repository.successorReceipts.isEmpty)
    }

    func testStatusAbsenceAndPermanentCancellationFence() async throws {
        let repository = MockWorkoutRepository(); let command = try command()
        guard case .pending = try await repository.resolveProgramSuccessor(userID: userID, command: command, cancelPending: false) else {
            return XCTFail("No receipt is pending")
        }
        guard case .cancelled = try await repository.resolveProgramSuccessor(userID: userID, command: command, cancelPending: true) else {
            return XCTFail("Cancellation must be fenced")
        }
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: command) }
        XCTAssertTrue(repository.createdSuccessorIDs.isEmpty)
    }

    func testSameOperationWithDifferentFrozenPayloadCannotReplayOrCancelAcceptance() async throws {
        let repository = MockWorkoutRepository(); let command = try command()
        _ = try await repository.createProgramSuccessor(userID: userID, command: command)
        var altered = try command.destination(); altered.name = "Altered payload"
        let collision = try WorkoutProgramSuccessorCommand(source: command.source(), destination: altered, operationID: command.operationID)
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: collision) }
        await expectFailure { _ = try await repository.resolveProgramSuccessor(userID: self.userID, command: collision, cancelPending: true) }
        XCTAssertEqual(repository.createdSuccessorIDs.count, 1)
    }

    func testWrongAccountAndDeletedSourceCannotCreateOrCancelForAnotherOwner() async throws {
        let repository = MockWorkoutRepository(); let command = try command()
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: "other", command: command) }
        await expectFailure { _ = try await repository.resolveProgramSuccessor(userID: "other", command: command, cancelPending: true) }
        repository.deletedProgramIDs = [command.sourceProgramID]
        await expectFailure { _ = try await repository.createProgramSuccessor(userID: self.userID, command: command) }
        XCTAssertTrue(repository.successorReceipts.isEmpty)
    }

    func testDurableSessionRestoresExactSubmittedCommandAndRejectsEditedRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("successor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EditorDraftStore(directory: folder)
        let repository = MockWorkoutRepository(); let auth = MockAuthService(); auth.currentUserID = userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repository
        let service = WorkoutService(defaults: UserDefaults(suiteName: "successor-test-\(UUID())")!)
        let original = try source(); service.userPrograms = [original]; service.activeProgram = original
        let session = try WorkoutSuccessorSaveSession(source: original, store: store)
        try session.update { $0.name = "Next PHUL" }
        repository.successorCommitError = APIError.apiError("Offline")
        let initial = await session.submit(using: service)
        XCTAssertFalse(initial); XCTAssertTrue(session.isSubmitted)
        let frozen = try XCTUnwrap(session.draft.command)
        XCTAssertThrowsError(try session.update { $0.name = "Unsafe retry change" })
        let restored = try WorkoutSuccessorSaveSession(source: original, store: store)
        XCTAssertEqual(restored.draft.command, frozen)
        repository.successorCommitError = nil
        let accepted = await restored.submit(using: service)
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.activeProgram?.id, original.id, "Creation never activates")
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 39)
        XCTAssertTrue(restored.finish())
        XCTAssertNil(try store.load(WorkoutSuccessorDraft.self, userID: userID, scope: WorkoutSuccessorSaveSession.scope(sourceProgramID: original.id!)))
    }

    func testActivationRequiresReceiptAndNoRecoverableWorkoutAndPreservesThatDraft() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("successor-active-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let draftStore = WorkoutDraftStore(directory: folder)
        let repository = MockWorkoutRepository(); let auth = MockAuthService(); auth.currentUserID = userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repository
        let service = WorkoutService(defaults: UserDefaults(suiteName: "successor-activation-\(UUID())")!)
        let original = try source(); service.activeProgram = original
        let command = try command(from: original)
        await expectFailure { _ = try await service.activateProgramSuccessor(command, draftStore: draftStore) }
        _ = try await service.createProgramSuccessor(command)
        let routine = try XCTUnwrap(original.routine(forSlot: 39))
        let draft = WorkoutSessionDraft(routine: routine, now: date, programContext: WorkoutRules.sessionContext(for: original, routineID: routine.id, slotIndex: 39))
        try draftStore.save(draft, userID: userID)
        let before = try WorkoutBlockRules.fingerprint(XCTUnwrap(draftStore.load(userID: userID)))
        await expectFailure { _ = try await service.activateProgramSuccessor(command, draftStore: draftStore) }
        XCTAssertEqual(service.activeProgram?.id, original.id)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(XCTUnwrap(draftStore.load(userID: userID))), before)
        try draftStore.remove(userID: userID)
        let active = try await service.activateProgramSuccessor(command, draftStore: draftStore)
        XCTAssertEqual(active.id, command.destinationProgramID)
        XCTAssertEqual(active.currentProgressIndex, 0)
        XCTAssertEqual(service.activeProgram?.id, command.destinationProgramID)
    }

    func testTwoEditorsCannotOverwriteNewerDurableProposal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("successor-two-editors-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EditorDraftStore(directory: folder)
        let original = try source()
        let first = try WorkoutSuccessorSaveSession(source: original, store: store, currentUserID: { self.userID })
        let second = try WorkoutSuccessorSaveSession(source: original, store: store, currentUserID: { self.userID })
        try first.update { $0.name = "Newer draft" }
        XCTAssertThrowsError(try second.update { $0.name = "Stale draft" })
        XCTAssertFalse(second.finish())
        let restored = try WorkoutSuccessorSaveSession(source: original, store: store, currentUserID: { self.userID })
        XCTAssertEqual(try restored.draft.destination().name, "Newer draft")
    }
}
