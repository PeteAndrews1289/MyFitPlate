import CryptoKit
import Foundation

public enum PlanFingerprint {
    public static func make<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum WeekRescueReason: String, Codable, CaseIterable, Identifiable {
    case missedWorkout = "Missed a workout"
    case lessTime = "Less time to train"
    case busyDay = "A busy day"
    case lighterWeek = "A lighter training week"
    public var id: String { rawValue }
}

public struct RescueWorkoutSlot: Codable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let originalDate: Date?
    public let date: Date
    public var routine: WorkoutRoutine?
    public var originalRoutineFingerprint: String?
}

public struct RescueMealChange: Codable, Identifiable {
    public var id: String { replacement.id }
    public let originalFingerprint: String
    public let original: MealPlanDay?
    public let replacement: MealPlanDay

    public init(original: MealPlanDay?, replacement: MealPlanDay) throws {
        try Self.validateReplacement(original: original, replacement: replacement)
        self.original = original
        originalFingerprint = try PlanFingerprint.make(original)
        self.replacement = replacement
    }

    public func matches(_ original: MealPlanDay?) -> Bool {
        (try? PlanFingerprint.make(original)) == originalFingerprint
    }

    /// Creation/resolution validation is intentionally separate from Codable. Existing
    /// programs retain readable rescue snapshots and their ordinary Undo path.
    fileprivate static func validateReplacement(original: MealPlanDay?, replacement: MealPlanDay) throws {
        let before = original ?? MealPlanEditingRules.emptyDay(replacement.date)
        do {
            try MealPlanEditingRules.validate(MealPlanChange(title: "Rescue meal", before: [before], after: [replacement]))
        } catch is MealCookingError {
            throw WeekRescueError.linkedMealBatch
        }
    }
}

public struct WeekRescueAdjustment: Codable, Identifiable {
    public let id: String
    public let createdAt: Date
    public let reason: WeekRescueReason
    public let sourceProgramFingerprint: String
    public var slots: [RescueWorkoutSlot]
    public var meals: [RescueMealChange]
    public var explanation: [String]

    public func resolving(_ original: MealPlanDay?, on date: Date, calendar: Calendar = .current) -> MealPlanDay? {
        guard let change = meals.first(where: { calendar.isDate($0.replacement.date, inSameDayAs: date) }),
              change.matches(original) else { return original }
        do {
            try RescueMealChange.validateReplacement(original: original, replacement: change.replacement)
            return change.replacement
        } catch {
            // A previously saved incompatible overlay must not hide the underlying
            // batch, lose its shopping anchor, or make its active program unreadable.
            return original
        }
    }
}

public enum WeekRescueError: LocalizedError {
    case noProgram, alreadyAdjusted, invalidDate, tooShort, changed, saveFailed, noChange, linkedMealBatch
    public var errorDescription: String? {
        switch self {
        case .noProgram: return "Choose an active program with upcoming scheduled workouts first."
        case .alreadyAdjusted: return "Undo your current rescue before making another. Completed workouts and later meal edits will stay."
        case .invalidDate: return "Choose a date within the next seven days, on or after the scheduled workout."
        case .tooShort: return "This routine cannot be shortened safely with the available set information. Choose another rescue."
        case .changed: return "Your plan changed while this preview was open. Preview it again before applying."
        case .saveFailed: return "Your rescue could not be saved. Nothing has been applied. Try again."
        case .noChange: return "This would leave your plan unchanged. Choose a later workout date or a different meal."
        case .linkedMealBatch: return "This meal shares a cooking batch. Keep planned meals in this rescue, or review its linked allocations in Meal Plan first."
        }
    }
}

public extension WorkoutProgram {
    var totalSlots: Int { trainingBlock?.totalSlots ?? max((daysOfWeek?.count ?? 0) * 12, routines.count) }

    func routine(forSlot index: Int) -> WorkoutRoutine? {
        guard index >= 0, index < totalSlots, !routines.isEmpty else { return nil }
        guard let original = WorkoutBlockRules.baseRoutine(for: self, slot: index) else { return nil }
        if let slot = weekRescue?.slots.first(where: { $0.index == index }), let routine = slot.routine,
           slot.originalRoutineFingerprint == (try? PlanFingerprint.make(original)) { return routine }
        return original
    }

    func weekAndDay(forSlot index: Int) -> (week: Int, day: Int) {
        let count = max(daysOfWeek?.count ?? 1, 1)
        return (index / count + 1, index % count + 1)
    }

