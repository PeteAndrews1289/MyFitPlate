import XCTest
@testable import MyFitPlateCore

final class WorkoutProgressReceiptAndAIContractTests: XCTestCase {
    func testNormalOutlineEditorReturnsValidatedIndependentRecoverableProposal() throws {
        let request = WorkoutAIRequestSnapshot(goal: "Strength", daysPerWeek: 1, maximumSessionMinutes: 30, experience: "Beginner",
            equipmentClass: "Bodyweight Only", details: "Floor", gym: nil, movementMappings: [:], startDate: now, weekdays: [2])
        var original = try WorkoutAIContract.map(response(), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30)
        original.id = "proposal"; original.startDate = now; original.daysOfWeek = [2]
        var proposal = WorkoutAIProposal(ownerID: "owner", request: request, program: original)
        proposal.pendingRequest = request
        let fingerprint = try PlanFingerprint.make(proposal)
        var edited = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(original))
        edited.id = "editor-local-id"; edited.name = "My outline"; edited.daysOfWeek = [4]; edited.startDate = now.addingTimeInterval(86_400)
        edited.routines[0].name = "My session"
        let reviewed = try proposal.replacingOutline(with: edited)
        XCTAssertEqual(reviewed.program?.id, "proposal")
        XCTAssertEqual(reviewed.program?.name, "My outline"); XCTAssertEqual(reviewed.program?.routines[0].name, "My session")
        XCTAssertEqual(reviewed.program?.daysOfWeek, [4]); XCTAssertNil(reviewed.program?.trainingBlock); XCTAssertNil(reviewed.pendingRequest)
        XCTAssertEqual(try PlanFingerprint.make(proposal), fingerprint, "Reviewing never mutates the original shared routine references")
        let restored = try JSONDecoder().decode(WorkoutAIProposal.self, from: JSONEncoder().encode(reviewed))
        XCTAssertEqual(restored.program?.daysOfWeek, [4]); XCTAssertEqual(restored.request.weekdays, [2], "Generated-request provenance remains original")
    }

    func testOutlineReviewRefusesChangedOwnerUnapprovedGearAndFrozenSubmission() throws {
        let request = WorkoutAIRequestSnapshot(goal: "Strength", daysPerWeek: 1, maximumSessionMinutes: 30, experience: "Beginner",
            equipmentClass: "Bodyweight Only", details: "Floor", gym: nil, movementMappings: [:], startDate: now, weekdays: [2])
        var original = try WorkoutAIContract.map(response(), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30)
        original.id = "proposal"; original.startDate = now; original.daysOfWeek = [2]
        var proposal = WorkoutAIProposal(ownerID: "owner", request: request, program: original)
        var edited = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(original))
        edited.daysOfWeek = [2, 2]; XCTAssertThrowsError(try proposal.replacingOutline(with: edited))
        edited.daysOfWeek = [2]; edited.userID = "other"; XCTAssertThrowsError(try proposal.replacingOutline(with: edited))
        edited.userID = "owner"; edited.routines[0].exercises[0].name = "Barbell Bench Press"
        XCTAssertThrowsError(try proposal.replacingOutline(with: edited))
        proposal.program?.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: original)
        XCTAssertThrowsError(try proposal.replacingOutline(with: original))
        XCTAssertThrowsError(try proposal.replacingRoutine(id: original.routines[0].id, with: original.routines[0]))
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func program() -> WorkoutProgram {
        var value = WorkoutProgram(id: "phul", userID: "owner", name: "PHUL", dateCreated: now.addingTimeInterval(-100),
            routines: [WorkoutRoutine(id: "day", userID: "owner", name: "Upper", dateCreated: now.addingTimeInterval(-100),
                exercises: [RoutineExercise(id: "lift", name: "Barbell Bench Press", sets: [ExerciseSet(id: "set", target: "8-12")])])],
            daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39, skippedIndices: [2, 9, 20])
        value.progressEpoch = "initial"
        return value
    }
    private func log(_ slot: Int, program: WorkoutProgram, id: String? = nil) -> WorkoutSessionLog {
        WorkoutSessionLog(id: id ?? "session-\(slot)", date: now.addingTimeInterval(-10), routineID: "day", completedExercises: [],
            programContext: WorkoutProgramSessionContext(programID: program.id!, slotIndex: slot))
    }
    func testPendingPHULProgressSurvivesItsOwnHistorySnapshotOnly() throws {
        let source = program()
        let session = log(39, program: source, id: "at-the-gym")
        let command = try WorkoutProgramProgressCommand(program: source, kind: .completion, sessionID: "at-the-gym")
        let proposed = try command.applying(to: source, verifiedLogs: [session], now: now)
        var afterHistory = source
        afterHistory.name = "Renamed plan"
        afterHistory.progressEpoch = try WorkoutProgramProgressCommand.historySaveEpoch(ownerID: source.userID, sessionID: "at-the-gym")
        let visible = try command.overlay(proposed: proposed, on: afterHistory)
        XCTAssertEqual(visible.currentProgressIndex, 40)
        XCTAssertEqual(visible.name, afterHistory.name)
        XCTAssertEqual(visible.skippedIndices, source.skippedIndices)
        XCTAssertEqual(try command.overlay(proposed: proposed, on: visible).currentProgressIndex, 40)

        var newer = afterHistory
        newer.currentProgressIndex = 43
        XCTAssertEqual(try command.overlay(proposed: proposed, on: newer).currentProgressIndex, 43)
        afterHistory.progressEpoch = try WorkoutProgramProgressCommand.historySaveEpoch(ownerID: source.userID, sessionID: "another-session")
        XCTAssertEqual(try command.overlay(proposed: proposed, on: afterHistory).progressEpoch, afterHistory.progressEpoch)
    }
    func testSkipLandsOnFirstUnfinishedSessionAndUndoPreservesTheEarlyWorkout() throws {
        let source = program()
        let early = log(40, program: source)
        let completion = try WorkoutProgramProgressCommand(program: source, kind: .completion, sessionID: early.id!)
        let withProof = try completion.applying(to: source, verifiedLogs: [early], now: now)
        XCTAssertEqual(withProof.currentProgressIndex, 39)
        let skip = try WorkoutProgramProgressCommand(program: withProof, kind: .skip, targetIndex: 40)
        let skipped = try skip.applying(to: withProof, verifiedLogs: [early], now: now)
        XCTAssertEqual(skipped.currentProgressIndex, 41)
        XCTAssertEqual(skipped.lastSkipReceipt?.addedSkips, [39])
        XCTAssertEqual(skipped.slotCompletionProofs, withProof.slotCompletionProofs)
        let undo = try WorkoutProgramProgressCommand(program: skipped, kind: .undoSkip)
        let restored = try undo.applying(to: skipped, verifiedLogs: [early], now: now)
        XCTAssertEqual(restored.currentProgressIndex, 39)
        XCTAssertEqual(restored.skippedIndices, source.skippedIndices)
        XCTAssertEqual(restored.slotCompletionProofs, withProof.slotCompletionProofs)
    }

    func testSkipReviewPreservesLinkedCompletionAndUndoRestoresOnlyItsOwnSkips() throws {
        let source = program(); let early = log(40, program: source)
        let skip = try WorkoutProgramProgressCommand(program: source, kind: .skip, targetIndex: 42, proofSessionIDs: [early.id!], now: now)
        let skipped = try skip.applying(to: source, verifiedLogs: [early], now: now)
        XCTAssertEqual(skipped.currentProgressIndex, 42)
        XCTAssertEqual(skipped.skippedIndices, [2, 9, 20, 39, 41])
        XCTAssertEqual(skipped.lastSkipReceipt?.addedSkips, [39, 41])
        let undo = try WorkoutProgramProgressCommand(program: skipped, kind: .undoSkip, now: now)
        let restored = try undo.applying(to: skipped, verifiedLogs: [early], now: now)
        XCTAssertEqual(restored.currentProgressIndex, 39); XCTAssertEqual(restored.skippedIndices, source.skippedIndices)
        XCTAssertNil(restored.lastSkipReceipt)
        XCTAssertEqual(try WorkoutProgramProgressCommand.structure(restored), try WorkoutProgramProgressCommand.structure(source))
    }
    func testLaterCompletionFencesUndoAndStaleSkipWithoutRewindingOrDroppingTemplate() throws {
        let source = program()
        let skip = try WorkoutProgramProgressCommand(program: source, kind: .skip, targetIndex: 40, now: now)
        let skipped = try skip.applying(to: source, verifiedLogs: [], now: now)
        let completed = log(40, program: source)
        let completion = try WorkoutProgramProgressCommand(program: skipped, kind: .completion, sessionID: completed.id!, now: now)
        let newest = try completion.applying(to: skipped, verifiedLogs: [completed], now: now)
        XCTAssertEqual(newest.currentProgressIndex, 41)
        let undo = try WorkoutProgramProgressCommand(program: skipped, kind: .undoSkip, now: now)
        XCTAssertThrowsError(try undo.applying(to: newest, verifiedLogs: [completed], now: now))
        XCTAssertThrowsError(try skip.applying(to: newest, verifiedLogs: [completed], now: now))
        XCTAssertEqual(try skip.overlay(proposed: skipped, on: newest).currentProgressIndex, 41)
        XCTAssertEqual(newest.routines[0].exercises[0].sets[0].id, "set")
    }
    func testUndoRejectsACompletedReceiptNotYetReflectedInProgressEpoch() throws {
        let source = program(); let skip = try WorkoutProgramProgressCommand(program: source, kind: .skip, targetIndex: 40, now: now)
        let skipped = try skip.applying(to: source, verifiedLogs: [], now: now)
        let undo = try WorkoutProgramProgressCommand(program: skipped, kind: .undoSkip, now: now)
        XCTAssertThrowsError(try undo.applying(to: skipped, verifiedLogs: [log(40, program: source)], now: now))
    }
    func testCompletionIdentityIsStableAcrossFreshReadHintsAndDoesNotSkipGap() throws {
        let source = program(); let early = log(41, program: source)
        let first = try WorkoutProgramProgressCommand(program: source, kind: .completion, sessionID: early.id!, now: now)
        var edited = source; edited.name = "New name"; edited.progressEpoch = "newer"
        let retry = try WorkoutProgramProgressCommand(program: edited, kind: .completion, sessionID: early.id!, proofSessionIDs: ["another"], now: now.addingTimeInterval(100))
        XCTAssertEqual(first.id, retry.id); XCTAssertEqual(try first.fingerprint(), try retry.fingerprint())
        let result = try first.applying(to: edited, verifiedLogs: [early], now: now)
        XCTAssertEqual(result.currentProgressIndex, 39); XCTAssertEqual(result.name, "New name")
        XCTAssertEqual(result.slotCompletionProofs?.first?.slotIndex, 41)
        var standalone = early; standalone.programLinkDecision = .standalone
        XCTAssertThrowsError(try first.applying(to: edited, verifiedLogs: [standalone], now: now))
        var future = early; future.date = now.addingTimeInterval(1)
        XCTAssertThrowsError(try first.applying(to: edited, verifiedLogs: [future], now: now))
    }
    func testDecodedForgedCompletionIDOrUnsafeProofPathIsRejected() throws {
        let source = program(); let command = try WorkoutProgramProgressCommand(program: source, kind: .completion, sessionID: "session", now: now)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        object["id"] = "forged"
        let forged = try JSONDecoder().decode(WorkoutProgramProgressCommand.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try forged.fingerprint())
        XCTAssertThrowsError(try WorkoutProgramProgressCommand(program: source, kind: .completion, sessionID: "unsafe/path", now: now))
    }
    func testPermanentProgressAcceptanceReplayReturnsNewerCanonicalAndCancellationFencesRetry() async throws {
        let source = program(); let repo = MockWorkoutRepository(); repo.mockSaveProgramResult = source
        let skip = try WorkoutProgramProgressCommand(program: source, kind: .skip, targetIndex: 40, now: now)
        _ = try await repo.enqueueProgramProgress(userID: "owner", command: skip, locallyVerifiedLogs: [])
        var newest = source; newest.name = "Later"; newest.currentProgressIndex = 44; newest.progressEpoch = "later"
        repo.committedBlockPrograms = [newest]
        let replay = try await repo.enqueueProgramProgress(userID: "owner", command: skip, locallyVerifiedLogs: [])
        XCTAssertEqual(replay.currentProgressIndex, 44); XCTAssertEqual(replay.name, "Later")
        repo.deletedProgramIDs = ["phul"]
        if case .accepted(let canonical) = try await repo.resolveProgramProgress(userID: "owner", command: skip, cancelPending: true) { XCTAssertNil(canonical) } else { XCTFail("Acceptance must survive deletion") }
        do { _ = try await repo.enqueueProgramProgress(userID: "owner", command: skip, locallyVerifiedLogs: []); XCTFail("Deleted program cannot be projected back") } catch {}
        repo.deletedProgramIDs = []
        let pending = try WorkoutProgramProgressCommand(program: newest, kind: .skip, targetIndex: 45, now: now)
        _ = try await repo.resolveProgramProgress(userID: "owner", command: pending, cancelPending: true)
        do { _ = try await repo.enqueueProgramProgress(userID: "owner", command: pending, locallyVerifiedLogs: []); XCTFail("Cancelled operation must stay cancelled") } catch {}
    }
    private func response(name: String = "Bodyweight Squat", displayed: String = "10", target: Double = 10,
                          version: Int = 2, variant: String = "standard-v1", policy: WorkoutProgressionPolicy.Kind = .bodyweight,
                          type: ExerciseType = .strength, profile: String? = nil, implement: String? = nil, alternatives: [String]? = nil) throws -> AIProgramResponse {
        let identity = try XCTUnwrap(WorkoutMovementCatalog.identity(for: name))
        return AIProgramResponse(programName: "Reviewed", routines: [AIRoutine(name: "Day", exercises: [AIExercise(name: name, type: type,
            sets: [AISet(target: displayed, prescription: WorkoutPrescription(kind: .repetitions, lowerBound: target))], alternatives: alternatives,
            movementID: identity.movementID, variantID: variant, progressionPolicy: WorkoutProgressionPolicy(kind: policy),
            equipmentProfileID: profile, equipmentImplementID: implement, restSeconds: 60)])], schemaVersion: version)
    }
    func testStrictAIV2AcceptsCanonicalTypedBodyweightAndRejectsLegacyVariantOrMismatchedTarget() throws {
        let valid = try WorkoutAIContract.map(response(), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30)
        XCTAssertEqual(valid.routines[0].exercises[0].loadEquipment?.loadingMeaning, .bodyweightOnly)
        XCTAssertThrowsError(try WorkoutAIContract.map(response(version: 1), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30))
        XCTAssertThrowsError(try WorkoutAIContract.map(response(variant: "another"), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30))
        XCTAssertThrowsError(try WorkoutAIContract.map(response(displayed: "20"), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30))
        XCTAssertThrowsError(try WorkoutAIContract.map(response(type: .cardio), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30))
    }
    func testStrictAIUsesExactConfirmedGymImplementAndRejectsUnconfirmedInventory() throws {
        let gym = StrengthGymProfile(id: "gym", revisionID: "revision", name: "Home", implements: [StrengthGymImplement(id: "bar", name: "Bar", equipment: StrengthEquipment(availableWeights: [45, 50, 55]))])
        let valid = try response(name: "Barbell Bench Press", policy: .linear, profile: "gym", implement: "bar")
        let result = try WorkoutAIContract.map(valid, userID: "owner", daysPerWeek: 1, equipment: .fullGym, maximumSessionMinutes: 30, gym: gym, confirmedMovements: ["Barbell Bench Press": "bar"])
        XCTAssertEqual(result.routines[0].exercises[0].loadEquipment?.gymProfile?.revisionID, "revision")
        XCTAssertThrowsError(try WorkoutAIContract.map(valid, userID: "owner", daysPerWeek: 1, equipment: .fullGym, maximumSessionMinutes: 30, gym: gym))
        XCTAssertThrowsError(try WorkoutAIContract.map(response(name: "Barbell Bench Press", policy: .linear, profile: "gym", implement: "other"), userID: "owner", daysPerWeek: 1, equipment: .fullGym, maximumSessionMinutes: 30, gym: gym, confirmedMovements: ["Barbell Bench Press": "bar"]))
        XCTAssertThrowsError(try WorkoutAIContract.map(response(name: "Barbell Bench Press", policy: .linear, profile: "gym", implement: "bar", alternatives: ["Dumbbell Bench Press"]), userID: "owner", daysPerWeek: 1, equipment: .fullGym, maximumSessionMinutes: 30, gym: gym, confirmedMovements: ["Barbell Bench Press": "bar"]))
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Barbell Bent-over Row", category: "Back"), .strength)
    }
    @MainActor
    func testScopedCuesSeparateVariantRoutineSetupAndOwnerAndRefuseStaleOverwrite() throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "owner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutScopedCueStore(store: EditorDraftStore(directory: directory))
        var exercise = program().routines[0].exercises[0]
        exercise.movementIdentity = WorkoutMovementCatalog.identity(for: exercise.name)
        let variant = try store.save(text: "Shoulders set", exercise: exercise, routineID: "day", scope: .movementVariant, expected: nil, userID: "owner")
        XCTAssertEqual(try store.best(exercise: exercise, routineID: "another", userID: "owner"), variant)
        let routine = try store.save(text: "Day-specific", exercise: exercise, routineID: "day", scope: .routineSlot, expected: nil, userID: "owner")
        XCTAssertEqual(try store.best(exercise: exercise, routineID: "day", userID: "owner"), routine)
        XCTAssertThrowsError(try store.save(text: "Stale", exercise: exercise, routineID: "day", scope: .routineSlot, expected: nil, userID: "owner"))
        var otherVariant = exercise; otherVariant.movementIdentity?.variantID = "different"
        XCTAssertNil(try store.best(exercise: otherVariant, routineID: "day", userID: "owner"))
        auth.currentUserID = "other"
        XCTAssertThrowsError(try store.best(exercise: exercise, routineID: "day", userID: "owner"))
        XCTAssertNil(try store.best(exercise: exercise, routineID: "day", userID: "other"))
        XCTAssertEqual(variant?.snapshot.text, "Shoulders set", "Captured historical cue remains immutable after later library changes")
    }
    func testBundledInstructionResolverRequiresExactVariantAndRejectsMalformedOrDuplicateManifest() throws {
        let name = "Barbell Bench Press"; let identity = try XCTUnwrap(WorkoutMovementCatalog.identity(for: name))
        let entry = WorkoutBuiltinInstructionMedia(id: "bench", version: 1, canonicalName: name,
            movementID: identity.movementID, variantID: identity.variantID, resourceName: "bench", fileExtension: "mov",
            contentSHA256: String(repeating: "a", count: 64), author: "Licensed author", sourceURL: URL(string: "https://example.com/source")!,
            licenseName: "CC BY 3.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/3.0/")!, captionTranscript: "Readable transcript")
        let catalog = WorkoutBuiltinInstructionCatalog(version: 1, entries: [entry])
        let decoded = try WorkoutBuiltinInstructionCatalog.decode(JSONEncoder().encode(catalog))
        var exercise = RoutineExercise(name: name); exercise.movementIdentity = identity
        XCTAssertEqual(decoded.media(for: exercise)?.id, "bench")
        exercise.movementIdentity?.variantID = "smith"
        XCTAssertNil(decoded.media(for: exercise))
        exercise.movementIdentity = nil; exercise.name = "Bench press"
        XCTAssertNil(decoded.media(for: exercise), "Legacy aliases do not authorize a different physical demonstration")
        var invalid = entry; invalid.resourceName = "../escape"
        XCTAssertThrowsError(try WorkoutBuiltinInstructionCatalog.decode(JSONEncoder().encode(WorkoutBuiltinInstructionCatalog(version: 1, entries: [invalid]))))
        XCTAssertThrowsError(try WorkoutBuiltinInstructionCatalog.decode(JSONEncoder().encode(WorkoutBuiltinInstructionCatalog(version: 1, entries: [entry, entry]))))
    }

    func testAIExclusionsAreHardConstraintsAndLegacyRequestRemainsReadable() throws {
        XCTAssertThrowsError(try WorkoutAIContract.map(response(), userID: "owner", daysPerWeek: 1, equipment: .floorOnly,
            maximumSessionMinutes: 30, avoidedMovements: ["Bodyweight Squat"]))
        XCTAssertThrowsError(try WorkoutAIContract.validateMovementChoices(preferred: ["Bodyweight Squat"], avoided: ["Bodyweight Squat"]))
        let request = WorkoutAIRequestSnapshot(goal: "Strength", daysPerWeek: 1, maximumSessionMinutes: 30, experience: "Beginner",
            equipmentClass: "Bodyweight Only", details: "Keep PHUL", gym: nil, movementMappings: [:], startDate: now, weekdays: [2],
            preferredMovements: ["Push-up"], avoidedMovements: ["Bodyweight Squat"])
        let proposal = WorkoutAIProposal(ownerID: "owner", request: request)
        let valid = try WorkoutAIContract.map(response(), userID: "owner", daysPerWeek: 1, equipment: .floorOnly, maximumSessionMinutes: 30)
        XCTAssertThrowsError(try proposal.validatedProgram(valid))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object.removeValue(forKey: "preferredMovements"); object.removeValue(forKey: "avoidedMovements")
        let legacy = try JSONDecoder().decode(WorkoutAIRequestSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.avoidedMovements); XCTAssertEqual(legacy.details, "Keep PHUL")
    }
    @MainActor
    func testDiscoveryFavoritesRecentAndCustomRenameAreAccountBoundAndStable() throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "owner"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutMovementSelectionStore(store: EditorDraftStore(directory: directory))
        let bench = WorkoutMovementSelectionStore.key(name: "Barbell Bench Press", identity: WorkoutMovementCatalog.identity(for: "Barbell Bench Press"))
        try store.record([bench, "another", bench], userID: "owner")
        try store.setFavorite(bench, enabled: true, userID: "owner")
        let saved = try store.load(userID: "owner")
        XCTAssertEqual(saved.recent, [bench, "another"]); XCTAssertEqual(saved.favorites, [bench])
        let custom = WorkoutCustomMovement(id: "custom", name: "Old name", type: .strength)
        var renamed = custom; renamed.name = "New name"
        XCTAssertEqual(WorkoutMovementSelectionStore.key(name: custom.name, identity: custom.identity(ownerID: "owner")),
            WorkoutMovementSelectionStore.key(name: renamed.name, identity: renamed.identity(ownerID: "owner")))
        auth.currentUserID = "other"
        XCTAssertThrowsError(try store.load(userID: "owner")); XCTAssertTrue(try store.load(userID: "other").favorites.isEmpty)
    }
    func testSubstitutionShortlistUsesAuthorFirstDeduplicatesAndDoesNotClaimInventory() {
        var source = program().routines[0].exercises[0]
        source.alternatives = ["Dumbbell Bench Press", "Dumbbell Bench Press", "Unknown movement"]
        let names = WorkoutSessionAdaptationRules.substitutionCandidates(for: source, limit: 5)
        XCTAssertEqual(names.first, "Dumbbell Bench Press"); XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(source.name)); XCTAssertFalse(names.contains("Unknown movement"))
        XCTAssertEqual(names.count, 5)
    }

}
