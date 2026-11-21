import Foundation

public struct WorkoutBlockLoadComparison: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let context: String
    public let repetitions: Int
    public let firstWeightPounds: Double
    public let latestWeightPounds: Double
    public let unit: StrengthEquipment.Unit
    public let firstDate: Date
    public let latestDate: Date
    public let comparableSessions: Int
}

/// Recorded load at the same rep count in the same exercise/routine/equipment
/// context. This does not combine volume conventions or claim estimated strength.
public struct WorkoutBlockPerformance: Equatable, Sendable {
    public let comparisons: [WorkoutBlockLoadComparison]
    public let workingSets: Int
    public let effortRecordedSets: Int
    public let longestGapDays: Int?

    public static func make(program: WorkoutProgram, logs: [WorkoutSessionLog], now: Date = Date(),
                            calendar: Calendar = .current) -> WorkoutBlockPerformance {
        let linked = WorkoutSetMath.uniqueSessions(logs.filter { log in
            guard log.programLinkDecision != .standalone, let context = log.programContext,
                  context.programID == program.id, (0..<program.totalSlots).contains(context.slotIndex),
                  log.date.timeIntervalSinceReferenceDate.isFinite, log.date <= now else { return false }
            return context.blockSession == nil || context.blockSession?.blockID == program.trainingBlock?.id
        }).sorted { $0.date < $1.date }
        struct Sample { let log: WorkoutSessionLog; let exercise: CompletedExercise }
        var groups: [String: [Sample]] = [:]
        var workingSets = 0; var effortSets = 0
        for log in linked {
            for exercise in log.completedExercises where exercise.exercise.type == .strength {
                let sets = WorkoutSetMath.workingSets(in: exercise).filter { $0.reps > 0 }
                workingSets += sets.count
                effortSets += sets.filter { set in
                    guard let effort = set.effort, effort.value.isFinite else { return false }
                    return effort.scale == .rpe ? (1...10).contains(effort.value) : (0...10).contains(effort.value)
                }.count
                let key = log.routineID + "|" + exercise.exercise.id + "|" + WorkoutEvidenceReportRules.setupKey(exercise.exercise)
                groups[key, default: []].append(Sample(log: log, exercise: exercise))
            }
        }
        let comparisons = groups.compactMap { key, samples -> WorkoutBlockLoadComparison? in
            guard let latest = samples.last else { return nil }
            let compatible = samples.filter { WorkoutSetMath.compatible($0.exercise, latest.exercise) && WorkoutSetMath.prescriptionCompatible($0.exercise.exercise, latest.exercise.exercise) }
            guard let first = compatible.first, first.log.date < latest.log.date else { return nil }
            let earlierSets = WorkoutSetMath.workingSets(in: first.exercise).filter { $0.reps > 0 && $0.weight > 0 }
            let latestSets = WorkoutSetMath.workingSets(in: latest.exercise).filter { $0.reps > 0 && $0.weight > 0 }
            let common = Set(earlierSets.map(\.reps)).intersection(latestSets.map(\.reps))
            let assisted = latest.exercise.exercise.loadEquipment?.loadingMeaning == .assistance
            guard let lastSet = latestSets.filter({ common.contains($0.reps) }).max(by: { assisted ? $0.weight > $1.weight : $0.weight < $1.weight }),
                  let firstSet = earlierSets.filter({ $0.reps == lastSet.reps }).max(by: { assisted ? $0.weight > $1.weight : $0.weight < $1.weight }) else { return nil }
            return WorkoutBlockLoadComparison(id: key, name: latest.exercise.exerciseName,
                context: WorkoutSetMath.contextLabel(latest.exercise.exercise), repetitions: lastSet.reps,
                firstWeightPounds: firstSet.weight, latestWeightPounds: lastSet.weight,
                unit: latest.exercise.exercise.loadEquipment?.unit ?? .lb,
                firstDate: first.log.date, latestDate: latest.log.date,
                comparableSessions: Set(compatible.map { $0.log.id ?? "\($0.log.date.timeIntervalSinceReferenceDate)" }).count)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let gaps = zip(linked, linked.dropFirst()).compactMap {
            calendar.dateComponents([.day], from: $0.0.date, to: $0.1.date).day
        }
        return WorkoutBlockPerformance(comparisons: comparisons, workingSets: workingSets, effortRecordedSets: effortSets,
            longestGapDays: gaps.max())
    }
}
