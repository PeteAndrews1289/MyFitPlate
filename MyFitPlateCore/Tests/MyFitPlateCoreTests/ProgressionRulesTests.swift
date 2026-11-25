import XCTest
@testable import MyFitPlateCore

final class ProgressionRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testAuthoredPercentageOwnsLoadInsteadOfGenericProgression() throws {
        let plain = exercise()
        let previous = [log([12, 12, 12]), log([12, 12, 12], daysAgo: 9)]
        let oldPlan = try plan(previous)
        var prescribed = plain
        for index in prescribed.sets.indices {
            prescribed.sets[index].prescription = WorkoutPrescription(kind: .repetitions, lowerBound: 8, upperBound: 12,
                loadPercentage: 60, loadReference: .init(label: "Reviewed reference", weightPounds: 200, date: now))
        }
        XCTAssertNil(ProgressionRules.plan(for: prescribed, history: previous, now: now))
        XCTAssertNil(ProgressionRules.trend(for: prescribed, history: previous, now: now))
        let unchanged = ProgressionRules.applying(oldPlan, to: prescribed)
        XCTAssertEqual(unchanged.sets.map(\.weight), prescribed.sets.map(\.weight))
        XCTAssertEqual(unchanged.sets[0].prescription?.loadPercentage, 60)
    }

    func testChangedPrescribedEffortDoesNotQualifyOldCeilingAsSamePrescription() throws {
        var earlier = exercise()
        for index in earlier.sets.indices {
            earlier.sets[index].prescription = WorkoutPrescription(kind: .repetitions, lowerBound: 8, upperBound: 12,
                effort: SetEffort(scale: .rpe, value: 9))
        }
        var current = earlier
        for index in current.sets.indices { current.sets[index].prescription?.effort = SetEffort(scale: .rpe, value: 6) }
        let result = try plan([log([12, 12, 12], template: earlier), log([12, 12, 12], daysAgo: 9, template: earlier)], exercise: current)
        XCTAssertEqual(result.move, .hold)
        XCTAssertEqual(result.sessionCount, 1)
        XCTAssertTrue(result.rationale.contains("prescription has changed"))
    }

    func testReviewedProgressionCannotApplyAfterTargetBasisChanges() throws {
        let previous = [log([12, 12, 12])]
        let reviewed = try plan(previous)
        var changed = exercise()
        changed.sets[0].target = "3-5 reps"
        changed.sets[0].weight = 65
        let result = ProgressionRules.applying(reviewed, to: changed)
        XCTAssertEqual(result.sets[0].weight, 65)
        XCTAssertEqual(result.sets[0].target, "3-5 reps")
        XCTAssertEqual(result.sets[0].reps, changed.sets[0].reps)
    }

    private func exercise(reps: String = "8-12", count: Int = 3) -> RoutineExercise {
        RoutineExercise(id: "bench", name: "Bench press", sets: (0..<count).map {
            ExerciseSet(id: "set-\($0)", target: reps)
        }, targetSets: count, targetReps: reps)
    }

    private func log(_ reps: [Int], weight: Double = 100, effort: Double? = 7,
                     daysAgo: Int = 2, template: RoutineExercise? = nil, id: String? = nil) -> WorkoutSessionLog {
        let source = template ?? exercise()
        return WorkoutSessionLog(id: id ?? "session-\(daysAgo)", date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                                 routineID: "routine", completedExercises: [CompletedExercise(
                                    exerciseName: source.name, exercise: source,
                                    sets: reps.map { CompletedSet(reps: $0, weight: weight, effort: effort.map { SetEffort(scale: .rpe, value: $0) }) })])
    }

    private func plan(_ logs: [WorkoutSessionLog], exercise current: RoutineExercise? = nil,
                      increment: Double? = nil, lighter: Bool = false) throws -> ProgressionPlan {
        try XCTUnwrap(ProgressionRules.plan(for: current ?? exercise(), history: logs, increment: increment, lighterSession: lighter, now: now))
    }

    func testPlanDayContextKeepsPowerLoadsOutOfHypertrophyTargetsAndPreviousSets() throws {
        let volumeExercise = exercise()
        var powerExercise = exercise(reps: "3-5")
        powerExercise.id = "power-bench"
        var power = log([5, 5, 5], weight: 200, daysAgo: 1, template: powerExercise)
        power.routineID = "phul-power"
        var volume = log([12, 12, 12], weight: 100, daysAgo: 8, template: volumeExercise)
        volume.routineID = "phul-hypertrophy"
        let mixed = [power, volume]
        let context = ProgressionRules.history(for: volumeExercise, in: mixed, routineID: "phul-hypertrophy", now: now)
        XCTAssertEqual(context.map(\.routineID), ["phul-hypertrophy"])
        let previous = try XCTUnwrap(context.first.flatMap { ProgressionRules.performance(for: volumeExercise, in: $0) })
        XCTAssertEqual(ProgressionRules.previousSet(for: volumeExercise.sets[0].id, exercise: volumeExercise, previous: previous)?.weight, 100)
        let target = try XCTUnwrap(ProgressionRules.plan(for: volumeExercise, history: mixed, routineID: "phul-hypertrophy", now: now))
        XCTAssertEqual(target.move, .addWeight)
        XCTAssertEqual(target.targets.map(\.weight), [105, 105, 105])
        XCTAssertEqual(target.targets.map(\.reps), [8, 8, 8])
        XCTAssertNil(ProgressionRules.plan(for: volumeExercise, history: [power], routineID: "phul-hypertrophy", now: now))
        XCTAssertTrue(ProgressionRules.history(for: volumeExercise, in: [power], routineID: "phul-hypertrophy", now: now).isEmpty)
        XCTAssertEqual(ProgressionRules.history(for: volumeExercise, in: mixed, now: now).count, 2,
                       "Generic history callers still retain their complete exercise history")
    }

    func testPlanDayContextPreservesComparableTrendDespiteInterleavedPowerSessions() throws {
        let volumeExercise = exercise()
        var powerExercise = exercise(reps: "3-5")
        powerExercise.id = "power-bench"
        let volumeHistory = [1, 8, 15, 22].map { day -> WorkoutSessionLog in
            var session = log([10, 10, 10], weight: day < 15 ? 110 : 100, daysAgo: day, template: volumeExercise)
            session.routineID = "phul-hypertrophy"
            return session
        }
        var power = log([5, 5, 5], weight: 200, daysAgo: 3, template: powerExercise)
        power.routineID = "phul-power"
        let mixed = volumeHistory + [power]
        let trend = try XCTUnwrap(ProgressionRules.trend(for: volumeExercise, history: mixed, routineID: "phul-hypertrophy", now: now))
        XCTAssertEqual(trend.direction, .improving)
        XCTAssertEqual(trend.sessionCount, 4)
        let plan = try XCTUnwrap(ProgressionRules.plan(for: volumeExercise, history: mixed, routineID: "phul-hypertrophy", now: now))
        XCTAssertEqual(plan.trend, trend, "Target review and trend must use the same routine context")
    }

    func testLongTermTrendRequiresFourComparableSessionsAcrossTwoWeeks() throws {
        let rising = [log([10, 10, 10], weight: 110, daysAgo: 1), log([9, 9, 9], weight: 110, daysAgo: 8),
                      log([10, 10, 10], daysAgo: 15), log([9, 9, 9], daysAgo: 22)]
        let trend = try XCTUnwrap(try plan(rising).trend)
        XCTAssertEqual(trend.direction, .improving)
        XCTAssertEqual(trend.sessionCount, 4)
        XCTAssertFalse(trend.reviewLighterWeek)
        XCTAssertNil(try plan(Array(rising.prefix(3))).trend)
        XCTAssertNil(try plan([log([10, 10, 10], daysAgo: 1), log([10, 10, 10], daysAgo: 2),
                              log([10, 10, 10], daysAgo: 3), log([10, 10, 10], daysAgo: 4)]).trend)
    }
    func testSustainedHardPlateauSuggestsReviewButNeverRewritesTargetsOrProgram() throws {
        let logs = [1, 8, 15, 22].map { log([10, 10, 10], effort: 9, daysAgo: $0) }
        let result = try plan(logs)
        XCTAssertEqual(result.trend?.direction, .steady)
        XCTAssertEqual(result.trend?.reviewLighterWeek, true)
        XCTAssertEqual(result.move, .hold)
        XCTAssertEqual(result.targets.map(\.weight), [100, 100, 100])
    }
    func testLongTermTrendResetsForPrescriptionChangesIncompleteWorkOrLongBreak() throws {
        let stable = [log([10, 10, 10], daysAgo: 1), log([10, 10, 10], daysAgo: 8), log([10, 10, 10], daysAgo: 15)]
        XCTAssertNil(try plan(stable + [log([10, 10], daysAgo: 22)]).trend)
        XCTAssertNil(try plan(stable + [log([10, 10, 10], daysAgo: 50)]).trend)
        XCTAssertNil(try plan(stable + [log([10, 10, 10], daysAgo: 22, template: exercise(reps: "5-8"))]).trend)
        XCTAssertNil(try plan(stable + [stable[2]]).trend)
    }

    func testNoHistoryOrUnsupportedTargetsDoNotInventTargets() {
        XCTAssertNil(ProgressionRules.plan(for: exercise(), history: [], now: now))
        for target in ["AMRAP", "30 seconds", "3 x 8", "12-8", "0", "101", "8-12-15", ""] {
            XCTAssertNil(ProgressionRules.plan(for: exercise(reps: target), history: [log([12, 12, 12])], now: now), target)
        }
        XCTAssertEqual(ProgressionRules.repRange(" 8 – 12 "), 8...12)
        XCTAssertEqual(ProgressionRules.repRange("5"), 5...5)
        XCTAssertEqual(ProgressionRules.repRange("10–12 reps"), 10...12)
        XCTAssertEqual(ProgressionRules.repRange("8 reps / side"), 8...8)
        XCTAssertNil(ProgressionRules.repRange("10 reps @ light"))
        XCTAssertNil(ProgressionRules.repRange("5+ reps"))
        XCTAssertNil(ProgressionRules.repRange("5/3/1 reps"))
        XCTAssertEqual(ProgressionRules.targetRepsLowEnd("AMRAP"), 0)
    }

    func testRealPrebuiltPlansCanProduceTargetsWithoutChangingTheirPrescription() throws {
        let programs = WorkoutRules.generatePreBuiltPrograms().filter {
            $0.name.localizedCaseInsensitiveContains("PHUL") || $0.id == "prebuilt_dumbbell_hypertrophy_4_day"
        }
        XCTAssertGreaterThanOrEqual(programs.count, 2)
        for current in programs.flatMap(\.routines).flatMap(\.exercises) where current.type == .strength {
            if current.sets.contains(where: { ($0.target ?? "").contains("sec") }) {
                XCTAssertNil(ProgressionRules.plan(for: current, history: [log([12, 12, 12], template: current)], now: now), "Timed carries should stay manual")
                continue
            }
            let repCounts = try current.sets.map { try XCTUnwrap(ProgressionRules.repRange($0.target ?? current.targetReps)).upperBound }
            let suggestion = try plan([log(repCounts, template: current)], exercise: current)
            XCTAssertEqual(suggestion.targets.count, current.sets.count, current.name)
            let updated = ProgressionRules.applying(suggestion, to: current)
            XCTAssertEqual(updated.sets.map(\.target), current.sets.map(\.target), current.name)
        }
    }

    func testAllSetsMustReachTheCeilingBeforeAddingLoad() throws {
        let building = try plan([log([12, 10, 8])])
        XCTAssertEqual(building.move, .addRep)
        XCTAssertEqual(building.targets.map(\.reps), [12, 11, 9])
        XCTAssertEqual(building.targets.map(\.weight), [100, 100, 100])
        let increase = try plan([log([12, 12, 12])], increment: 2.5)
        XCTAssertEqual(increase.move, .addWeight)
        XCTAssertEqual(increase.targets.map(\.weight), [102.5, 102.5, 102.5])
        XCTAssertEqual(increase.targets.map(\.reps), [8, 8, 8])
    }

    func testStrongTopSetCannotHideMissedRepsOnLaterSets() throws {
        let suggestion = try plan([log([12, 9, 6])])
        XCTAssertEqual(suggestion.move, .hold)
        XCTAssertEqual(suggestion.targets.map(\.weight), [100, 100, 100])
        XCTAssertEqual(suggestion.targets.map(\.reps), [12, 9, 8])
    }

    func testMissingEffortRequiresTwoComparableSuccessfulSessions() throws {
        XCTAssertEqual(try plan([log([12, 12, 12], effort: nil)]).move, .hold)
        XCTAssertEqual(try plan([log([12, 12, 12], effort: nil), log([12, 12, 12], effort: nil, daysAgo: 5)]).move, .addWeight)
        XCTAssertEqual(try plan([log([12, 12, 12], effort: nil), log([12, 12, 12], weight: 95, effort: nil, daysAgo: 5)]).move, .hold)
        var legacy = log([12, 12, 12], effort: nil)
        legacy.id = nil
        XCTAssertEqual(try plan([legacy, legacy]).move, .hold, "A duplicate legacy session is not two independent observations")
    }

    func testPreBreakSuccessCannotConfirmARecentUnratedSession() throws {
        let recent = log([12, 12, 12], effort: nil)
        let preBreak = log([12, 12, 12], effort: nil, daysAgo: 30)
        let suggestion = try plan([recent, preBreak])
        XCTAssertEqual(suggestion.move, .hold)
        XCTAssertEqual(suggestion.targets.map(\.weight), [100, 100, 100])
        XCTAssertEqual(suggestion.targets.map(\.reps), [12, 12, 12])
        XCTAssertEqual(suggestion.headline, "Confirm this performance")
        XCTAssertEqual(suggestion.sessionCount, 1, "The review must not describe pre-break evidence as a recent session")

        let independentlyRated = try plan([log([12, 12, 12]), preBreak])
        XCTAssertEqual(independentlyRated.move, .addWeight,
                       "A recent complete session with low effort remains enough evidence on its own")
    }

    func testRepeatedMissResetsAfterABreakAndRecentContinuousEvidenceStillCounts() throws {
        let recent = log([7, 6, 5])
        let preBreak = log([7, 7, 6], daysAgo: 30)
        let suggestion = try plan([recent, preBreak])
        XCTAssertEqual(suggestion.move, .hold)
        XCTAssertEqual(suggestion.targets.map(\.weight), [100, 100, 100])

        let continuous = try plan([recent, log([7, 7, 6], daysAgo: 23)])
        XCTAssertEqual(continuous.move, .easeBack, "The existing 21-day continuity boundary is inclusive")
        XCTAssertEqual(continuous.targets.map(\.weight), [90, 90, 90])
        XCTAssertEqual(continuous.sessionCount, 2)
        XCTAssertEqual(try plan([recent, log([7, 7, 6], daysAgo: 24)]).move, .hold)
    }

    func testMalformedOlderWorkingSetCannotBeDiscardedToConfirmProgression() throws {
        let recent = log([12, 12, 12], effort: nil)
        var malformed = log([12, 12, 12], effort: nil, daysAgo: 5)
        malformed.completedExercises[0].sets.append(CompletedSet(reps: 0, weight: 100))
        let originalIDs = malformed.completedExercises[0].sets.map(\.id)
        let originalReps = malformed.completedExercises[0].sets.map(\.reps)
        let suggestion = try plan([recent, malformed])
        XCTAssertEqual(suggestion.move, .hold)
        XCTAssertEqual(suggestion.targets.map(\.weight), [100, 100, 100])
        XCTAssertEqual(suggestion.sessionCount, 1)
        XCTAssertEqual(malformed.completedExercises[0].sets.map(\.id), originalIDs)
        XCTAssertEqual(malformed.completedExercises[0].sets.map(\.reps), originalReps,
                       "Invalid evidence is excluded, never cleaned up by changing recorded history")
        XCTAssertEqual(try plan([recent, log([12, 12], effort: nil, daysAgo: 5)]).move, .hold)
    }

    func testNearMaxEffortOnAnySetHoldsIncludingRIR() throws {
        var previous = log([12, 12, 12])
        previous.completedExercises[0].sets[2].effort = SetEffort(scale: .rir, value: 0)
        XCTAssertEqual(try plan([previous]).move, .hold)
    }

    func testIncompleteSessionAndChangedPrescriptionCannotIncreaseLoad() throws {
        XCTAssertEqual(try plan([log([12, 12])]).move, .hold)
        XCTAssertEqual(try plan([log([12, 12, 12])], exercise: exercise(reps: "4-6")).move, .hold)
        XCTAssertEqual(try plan([log([12, 12, 12])], exercise: exercise(count: 4)).move, .hold)
    }

    func testTwoComparableMissesOfferLighterLoads() throws {
        let lighter = try plan([log([7, 6, 5]), log([7, 7, 6], daysAgo: 5)])
        XCTAssertEqual(lighter.move, .easeBack)
        XCTAssertEqual(lighter.targets.map(\.weight), [90, 90, 90])
        XCTAssertEqual(try plan([log([7, 6, 5]), log([7, 7, 6], weight: 95, daysAgo: 5)]).move, .hold)
    }

    func testLongBreakAndExplicitLighterSessionOfferReviewableReduction() throws {
        XCTAssertEqual(try plan([log([12, 12, 12], daysAgo: 30)]).move, .easeBack)
        let lighter = try plan([log([12, 12, 12])], increment: 2.5, lighter: true)
        XCTAssertEqual(lighter.move, .easeBack)
        XCTAssertEqual(lighter.targets.map(\.weight), [90, 90, 90])
    }

    func testBodyweightDoesNotAcquireExternalWeightAutomatically() throws {
        let bodyweight = try plan([log([12, 12, 12], weight: 0)])
        XCTAssertEqual(bodyweight.move, .hold)
        XCTAssertEqual(bodyweight.targets.map(\.weight), [0, 0, 0])
        XCTAssertEqual(try plan([log([9, 8, 8], weight: 0)]).targets.map(\.reps), [10, 9, 9])
    }

    func testWarmupDropAndFailureSetsDoNotBecomeProgressionTargets() throws {
        var current = exercise()
        current.sets.insert(ExerciseSet(id: "warmup", isWarmup: true, reps: 5, weight: 50), at: 0)
        current.sets.append(ExerciseSet(id: "drop", setType: .drop, reps: 15, weight: 80))
        current.sets.append(ExerciseSet(id: "failure", setType: .failure, reps: 3, weight: 200))
        var previous = log([12, 12, 12], template: current)
        previous.completedExercises[0].sets.insert(CompletedSet(reps: 2, weight: 300, setType: .warmup), at: 0)
        previous.completedExercises[0].sets.append(CompletedSet(reps: 3, weight: 200, setType: .failure))
        let suggestion = try plan([previous], exercise: current)
        XCTAssertEqual(suggestion.move, .addWeight)
        XCTAssertEqual(suggestion.targets.map(\.id), ["set-0", "set-1", "set-2"])
        XCTAssertEqual(suggestion.targets.map(\.setNumber), [2, 3, 4])
        let applied = ProgressionRules.applying(suggestion, to: current)
        XCTAssertEqual(applied.sets.first?.weight, 50)
        XCTAssertEqual(applied.sets.last?.weight, 200)
    }

    func testPerSetRepRangesAndDifferentWorkingWeightsArePreserved() throws {
        var current = exercise()
        current.sets[0].target = "4-6"
        var previous = log([6, 12, 12], template: current)
        previous.completedExercises[0].sets[0].weight = 120
        let suggestion = try plan([previous], exercise: current)
        XCTAssertEqual(suggestion.targets.map(\.weight), [125, 105, 105])
        XCTAssertEqual(suggestion.targets.map(\.reps), [4, 8, 8])
    }

    func testHistorySortsDeduplicatesAndNeverUsesAnotherExerciseOrFutureSession() throws {
        var other = exercise()
        other.name = "Dumbbell bench"
        let older = log([12, 12, 12], daysAgo: 5)
        let latest = log([10, 9, 8])
        let logs = [older, log([12, 12, 12], daysAgo: -1), log([12, 12, 12], daysAgo: 1, template: other), latest, latest]
        let suggestion = try plan(logs)
        XCTAssertEqual(suggestion.sessionCount, 2)
        XCTAssertEqual(suggestion.targets.map(\.reps), [11, 10, 9])
        XCTAssertNil(ProgressionRules.plan(for: other, history: [older], now: now))
    }

    func testRepeatedExerciseNamesUseTheMatchingBlockAndRejectAmbiguousLegacyHistory() throws {
        let current = exercise()
        var otherBlock = exercise()
        otherBlock.id = "other-block"
        var session = log([12, 12, 12], weight: 300, template: otherBlock)
        session.completedExercises.append(log([9, 9, 9]).completedExercises[0])
        let suggestion = try plan([session])
        XCTAssertEqual(suggestion.targets.map(\.weight), [100, 100, 100])
        var imported = current
        imported.id = "new-imported-id"
        XCTAssertNil(ProgressionRules.plan(for: imported, history: [session], now: now))
    }

    func testIncrementPreferenceSurvivesHistoryAndCodableRoundTrip() throws {
        var previousTemplate = exercise()
        previousTemplate.progressionIncrement = 2.5
        let decoded = try JSONDecoder().decode(RoutineExercise.self, from: JSONEncoder().encode(previousTemplate))
        XCTAssertEqual(decoded.progressionIncrement, 2.5)
        let suggestion = try plan([log([12, 12, 12], template: decoded)])
        XCTAssertEqual(suggestion.increment, 2.5)
        XCTAssertEqual(suggestion.targets[0].weight, 102.5)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        legacy.removeValue(forKey: "progressionIncrement")
        XCTAssertNil(try JSONDecoder().decode(RoutineExercise.self, from: JSONSerialization.data(withJSONObject: legacy)).progressionIncrement)
    }

    func testApplyingTargetsKeepsCompletedWorkSetIDsAndPrescription() throws {
        var current = exercise()
        current.sets[0].isCompleted = true
        current.sets[0].weight = 95
        current.sets[0].reps = 11
        current.sets[1].effort = SetEffort(scale: .rpe, value: 8)
        var suggestion = try plan([log([12, 12, 12])], exercise: current)
        suggestion.targets[1].weight = 102.5
        let applied = ProgressionRules.applying(suggestion, to: current)
        XCTAssertEqual(applied.sets[0].weight, 95)
        XCTAssertEqual(applied.sets[0].reps, 11)
        XCTAssertEqual(applied.sets[1].weight, 102.5)
        XCTAssertEqual(applied.sets[1].effort, current.sets[1].effort)
        XCTAssertEqual(applied.sets.map(\.id), current.sets.map(\.id))
        XCTAssertEqual(applied.sets.map(\.target), current.sets.map(\.target))
        XCTAssertFalse(applied.sets[1].isCompleted)
    }

    func testUndoDoesNotOverwriteLaterEditsOrCompletedWork() throws {
        let before = exercise()
        let applied = ProgressionRules.applying(try plan([log([12, 12, 12])]), to: before)
        var current = applied
        current.sets[0].isCompleted = true
        current.sets[1].weight = 110
        current.notes = "Keep this note"
        let restored = ProgressionRules.undo(before: before, applied: applied, current: current)
        XCTAssertEqual(restored.sets[0].weight, 105)
        XCTAssertTrue(restored.sets[0].isCompleted)
        XCTAssertEqual(restored.sets[1].weight, 110)
        XCTAssertEqual(restored.sets[2].weight, 0)
        XCTAssertEqual(restored.notes, current.notes)
    }

    func testInvalidTargetsAndStaleSubstitutionCannotBeApplied() throws {
        let current = exercise()
        var suggestion = try plan([log([12, 12, 12])])
        var substituted = current
        substituted.name = "Dumbbell bench"
        XCTAssertEqual(ProgressionRules.applying(suggestion, to: substituted).sets[0].weight, 0)
        suggestion.targets[1].weight = .nan
        XCTAssertFalse(suggestion.isValid)
        XCTAssertEqual(ProgressionRules.applying(suggestion, to: current).sets[0].weight, 0)
        for increment in [0, -5, .infinity, .nan] {
            XCTAssertNil(ProgressionRules.plan(for: current, history: [log([12, 12, 12])], increment: increment, now: now))
        }
        XCTAssertNil(ProgressionRules.plan(for: current, history: [log([Int.max, 8, 8])], now: now))
        XCTAssertNil(ProgressionRules.plan(for: current, history: [log([12, 12, 12], weight: .nan)], now: now))
    }

    func testPreviousSetMatchingIgnoresInsertedWarmup() throws {
        var current = exercise()
        current.sets.insert(ExerciseSet(id: "new-warmup", isWarmup: true), at: 0)
        let previous = log([10, 9, 8]).completedExercises[0]
        XCTAssertNil(ProgressionRules.previousSet(for: "new-warmup", exercise: current, previous: previous))
        XCTAssertEqual(ProgressionRules.previousSet(for: "set-0", exercise: current, previous: previous)?.reps, 10)
        XCTAssertEqual(ProgressionRules.previousSet(for: "set-2", exercise: current, previous: previous)?.reps, 8)
    }
}
