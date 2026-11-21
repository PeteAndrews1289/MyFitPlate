import XCTest
@testable import MyFitPlateCore

final class WorkoutTechniqueCatalogTests: XCTestCase {
    func testSelectivePHULCoverageLeavesProgressAndPrescriptionsUntouched() throws {
        var phul = try XCTUnwrap(WorkoutRules.generatePreBuiltPrograms().first { $0.id == "prebuilt_phul" })
        phul.currentProgressIndex = 39
        phul.skippedIndices = [2, 9, 20]
        phul.progressEpoch = "existing-account-epoch"
        phul.routines[0].exercises[0].notes = "My existing setup"
        let before = try PlanFingerprint.make(phul)
        let exercises = phul.routines.flatMap(\.exercises)
        let covered = Set(exercises.compactMap { WorkoutTechniqueCatalog.guide(for: $0)?.canonicalName })
        XCTAssertEqual(covered, ["Barbell Bench Press", "Incline Dumbbell Bench Press", "Barbell Bent-over Row",
            "Lat Pulldown", "Barbell Overhead Press (Military Press)", "Barbell Back Squat", "Deadlift (Conventional)",
            "Leg Press", "Incline Barbell Bench Press", "Seated Cable Row", "Dumbbell Row", "Barbell Front Squat", "Walking Lunge"])
        XCTAssertEqual(exercises.count, 24)
        XCTAssertTrue(exercises.allSatisfy { WorkoutTechniqueCatalog.briefCue(for: $0) != nil })
        XCTAssertEqual(try PlanFingerprint.make(phul), before)
        XCTAssertEqual(phul.currentProgressIndex, 39)
        XCTAssertEqual(phul.skippedIndices, [2, 9, 20])
    }

    func testGuidesAreUniqueExactCatalogEntriesWithOfflineContentAndPrimaryReferences() {
        XCTAssertEqual(WorkoutTechniqueCatalog.guides.count, 16)
        XCTAssertEqual(Set(WorkoutTechniqueCatalog.guides.map(\.id)).count, 16)
        for guide in WorkoutTechniqueCatalog.guides {
            XCTAssertTrue(ExerciseList.entries.contains { $0.name == guide.canonicalName })
            XCTAssertEqual(guide.identity, WorkoutMovementCatalog.identity(for: guide.canonicalName))
            XCTAssertFalse(guide.quickCue.isEmpty)
            XCTAssertFalse(guide.setup.isEmpty)
            XCTAssertFalse(guide.execution.isEmpty)
            XCTAssertFalse(guide.corrections.isEmpty)
            XCTAssertFalse(guide.variation.isEmpty)
            XCTAssertEqual(guide.reference.url.scheme, "https")
            XCTAssertTrue(["www.acefitness.org", "www.catalystathletics.com", "www.nasm.org", "www.cscca.org"]
                .contains(guide.reference.url.host ?? ""))
        }
    }

