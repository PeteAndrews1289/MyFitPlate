import Foundation

public struct ProgressionTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let setNumber: Int
    public var weight: Double
    public var reps: Int

    public var isValid: Bool {
        weight.isFinite && (0...10_000).contains(weight) && (1...100).contains(reps)
    }
}

public struct ProgressionPlan: Equatable, Sendable {
    public enum Move: String, Sendable { case addWeight, addRep, hold, easeBack }
    public let exerciseID: String
    public let exerciseName: String
    public let move: Move
    public let headline: String
    public let rationale: String
    public let sessionCount: Int
    public let increment: Double
    public var targets: [ProgressionTarget]
    public var trend: ProgressionTrend?
    public var loadEquipment: StrengthEquipment?
    public var prescriptionFingerprint: String?
    public var policy: WorkoutProgressionPolicy?
    public var evidenceSessionIDs: [String]?

    public var isValid: Bool {
        guard increment.isFinite, (0.25...100).contains(increment), !targets.isEmpty,
              targets.allSatisfy(\.isValid), Set(targets.map(\.id)).count == targets.count else { return false }
        guard let loadEquipment else { return true }
        guard loadEquipment.isValid else { return false }
        let loads = loadEquipment.attainableLoads
        return targets.allSatisfy { target in loads.contains { abs($0 - target.weight) < 0.01 } }
    }
}

public struct ProgressionTrend: Equatable, Sendable {
    public enum Direction: String, Sendable { case improving, steady, declining }
    public let direction: Direction
    public let sessionCount: Int
    public let days: Int
    public let reviewLighterWeek: Bool
    public var title: String {
        switch direction {
        case .improving: return "Building over time"
        case .steady: return "Holding steady"
        case .declining: return "Recent performance is lower"
        }
    }
    public var detail: String {
        "\(sessionCount) comparable sessions over \(days) days. " +
        (reviewLighterWeek ? "Recent sets also felt hard. Consider reviewing a lighter week in Rescue my week."
         : "Compared working-set loads and reps across the first and second halves of this period.")
    }
}

public enum ProgressionRules {
    /// Uses a continuous block of the same prescription. Changes, incomplete sessions,
    /// and long breaks reset the window rather than manufacturing a plateau.
    public static func trend(for exercise: RoutineExercise, history logs: [WorkoutSessionLog], routineID: String? = nil, now: Date = Date()) -> ProgressionTrend? {
        let slots = exercise.sets.filter { $0.resolvedSetType == .normal }
        let ranges = slots.compactMap { repRange($0.target ?? exercise.targetReps) }
        guard supportsGenericProgression(exercise), exercise.type == .strength, !ranges.isEmpty, ranges.count == slots.count else { return nil }
        var samples: [(date: Date, score: Double, hard: Bool)] = []
        var usesLoad: Bool?
        for log in history(for: exercise, in: logs, routineID: routineID, now: now).prefix(8) {
            guard now.timeIntervalSince(log.date) <= 90 * 86_400,
                  (samples.last?.date ?? now).timeIntervalSince(log.date) <= 21 * 86_400,
                  let result = performance(for: exercise, in: log) else { break }
            let sets = regularSets(result)
            let oldRanges = result.exercise.sets.filter { $0.resolvedSetType == .normal }
                .compactMap { repRange($0.target ?? result.exercise.targetReps) }
            guard sets.count == slots.count, oldRanges == ranges, prescriptionMatches(exercise, result.exercise),
                  result.sets.filter({ $0.resolvedSetType == .normal }).count == sets.count,
                  sets.allSatisfy({ $0.reps <= 30 }) else { break }
            let loaded = sets.allSatisfy { $0.weight > 0 }
            guard loaded || sets.allSatisfy({ $0.weight == 0 }), usesLoad == nil || usesLoad == loaded else { break }
            usesLoad = loaded
            // A load/rep index, not a tested one-rep max. Bodyweight uses reps only.
            let assisted = exercise.loadEquipment?.loadingMeaning == .assistance
            let score = sets.reduce(0.0) { $0 + (assisted ? (1 + Double($1.reps) / 30) / (1 + $1.weight) : loaded ? $1.weight * (1 + Double($1.reps) / 30) : Double($1.reps)) } / Double(sets.count)
            let hard = sets.allSatisfy { set in
                guard let effort = set.effort, effort.value.isFinite else { return false }
                return effort.normalizedRPE >= 8.5
            }
            samples.append((log.date, score, hard))
        }
        guard samples.count >= 4, let first = samples.first, let last = samples.last else { return nil }
        let days = Int(first.date.timeIntervalSince(last.date) / 86_400)
        guard days >= 14 else { return nil }
        let half = samples.count / 2
        let recent = samples.prefix(half).map(\.score).reduce(0, +) / Double(half)
        let earlier = samples.suffix(half).map(\.score).reduce(0, +) / Double(half)
        guard earlier > 0 else { return nil }
        let change = (recent - earlier) / earlier
        let direction: ProgressionTrend.Direction = change >= 0.025 ? .improving : change <= -0.05 ? .declining : .steady
        return ProgressionTrend(direction: direction, sessionCount: samples.count, days: days,
                                reviewLighterWeek: direction != .improving && samples.prefix(2).allSatisfy(\.hard))
    }
    /// Accept only an explicit rep count or range. AMRAP, timed sets and compound
    /// prescriptions need their own rules; do not silently interpret them as one rep.
    public static func repRange(_ text: String) -> ClosedRange<Int>? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        // Pre-built and older saved plans include the unit and sometimes a side cue.
        // Keep open-ended or effort-qualified targets ("5+", "@ light") unsupported.
        for suffix in [" reps / side", " rep / side", " reps per side", " reps", " rep"] where normalized.hasSuffix(suffix) {
            normalized = String(normalized.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let parts = normalized.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...2).contains(parts.count), let lower = Int(parts[0]), (1...100).contains(lower),
              let upper = Int(parts.last ?? ""), (lower...100).contains(upper) else { return nil }
        return lower...upper
    }