    func date(forSlot index: Int, calendar: Calendar = .current) -> Date? {
        guard (0..<totalSlots).contains(index) else { return nil }
        if let fixed = slotDateSnapshots?.first(where: { $0.slotIndex == index }) { return fixed.day?.date(calendar: calendar) ?? fixed.date }
        let original = trainingBlock?.scheduleExceptions?.first(where: { $0.slotIndex == index })?.proposedDay.date(calendar: calendar)
            ?? originalDate(forSlot: index, calendar: calendar)
        if let adjusted = weekRescue?.slots.first(where: { $0.index == index }), adjusted.originalDate == original {
            return adjusted.date
        }
        return original
    }

    func originalDate(forSlot index: Int, calendar: Calendar = .current) -> Date? {
        guard index >= 0, index < totalSlots, let startDate, let daysOfWeek,
              !daysOfWeek.isEmpty, daysOfWeek.allSatisfy({ (1...7).contains($0) }) else { return nil }
        var matched = 0
        for offset in 0..<(7 * max(14, totalSlots + 1)) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: scheduleAnchorDay?.date(calendar: calendar) ?? calendar.startOfDay(for: startDate)) else { continue }
            if daysOfWeek.contains(calendar.component(.weekday, from: date)) {
                if matched == index { return date }
                matched += 1
            }
        }
        return nil
    }
}

