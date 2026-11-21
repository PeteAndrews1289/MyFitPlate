import XCTest
@testable import MyFitPlateCore

final class MealExperimentEvidenceTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))! }
    private var now: Date { start.addingTimeInterval(14 * 86_400) }
    private func program() -> WorkoutProgram {
        let routine = WorkoutRoutine(id: "routine", userID: "owner", name: "Upper", dateCreated: start,
            exercises: [RoutineExercise(id: "press", name: "Press", sets: [ExerciseSet(id: "set", target: "8", reps: 8, weight: 100)], targetSets: 1)])
        return WorkoutProgram(id: "program", userID: "owner", name: "Plan", dateCreated: start,
            routines: [routine], startDate: start, daysOfWeek: Array(1...7), currentProgressIndex: 0)
    }
    private func experiment(_ source: WorkoutProgram? = nil) throws -> MealExperiment {
        try MealExperimentRules.create(program: source ?? program(), routineID: "routine",
            mealA: FoodItem(id: "oats", name: "Oats", calories: 300), mealB: FoodItem(id: "toast", name: "Toast", calories: 300),
            minutesBefore: 90, startsWithA: true, now: start, calendar: calendar)
    }
    private func session(slot: Int = 0, id: String = "session") -> WorkoutSessionLog {
        let source = program().routines[0].exercises[0]
        return WorkoutSessionLog(id: id, date: start.addingTimeInterval(Double(slot) * 86_400 + 3_600), routineID: "routine",
            completedExercises: [CompletedExercise(id: "performed", exerciseName: "Press", exercise: source,
                sets: [CompletedSet(id: "completed", reps: 8, weight: 100)])],
            programContext: WorkoutProgramSessionContext(programID: "program", slotIndex: slot))
    }
    private func recorded() throws -> MealExperiment {
        let base = try experiment()
        return try MealExperimentRules.recording(in: base, trialID: base.trials[0].id, session: session(),
            energy: 3, comfort: 4, minutesBefore: 90, confounders: [], now: session().date)
    }
    private func correction(_ value: MealExperiment, energy: Int, at date: Date? = nil) throws -> MealExperiment {
        let observation = try XCTUnwrap(value.trials[0].observation)
        return try MealExperimentEvidenceRules.correctingRatings(value, trialID: value.trials[0].id,
            expectedObservationID: MealExperimentEvidenceRules.identity(observation), energy: energy, comfort: 4,
            minutesBefore: 90, confounders: [], note: "Reviewed correction", confirmedLegacySession: false, now: date ?? now)
    }

    func testEligibleScheduleExcludesProtectedSkippedAndEarlyCompletedSlots() throws {
        var source = program(); source.skippedIndices = [1]
        source.slotCompletionProofs = [WorkoutSlotCompletionProof(slotIndex: 2, sessionID: "already-completed")]
        let value = try MealExperimentRules.create(program: source, routineID: "routine",
            mealA: FoodItem(name: "Oats", calories: 300), mealB: FoodItem(name: "Toast", calories: 300),
            minutesBefore: 90, startsWithA: true, protectedSlots: [0], now: start, calendar: calendar)
        XCTAssertEqual(value.trials.map(\.slot), [3, 4, 5, 6, 7, 8])
        XCTAssertEqual(source.currentProgressIndex, 0)
        XCTAssertEqual(source.skippedIndices, [1])
    }

    func testExactProgramAndSlotMatchCannotBorrowARepeatedRoutineFromAnotherProgram() throws {
        let value = try experiment()
        XCTAssertTrue(MealExperimentEvidenceRules.matches(session(), experiment: value, trial: value.trials[0], allowLegacy: false, now: now))
        var foreign = session(); foreign.programContext = WorkoutProgramSessionContext(programID: "other", slotIndex: 0)
        XCTAssertFalse(MealExperimentEvidenceRules.matches(foreign, experiment: value, trial: value.trials[0], allowLegacy: true, now: now))
        XCTAssertFalse(MealExperimentEvidenceRules.matches(session(slot: 1), experiment: value, trial: value.trials[0], allowLegacy: true, now: now))
        var legacy = session(); legacy.programContext = nil
        XCTAssertFalse(MealExperimentEvidenceRules.matches(legacy, experiment: value, trial: value.trials[0], allowLegacy: false, now: now))
        XCTAssertTrue(MealExperimentEvidenceRules.matches(legacy, experiment: value, trial: value.trials[0], allowLegacy: true, now: now))
        XCTAssertThrowsError(try MealExperimentRules.recording(in: value, trialID: value.trials[0].id, session: legacy,
            energy: 3, comfort: 4, minutesBefore: 90, confounders: [], confirmedLegacySession: false, now: now))
    }

    func testRatingCorrectionPreservesMeasuredEvidenceMissingEffortAndPriorObservation() throws {
        var value = try recorded(); value.endedAt = now
        let original = try XCTUnwrap(value.trials[0].observation)
        let corrected = try correction(value, energy: 5)
        let result = try XCTUnwrap(corrected.trials[0].observation)
        XCTAssertEqual(result.energy, 5)
        XCTAssertEqual(result.volume, original.volume)
        XCTAssertEqual(result.sessionID, original.sessionID)
        XCTAssertEqual(result.evidenceFingerprint, original.evidenceFingerprint)
        XCTAssertNil(result.meanRPE)
        XCTAssertEqual(corrected.endedAt, value.endedAt)
        XCTAssertEqual(corrected.trials[0].observationHistory?.map(\.energy), [3])
        XCTAssertEqual(value.trials[0].observation?.energy, 3)
        XCTAssertThrowsError(try MealExperimentEvidenceRules.correctingRatings(corrected, trialID: value.trials[0].id,
            expectedObservationID: MealExperimentEvidenceRules.identity(original), energy: 2, comfort: 4,
            minutesBefore: 90, confounders: [], note: "stale", confirmedLegacySession: false))
    }

    func testConcurrentSameSessionCorrectionsStayVisibleAndExcludedUntilReviewedResolution() throws {
        let base = try recorded()
        let one = try correction(base, energy: 1, at: now)
        let two = try correction(base, energy: 5, at: now.addingTimeInterval(1))
        var a = MealExperimentCloudState(); a.update(one, now: now)
        var b = MealExperimentCloudState(); b.update(two, now: now.addingTimeInterval(1))
        let merged = a.merging(b)
        let value = try XCTUnwrap(merged.experiments.first)
        let trial = value.trials[0]
        XCTAssertEqual(trial.conflictingObservations?.count, 1)
        XCTAssertEqual(MealExperimentRules.summary(value).excluded, 1)
        XCTAssertEqual(MealExperimentRules.summary(value).a.count, 0)
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(b.merging(a)))
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(merged.merging(a)))
        let selected = try XCTUnwrap(trial.conflictingObservations?.first)
        let resolved = try MealExperimentEvidenceRules.resolving(value, trialID: trial.id,
            chosenObservationID: MealExperimentEvidenceRules.identity(selected), expectedFingerprint: PlanFingerprint.make(trial), now: now.addingTimeInterval(2))
        XCTAssertNil(resolved.trials[0].conflictingObservations)
        XCTAssertEqual(resolved.trials[0].observation?.energy, selected.energy)
        var accepted = merged; accepted.update(resolved, now: now.addingTimeInterval(2))
        XCTAssertNil(accepted.merging(b).experiments[0].trials[0].conflictingObservations, "An old replica cannot reopen an explicitly resolved alternative.")
        XCTAssertEqual(MealExperimentRules.summary(accepted.experiments[0]).a.count, 1)
    }

    func testSelectiveDeletionWinsAgainstLaterStaleEditAndKeepsOtherComparison() throws {
        let first = try experiment(); let second = try experiment()
        var old = MealExperimentCloudState(); old.update(first); old.update(second)
        var deleted = old; deleted.delete(experimentID: first.id, now: now)
        var late = first; late.trials[0].skipped = true
        old.update(late, now: now.addingTimeInterval(300))
        XCTAssertEqual(deleted.merging(old).experiments.map(\.id), [second.id])
        XCTAssertEqual(old.merging(deleted).experiments.map(\.id), [second.id])
    }

    func testSummariesSeparateNoEffectVariabilityAndDirectionalObservations() throws {
        func summary(a: [Int], b: [Int]) throws -> MealExperimentSummary {
            var value = try experiment()
            var aIndex = 0, bIndex = 0
            for index in value.trials.indices {
                let rating: Int
                if value.trials[index].side == .a { rating = a[aIndex]; aIndex += 1 } else { rating = b[bIndex]; bIndex += 1 }
                let log = session(slot: value.trials[index].slot, id: "session-\(index)")
                value = try MealExperimentRules.recording(in: value, trialID: value.trials[index].id, session: log,
                    energy: rating, comfort: 3, minutesBefore: 90, confounders: [], now: log.date)
            }
            return MealExperimentRules.summary(value)
        }
        XCTAssertEqual(try summary(a: [3, 3, 3], b: [3, 3, 3]).headline, "No clear preference yet")
        let mixed = try summary(a: [1, 5, 1], b: [5, 1, 5])
        XCTAssertEqual(mixed.headline, "Mixed observations")
        XCTAssertEqual(mixed.a.energyRange, 1...5)
        XCTAssertEqual(try summary(a: [5, 5, 5], b: [2, 2, 2]).headline, "A pattern worth repeating")
        XCTAssertEqual(MealExperimentRules.summary(try experiment()).headline, "Still learning")
    }

    @MainActor func testStoreRejectsStaleSameSessionCorrectionAndExportRetainsEarlierVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MealExperimentStore(storage: EditorDraftStore(directory: directory))
        store.activateAccount("owner")
        let original = try recorded(); try store.save(original, for: "owner")
        let corrected = try correction(original, energy: 5); try store.save(corrected, for: "owner")
        XCTAssertThrowsError(try store.save(original, for: "owner"))
        let export = try MealExperimentEvidenceRules.export(corrected)
        XCTAssertTrue(export.contains("observationHistory"))
        XCTAssertTrue(export.contains("evidenceFingerprint"))
        XCTAssertTrue(export.contains("sourceProgramID"))
        try store.delete(experimentID: original.id, for: "owner")
        XCTAssertTrue(store.experiments.isEmpty)
        XCTAssertThrowsError(try store.save(corrected, for: "owner"))
        store.activateAccount("other")
        XCTAssertTrue(store.experiments.isEmpty)
        XCTAssertThrowsError(try store.save(corrected, for: "owner"))
    }
}