    public static func targetRepsLowEnd(_ target: String) -> Int { repRange(target)?.lowerBound ?? 0 }

    /// History is sorted, deduplicated, and scoped to this exercise and optional plan day.
    /// A supplied routine context is strict: a power day must not supply a hypertrophy
    /// day's starting load. Generic callers can omit context to inspect overall history.
    public static func history(for exercise: RoutineExercise, in logs: [WorkoutSessionLog], routineID: String? = nil, now: Date = Date()) -> [WorkoutSessionLog] {
        var seen = Set<String>()
        return logs.filter { $0.date <= now && (routineID == nil || $0.routineID == routineID) }
            .sorted { $0.date > $1.date }.filter { log in
            let identity = log.id ?? "\(log.routineID)|\(log.date.timeIntervalSince1970)"
            if !seen.insert(identity).inserted { return false }
            return performance(for: exercise, in: log) != nil
        }
    }

    public static func performance(for exercise: RoutineExercise, in log: WorkoutSessionLog) -> CompletedExercise? {
        // A newly swapped strength movement without a confirmed implement starts with manual loads.
        if exercise.type == .strength, exercise.substitution != nil, exercise.loadEquipment == nil { return nil }
        let matches = log.completedExercises.filter {
            WorkoutMovementCatalog.matches(exercise, $0.exercise)
                && StrengthEquipment.historyCompatible(current: exercise.loadEquipment, previous: $0.exercise.loadEquipment)
        }
        if let exact = matches.first(where: { $0.exercise.id == exercise.id }) { return exact }
        // Older/imported routines can have different IDs. A unique name is a useful
        // fallback; multiple same-name blocks must not borrow one another's loads.
        return matches.count == 1 ? matches.first : nil
    }