    func testSavedPHULAndLoggedExercisesResolveAfterRecoveryAndDeepCopyWithoutMigration() throws {
        for legacy in [false, true] {
            let template = try XCTUnwrap(WorkoutRules.generatePreBuiltPrograms().first { $0.id == "prebuilt_phul" })
            var program = WorkoutRules.preparePreBuiltProgramForUser(template, userID: "existing-owner")
            program.id = "accepted-phul"
            program.currentProgressIndex = 39
            program.skippedIndices = [2, 9, 20]
            if legacy {
                for routine in program.routines {
                    for index in routine.exercises.indices { routine.exercises[index].movementIdentity = nil }
                }
            }
            let recovered = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(program))
            let before = try PlanFingerprint.make(recovered)
            var restoredGuideIDs = Set<String>()
            for routine in recovered.routines {
                let copied = try XCTUnwrap(routine.deepCopy())
                XCTAssertEqual(try PlanFingerprint.make(copied), try PlanFingerprint.make(routine))
                for exercise in copied.exercises {
                    let expected = WorkoutTechniqueCatalog.guide(for: exercise)
                    if let expected { restoredGuideIDs.insert(expected.id) }
                    let logged = CompletedExercise(exerciseName: exercise.name, exercise: exercise,
                        sets: [CompletedSet(id: "accepted-set", reps: 8, weight: 135)])
                    let restoredLog = try JSONDecoder().decode(CompletedExercise.self, from: JSONEncoder().encode(logged))
                    let logBefore = try PlanFingerprint.make(restoredLog)
                    XCTAssertEqual(WorkoutTechniqueCatalog.guide(for: restoredLog.exercise)?.id, expected?.id)
                    XCTAssertNotNil(WorkoutTechniqueCatalog.briefCue(for: restoredLog.exercise))
                    XCTAssertEqual(try PlanFingerprint.make(restoredLog), logBefore)
                    XCTAssertEqual(restoredLog.exercise.movementIdentity, exercise.movementIdentity)
                    XCTAssertEqual(restoredLog.sets.first?.id, "accepted-set")
                }
            }
            XCTAssertEqual(restoredGuideIDs.count, 13)
            XCTAssertEqual(try PlanFingerprint.make(recovered), before)
            XCTAssertEqual(recovered.currentProgressIndex, 39)
        }
    }

    func testCustomAndDifferentVariantCannotInheritGuidanceByDisplayName() throws {
        var exercise = RoutineExercise(name: "Barbell Bench Press")
        let catalogIdentity = try XCTUnwrap(WorkoutMovementCatalog.identity(for: exercise.name))
        exercise.movementIdentity = catalogIdentity
        XCTAssertNotNil(WorkoutTechniqueCatalog.guide(for: exercise))
        var identities = [catalogIdentity, catalogIdentity, catalogIdentity, catalogIdentity]
        identities[0].ownerID = "another-owner"
        identities[1].variantID = "paused-v2"
        identities[2].catalogVersion = 2
        identities[3].movementID = "custom-movement"
        for identity in identities {
            exercise.movementIdentity = identity
            XCTAssertNil(WorkoutTechniqueCatalog.guide(for: exercise))
            XCTAssertNil(WorkoutTechniqueCatalog.briefCue(for: exercise))
            let restored = try JSONDecoder().decode(RoutineExercise.self, from: JSONEncoder().encode(exercise))
            XCTAssertNil(WorkoutTechniqueCatalog.guide(for: restored))
            XCTAssertNil(WorkoutTechniqueCatalog.briefCue(for: restored))
        }
    }

    func testIdentityKeepsItsTechniqueWhenDisplayNameChanges() throws {
        var exercise = RoutineExercise(name: "My gym bench")
        exercise.movementIdentity = try XCTUnwrap(WorkoutMovementCatalog.identity(for: "Barbell Bench Press"))
        XCTAssertEqual(WorkoutTechniqueCatalog.guide(for: exercise)?.canonicalName, "Barbell Bench Press")
        XCTAssertNotNil(WorkoutTechniqueCatalog.briefCue(for: exercise))
    }

    func testLegacyGuidanceRequiresExactNameWithoutAssigningIdentity() throws {
        let exercise = RoutineExercise(name: "Barbell Bench Press")
        let before = try PlanFingerprint.make(exercise)
        XCTAssertNotNil(WorkoutTechniqueCatalog.guide(for: exercise))
        XCTAssertNotNil(WorkoutTechniqueCatalog.briefCue(for: exercise))
        XCTAssertNil(exercise.movementIdentity)
        XCTAssertEqual(try PlanFingerprint.make(exercise), before)
        for name in ["bench press", "barbell bench press", "Barbell Bench Press ", "Bench press machine"] {
            XCTAssertNil(WorkoutTechniqueCatalog.guide(for: RoutineExercise(name: name)))
            XCTAssertNil(WorkoutTechniqueCatalog.briefCue(for: RoutineExercise(name: name)))
        }
    }

    func testUnexpandedExercisesRetainBriefGuidanceWithSameIdentityFence() throws {
        var exercise = RoutineExercise(name: "Barbell Curl")
        XCTAssertNil(WorkoutTechniqueCatalog.guide(for: exercise))
        XCTAssertEqual(WorkoutTechniqueCatalog.briefCue(for: exercise), ExerciseList.instructions(for: exercise.name))
        exercise.movementIdentity = try XCTUnwrap(WorkoutMovementCatalog.identity(for: exercise.name))
        exercise.name = "My curl"
        XCTAssertEqual(WorkoutTechniqueCatalog.briefCue(for: exercise), ExerciseList.instructions(for: "Barbell Curl"))
        exercise.movementIdentity?.ownerID = "owner"
        exercise.name = "Barbell Curl"
        XCTAssertNil(WorkoutTechniqueCatalog.briefCue(for: exercise))
    }

    func testStrengthGuidanceNeverAttachesToCardioOrFlexibilityRecords() {
        for type in [ExerciseType.cardio, .flexibility] {
            var exercise = RoutineExercise(name: "Barbell Bench Press", type: type)
            exercise.movementIdentity = WorkoutMovementCatalog.identity(for: exercise.name)
            XCTAssertNil(WorkoutTechniqueCatalog.guide(for: exercise))
            XCTAssertNil(WorkoutTechniqueCatalog.briefCue(for: exercise))
        }
    }
}
