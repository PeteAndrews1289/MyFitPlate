import Foundation

public struct UpcomingTrainingSession: Identifiable {
    public var id: Int { slot }
    public let slot: Int
    public let date: Date?
    public let routine: WorkoutRoutine
    public let week: Int
    public let day: Int
    public let isOverdue: Bool

    public var workingSets: Int {
        routine.exercises.reduce(0) { count, exercise in
            count + (exercise.sets.isEmpty ? max(0, exercise.targetSets)
                     : exercise.sets.filter { !$0.isWarmup && $0.setType != .warmup }.count)
        }
    }
}

public enum TrainingScheduleOverview {
    /// Follow the actual slot sequence, including rescue overlays; weekday initials cannot
    /// represent plans whose routine rotation and number of weekly sessions differ.
    public static func upcoming(_ program: WorkoutProgram, limit: Int = 4,
                                now: Date = Date(), calendar: Calendar = .current) -> [UpcomingTrainingSession] {
        let start = min(program.totalSlots, max(0, program.currentProgressIndex ?? 0))
        return (start..<min(program.totalSlots, start + max(0, min(limit, 14)))).compactMap { slot in
            guard let routine = program.routine(forSlot: slot) else { return nil }
            let date = program.date(forSlot: slot, calendar: calendar)
            let position = program.weekAndDay(forSlot: slot)
            return UpcomingTrainingSession(slot: slot, date: date, routine: routine,
                                           week: position.week, day: position.day,
                                           isOverdue: date.map { $0 < calendar.startOfDay(for: now) } ?? false)
        }
    }
}