    public static func plan(
        for exercise: RoutineExercise,
        history logs: [WorkoutSessionLog],
        routineID: String? = nil,
        increment requestedIncrement: Double? = nil,
        lighterSession: Bool = false,
        now: Date = Date()
    ) -> ProgressionPlan? {
        let policy = exercise.progressionPolicy
        guard policy?.validationMessage(for: exercise) == nil,
              exercise.loadEquipment?.loadingMeaning != .assistance || policy?.kind == .assistance else { return nil }
        if policy?.kind == .percentage { return percentagePlan(for: exercise) }
        let slots = exercise.sets.enumerated().filter { $0.element.resolvedSetType == .normal }
        let ranges = slots.compactMap { repRange($0.element.target ?? exercise.targetReps) }
        guard supportsGenericProgression(exercise), exercise.type == .strength, !slots.isEmpty, ranges.count == slots.count else { return nil }
        let recent = Array(history(for: exercise, in: logs, routineID: routineID, now: now).prefix(2))
        guard let lastLog = recent.first, let last = performance(for: exercise, in: lastLog) else { return nil }
        let previous = regularSets(last)
        guard !previous.isEmpty,
              previous.count == last.sets.filter({ $0.resolvedSetType == .normal }).count else { return nil }
        let defaultIncrement = exercise.loadEquipment.map { $0.unit.storedWeight($0.unit == .kg ? 2.5 : 5) } ?? 5
        let increment = requestedIncrement ?? policy?.incrementPounds ?? exercise.progressionIncrement ?? last.exercise.progressionIncrement ?? defaultIncrement
        guard increment.isFinite, (0.25...100).contains(increment) else { return nil }

        // An incomplete session, a changed set count, or a changed rep prescription
        // must never qualify as evidence to increase load.
        let complete = previous.count == slots.count
        let priorRanges = last.exercise.sets.filter { $0.resolvedSetType == .normal }
            .compactMap { repRange($0.target ?? last.exercise.targetReps) }
        let samePrescription = priorRanges == ranges && prescriptionMatches(exercise, last.exercise)
        let hitFloor = complete && zip(previous, ranges).allSatisfy { $0.reps >= $1.lowerBound }
        let hitCeiling = complete && zip(previous, ranges).allSatisfy { $0.reps >= $1.upperBound }
        let hard = previous.contains { ($0.effort?.normalizedRPE ?? 0) >= 9 }
        let effortSupportsIncrease = previous.allSatisfy { set in
            guard let rating = set.effort, rating.value.isFinite else { return false }
            let effort = rating.normalizedRPE
            return effort.isFinite && effort <= 8
        }
        let olderLog = recent.dropFirst().first
        let older = olderLog.flatMap { performance(for: exercise, in: $0) }
        let olderSets = older.map(regularSets) ?? []
        let olderRanges = older?.exercise.sets.filter { $0.resolvedSetType == .normal }
            .compactMap { repRange($0.target ?? older?.exercise.targetReps ?? "") } ?? []
        // Two-session evidence must belong to a continuous training window, just as
        // the longer-term trend does. A recent workout cannot revive a pre-break
        // success or miss, and filtering a malformed older set cannot complete it.
        let continuousPair = olderLog.map { lastLog.date.timeIntervalSince($0.date) <= 21 * 86_400 } ?? false
        let olderWorkingSetCount = older?.sets.filter { $0.resolvedSetType == .normal }.count ?? 0
        let comparable = complete && continuousPair && olderSets.count == olderWorkingSetCount
            && olderSets.count == previous.count && olderRanges == ranges && samePrescription
            && (older.map { prescriptionMatches(exercise, $0.exercise) } ?? false)
            && zip(previous, olderSets).allSatisfy { abs($0.weight - $1.weight) < 0.01 }
        let repeatedCeiling = comparable && zip(olderSets, ranges).allSatisfy { $0.reps >= $1.upperBound }
            && olderSets.allSatisfy { ($0.effort?.normalizedRPE ?? 0) < 9 }
        let repeatedMiss = comparable && !hitFloor
            && zip(olderSets, ranges).contains { $0.reps < $1.lowerBound }
        let afterBreak = now.timeIntervalSince(lastLog.date) > 21 * 86_400
        let loaded = previous.allSatisfy { $0.weight > 0 }

        var move: ProgressionPlan.Move
        var headline: String
        var rationale: String
        if lighterSession || (samePrescription && (repeatedMiss || afterBreak)) {
            move = .easeBack
            headline = "Take a lighter session"
            rationale = lighterSession ? "A lighter starting point for today. Review the loads before applying."
                : afterBreak ? "Your last session was more than three weeks ago. Review a lighter starting point."
                : "Two comparable sessions fell below the rep range. Review a smaller load and rebuild clean reps."
        } else if !complete || !samePrescription {
            move = .hold
            headline = "Establish these targets"
            rationale = !complete ? "The last session has a different number of working sets. Keep the load while you establish this session."
                : "The prescription has changed. Keep the previous load as a reference and review the new targets."
        } else if !hitFloor || hard {
            move = .hold
            headline = "Repeat the load"
            rationale = !hitFloor ? "Some working sets were below the rep range. Build those reps before adding weight."
                : "At least one working set was near your limit. Repeat the load before progressing."
        } else if ((policy?.kind == .linear && hitFloor) || hitCeiling) && loaded && (effortSupportsIncrease || repeatedCeiling) {
            move = .addWeight
            headline = "Ready for a small increase"
            if policy?.kind == .linear && !hitCeiling {
                rationale = effortSupportsIncrease
                    ? "Your linear policy allows a small increase after every working set reaches its minimum with effort at RPE 8 or below."
                    : "Your linear policy allows a small increase: every working set reached its minimum, and the previous comparable session reached the top of each range at the same load. Current effort was not recorded."
            } else {
                rationale = effortSupportsIncrease ? "Every working set reached the top of its rep range with effort at RPE 8 or below."
                    : "Two comparable sessions reached the top of every rep range at the same load."
            }
        } else if !hitCeiling {
            move = .addRep
            headline = "Build reps at this load"
            rationale = "Every working set reached its minimum. Add a rep where there is room within the range."
        } else {
            move = .hold
            headline = "Confirm this performance"
            rationale = loaded ? "Repeat the top of the range, or record effort, before increasing load."
                : "You reached the rep range. Keep bodyweight sets unweighted and review your next goal."
        }

        let equipment = exercise.loadEquipment
        let assisted = policy?.kind == .assistance
        let bodyweight = policy?.kind == .bodyweight
        if bodyweight, previous.contains(where: { $0.weight != 0 }) { return nil }
        if assisted && move == .addWeight { headline = "Ready for less assistance"; rationale += " Less machine assistance is a harder load." }
        guard equipment?.isValid != false else { return nil }
        let loads = equipment?.attainableLoads
        if move == .addWeight, let loads {
            let increases = previous.map { reference in
                assisted ? loads.last { $0 <= reference.weight - increment + 0.01 } : loads.first { $0 >= reference.weight + increment - 0.01 }
            }
            let practical = zip(previous, increases).allSatisfy { reference, candidate in
                guard let candidate else { return false }
                // A coarse rack jump is not automatically equivalent to the user's chosen step.
                return abs(candidate - reference.weight) <= max(increment, reference.weight * 0.1) + 0.01
            }
            if !practical {
                move = .hold
                headline = "Keep this load"
                rationale = "No available load fits the next progression step. A jump larger than both your chosen step and 10% is held for review. Keep this load or adjust your equipment and step."
            }
        }

        let targets = slots.enumerated().compactMap { ordinal, slot -> ProgressionTarget? in
            let reference = previous[min(ordinal, previous.count - 1)]
            let range = ranges[ordinal]
            let weight: Double
            let reps: Int
            switch move {
            case .addWeight:
                if let loads {
                    guard let attainable = assisted ? loads.last(where: { $0 <= reference.weight - increment + 0.01 }) : loads.first(where: { $0 >= reference.weight + increment - 0.01 }) else { return nil }
                    weight = attainable
                } else {
                    weight = assisted ? max(0, reference.weight - increment) : reference.weight + increment
                }
                reps = range.lowerBound
            case .addRep:
                weight = reference.weight
                reps = min(max(reference.reps + 1, range.lowerBound), range.upperBound)
            case .easeBack:
                weight = assisted ? reference.weight + increment : reference.weight == 0 ? 0 : min(reference.weight, max(increment, (reference.weight * 0.9 / increment).rounded(.down) * increment))
                reps = range.lowerBound
            case .hold:
                weight = reference.weight
                reps = min(max(reference.reps, range.lowerBound), range.upperBound)
            }
            let availableWeight: Double
            if let loads {
                if move == .easeBack {
                    // Pick the closest practical lighter target, including the current load
                    // when the next lower implement would be a disproportionate drop.
                    let candidates = loads.filter { assisted ? $0 >= reference.weight - 0.01 : $0 <= reference.weight + 0.01 }
                    guard let attainable = candidates.min(by: { abs($0 - weight) < abs($1 - weight) }) else { return nil }
                    availableWeight = attainable
                } else {
                    // A changed inventory never forces a held target upward.
                    guard let attainable = loads.last(where: { $0 <= weight + 0.01 }) else { return nil }
                    availableWeight = attainable
                }
            } else {
                availableWeight = weight
            }
            return ProgressionTarget(id: slot.element.id, setNumber: slot.offset + 1, weight: availableWeight, reps: reps)
        }
        guard targets.count == slots.count else { return nil }
        if equipment != nil, move == .easeBack,
           zip(targets, previous).allSatisfy({ assisted ? $0.weight <= $1.weight + 0.01 : $0.weight >= $1.weight - 0.01 }) {
            move = .hold
            headline = "Review a lighter load"
            rationale = "The available equipment does not provide a practical lighter load. Keep these values as a reference and review your setup before changing them."
        } else if equipment != nil, move != .addWeight, move != .easeBack,
                  zip(targets, previous).contains(where: { abs($0.weight - $1.weight) >= 0.01 }) {
            headline = "Review available loads"
            rationale = "Some previous loads are not available in this setup. Review the available loads below before applying them. Your history stays unchanged."
        }
        var result = ProgressionPlan(exerciseID: exercise.id, exerciseName: exercise.name, move: move, headline: headline, rationale: rationale,
                                     sessionCount: comparable ? 2 : 1, increment: increment, targets: targets,
                                     trend: trend(for: exercise, history: logs, routineID: routineID, now: now))
        result.loadEquipment = equipment
        result.prescriptionFingerprint = prescriptionFingerprint(exercise)
        result.policy = policy
        result.evidenceSessionIDs = recent.compactMap(\.id)
        return result
    }

