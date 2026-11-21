import XCTest
@testable import MyFitPlateCore

@MainActor
final class StrengthSessionToolsTests: XCTestCase {
    private func bar() -> StrengthEquipment {
        StrengthEquipment(kind: .barbell, loadingMeaning: .total, name: "Training bar", barWeight: 45,
                          plates: [45, 25, 10, 5, 2.5])
    }
    private func exercise(id: String = "bench", weight: Double = 165) -> RoutineExercise {
        RoutineExercise(id: id, name: "Bench press", sets: (0..<3).map {
            ExerciseSet(id: "\(id)-\($0)", target: "8-12", reps: 8, weight: weight)
        }, targetSets: 3, targetReps: "8-12", loadEquipment: bar())
    }
    private func profile() -> StrengthGymProfile {
        StrengthGymProfile(id: "gym", name: "Home", implements: [StrengthGymImplement(id: "bar", name: "Olympic bar", equipment: bar())])
    }

    func testGymLibraryPreservesPhysicalInventoryAndChecksStaleEditors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner = "one"
        let store = StrengthGymProfileStore(store: EditorDraftStore(directory: directory), currentUserID: { owner })
        var gym = profile()
        gym.implements[0].equipment.unit = .kg
        gym.implements[0].equipment.plates.append(StrengthEquipment.Unit.kg.storedWeight(1.125))
        let first = try store.save(gym, expected: nil, userID: "one")
        XCTAssertEqual(try store.profiles(userID: "one").first?.implements[0].equipment.plates.last,
                       StrengthEquipment.Unit.kg.storedWeight(1.125))
        var renamed = first; renamed.name = "Garage"
        let latest = try store.save(renamed, expected: first, userID: "one")
        XCTAssertThrowsError(try store.save(first, expected: first, userID: "one"))
        XCTAssertThrowsError(try store.remove(first, userID: "one"))
        XCTAssertEqual(try store.profiles(userID: "one"), [latest])
        owner = "two"
        XCTAssertThrowsError(try store.profiles(userID: "one"))
        XCTAssertTrue(try store.profiles(userID: "two").isEmpty)
    }

    func testProfileSnapshotsKeepIdentityAcrossRenameAndSeparateDifferentGyms() throws {
        let first = profile()
        let original = try XCTUnwrap(first.equipment(for: "bar"))
        var renamed = first; renamed.name = "Renamed gym"; renamed.revisionID = "next"
        renamed.implements[0].name = "Renamed bar"; renamed.implements[0].equipment.plates.removeLast()
        let later = try XCTUnwrap(renamed.equipment(for: "bar"))
        XCTAssertTrue(StrengthEquipment.historyCompatible(current: later, previous: original))
        XCTAssertNotEqual(later, original, "A reviewed proposal still sees inventory revision changes")
        XCTAssertEqual(original.plates, bar().plates)
        var travel = renamed; travel.id = "travel"
        XCTAssertFalse(StrengthEquipment.historyCompatible(current: travel.equipment(for: "bar"), previous: original))
        XCTAssertFalse(StrengthEquipment.historyCompatible(current: original, previous: bar()), "Legacy context is not silently assigned to a new named machine")
    }

    func testRememberedGymMappingsAreRoutineAndAccountScoped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StrengthGymProfileStore(store: EditorDraftStore(directory: directory), currentUserID: { "one" })
        let gym = try store.save(profile(), expected: nil, userID: "one")
        try store.rememberMappings(["bench": "bar"], profile: gym, routineID: "upper", userID: "one")
        XCTAssertEqual(try store.mappings(profile: gym, routineID: "upper", userID: "one"), ["bench": "bar"])
        XCTAssertTrue(try store.mappings(profile: gym, routineID: "lower", userID: "one").isEmpty)
        XCTAssertThrowsError(try store.rememberMappings(["bench": "missing"], profile: gym, routineID: "upper", userID: "one"))
        XCTAssertThrowsError(try store.mappings(profile: gym, routineID: "upper", userID: "other"))
        var edited = gym; edited.name = "Updated gym"
        _ = try store.save(edited, expected: gym, userID: "one")
        XCTAssertThrowsError(try store.rememberMappings(["bench": "bar"], profile: gym, routineID: "upper", userID: "one"))
    }

    func testUnreadableGymLibraryIsRetainedAndCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = EditorDraftStore(directory: directory)
        try drafts.save(["future": "unreadable library"], userID: "one", scope: "strength-gym-library-v1")
        let accountDirectory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: accountDirectory, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file)
        let store = StrengthGymProfileStore(store: drafts, currentUserID: { "one" })
        XCTAssertThrowsError(try store.profiles(userID: "one"))
        XCTAssertThrowsError(try store.save(profile(), expected: nil, userID: "one"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testGymReviewUsesAttainableLoadsAndKeepsUnmappedPerformedMovement() throws {
        var gym = profile(); gym.implements[0].equipment.plates = [45, 10, 2.5]
        var performed = exercise(id: "row", weight: 75); performed.sets[0].isCompleted = true
        let before = [exercise(), performed]
        let change = try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: ["bench": "bar"], exercises: before)
        let applied = try StrengthSessionToolsRules.applying(change, to: before)
        XCTAssertEqual(applied[0].sets.map(\.weight), [160, 160, 160])
        XCTAssertTrue(applied[0].sets.allSatisfy { applied[0].loadEquipment?.contains($0.weight) == true })
        XCTAssertEqual(try PlanFingerprint.make(applied[1]), try PlanFingerprint.make(performed))
        XCTAssertEqual(before[0].sets[0].weight, 165)
        XCTAssertThrowsError(try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: ["row": "bar"], exercises: before))
    }

    func testChangedLoadingMeaningNeverTransfersTotalWeightIntoPerHand() throws {
        var gym = profile()
        gym.implements[0].equipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [20, 25, 30, 35, 40])
        let change = try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: ["bench": "bar"], exercises: [exercise()])
        XCTAssertTrue(change.after[0].sets.allSatisfy { $0.weight == 0 && $0.reps == 8 && !$0.isCompleted })
        XCTAssertEqual(change.after[0].loadEquipment?.loadingMeaning, .perHand)
    }

    func testGymChangeAdaptsWarmupDropAndFailureLoadsToActualInventory() throws {
        var source = exercise(weight: 37)
        source.loadEquipment = StrengthEquipment(loadingMeaning: .perHand, name: "Home dumbbells", availableWeights: [17, 27, 32, 37])
        source.sets.insert(ExerciseSet(id: "warmup", target: "5", isWarmup: true, reps: 5, weight: 17), at: 0)
        source.sets.append(ExerciseSet(id: "drop", target: "10", setType: .drop, reps: 10, weight: 27))
        source.sets.append(ExerciseSet(id: "failure", target: "AMRAP", setType: .failure, reps: 12, weight: 32))
        var gym = profile()
        gym.implements[0].equipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [5, 10, 15, 20, 25, 30])
        let change = try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: [source.id: "bar"], exercises: [source])
        let applied = try StrengthSessionToolsRules.applying(change, to: [source])[0]
        XCTAssertEqual(applied.sets.map(\.weight), [15, 30, 30, 30, 25, 30])
        XCTAssertTrue(applied.sets.allSatisfy { applied.loadEquipment?.contains($0.weight) == true })
        XCTAssertEqual(applied.sets.map(\.id), source.sets.map(\.id))
        XCTAssertEqual(applied.sets.map(\.resolvedSetType), source.sets.map(\.resolvedSetType))
        XCTAssertEqual(applied.sets.map(\.reps), source.sets.map(\.reps))
        XCTAssertFalse(applied.sets.contains(where: \.isCompleted))
    }

    func testChangedMeaningClearsEverySetRoleWithoutReinterpretingWarmupOrDropLoad() throws {
        var source = exercise()
        source.sets.insert(ExerciseSet(id: "warmup", target: "5", isWarmup: true, reps: 5, weight: 45), at: 0)
        source.sets.append(ExerciseSet(id: "drop", target: "12", setType: .drop, reps: 12, weight: 95))
        source.sets.append(ExerciseSet(id: "failure", target: "AMRAP", setType: .failure, reps: 10, weight: 135))
        var gym = profile()
        gym.implements[0].equipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [20, 25, 30])
        let change = try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: [source.id: "bar"], exercises: [source])
        XCTAssertEqual(change.after[0].sets.map(\.weight), Array(repeating: 0, count: source.sets.count))
        XCTAssertEqual(change.after[0].sets.map(\.resolvedSetType), source.sets.map(\.resolvedSetType))
        let recovered = try JSONDecoder().decode(StrengthSessionChange.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(try PlanFingerprint.make(StrengthSessionToolsRules.undo(recovered, current: recovered.after)),
                       try PlanFingerprint.make([source]))
    }

    func testUnavailableWarmupBlocksGymChangeWithoutLosingTheOriginalSession() throws {
        var source = exercise()
        source.sets.insert(ExerciseSet(id: "warmup", target: "5", isWarmup: true, reps: 5, weight: 35), at: 0)
        let fingerprint = try PlanFingerprint.make(source)
        XCTAssertThrowsError(try StrengthSessionToolsRules.equipmentChange(profile: profile(), mappings: [source.id: "bar"], exercises: [source]))
        XCTAssertEqual(try PlanFingerprint.make(source), fingerprint)
        source.sets[0].weight = 0
        let change = try StrengthSessionToolsRules.equipmentChange(profile: profile(), mappings: [source.id: "bar"], exercises: [source])
        XCTAssertEqual(change.after[0].sets[0].weight, 0, "An unentered warm-up stays available for manual review")
    }

    func testReviewedChangeRejectsSetLoggedOrEditedDuringReview() throws {
        let before = [exercise()]
        let change = try StrengthSessionToolsRules.equipmentChange(profile: profile(), mappings: ["bench": "bar"], exercises: before)
        var changed = before; changed[0].sets[0].isCompleted = true
        XCTAssertThrowsError(try StrengthSessionToolsRules.applying(change, to: changed))
        changed = before; changed[0].sets[1].weight = 155
        XCTAssertThrowsError(try StrengthSessionToolsRules.applying(change, to: changed))
    }

    func testMalformedReviewedChangeCannotEditOrRemovePerformedSet() throws {
        var source = exercise(); source.sets[0].isCompleted = true
        var modified = source; modified.sets[0].weight = 5
        let altered = StrengthSessionChange(kind: .progression, title: "Invalid", before: [source], after: [modified])
        XCTAssertThrowsError(try StrengthSessionToolsRules.applying(altered, to: [source]))
        modified = source; modified.sets.removeFirst()
        let removed = StrengthSessionChange(kind: .equipment, title: "Invalid", before: [source], after: [modified])
        XCTAssertThrowsError(try StrengthSessionToolsRules.applying(removed, to: [source]))
    }

    func testEquipmentUndoCannotRelabelLaterManualOrPerformedWork() throws {
        let before = [exercise()]
        let change = try StrengthSessionToolsRules.equipmentChange(profile: profile(), mappings: ["bench": "bar"], exercises: before)
        XCTAssertEqual(StrengthSessionToolsRules.undo(change, current: change.after)[0].loadEquipment, before[0].loadEquipment)
        var edited = change.after; edited[0].sets[0].weight = 150
        XCTAssertEqual(try PlanFingerprint.make(StrengthSessionToolsRules.undo(change, current: edited)), try PlanFingerprint.make(edited))
        var logged = change.after; logged[0].sets[1].isCompleted = true
        XCTAssertEqual(try PlanFingerprint.make(StrengthSessionToolsRules.undo(change, current: logged)), try PlanFingerprint.make(logged))
    }

    func testWarmupRampUsesActualPlatePairsAndExcludesWorkingLoad() throws {
        let source = exercise()
        let plan = try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165)
        XCTAssertFalse(plan.sets.isEmpty)
        XCTAssertEqual(plan.sets.first?.weight, 45)
        for set in plan.sets {
            XCTAssertTrue(bar().contains(set.weight)); XCTAssertNotNil(bar().platePairs(for: set.weight))
            XCTAssertLessThan(set.weight, 165); XCTAssertGreaterThanOrEqual(set.weight, 45)
            XCTAssertEqual(set.resolvedSetType, .warmup); XCTAssertFalse(set.isCompleted)
        }
        let applied = try StrengthWarmupRules.applying(plan, to: source)
        XCTAssertEqual(applied.sets.filter { $0.resolvedSetType == .normal }.map(\.id), source.sets.map(\.id))
        XCTAssertEqual(applied.sets.filter { $0.resolvedSetType == .normal }.map(\.weight), source.sets.map(\.weight))
        XCTAssertThrowsError(try StrengthWarmupRules.applying(plan, to: applied), "The same frozen proposal cannot stack itself")
    }

    func testRepeatedRampReplacesOnlyUntouchedGeneratedRows() throws {
        let source = exercise()
        var applied = try StrengthWarmupRules.applying(StrengthWarmupRules.prepare(exercise: source, workingWeight: 165), to: source)
        let count = applied.sets.count
        let repeated = try StrengthWarmupRules.prepare(exercise: applied, workingWeight: 165)
        XCTAssertEqual(repeated.replacingIDs.count, repeated.sets.count)
        applied = try StrengthWarmupRules.applying(repeated, to: applied)
        XCTAssertEqual(applied.sets.count, count)
        let loggedID = applied.sets[0].id
        applied.sets[0].isCompleted = true
        let editedID = applied.sets[1].id
        applied.sets[1].reps += 1
        let next = try StrengthWarmupRules.prepare(exercise: applied, workingWeight: 165)
        XCTAssertFalse(next.replacingIDs.contains(loggedID)); XCTAssertFalse(next.replacingIDs.contains(editedID))
        let final = try StrengthWarmupRules.applying(next, to: applied)
        XCTAssertTrue(final.sets.contains { $0.id == loggedID && $0.isCompleted })
        XCTAssertEqual(final.sets.first { $0.id == editedID }?.reps, applied.sets[1].reps)
        XCTAssertEqual(final.sets.filter { $0.isCompleted && $0.weight == 45 }.count, 1)
    }

    func testWarmupRegenerationDoesNotDuplicateMatchingManualPreparation() throws {
        var source = exercise()
        let manual = ExerciseSet(id: "manual-warmup", target: "8", isWarmup: true, reps: 8, weight: 45)
        source.sets.insert(manual, at: 0)
        let plan = try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165)
        XCTAssertFalse(plan.sets.contains { $0.weight == 45 && $0.reps == 8 })
        let after = try StrengthWarmupRules.applying(plan, to: source)
        XCTAssertEqual(after.sets.filter { $0.weight == 45 && $0.reps == 8 }.count, 1)
        XCTAssertEqual(try PlanFingerprint.make(try XCTUnwrap(after.sets.first { $0.id == manual.id })), try PlanFingerprint.make(manual))
    }

    func testGymAdjustedGeneratedWarmupRetainsProvenanceAndIsNotGeneratedTwice() throws {
        let source = exercise()
        let ramped = try StrengthWarmupRules.applying(StrengthWarmupRules.prepare(exercise: source, workingWeight: 165), to: source)
        var gym = profile(); gym.implements[0].equipment.plates = [45, 10, 2.5]
        let change = try StrengthSessionToolsRules.equipmentChange(profile: gym, mappings: [source.id: "bar"], exercises: [ramped])
        let mapped = change.after[0]
        let adjusted = try XCTUnwrap(mapped.sets.first { $0.weight == 70 && $0.reps == 5 })
        XCTAssertEqual(adjusted.generatedWarmup, ramped.sets.first { $0.id == adjusted.id }?.generatedWarmup)
        XCTAssertFalse(try XCTUnwrap(adjusted.generatedWarmup).isUntouched(adjusted))
        let next = try StrengthWarmupRules.prepare(exercise: mapped, workingWeight: 160)
        XCTAssertFalse(next.replacingIDs.contains(adjusted.id), "A reviewed equipment adjustment is retained as an edited row")
        XCTAssertFalse(next.sets.contains { $0.weight == adjusted.weight && $0.reps == adjusted.reps })
        let after = try StrengthWarmupRules.applying(next, to: mapped)
        XCTAssertEqual(after.sets.filter { $0.weight == adjusted.weight && $0.reps == adjusted.reps }.count, 1)
        XCTAssertTrue(after.sets.contains { $0.id == adjusted.id })
        let recovered = try JSONDecoder().decode(StrengthSessionChange.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(try PlanFingerprint.make(StrengthSessionToolsRules.undo(recovered, current: recovered.after)),
                       try PlanFingerprint.make([ramped]))
    }

    func testWarmupRefusesUnknownLoadingMeaningAndInsufficientInventory() throws {
        var source = exercise(); source.loadEquipment = nil
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165))
        source.loadEquipment = bar(); source.loadEquipment?.loadingMeaning = .asLogged
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165))
        source.loadEquipment?.loadingMeaning = .added
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165))
        source.loadEquipment = bar()
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 40))
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 45))
        var formula = StrengthWarmupFormula.standard; formula.steps[1].fraction = 0.1
        XCTAssertThrowsError(try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165, formula: formula))
    }

    func testKilogramWarmupKeepsExactInventoryThroughRecovery() throws {
        let unit = StrengthEquipment.Unit.kg
        var source = exercise(weight: unit.storedWeight(62.25))
        source.loadEquipment = StrengthEquipment(kind: .barbell, unit: unit, loadingMeaning: .total,
            barWeight: unit.storedWeight(20), plates: [20, 1.125].map(unit.storedWeight))
        let plan = try StrengthWarmupRules.prepare(exercise: source, workingWeight: unit.storedWeight(62.25))
        let updated = try StrengthWarmupRules.applying(plan, to: source)
        let decoded = try JSONDecoder().decode(RoutineExercise.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(decoded.loadEquipment, source.loadEquipment)
        XCTAssertEqual(decoded.sets.map(\.weight), updated.sets.map(\.weight))
        XCTAssertEqual(decoded.sets.compactMap(\.generatedWarmup), updated.sets.compactMap(\.generatedWarmup))
    }

    func testWarmupChangeKeepsRestIdentityAndIsExcludedFromWorkingVolume() throws {
        let source = exercise()
        let plan = try StrengthWarmupRules.prepare(exercise: source, workingWeight: 165)
        let updated = try StrengthWarmupRules.applying(plan, to: source)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let routine = WorkoutRoutine(id: "routine", userID: "one", name: "Upper", dateCreated: now, exercises: [updated])
        var draft = WorkoutSessionDraft(routine: routine, now: now)
        draft.rest = try XCTUnwrap(WorkoutRestState(duration: 90, routineName: "Upper", exerciseID: source.id, setID: source.sets[0].id, now: now))
        let saved = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(saved.rest, draft.rest)
        XCTAssertEqual(saved.rest?.remaining(at: now.addingTimeInterval(30)), 60)
        XCTAssertEqual(plan.sets.compactMap { $0.generatedWarmup?.restSeconds }, [45, 60, 90])
        let completed = CompletedExercise(exerciseName: source.name, exercise: updated,
            sets: updated.sets.map { CompletedSet(reps: $0.reps, weight: $0.weight, setType: $0.resolvedSetType) })
        XCTAssertEqual(WorkoutSetMath.volume(completed), 165 * 8 * 3)
        XCTAssertEqual(WorkoutSetMath.workingSets(in: completed).count, 3)
    }

    func testUnknownOptionalSessionToolsMetadataDoesNotLoseLegacyLoggedSets() throws {
        var source = exercise(); source.sets[0].isCompleted = true
        let routine = WorkoutRoutine(id: "routine", userID: "one", name: "Upper", dateCreated: Date(), exercises: [source])
        let draft = WorkoutSessionDraft(routine: routine)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object["sessionToolsReceipt"] = ["newerFormat": true]
        let restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.sessionToolsReceipt)
        XCTAssertTrue(restored.routine.exercises[0].sets[0].isCompleted)
        XCTAssertEqual(restored.routine.exercises[0].sets[0].weight, 165)
        XCTAssertEqual(restored.sessionID, draft.sessionID)
    }

    func testSessionProgressionUndoAndReceiptSurviveDraftRecovery() throws {
        let before = exercise(weight: 100)
        var plan = ProgressionPlan(exerciseID: before.id, exerciseName: before.name, move: .addRep,
            headline: "Build reps", rationale: "Reference", sessionCount: 1, increment: 5,
            targets: before.sets.enumerated().map { ProgressionTarget(id: $0.element.id, setNumber: $0.offset + 1, weight: 100, reps: 9) })
        plan.loadEquipment = before.loadEquipment
        // The chosen bar needs attainable 100 lb for this fixture.
        var source = before; source.loadEquipment = StrengthEquipment(loadingMeaning: .total, availableWeights: [100, 105])
        plan.loadEquipment = source.loadEquipment
        let change = try StrengthSessionToolsRules.progressionChange(plans: [plan], exercises: [source])
        let routine = WorkoutRoutine(id: "routine", userID: "one", name: "Upper", dateCreated: Date(), exercises: change.after)
        var draft = WorkoutSessionDraft(routine: routine); draft.sessionToolsReceipt = change
        let decoded = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONEncoder().encode(draft))
        let receipt = try XCTUnwrap(decoded.sessionToolsReceipt)
        var current = decoded.routine.exercises
        current[0].sets[0].isCompleted = true
        current[0].sets[1].weight = 107
        let restored = StrengthSessionToolsRules.undo(receipt, current: current)
        XCTAssertTrue(restored[0].sets[0].isCompleted); XCTAssertEqual(restored[0].sets[0].reps, 9)
        XCTAssertEqual(restored[0].sets[1].weight, 107); XCTAssertEqual(restored[0].sets[1].reps, 8)
        XCTAssertEqual(restored[0].sets[2].reps, 8)
        XCTAssertEqual(decoded.sessionID, draft.sessionID)
    }
}
