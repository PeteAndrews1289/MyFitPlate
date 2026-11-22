import XCTest
@testable import MyFitPlateCore

final class StrengthEquipmentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func exercise(_ equipment: StrengthEquipment? = nil) -> RoutineExercise {
        var value = RoutineExercise(id: "bench", name: "Bench press", sets: (1...3).map {
            ExerciseSet(id: "set-\($0)", target: "8-12")
        }, targetSets: 3, targetReps: "8-12")
        value.loadEquipment = equipment
        return value
    }

    private func history(_ template: RoutineExercise, weight: Double = 100, reps: Int = 12,
                         effort: Double = 7, daysAgo: Int = 2) -> [WorkoutSessionLog] {
        [WorkoutSessionLog(id: "previous", date: now.addingTimeInterval(-Double(daysAgo) * 86_400), routineID: "phul-upper",
                           completedExercises: [CompletedExercise(exerciseName: template.name, exercise: template,
                             sets: (1...3).map { _ in CompletedSet(reps: reps, weight: weight, effort: SetEffort(scale: .rpe, value: effort)) })])]
    }

    func testBarbellUsesAvailablePairsAndRepeatedPairs() {
        let equipment = StrengthEquipment(kind: .barbell, barWeight: 45, plates: [25, 2.5, 2.5])
        XCTAssertEqual(equipment.attainableLoads, [45, 50, 55, 95, 100, 105])
        XCTAssertFalse(equipment.contains(135), "The calculator must not invent a missing plate pair")
        XCTAssertEqual(equipment.next(after: 100), 105)
        XCTAssertEqual(equipment.previous(before: 100), 95)
        XCTAssertNil(equipment.next(after: 105))
        XCTAssertNil(equipment.atOrBelow(40))
    }

    func testSelectableWeightConventionsCanBeSavedForThatEquipment() {
        let meanings = StrengthEquipment.LoadingMeaning.allCases
        XCTAssertEqual(meanings.filter { $0.supports(.fixedWeights) }, meanings)
        XCTAssertEqual(meanings.filter { $0.supports(.barbell) }, [.asLogged, .total, .perHand, .added])
        for kind in StrengthEquipment.Kind.allCases {
            for meaning in meanings {
                let equipment = StrengthEquipment(kind: kind, loadingMeaning: meaning, availableWeights: [0], barWeight: 45, plates: [25])
                XCTAssertEqual(equipment.isValid, meaning.supports(kind), "\(kind) with \(meaning)")
            }
        }
        XCTAssertFalse(StrengthEquipment(loadingMeaning: .bodyweightOnly, availableWeights: [10]).isValid)
    }

    func testPlateBreakdownUsesExactAvailablePairsIncludingDuplicatesAndKilograms() throws {
        let equipment = StrengthEquipment(kind: .barbell, barWeight: 45, plates: [25, 2.5, 2.5])
        XCTAssertEqual(equipment.platePairs(for: 105), [25, 2.5, 2.5])
        XCTAssertEqual(equipment.platePairs(for: 100), [25, 2.5])
        XCTAssertEqual(equipment.platePairs(for: 45), [])
        let alternative = StrengthEquipment(kind: .barbell, barWeight: 45, plates: [10, 10, 5, 25])
        XCTAssertEqual(alternative.platePairs(for: 95), [25], "Prefer one real pair over three smaller pairs")
        let unit = StrengthEquipment.Unit.kg
        let metric = StrengthEquipment(kind: .barbell, unit: unit, barWeight: unit.storedWeight(20),
                                       plates: [10, 1.25, 1.25].map(unit.storedWeight))
        let pairs = try XCTUnwrap(metric.platePairs(for: unit.storedWeight(45)))
        XCTAssertEqual(pairs.count, 3)
        for (actual, expected) in zip(pairs.map(unit.displayWeight), [10.0, 1.25, 1.25]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
        XCTAssertEqual(metric.barWeight + pairs.reduce(0, +) * 2, unit.storedWeight(45), accuracy: 0.0001)
    }

    func testPlateBreakdownRefusesMissingPlatesInvalidLoadsAndNonBarbellEquipment() {
        let equipment = StrengthEquipment(kind: .barbell, barWeight: 45, plates: [25, 2.5])
        XCTAssertNil(equipment.platePairs(for: 105), "The second small pair is missing")
        XCTAssertNil(equipment.platePairs(for: 47.5), "Do not invent a 1.25 lb plate")
        XCTAssertNil(equipment.platePairs(for: 40))
        XCTAssertNil(equipment.platePairs(for: .nan))
        XCTAssertNil(equipment.platePairs(for: .infinity))
        XCTAssertNil(StrengthEquipment(availableWeights: [100, 105]).platePairs(for: 105))
        XCTAssertNil(StrengthEquipment(kind: .barbell, plates: Array(repeating: 2.5, count: 13)).platePairs(for: 50))
    }

    func testKilogramEquipmentConvertsOnlyAtTheBoundary() {
        let unit = StrengthEquipment.Unit.kg
        let equipment = StrengthEquipment(kind: .barbell, unit: unit, barWeight: unit.storedWeight(20),
                                          plates: [unit.storedWeight(10), unit.storedWeight(1.25)])
        let fortyTwoAndHalf = unit.storedWeight(42.5)
        XCTAssertTrue(equipment.contains(fortyTwoAndHalf))
        XCTAssertEqual(unit.displayWeight(fortyTwoAndHalf), 42.5, accuracy: 0.0001)
        XCTAssertEqual(unit.storedWeight(unit.displayWeight(135)), 135, accuracy: 0.0001)
        XCTAssertNil(equipment.next(after: .infinity))
        XCTAssertNil(equipment.atOrBelow(.nan))
    }

    func testMalformedAndExcessiveInventoriesAreRejectedBeforeEnumeration() {
        let bad = [StrengthEquipment(availableWeights: []), StrengthEquipment(availableWeights: [.nan]),
                   StrengthEquipment(availableWeights: [-5]), StrengthEquipment(availableWeights: Array(repeating: 10, count: 257)),
                   StrengthEquipment(kind: .barbell, barWeight: .infinity),
                   StrengthEquipment(kind: .barbell, plates: Array(repeating: 2.5, count: 13)),
                   StrengthEquipment(kind: .barbell, plates: [0]),
                   StrengthEquipment(name: " ", availableWeights: [10])]
        for inventory in bad {
            XCTAssertFalse(inventory.isValid)
            XCTAssertTrue(inventory.attainableLoads.isEmpty)
        }
        XCTAssertEqual(StrengthEquipment(availableWeights: [25, 20, 25, 30]).attainableLoads, [20, 25, 30])
    }

    func testLegacyExerciseRoundTripRetainsValuesAndIDsWithoutEquipment() throws {
        let value = exercise()
        let encoded = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["loadEquipment"])
        let decoded = try JSONDecoder().decode(RoutineExercise.self, from: encoded)
        XCTAssertNil(decoded.loadEquipment)
        XCTAssertEqual(decoded.id, value.id)
        XCTAssertEqual(decoded.sets.map(\.id), value.sets.map(\.id))
        XCTAssertEqual(decoded.sets.map(\.weight), value.sets.map(\.weight))
        var configured = value
        configured.loadEquipment = StrengthEquipment(unit: .kg, loadingMeaning: .perHand, availableWeights: [20, 25])
        let saved = try JSONDecoder().decode(RoutineExercise.self, from: JSONEncoder().encode(configured))
        XCTAssertEqual(saved.loadEquipment, configured.loadEquipment)
        XCTAssertEqual(saved.sets.map(\.weight), value.sets.map(\.weight))
    }

    func testBarbellProgressionChoosesFeasibleLoadAndLeavesProgramTemplateIntact() throws {
        let equipment = StrengthEquipment(kind: .barbell, barWeight: 45, plates: [25, 2.5, 2.5])
        let template = exercise(equipment)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(template)
        let plan = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template), now: now))
        XCTAssertEqual(plan.move, .addWeight)
        XCTAssertEqual(plan.targets.map(\.weight), [105, 105, 105])
        XCTAssertEqual(plan.loadEquipment, equipment)
        XCTAssertTrue(plan.isValid)
        let updated = ProgressionRules.applying(plan, to: template)
        XCTAssertEqual(updated.id, template.id)
        XCTAssertEqual(updated.sets.map(\.id), template.sets.map(\.id))
        XCTAssertEqual(updated.sets.map(\.target), template.sets.map(\.target))
        XCTAssertEqual(try encoder.encode(template), bytes)
    }

    func testCoarseDumbbellJumpHoldsInsteadOfGuessingAnUnavailableIntermediate() throws {
        let template = exercise(StrengthEquipment(availableWeights: [40, 50, 60]))
        let plan = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template, weight: 40), now: now))
        XCTAssertEqual(plan.move, .hold)
        XCTAssertEqual(plan.targets.map(\.weight), [40, 40, 40])
        XCTAssertEqual(plan.targets.map(\.reps), [12, 12, 12])
        XCTAssertTrue(plan.rationale.contains("available"))
        let explicitStep = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template, weight: 40), increment: 10, now: now))
        XCTAssertEqual(explicitStep.targets.map(\.weight), [50, 50, 50])
        XCTAssertEqual(explicitStep.move, .addWeight)
    }

    func testEffortMissedRepsAndLongBreakKeepTheirConservativeRules() throws {
        let template = exercise(StrengthEquipment(availableWeights: [90, 95, 100, 105]))
        let hard = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template, effort: 9), now: now))
        XCTAssertEqual(hard.move, .hold)
        let incomplete = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template, reps: 7), now: now))
        XCTAssertEqual(incomplete.move, .hold)
        let returning = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template, daysAgo: 30), now: now))
        XCTAssertEqual(returning.move, .easeBack)
        XCTAssertEqual(returning.targets.map(\.weight), [90, 90, 90])
        XCTAssertTrue(returning.isValid)
    }

    func testLighterEquipmentTargetAvoidsAnExcessiveRackDropOrForcedIncrease() throws {
        let template = exercise(StrengthEquipment(availableWeights: [50, 95, 100]))
        let lighter = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template), lighterSession: true, now: now))
        XCTAssertEqual(lighter.targets.map(\.weight), [95, 95, 95])
        let noLower = exercise(StrengthEquipment(availableWeights: [50, 100]))
        let held = try XCTUnwrap(ProgressionRules.plan(for: noLower, history: history(noLower), lighterSession: true, now: now))
        XCTAssertEqual(held.move, .hold)
        XCTAssertEqual(held.targets.map(\.weight), [100, 100, 100])
        let tooHeavy = exercise(StrengthEquipment(availableWeights: [110, 120]))
        XCTAssertNil(ProgressionRules.plan(for: tooHeavy, history: history(tooHeavy, weight: 100, effort: 9), now: now))
    }

    func testDifferentMeaningOrMachineCannotBorrowHistoricalLoads() throws {
        let legacy = exercise()
        var configured = legacy
        configured.loadEquipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [100, 105])
        XCTAssertNil(ProgressionRules.plan(for: configured, history: history(legacy), now: now))
        XCTAssertNil(ProgressionRules.previousSet(for: "set-1", exercise: configured, previous: history(legacy)[0].completedExercises[0]))
        configured.loadEquipment?.loadingMeaning = .asLogged
        XCTAssertNotNil(ProgressionRules.plan(for: configured, history: history(legacy), now: now))
        var other = configured
        configured.loadEquipment?.name = "Machine A"
        other.loadEquipment?.name = "Machine B"
        XCTAssertNil(ProgressionRules.plan(for: configured, history: history(other), now: now))
        other.loadEquipment?.name = " machine a "
        XCTAssertNotNil(ProgressionRules.plan(for: configured, history: history(other), now: now))
        other.loadEquipment?.unit = .kg
        XCTAssertNotNil(ProgressionRules.plan(for: configured, history: history(other), now: now))
    }

    func testUnavailableManualTargetsAndChangedEquipmentAreRejectedAndUndoPreservesCompletedWork() throws {
        var template = exercise(StrengthEquipment(availableWeights: [95, 100, 105, 110]))
        template.sets[0].isCompleted = true
        template.sets[0].weight = 95
        template.sets[0].reps = 9
        let plan = try XCTUnwrap(ProgressionRules.plan(for: template, history: history(template), now: now))
        let updated = ProgressionRules.applying(plan, to: template)
        XCTAssertEqual(updated.sets[0].weight, 95)
        XCTAssertEqual(updated.sets[0].reps, 9)
        var unavailable = plan
        unavailable.targets[1].weight = 102.5
        XCTAssertFalse(unavailable.isValid)
        XCTAssertEqual(ProgressionRules.applying(unavailable, to: template).sets.map(\.weight), template.sets.map(\.weight))
        var changed = template
        changed.loadEquipment?.availableWeights = [100, 110]
        XCTAssertEqual(ProgressionRules.applying(plan, to: changed).sets.map(\.weight), changed.sets.map(\.weight))
        var current = updated
        current.sets[1].isCompleted = true
        current.sets[2].weight = 110
        let restored = ProgressionRules.undo(before: template, applied: updated, current: current)
        XCTAssertEqual(restored.sets[0].weight, 95)
        XCTAssertEqual(restored.sets[1].weight, 105)
        XCTAssertEqual(restored.sets[2].weight, 110)
    }

    func testPHULProgressAndTemplateStayIntactThroughConfiguredDraftRecoveryAndCompletion() throws {
        var program = try XCTUnwrap(WorkoutRules.generatePreBuiltPrograms().first {
            $0.name.localizedCaseInsensitiveContains("PHUL")
        })
        program.currentProgressIndex = 7
        program.skippedIndices = [2]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(program)
        let session = try XCTUnwrap(program.routines.first?.deepCopy())
        var movement = try XCTUnwrap(session.exercises.first)
        let equipment = StrengthEquipment(availableWeights: [95, 100, 105, 110])
        movement.loadEquipment = equipment
        let pastSets = try movement.sets.map { set in
            CompletedSet(reps: try XCTUnwrap(ProgressionRules.repRange(set.target ?? movement.targetReps)).upperBound,
                         weight: 100, effort: SetEffort(scale: .rpe, value: 7))
        }
        let past = WorkoutSessionLog(id: "phul-history", date: now.addingTimeInterval(-86_400), routineID: session.id,
                                    completedExercises: [CompletedExercise(exerciseName: movement.name, exercise: movement, sets: pastSets)])
        let targets = try XCTUnwrap(ProgressionRules.plan(for: movement, history: [past], now: now))
        session.exercises[0] = ProgressionRules.applying(targets, to: movement)
        session.exercises[0].sets[0].isCompleted = true
        var draft = WorkoutSessionDraft(routine: session, now: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutDraftStore(directory: directory)
        try store.save(draft, userID: "phul-user")
        draft = try XCTUnwrap(store.load(userID: "phul-user"))
        XCTAssertEqual(draft.routine.exercises[0].loadEquipment, equipment)
        XCTAssertTrue(draft.routine.exercises[0].sets[0].isCompleted)
        XCTAssertEqual(draft.routine.exercises[0].sets[0].weight, 105)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: now))
        XCTAssertEqual(draft.completion?.completedExercises.first?.exercise.loadEquipment, equipment)
        XCTAssertEqual(draft.completion?.routineID, session.id)
        XCTAssertEqual(program.currentProgressIndex, 7)
        XCTAssertEqual(program.skippedIndices, [2])
        XCTAssertEqual(try encoder.encode(program), original, "Session targets must not rewrite the active PHUL template")
    }

}