    private static func percentagePlan(for exercise: RoutineExercise) -> ProgressionPlan? {
        let working = exercise.sets.enumerated().filter { $0.element.resolvedSetType == .normal }
        let targets = working.compactMap { index, set -> ProgressionTarget? in
            guard let prescription = set.prescription, let weight = prescription.resolvedWeightPounds,
                  let reps = prescription.lowerBound, prescription.kind == .repetitions else { return nil }
            let actual = exercise.loadEquipment?.atOrBelow(weight) ?? weight
            guard exercise.loadEquipment == nil || exercise.loadEquipment?.contains(actual) == true,
                  actual <= weight + 0.01 else { return nil }
            return ProgressionTarget(id: set.id, setNumber: index + 1, weight: actual, reps: Int(reps))
        }
        guard !targets.isEmpty, targets.count == working.count else { return nil }
        var plan = ProgressionPlan(exerciseID: exercise.id, exerciseName: exercise.name, move: .hold,
            headline: "Follow authored percentages", rationale: "Uses each set's named reference and percentage, rounded down only to available equipment. Previous heavy sessions do not replace these targets.",
            sessionCount: 0, increment: exercise.progressionPolicy?.incrementPounds ?? 5, targets: targets)
        plan.loadEquipment = exercise.loadEquipment; plan.policy = exercise.progressionPolicy
        plan.prescriptionFingerprint = prescriptionFingerprint(exercise); plan.evidenceSessionIDs = []
        return plan
    }