public enum WeekRescueRules {
    /// Keeps routine identities, program progress and the spacing between future sessions.
    public static func preview(
        program: WorkoutProgram, reason: WeekRescueReason, workoutDate: Date,
        minutes: Int = 30, mealChanges: [RescueMealChange] = [], windowDays: Int = 7, now: Date = Date(), calendar: Calendar = .current
    ) throws -> WeekRescueAdjustment {
        guard program.weekRescue == nil else { throw WeekRescueError.alreadyAdjusted }
        let index = program.currentProgressIndex ?? 0
        guard program.id != nil, index >= 0, index < program.totalSlots,
              let oldDate = program.date(forSlot: index, calendar: calendar),
              let routine = program.routine(forSlot: index) else { throw WeekRescueError.noProgram }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: workoutDate)
        guard (1...14).contains(windowDays), let end = calendar.date(byAdding: .day, value: windowDays, to: today), target >= today, target <= end else {
            throw WeekRescueError.invalidDate
        }
        var slots: [RescueWorkoutSlot] = []
        var explanation: [String] = []
        if reason == .lighterWeek {
            let offset = max(0, calendar.dateComponents([.day], from: oldDate, to: today).day ?? 0)
            var removed = 0
            var affected = 0
            for slot in index..<program.totalSlots {
                guard let original = program.date(forSlot: slot, calendar: calendar),
                      let date = calendar.date(byAdding: .day, value: offset, to: original) else { continue }
                var lighter: WorkoutRoutine?
                var fingerprint: String?
                if date < end, let base = program.routine(forSlot: slot), let adjusted = try lighterVolume(base) {
                    lighter = adjusted
                    fingerprint = try PlanFingerprint.make(base)
                    removed += base.exercises.reduce(0) { $0 + $1.sets.count } - adjusted.exercises.reduce(0) { $0 + $1.sets.count }
                    affected += 1
                }
                if offset > 0 || lighter != nil {
                    slots.append(RescueWorkoutSlot(index: slot, originalDate: original, date: date,
                                                  routine: lighter, originalRoutineFingerprint: fingerprint))
                }
            }
            guard affected > 0 else { throw WeekRescueError.noChange }
            explanation.append("Next \(windowDays) days: remove one regular working set from each eligible strength exercise, keeping at least one. \(affected) sessions, \(removed) fewer sets total. Loads and rep ranges stay yours to review.")
            explanation.append("Warm-ups, exercise order, supersets, and special sets are kept. Later weeks return to your full routines automatically.")
            if offset > 0 { explanation.append("Move the overdue session to today and preserve the gaps between all remaining sessions.") }
        } else if reason != .lessTime {
            let offset = calendar.dateComponents([.day], from: oldDate, to: target).day ?? 0
            guard offset >= 0 else { throw WeekRescueError.invalidDate }
            if offset > 0 {
                for slot in index..<program.totalSlots {
                    guard let original = program.date(forSlot: slot, calendar: calendar),
                          let date = calendar.date(byAdding: .day, value: offset, to: original) else { continue }
                    slots.append(RescueWorkoutSlot(index: slot, originalDate: original, date: date))
                }
                explanation.append("Move all \(slots.count) remaining sessions by \(offset) \(offset == 1 ? "day" : "days"). Workout order and recovery gaps stay the same.")
            }
        } else {
            let short = try shortened(routine, minutes: minutes)
            let offset = max(0, calendar.dateComponents([.day], from: oldDate, to: today).day ?? 0)
            if offset > 0 {
                for slot in index..<program.totalSlots {
                    guard let original = program.date(forSlot: slot, calendar: calendar),
                          let date = calendar.date(byAdding: .day, value: offset, to: original) else { continue }
                    slots.append(RescueWorkoutSlot(index: slot, originalDate: original, date: date,
                                                  routine: slot == index ? short : nil))
                }
                explanation.append("Your next session is overdue. Move it to today and shift the later dates by the same amount to preserve recovery gaps.")
            } else {
                slots = [RescueWorkoutSlot(index: index, originalDate: oldDate, date: oldDate, routine: short)]
            }
            if let changedIndex = slots.firstIndex(where: { $0.index == index }) {
                slots[changedIndex].originalRoutineFingerprint = try PlanFingerprint.make(routine)
            }
            let before = routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
            let after = short.exercises.reduce(0) { $0 + $1.sets.count }
            explanation.append("This session only: \(routine.exercises.count) → \(short.exercises.count) exercises, \(before) → \(after) sets. Allow about \(estimatedMinutes(short)) minutes including warm-up; actual time varies.")
            explanation.append("Keep the first exercises in your plan and all their warm-up sets. Review the exercise list before applying.")
        }
        guard !slots.isEmpty || !mealChanges.isEmpty else { throw WeekRescueError.noChange }
        explanation.append("Your active program, completed sessions and progress stay in place. Meal targets are not reduced to compensate for missed training.")
        return WeekRescueAdjustment(id: UUID().uuidString, createdAt: now, reason: reason,
                                    sourceProgramFingerprint: try PlanFingerprint.make(program), slots: slots,
                                    meals: mealChanges, explanation: explanation)
    }

    public static func applying(_ rescue: WeekRescueAdjustment, to program: WorkoutProgram) throws -> WorkoutProgram {
        guard program.weekRescue == nil, try PlanFingerprint.make(program) == rescue.sourceProgramFingerprint else {
            throw WeekRescueError.changed
        }
        var updated = program
        updated.weekRescue = rescue
        return updated
    }

    public static func undoing(id: String, in program: WorkoutProgram) throws -> WorkoutProgram {
        guard program.weekRescue?.id == id else { throw WeekRescueError.changed }
        var updated = program
        updated.weekRescue = nil
        return updated
    }

    public static func estimatedMinutes(_ routine: WorkoutRoutine) -> Int {
        let seconds = routine.exercises.reduce(300) { total, exercise in
            let count = max(exercise.sets.count, exercise.targetSets)
            return total + count * (45 + max(exercise.restTimeInSeconds, 0)) + 60
        }
        return Int(ceil(Double(seconds) / 60))
    }

    private static func lighterVolume(_ original: WorkoutRoutine) throws -> WorkoutRoutine? {
        guard let copy = original.deepCopy() else { return nil }
        var changed = false
        copy.exercises = copy.exercises.map { exercise in
            guard exercise.type == .strength else { return exercise }
            var result = exercise
            let normal = result.sets.indices.filter { result.sets[$0].resolvedSetType == .normal && !result.sets[$0].isCompleted }
            guard normal.count > 1, let last = normal.last else { return exercise }
            result.sets.remove(at: last)
            result.targetSets = result.sets.count
            changed = true
            return result
        }
        return changed ? copy : nil
    }

    private static func shortened(_ original: WorkoutRoutine, minutes: Int) throws -> WorkoutRoutine {
        guard minutes >= 15, let result = original.deepCopy(), !result.exercises.isEmpty,
              result.exercises.allSatisfy({ $0.type == .strength }) else { throw WeekRescueError.tooShort }
        // Work with whole superset groups; never leave one half of a superset behind.
        var groups: [[RoutineExercise]] = []
        for exercise in result.exercises {
            if let group = exercise.supersetGroupID, groups.last?.last?.supersetGroupID == group {
                groups[groups.count - 1].append(exercise)
            } else { groups.append([exercise]) }
        }
        var retained: [RoutineExercise] = []
        for group in groups {
            let trimmed = group.map { exercise -> RoutineExercise in
                var copy = exercise
                if copy.sets.isEmpty {
                    copy.sets = (0..<max(1, min(copy.targetSets, 2))).map { _ in ExerciseSet(target: copy.targetReps) }
                } else {
                    var working = 0
                    copy.sets = copy.sets.filter { set in
                        if set.isCompleted || set.isWarmup || set.resolvedSetType != .normal { return true }
                        working += 1
                        return working <= 2
                    }
                }
                copy.targetSets = copy.sets.count
                return copy
            }
            result.exercises = retained + trimmed
            if estimatedMinutes(result) > minutes { break }
            retained += trimmed
        }
        guard !retained.isEmpty else { throw WeekRescueError.tooShort }
        result.exercises = retained
        guard try PlanFingerprint.make(result) != PlanFingerprint.make(original) else { throw WeekRescueError.noChange }
        return result
    }
}
