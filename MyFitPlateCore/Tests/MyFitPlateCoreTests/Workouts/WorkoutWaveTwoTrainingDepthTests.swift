import XCTest
@testable import MyFitPlateCore

final class WorkoutWaveTwoTrainingDepthTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func exercise(_ meaning: StrengthEquipment.LoadingMeaning = .total, policy: WorkoutProgressionPolicy.Kind = .conservativeDouble) -> RoutineExercise {
        var value = RoutineExercise(id: "lift", name: "Barbell Bench Press", sets: (0..<3).map { ExerciseSet(id: "s\($0)", target: "8-12") }, targetReps: "8-12",
            loadEquipment: StrengthEquipment(loadingMeaning: meaning, availableWeights: meaning == .bodyweightOnly ? [0] : [0, 45, 50, 55, 60, 90, 95, 100, 105, 110]))
        value.progressionPolicy = WorkoutProgressionPolicy(kind: policy)
        value.movementIdentity = WorkoutMovementCatalog.identity(for: value.name)
        return value
    }
    func testParkingEntireLiftRoundTripsWithoutChangingSetsPartnerDeferralOrProgramSlot() throws {
        var bench = exercise()
        bench.sets[0].isCompleted = true
        bench.sets[0].weight = 135
        bench.sets[1].isDeferred = true
        let row = RoutineExercise(id: "row", name: "Row", sets: [ExerciseSet(id: "row-1")])
        let routine = WorkoutRoutine(userID: "qa", name: "Upper", dateCreated: now, exercises: [bench, row])
        let context = WorkoutProgramSessionContext(programID: "phul", slotIndex: 7)
        var draft = WorkoutSessionDraft(routine: routine, programContext: context)
        XCTAssertTrue(draft.setParked(true, exerciseID: bench.id, currentSetID: "s2"))
        XCTAssertEqual(draft.selectedSetID, "row-1")
        XCTAssertTrue(draft.setParked(true, exerciseID: row.id, currentSetID: "row-1"))
        XCTAssertNil(draft.selectedSetID)
        var restored = try JSONDecoder().decode(WorkoutSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertNil(WorkoutSetNavigation.firstUnfinished(in: restored.navigationExercises(restored.routine.exercises)))
        XCTAssertTrue(restored.setParked(false, exerciseID: bench.id, currentSetID: nil))
        XCTAssertEqual(restored.selectedSetID, "s2")
        XCTAssertEqual(restored.parkedExerciseIDs, ["row"])
        XCTAssertEqual(restored.programContext?.slotIndex, 7)
        XCTAssertTrue(restored.routine.exercises[0].sets[0].isCompleted)
        XCTAssertEqual(restored.routine.exercises[0].sets[0].weight, 135)
        XCTAssertTrue(restored.routine.exercises[0].sets[1].isDeferred == true)
        XCTAssertNil(routine.exercises[0].sets[2].isDeferred)
    }

    private func log(_ exercise: RoutineExercise, reps: Int = 12, weight: Double = 100, days: Int = 1, id: String = "log") -> WorkoutSessionLog {
        WorkoutSessionLog(id: id, date: now.addingTimeInterval(-Double(days) * 86_400), routineID: "routine", completedExercises: [
            CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: (0..<3).map { _ in CompletedSet(reps: reps, weight: weight, effort: SetEffort(scale: .rpe, value: 7)) })
        ])
    }

    func testDurationSummaryCountsOnlyValidTimedSessionsInScope() throws {
        func timed(_ id: String, _ seconds: Double?, days: Int = 1) -> WorkoutSessionLog {
            var session = log(exercise(), days: days, id: id)
            session.elapsedSeconds = seconds
            return session
        }
        func report(_ logs: [WorkoutSessionLog]) throws -> WorkoutEvidenceSnapshot {
            try WorkoutEvidenceReportRules.snapshot(logs: logs, scope: .init(), now: now)
        }

        let missing = timed("missing", nil)
        let short = timed("short", 45)
        let invalid = [timed("negative", -1), timed("long", 86_401), timed("nonfinite", .nan)]
        let untimed = try report([missing] + invalid)
        XCTAssertEqual(untimed.timedSessionCount, 0)
        XCTAssertEqual(untimed.sessionIDs.count, 4)
        XCTAssertEqual(untimed.durationSummary, "Duration unavailable")
        XCTAssertEqual(try report([]).durationSummary, "Duration unavailable")

        let partial = try report([short, missing, short, timed("future", 120, days: -1)])
        XCTAssertEqual(partial.durationSeconds, 45)
        XCTAssertEqual(partial.timedSessionCount, 1)
        XCTAssertEqual(partial.durationSummary, Duration.seconds(45).formattedWorkoutTime + " recorded · 1 of 2 sessions timed")

        let full = try report([short, timed("longer", 3_555), timed("zero", 0)])
        XCTAssertEqual(full.durationSeconds, 3_600)
        XCTAssertEqual(full.timedSessionCount, 3)
        XCTAssertEqual(full.durationSummary, Duration.seconds(3_600).formattedWorkoutTime + " recorded")
        XCTAssertEqual(try report([timed("zero", 0)]).durationSummary, Duration.zero.formattedWorkoutTime + " recorded")
        XCTAssertEqual(try report([timed("fraction", 0.25)]).durationSummary, "<1 sec recorded")
        XCTAssertEqual(try report([timed("boundary", 86_400)]).timedSessionCount, 1)
    }

    func testEarlierDurationSnapshotsRemainReadableWithoutInventingCoverage() throws {
        var session = log(exercise())
        for seconds in [0.0, 120.0] {
            session.elapsedSeconds = seconds
            let report = try WorkoutOutcomeReportDocument(logs: [session], scope: .init(), now: now)
            let data = try JSONEncoder().encode(report)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var performance = try XCTUnwrap(json["performance"] as? [String: Any])
            performance.removeValue(forKey: "timedSessionCount")
            json["performance"] = performance
            let legacy = try JSONDecoder().decode(WorkoutOutcomeReportDocument.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(legacy.performance.timedSessionCount)
            XCTAssertEqual(legacy.performance.fingerprint, report.performance.fingerprint)
            XCTAssertEqual(legacy.performance.durationSummary, seconds == 0 ? "Duration unavailable" :
                            Duration.seconds(seconds).formattedWorkoutTime + " recorded · timing coverage unknown")
        }
    }

    func testStrengthComparisonCountsMatchingSetsAndDistinctDaysAtTheSameCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let clock = ISO8601DateFormatter()
        let cutoff = try XCTUnwrap(clock.date(from: "2026-11-02T15:00:00-05:00"))
        let start = try XCTUnwrap(clock.date(from: "2026-10-27T00:00:00-04:00"))
        let scope = WorkoutReportScope(startDate: start, endDate: cutoff.addingTimeInterval(3600),
                                       setupKey: WorkoutEvidenceReportRules.setupKey(exercise()))
        func session(_ id: String, _ timestamp: String) throws -> WorkoutSessionLog {
            var session = log(exercise(), id: id)
            session.date = try XCTUnwrap(clock.date(from: timestamp))
            return session
        }
        let first = try session("first", "2026-11-01T08:00:00-05:00")
        let second = try session("second", "2026-11-01T09:00:00-05:00")
        let previous = try session("previous", "2026-10-26T15:00:00-04:00")
        let later = try session("after-cutoff", "2026-10-26T15:01:00-04:00")
        var other = second
        other.id = "other"
        other.completedExercises = log(exercise(.assistance)).completedExercises
        let comparison = try XCTUnwrap(StrengthPeriodComparison.make(logs: [first, first, second, previous, later, other],
                                                                      scope: scope, now: cutoff, calendar: calendar))
        XCTAssertEqual(comparison.current.workingSets, 6)
        XCTAssertEqual(comparison.current.trainingDays, 1)
        XCTAssertEqual(comparison.previous.workingSets, 3)
        XCTAssertEqual(comparison.previous.trainingDays, 1)
        XCTAssertEqual(comparison.previous.dates.upperBound, previous.date)
        XCTAssertTrue(comparison.includesPartialDay)
        XCTAssertNil(StrengthPeriodComparison.make(logs: [first], scope: .init(), now: cutoff))
    }

    private func program(progress: Int = 0) throws -> WorkoutProgram {
        var value = WorkoutProgram(id: "program", userID: "owner", name: "PHUL", dateCreated: now,
            routines: [WorkoutRoutine(id: "routine", userID: "owner", name: "Upper", dateCreated: now, exercises: [exercise()])],
            startDate: now, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: progress, skippedIndices: [2, 9])
        value.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: value)
        return value
    }
    func testLinearPolicyIncreasesAfterSupportedFloorWhileDoubleBuildsReps() throws {
        let double = exercise()
        let doublePlan = try XCTUnwrap(ProgressionRules.plan(for: double, history: [log(double, reps: 8)], now: now))
        XCTAssertEqual(doublePlan.move, .addRep)
        let linear = exercise(policy: .linear)
        let plan = try XCTUnwrap(ProgressionRules.plan(for: linear, history: [log(linear, reps: 8)], now: now))
        XCTAssertEqual(plan.move, .addWeight); XCTAssertEqual(plan.targets.first?.weight, 105)
        XCTAssertEqual(plan.policy?.version, 1); XCTAssertEqual(plan.evidenceSessionIDs, ["log"])
    }
    func testAssistanceImprovementDecreasesAssistanceAndLighterIncreasesIt() throws {
        let value = exercise(.assistance, policy: .assistance)
        let plan = try XCTUnwrap(ProgressionRules.plan(for: value, history: [log(value, weight: 55)], now: now))
        XCTAssertEqual(plan.targets.first?.weight, 50)
        let lighter = try XCTUnwrap(ProgressionRules.plan(for: value, history: [log(value, weight: 55)], lighterSession: true, now: now))
        XCTAssertEqual(lighter.targets.first?.weight, 60)
        XCTAssertEqual(WorkoutSetMath.volume(try XCTUnwrap(log(value).completedExercises.first)), 0)
        XCTAssertNil(WorkoutSetMath.bestSet(try XCTUnwrap(log(value).completedExercises.first)))
        var unknown = value; unknown.progressionPolicy = nil
        XCTAssertNil(ProgressionRules.plan(for: unknown, history: [log(unknown)], now: now))
    }
    func testBodyweightOnlyNeverInventsExternalLoad() throws {
        let value = exercise(.bodyweightOnly, policy: .bodyweight)
        let plan = try XCTUnwrap(ProgressionRules.plan(for: value, history: [log(value, reps: 8, weight: 0)], now: now))
        XCTAssertTrue(plan.targets.allSatisfy { $0.weight == 0 && $0.reps == 9 })
    }
    func testExplicitPercentagePolicyUsesReferenceWithoutHistoryAndStalePolicyCannotApply() throws {
        var value = exercise(policy: .percentage)
        for index in value.sets.indices { value.sets[index].prescription = WorkoutPrescription(kind: .repetitions, lowerBound: 8,
            loadPercentage: 50, loadReference: .init(label: "Reviewed reference", weightPounds: 200, date: now)) }
        let plan = try XCTUnwrap(ProgressionRules.plan(for: value, history: [], now: now))
        XCTAssertEqual(plan.sessionCount, 0); XCTAssertEqual(plan.targets.first?.weight, 100)
        var changed = value; changed.progressionPolicy = WorkoutProgressionPolicy(kind: .linear)
        XCTAssertEqual(ProgressionRules.applying(plan, to: changed).sets.map(\.weight), changed.sets.map(\.weight))
    }
    func testIdentitySurvivesRenameAndDoesNotMergeUnknownOrDifferentVariant() {
        var value = exercise(); var renamed = value; renamed.name = "My press"
        XCTAssertTrue(WorkoutMovementCatalog.matches(value, renamed))
        renamed.movementIdentity?.variantID = "smith"
        XCTAssertFalse(WorkoutMovementCatalog.matches(value, renamed))
        renamed = value; renamed.movementIdentity = nil
        XCTAssertFalse(WorkoutMovementCatalog.matches(value, renamed))
        value.movementIdentity = nil
        XCTAssertTrue(WorkoutMovementCatalog.matches(value, renamed))
    }
    func testDeloadOnlyChangesReviewedFutureWeekAndKeepsReturnAndProgress() throws {
        let source = try program(progress: 39)
        let sourceData = try JSONEncoder().encode(source)
        let returnBefore = try WorkoutBlockRules.fingerprint(source.routine(forSlot: 44))
        let review = try WorkoutDeloadRules.review(program: source, week: 10)
        var updated = source; updated.trainingBlock = try WorkoutDeloadRules.applying(review, to: source)
        XCTAssertEqual(updated.currentProgressIndex, 39); XCTAssertEqual(updated.skippedIndices, source.skippedIndices)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(updated.routine(forSlot: 44)), returnBefore)
        XCTAssertEqual(updated.trainingBlock?.weeks[10].isDeload, true)
        XCTAssertEqual(review.returnWeekName, source.trainingBlock?.weeks[11].name)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(source), try WorkoutBlockRules.fingerprint(JSONDecoder().decode(WorkoutProgram.self, from: sourceData)))
        XCTAssertThrowsError(try WorkoutDeloadRules.review(program: source, week: 9))
        XCTAssertThrowsError(try WorkoutDeloadRules.review(program: source, week: 10, protectedSlots: [40]))
    }
    func testDateOnlyMoveSurvivesTimezoneAndRejectsActiveOrPassedSlots() throws {
        let source = try program(progress: 39)
        let date = now.addingTimeInterval(14 * 86_400)
        let review = try WorkoutScheduleReviewRules.review(program: source, slot: 40, date: date, now: now)
        var updated = source; updated.trainingBlock = try WorkoutScheduleReviewRules.applying(review, to: source, now: now)
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        var tokyo = ny; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(ny.component(.day, from: try XCTUnwrap(updated.date(forSlot: 40, calendar: ny))), tokyo.component(.day, from: try XCTUnwrap(updated.date(forSlot: 40, calendar: tokyo))))
        XCTAssertThrowsError(try WorkoutScheduleReviewRules.review(program: source, slot: 38, date: date, now: now))
        XCTAssertThrowsError(try WorkoutScheduleReviewRules.review(program: source, slot: 40, date: date, protectedSlots: [40], now: now))
    }
    func testScheduleMoveReportsStrengthAndRunCollisionsWithoutSilentlySkipping() throws {
        let source = try program()
        let date = try XCTUnwrap(source.date(forSlot: 1))
        let run = TrainingRunCommitment(date: date, plan: RunWorkoutPlan.builtinTemplates(metric: true)[1])
        let review = try WorkoutScheduleReviewRules.review(program: source, slot: 0, date: date, runCommitments: [run], now: now)
        XCTAssertEqual(review.collisions.count, 2)
        let block = try WorkoutScheduleReviewRules.applying(review, to: source, now: now)
        XCTAssertEqual(block.scheduleExceptions?.first?.slotIndex, 0)
    }
    func testExplicitGroupOrderRestAndRepairKeepOtherSlotsIntact() throws {
        let first = exercise(); var second = first; second.id = "second"; var other = first; other.id = "other"
        let group = WorkoutExerciseGroup(memberSlotIDs: [second.id, first.id], transitionRestSeconds: [second.id: 15, first.id: 90])
        let result = try WorkoutExerciseGroupRules.applying(group, to: [first, other, second])
        XCTAssertEqual(result.map(\.id), [second.id, first.id, other.id])
        XCTAssertEqual(result[0].groupPlan?.transitionRestSeconds[second.id], 15)
        let repaired = WorkoutExerciseGroupRules.repairing(result.filter { $0.id != first.id })
        XCTAssertNil(repaired.first?.groupPlan); XCTAssertEqual(repaired.last?.id, other.id)
    }
    func testScopedReportUsesAllEvidenceAndSeparatesAssistanceAndFutureCorrections() throws {
        let value = exercise()
        var logs = (1...60).map { log(value, days: $0, id: "l\($0)") }
        logs.append(log(value, weight: 999, days: -1, id: "future"))
        let assisted = exercise(.assistance, policy: .assistance)
        logs.append(log(assisted, weight: 50, id: "assisted"))
        let snapshot = try WorkoutEvidenceReportRules.snapshot(logs: logs, scope: WorkoutReportScope(), now: now)
        XCTAssertEqual(snapshot.sessionIDs.count, 61); XCTAssertEqual(snapshot.setups.count, 2)
        XCTAssertNil(snapshot.setups.first { $0.id == WorkoutEvidenceReportRules.setupKey(assisted) }?.recordedVolume)
        let points = WorkoutEvidenceReportRules.points(logs: logs, scope: WorkoutReportScope(), setup: WorkoutEvidenceReportRules.setupKey(value), metric: .load, now: now)
        XCTAssertEqual(points.count, 60); XCTAssertFalse(points.contains { $0.value == 999 })
        var corrected = logs; corrected[0].correctionRevisionID = "corrected"
        XCTAssertNotEqual(snapshot.fingerprint, try WorkoutEvidenceReportRules.snapshot(logs: corrected, scope: WorkoutReportScope(), now: now).fingerprint)
    }
    func testMergeRequiresExplicitConflictingFieldChoiceAndRetainsNonconflictingSavedField() throws {
        var baseline = try program(); baseline.trainingBlock = nil
        var mine = baseline; mine.name = "Mine"
        var remote = baseline; remote.name = "Saved"; remote.currentProgressIndex = 12; remote.daysOfWeek = [2, 4, 6]
        let review = try WorkoutProgramMergeRules.review(baseline: baseline, local: mine, saved: remote)
        XCTAssertEqual(review.conflicts.map(\.id), ["name"])
        XCTAssertThrowsError(try WorkoutProgramMergeRules.resolving(review, choices: [:], latest: remote))
        let resolved = try WorkoutProgramMergeRules.resolving(review, choices: ["name": .mine], latest: remote)
        XCTAssertEqual(resolved.name, "Mine"); XCTAssertEqual(resolved.daysOfWeek, [2, 4, 6]); XCTAssertEqual(resolved.currentProgressIndex, 12)
    }
    func testCheckedEditReceiptsSurviveLostAckLaterEditDeleteAndFenceCancellation() async throws {
        var baseline = try program(); baseline.trainingBlock = nil
        var edited = baseline; edited.name = "Edited"
        let command = try WorkoutProgramEditCommand(expected: baseline, proposed: edited)
        let repository = MockWorkoutRepository(); repository.mockSaveProgramResult = baseline
        repository.programEditFailureAfterCommit = WorkoutBlockError.unavailable
        do { _ = try await repository.commitProgramEdit(userID: "owner", command: command); XCTFail("Expected lost acknowledgement") } catch {}
        repository.programEditFailureAfterCommit = nil
        var later = edited; later.name = "Later"; later.currentProgressIndex = 39
        repository.committedBlockPrograms = [later]
        let replay = try await repository.commitProgramEdit(userID: "owner", command: command)
        XCTAssertEqual(replay?.name, "Later")
        repository.deletedProgramIDs.append("program")
        if case .accepted(let missing) = try await repository.resolveProgramEdit(userID: "owner", command: command, cancelPending: true) { XCTAssertNil(missing) } else { XCTFail("Permanent acceptance expected") }
        let fresh = try WorkoutProgramEditCommand(expected: baseline, proposed: edited)
        _ = try await repository.resolveProgramEdit(userID: "owner", command: fresh, cancelPending: true)
        do { _ = try await repository.commitProgramEdit(userID: "owner", command: fresh); XCTFail("Cancelled save cannot apply") } catch {}
        var different = edited; different.name = "Other payload"
        let reused = try WorkoutProgramEditCommand(expected: baseline, proposed: different, id: command.id)
        do { _ = try await repository.resolveProgramEdit(userID: "owner", command: reused, cancelPending: false); XCTFail("ID reuse must fail") } catch {}
    }
    func testActualGymProposalRejectsUnmappedEquipmentAndCopiesSnapshots() throws {
        let setup = StrengthGymImplement(id: "rack", name: "My rack", equipment: StrengthEquipment(loadingMeaning: .total, availableWeights: [45, 95, 100]))
        let gym = StrengthGymProfile(name: "Home", implements: [setup])
        let source = try program()
        var request = WorkoutAIRequestSnapshot(goal: "Strength", daysPerWeek: 4, maximumSessionMinutes: 90,
            experience: "Intermediate", equipmentClass: "Full Gym", details: "", gym: gym, movementMappings: [:], startDate: now, weekdays: [2, 3, 5, 6])
        XCTAssertThrowsError(try WorkoutAIProposal(ownerID: "owner", request: request).validatedProgram(source))
        request.movementMappings = ["Barbell Bench Press": "rack"]
        let checked = try WorkoutAIProposal(ownerID: "owner", request: request).validatedProgram(source)
        XCTAssertEqual(checked.routines.first?.exercises.first?.loadEquipment?.gymProfile?.revisionID, gym.revisionID)
        XCTAssertNil(source.routines.first?.exercises.first?.loadEquipment?.gymProfile)
    }
    func testEveryCatalogEntryHasExplicitVersionAndPreservesUserCopies() throws {
        let catalog = WorkoutRules.generatePreBuiltPrograms()
        XCTAssertEqual(catalog.count, 27)
        for source in catalog {
            XCTAssertEqual(source.catalogRelease?.version, 2, source.name)
            XCTAssertTrue(source.catalogRelease?.fidelity.contains("adapted") == true, source.name)
            let adopted = WorkoutRules.preparePreBuiltProgramForUser(source, userID: "owner", startDate: now)
            XCTAssertEqual(adopted.currentProgressIndex, 0)
            XCTAssertNotNil(adopted.trainingBlock, source.name)
            try WorkoutBlockRules.validate(adopted)
        }
    }
    func testHoldTimerRecoversElapsedSegmentsWithoutCountingPauseOrDuplicatingCompletion() throws {
        var timer = WorkoutIntervalTimerState(setID: "hold", targetSeconds: 90)
        try timer.start(at: now)
        try timer.pause(at: now.addingTimeInterval(30))
        XCTAssertEqual(timer.elapsed(at: now.addingTimeInterval(500)), 30)
        timer = try JSONDecoder().decode(WorkoutIntervalTimerState.self, from: JSONEncoder().encode(timer))
        try timer.start(at: now.addingTimeInterval(600))
        XCTAssertEqual(try timer.complete(at: now.addingTimeInterval(660)), 90)
        XCTAssertEqual(try timer.complete(at: now.addingTimeInterval(900)), 90)
        XCTAssertNil(timer.runningSince)
    }
    func testRemovingUnfinishedRetainsEveryRecordedSetAndConditionalUndoProtectsLaterWork() throws {
        var source = exercise(); source.sets[0].isCompleted = true; source.sets[0].weight = 185; source.sets[0].reps = 8
        let review = try WorkoutSessionAdaptationRules.removingUnfinished(exerciseID: source.id, from: [source])
        let after = try WorkoutSessionAdaptationRules.applying(review, to: [source])
        XCTAssertEqual(after.first?.sets.map(\.id), ["s0"])
        XCTAssertEqual(after.first?.sets.first?.weight, 185)
        XCTAssertEqual(after.first?.sets.first?.reps, 8)
        let restored = try WorkoutSessionAdaptationRules.undo(review, in: after)
        XCTAssertEqual(restored.first?.sets.count, 3)
        var later = after; later[0].sets[0].weight = 190
        XCTAssertThrowsError(try WorkoutSessionAdaptationRules.undo(review, in: later))
    }
    func testShorteningKeepsWarmupsPriorityAndPerformedRows() throws {
        var source = (0..<4).map { index -> RoutineExercise in var value = exercise(); value.id = "lift-\(index)"; return value }
        let warmup = ExerciseSet(id: "warmup", target: "5", isWarmup: true)
        source[0].sets.insert(warmup, at: 0); source[0].sets[1].isCompleted = true
        let review = try WorkoutSessionAdaptationRules.shortening(source, toMinutes: 10, protectedMovementIDs: ["lift-0", "lift-1"])
        let after = try WorkoutSessionAdaptationRules.applying(review, to: source)
        XCTAssertTrue(after.flatMap(\.sets).contains { $0.id == "warmup" && $0.isWarmup })
        XCTAssertTrue(after[0].sets.contains { $0.isCompleted })
        for id in ["lift-0", "lift-1"] { XCTAssertTrue(after.first { $0.id == id }?.sets.contains { !$0.isCompleted && $0.resolvedSetType == .normal } == true) }
        XCTAssertLessThanOrEqual(review.afterMinutes, 10)
    }
    func testQuickSwapLeavesUnconfiguredLoadManualAndPreservesRecordedSetsThroughUndo() throws {
        var source = exercise()
        source.sets[0].isCompleted = true
        source.sets[0].weight = 185
        let name = "Dumbbell Bench Press"
        let selection = ExercisePickerDraft(name: name, category: "Chest", type: .strength)
        var previous = RoutineExercise(name: name)
        previous.movementIdentity = WorkoutMovementCatalog.identity(for: name)
        let history = WorkoutSessionLog(id: "previous", date: Date().addingTimeInterval(-60), routineID: "day",
            completedExercises: [CompletedExercise(exerciseName: name, exercise: previous, sets: [CompletedSet(reps: 10, weight: 75)])])
        let edit = try WorkoutSessionAdaptationRules.swapping(exerciseID: source.id, to: selection, in: [source], history: [history])
        let after = try WorkoutSessionAdaptationRules.applying(edit, to: [source])
        XCTAssertEqual(after[0].sets.map(\.id), [source.sets[0].id])
        XCTAssertEqual(after[0].sets[0].weight, 185)
        XCTAssertEqual(after[1].movementIdentity, previous.movementIdentity)
        XCTAssertNil(after[1].loadEquipment)
        XCTAssertNil(ProgressionRules.performance(for: after[1], in: history))
        XCTAssertTrue(after[1].sets.allSatisfy { !$0.isCompleted && $0.weight == 0 })
        let restored = try WorkoutSessionAdaptationRules.undo(edit, in: after)
        XCTAssertEqual(try PlanFingerprint.make(restored), try PlanFingerprint.make([source]))
    }

    func testQuickSwapReusesOnlyAnUnambiguousSetupForTheSelectedMovement() throws {
        let source = exercise()
        let name = "Dumbbell Bench Press"
        let selection = ExercisePickerDraft(name: name, category: "Chest", type: .strength)
        var mapped = RoutineExercise(name: name)
        mapped.loadEquipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [20, 25])
        func swapped(in exercises: [RoutineExercise]) throws -> RoutineExercise {
            let edit = try WorkoutSessionAdaptationRules.swapping(exerciseID: source.id, to: selection, in: exercises, history: [])
            return try XCTUnwrap(WorkoutSessionAdaptationRules.applying(edit, to: exercises).first)
        }
        XCTAssertEqual(try swapped(in: [source, mapped]).loadEquipment, mapped.loadEquipment)
        var other = RoutineExercise(name: name)
        other.loadEquipment = StrengthEquipment(loadingMeaning: .total, availableWeights: [40, 50])
        XCTAssertNil(try swapped(in: [source, mapped, other]).loadEquipment)
        let same = ExercisePickerDraft(name: source.name, category: nil, type: source.type)
        XCTAssertThrowsError(try WorkoutSessionAdaptationRules.swapping(exerciseID: source.id, to: same, in: [source], history: []))
    }

    func testSubstitutionRetainsPerformedOriginalAndNeverCopiesTotalLoadToPerHand() throws {
        var original = exercise(); original.sets[0].isCompleted = true; original.sets[0].weight = 185; original.sets[0].reps = 8
        var replacement = RoutineExercise(name: "Dumbbell Bench Press")
        replacement.loadEquipment = StrengthEquipment(loadingMeaning: .perHand, availableWeights: [20, 25, 30])
        let review = try WorkoutSessionAdaptationRules.substituting(exerciseID: original.id, replacement: replacement, reason: .occupied, in: [original], now: now)
        let after = try WorkoutSessionAdaptationRules.applying(review, to: [original])
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[0].name, original.name); XCTAssertEqual(after[0].sets.first?.weight, 185)
        XCTAssertNotEqual(after[1].id, original.id)
        XCTAssertTrue(after[1].sets.allSatisfy { $0.weight == 0 && !$0.isCompleted })
        XCTAssertEqual(after[1].substitution?.originalSlotID, original.id)
        XCTAssertEqual(after[1].loadEquipment?.loadingMeaning, .perHand)
    }
    func testDayReuseIsDeepFutureOnlyAndRetainsProgramPosition() throws {
        let source = try program(progress: 39)
        let review = try WorkoutDayReuseRules.review(program: source, sourceSlot: 0, destinationSlot: 40, mode: .copy)
        var after = source; after.trainingBlock = try WorkoutDayReuseRules.applying(review, to: source)
        XCTAssertEqual(after.currentProgressIndex, 39); XCTAssertEqual(after.skippedIndices, source.skippedIndices)
        XCTAssertNotEqual(after.routine(forSlot: 40)?.exercises.first?.id, source.routine(forSlot: 0)?.exercises.first?.id)
        XCTAssertEqual(after.routine(forSlot: 40)?.exercises.first?.movementIdentity, source.routine(forSlot: 0)?.exercises.first?.movementIdentity)
        XCTAssertThrowsError(try WorkoutDayReuseRules.review(program: source, sourceSlot: 0, destinationSlot: 40, mode: .swap))
        XCTAssertThrowsError(try WorkoutDayReuseRules.review(program: source, sourceSlot: 40, destinationSlot: 44, mode: .swap, protectedSlots: [44]))
    }
    func testDeloadKeepsLinkedNormalReturnAndUndoRestoresOriginalUnchangedTargets() throws {
        var source = try program(progress: 39)
        source.trainingBlock?.schemaVersion = 2
        let sourceWeekID = source.trainingBlock?.weeks[10].id
        source.trainingBlock?.weeks[11].linkedSourceWeekID = sourceWeekID
        let before = try WorkoutBlockRules.fingerprint(source.routine(forSlot: 44))
        let review = try WorkoutDeloadRules.review(program: source, week: 10)
        XCTAssertLessThan(review.afterSets, review.beforeSets)
        var after = source; after.trainingBlock = try WorkoutDeloadRules.applying(review, to: source)
        XCTAssertEqual(after.routine(forSlot: 40)?.exercises.first?.sets.count, 2)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(after.routine(forSlot: 44)), before)
        after.trainingBlock = try JSONDecoder().decode(WorkoutProgramBlock.self, from: JSONEncoder().encode(try XCTUnwrap(after.trainingBlock)))
        let undone = try WorkoutDeloadRules.undo(in: after, week: 10)
        after.trainingBlock = undone
        XCTAssertEqual(after.routine(forSlot: 40)?.exercises.first?.sets.count, 3)
        XCTAssertEqual(after.trainingBlock?.weeks[11].linkedSourceWeekID, source.trainingBlock?.weeks[10].id)
        XCTAssertEqual(after.currentProgressIndex, 39)
    }
    func testOrderedRoundsRestAfterLastAvailablePartnerAndDeferralIsNotCompletion() throws {
        var first = exercise(); first.id = "a"; first.sets = [ExerciseSet(id: "a1", isCompleted: true, target: "8"), ExerciseSet(id: "a2", target: "8")]
        var second = exercise(); second.id = "b"; second.sets = [ExerciseSet(id: "b1", isCompleted: true, target: "8")]
        let group = WorkoutExerciseGroup(memberSlotIDs: ["a", "b"], transitionRestSeconds: ["a": 0, "b": 90])
        first.groupPlan = group; second.groupPlan = group
        XCTAssertEqual(WorkoutExerciseGroupRules.restAfterCompleting(setID: "a1", in: [first, second]), 90)
        second.sets[0].isCompleted = false; second.sets[0].isDeferred = true
        XCTAssertEqual(WorkoutSetNavigation.nextAfterDeferring(setID: "b1", in: [first, second])?.setID, "a2")
        XCTAssertFalse(second.sets[0].isCompleted)
        XCTAssertEqual(WorkoutSetNavigation.firstUnfinished(in: [second, first])?.setID, "a2")
    }
    func testStoredProtectedSlotAndCacheSetEncodingRemainStableAfterReload() throws {
        var source = try program(); source.trainingBlock = nil
        var proposed = source; proposed.name = "Edited"
        let command = try WorkoutProgramEditCommand(expected: source, proposed: proposed, protectedSlots: [7, 2, 100, 39])
        let reloaded = try JSONDecoder().decode(WorkoutProgramEditCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(try command.fingerprint(), try reloaded.fingerprint())
        let cache = WorkoutLibrarySnapshot(values: [source], unreadableIDs: ["z", "x", "a", "b"])
        let decoded = try JSONDecoder().decode(WorkoutLibrarySnapshot<WorkoutProgram>.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(try PlanFingerprint.make(cache), try PlanFingerprint.make(decoded))
    }

}