    /// Authored percentages own the load. The ordinary double-progression helper must
    /// not replace a lighter week with a previous heavy session's Add load proposal.
    private static func supportsGenericProgression(_ exercise: RoutineExercise) -> Bool {
        exercise.sets.filter { $0.resolvedSetType == .normal }.allSatisfy { set in
            guard let target = set.prescription else { return true }
            return target.validationMessage == nil && target.kind == .repetitions
                && target.loadPercentage == nil && target.loadReference == nil
        }
    }

    private static func prescriptionMatches(_ first: RoutineExercise, _ second: RoutineExercise) -> Bool {
        let firstTargets = first.sets.filter { $0.resolvedSetType == .normal }.map(\.prescription)
        let secondTargets = second.sets.filter { $0.resolvedSetType == .normal }.map(\.prescription)
        return firstTargets == secondTargets && first.progressionPolicy == second.progressionPolicy
    }

    private static func prescriptionFingerprint(_ exercise: RoutineExercise) -> String? {
        struct Basis: Encodable {
            let fallback: String
            let policy: WorkoutProgressionPolicy?
            let sets: [ExerciseSet]
        }
        // Performed values are editable; only the reviewed target and role form the basis.
        let targets = exercise.sets.filter { $0.resolvedSetType == .normal }.map { original in
            var set = ExerciseSet(id: original.id, target: original.target)
            set.prescription = original.prescription
            return set
        }
        return try? PlanFingerprint.make(Basis(fallback: exercise.targetReps, policy: exercise.progressionPolicy, sets: targets))
    }

    /// Applies only reviewed targets to unfinished regular sets. Never records a set,
    /// edits warmups/drop/failure sets, or changes the underlying program prescription.
    public static func applying(_ plan: ProgressionPlan, to exercise: RoutineExercise) -> RoutineExercise {
        guard plan.isValid, plan.exerciseID == exercise.id, plan.exerciseName == exercise.name,
              plan.loadEquipment == exercise.loadEquipment, plan.policy == exercise.progressionPolicy,
              supportsGenericProgression(exercise) || exercise.progressionPolicy?.kind == .percentage,
              plan.prescriptionFingerprint == nil || plan.prescriptionFingerprint == prescriptionFingerprint(exercise) else { return exercise }
        var updated = exercise
        var changed = false
        for index in updated.sets.indices where !updated.sets[index].isCompleted && updated.sets[index].resolvedSetType == .normal {
            guard let target = plan.targets.first(where: { $0.id == updated.sets[index].id }) else { continue }
            updated.sets[index].weight = target.weight
            updated.sets[index].reps = target.reps
            changed = true
        }
        if changed { updated.progressionIncrement = plan.increment }
        return updated
    }

    /// Undo is conditional: subsequent edits and completed sets always win.
    public static func undo(before: RoutineExercise, applied: RoutineExercise, current: RoutineExercise) -> RoutineExercise {
        guard before.id == current.id, applied.id == current.id, before.name == current.name,
              before.loadEquipment == current.loadEquipment, applied.loadEquipment == current.loadEquipment,
              prescriptionFingerprint(applied) == prescriptionFingerprint(current) else { return current }
        var restored = current
        for index in restored.sets.indices where !restored.sets[index].isCompleted {
            guard let original = before.sets.first(where: { $0.id == restored.sets[index].id }),
                  let accepted = applied.sets.first(where: { $0.id == original.id }),
                  accepted.resolvedSetType == restored.sets[index].resolvedSetType,
                  restored.sets[index].weight == accepted.weight, restored.sets[index].reps == accepted.reps else { continue }
            restored.sets[index].weight = original.weight
            restored.sets[index].reps = original.reps
        }
        if restored.progressionIncrement == applied.progressionIncrement { restored.progressionIncrement = before.progressionIncrement }
        return restored
    }

    /// Match by set role and ordinal so inserting a warmup cannot shift every "last time" value.
    public static func previousSet(for setID: String, exercise: RoutineExercise, previous: CompletedExercise?) -> CompletedSet? {
        guard let set = exercise.sets.first(where: { $0.id == setID }), let previous,
              StrengthEquipment.historyCompatible(current: exercise.loadEquipment, previous: previous.exercise.loadEquipment) else { return nil }
        let currentRole = exercise.sets.filter { $0.resolvedSetType == set.resolvedSetType }
        let priorRole = previous.sets.filter { $0.resolvedSetType == set.resolvedSetType }
        guard let ordinal = currentRole.firstIndex(where: { $0.id == setID }), priorRole.indices.contains(ordinal) else { return nil }
        return priorRole[ordinal]
    }

    private static func regularSets(_ exercise: CompletedExercise) -> [CompletedSet] {
        exercise.sets.filter {
            $0.resolvedSetType == .normal && $0.weight.isFinite && (0...10_000).contains($0.weight) && (1...100).contains($0.reps)
        }
    }
}
