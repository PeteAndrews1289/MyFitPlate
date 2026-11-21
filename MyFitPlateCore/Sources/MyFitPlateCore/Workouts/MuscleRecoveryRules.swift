import Foundation

public enum RecoveryMuscleGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case chest
    case back
    case legs
    case arms
    case core
    case shoulders

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum MuscleRecoveryStatus: String, Codable, Sendable {
    case noRecentSignal
    case fatigued
    case recovering
    case nearlyReady
    case ready
}

/// An estimate derived from recent training volume and sleep, not a medical readiness claim.
/// Keeping the reference date explicit makes the model deterministic and straightforward to test.
public struct MuscleRecoveryEstimate: Identifiable, Equatable, Sendable {
    public var id: String { group.rawValue }

    public let group: RecoveryMuscleGroup
    public let lastTrained: Date?
    public let lastSessionSets: Int
    public let recoveryHours: Double
    public let sleepMultiplier: Double
    public let asOf: Date
    /// Optional qualitative projection used by the evidence-led map. Legacy numerical
    /// estimates remain readable, but the map never presents their ratio as measured readiness.
    public let planningStatus: MuscleRecoveryStatus?

    public init(
        group: RecoveryMuscleGroup,
        lastTrained: Date?,
        lastSessionSets: Int,
        recoveryHours: Double,
        sleepMultiplier: Double,
        asOf: Date,
        planningStatus: MuscleRecoveryStatus? = nil
    ) {
        self.group = group
        self.lastTrained = lastTrained
        self.lastSessionSets = lastSessionSets
        self.recoveryHours = recoveryHours
        self.sleepMultiplier = sleepMultiplier
        self.asOf = asOf
        self.planningStatus = planningStatus
    }

    public var hoursSinceTraining: Double? {
        guard let lastTrained else { return nil }
        return max(0, asOf.timeIntervalSince(lastTrained) / 3_600)
    }

    public var progress: Double {
        guard let hoursSinceTraining else { return 0 }
        return min(max(hoursSinceTraining / max(recoveryHours, 1), 0), 1)
    }

    public var roundedPercentage: Int {
        min(max(Int((progress * 20).rounded()) * 5, 0), 100)
    }

    public var hoursUntilReady: Double {
        guard let hoursSinceTraining else { return 0 }
        return max(0, recoveryHours - hoursSinceTraining)
    }

    public var isReady: Bool {
        lastTrained != nil && progress >= 1
    }

    public var wasNotTrainedRecently: Bool {
        guard let hoursSinceTraining else { return true }
        return hoursSinceTraining >= 8 * 24
    }

    public var status: MuscleRecoveryStatus {
        if let planningStatus { return planningStatus }
        guard lastTrained != nil else { return .noRecentSignal }
        if isReady { return .ready }
        if progress < 0.35 { return .fatigued }
        if progress < 0.72 { return .recovering }
        return .nearlyReady
    }
}

public enum MuscleRecoveryRules {
    public static func estimate(
        group: RecoveryMuscleGroup,
        lastTrained: Date?,
        sets: Int?,
        sleepScore: Int?,
        asOf: Date = Date()
    ) -> MuscleRecoveryEstimate {
        let multiplier = wellnessMultiplier(sleepScore)
        let validSignal = lastTrained.map { $0 <= asOf && $0.timeIntervalSinceReferenceDate.isFinite } == true && (sets ?? 0) > 0
        return MuscleRecoveryEstimate(
            group: group,
            lastTrained: validSignal ? lastTrained : nil,
            lastSessionSets: validSignal ? sets ?? 0 : 0,
            recoveryHours: recoveryWindowHours(
                group: group,
                sets: sets,
                wellnessMultiplier: multiplier
            ),
            sleepMultiplier: multiplier,
            asOf: asOf
        )
    }

    /// Only measured strength working sets create set-based recovery evidence.
    /// Diary summaries and running totals do not contain that measurement.
    public static func estimates(sessions: [WorkoutSessionLog], sleepScore: Int?, sleepDate: Date?, asOf now: Date = Date()) -> [MuscleRecoveryEstimate] {
        let freshSleep = sleepDate.map { (0...(36 * 3_600)).contains(now.timeIntervalSince($0)) } == true
        let recent = WorkoutSetMath.uniqueSessions(sessions).filter { $0.date <= now && now.timeIntervalSince($0.date) <= 14 * 86_400 }
        var latest: [RecoveryMuscleGroup: (Date, Int)] = [:]
        for session in recent {
            var measured: [RecoveryMuscleGroup: Int] = [:]
            for exercise in session.completedExercises where exercise.exercise.type == .strength {
                let sets = WorkoutSetMath.workingSets(in: exercise).filter { $0.reps > 0 }.count
                for group in muscleGroups(for: exercise.exerciseName) { measured[group, default: 0] += sets }
            }
            for (group, count) in measured where count > 0 && session.date > (latest[group]?.0 ?? .distantPast) {
                latest[group] = (session.date, count)
            }
        }
        return RecoveryMuscleGroup.allCases.map {
            estimate(group: $0, lastTrained: latest[$0]?.0, sets: latest[$0]?.1,
                     sleepScore: freshSleep ? sleepScore : nil, asOf: now)
        }
    }

    public static func wellnessMultiplier(_ sleepScore: Int?) -> Double {
        guard let score = sleepScore, score > 0 else { return 1 }
        if score >= 80 { return 0.9 }
        if score >= 60 { return 1 }
        if score >= 40 { return 1.1 }
        return 1.2
    }

    public static func recoveryWindowHours(
        group: RecoveryMuscleGroup,
        sets: Int?,
        wellnessMultiplier: Double
    ) -> Double {
        let base: Double
        switch group {
        case .legs, .back: base = 64
        case .chest: base = 56
        case .shoulders, .core: base = 44
        case .arms: base = 40
        }

        let volumeMultiplier = sets.map {
            min(1.5, max(0.8, 0.6 + Double($0) * 0.06))
        } ?? 1

        return base * volumeMultiplier * wellnessMultiplier
    }

    /// Maps common exercise names to broad regions used by the recovery visualization. Specific
    /// leg and compound patterns run before generic words such as "press" and "curl" so a leg
    /// press or leg curl cannot be mislabeled as shoulders or arms.
    public static func muscleGroups(for exerciseName: String) -> Set<RecoveryMuscleGroup> {
        let name = exerciseName.lowercased()
        var groups = Set<RecoveryMuscleGroup>()

        if containsAny(name, [
            "squat", "leg", "lunge", "quad", "calf", "calve", "hamstring", "glute",
            "hip thrust", "step up", "step-up"
        ]) {
            groups.insert(.legs)
        }

        if containsAny(name, ["bench", "pushup", "push-up", "chest", "pec", "fly", "dip"]) {
            groups.insert(.chest)
        }

        if containsAny(name, ["crunch", "plank", "oblique", "ab ", "abs", "situp", "sit-up", "core"]) {
            groups.insert(.core)
        }

        if containsAny(name, ["shoulder", "overhead", "military", "lateral", "delt", "shrug", "front raise"]) {
            groups.insert(.shoulders)
        }

        if containsAny(name, ["bicep", "tricep", "arm", "pushdown", "skull crusher", "hammer curl"]) {
            groups.insert(.arms)
        }

        if containsAny(name, ["deadlift", "row", "pullup", "pull-up", "pulldown", "lat", "back", "chinup", "chin-up"]) {
            groups.insert(.back)
        }

        if name.contains("deadlift") {
            groups.formUnion([.back, .legs])
        }

        if containsAny(name, ["bench", "pushup", "push-up", "dip"]) {
            groups.insert(.arms)
        }

        if containsAny(name, ["row", "pullup", "pull-up", "pulldown", "chinup", "chin-up"]) {
            groups.insert(.arms)
        }

        if groups.isEmpty && name.contains("press") {
            groups.formUnion([.shoulders, .arms])
        }

        if groups.isEmpty && name.contains("curl") {
            groups.insert(.arms)
        }

        return groups
    }

    private static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }
}

public extension MuscleRecoveryRules {
    /// Qualitative planning evidence. No percentage or modeled recovery deadline is a measurement.
    /// Only detailed history contributes sets; linked diary summaries are deliberately not an input.
    static func regionEvidence(sessions: [WorkoutSessionLog], runs: [Run] = [],
                               checkIns: [RecoveryCheckIn] = [], sleepScore: Int?, sleepDate: Date?,
                               asOf now: Date = Date()) -> [RecoveryRegionEvidence] {
        let sleepAge = sleepDate.map { now.timeIntervalSince($0) }
        let validSleep = sleepScore.map { (0...100).contains($0) } == true
        let sleepFreshness: RecoverySleepFreshness = validSleep && sleepAge.map({ (0...129_600).contains($0) }) == true
            ? .current : (validSleep && sleepAge.map { $0 >= 0 && $0.isFinite } == true ? .stale : .unknown)
        let history = WorkoutSetMath.uniqueSessions(sessions).filter {
            $0.date.timeIntervalSince1970.isFinite && (0...14 * 86_400).contains(now.timeIntervalSince($0.date))
        }
        var seenRuns = Set<String>()
        let runEvidence = runs.sorted { $0.startDate > $1.startDate }.compactMap { run -> RecoveryRunEvidence? in
            guard run.startDate.timeIntervalSince1970.isFinite, run.endDate.timeIntervalSince1970.isFinite,
                  run.endDate >= run.startDate, run.endDate <= now,
                  (0...7 * 86_400).contains(now.timeIntervalSince(run.startDate)),
                  run.movingSeconds.isFinite, (600...172_800).contains(run.movingSeconds),
                  run.distanceMeters.isFinite, run.distanceMeters >= 100,
                  run.movingSeconds <= run.endDate.timeIntervalSince(run.startDate) + 1,
                  seenRuns.insert(run.recordingID ?? run.id).inserted else { return nil }
            return .init(id: run.recordingID ?? run.id, date: run.startDate,
                         movingMinutes: run.movingSeconds / 60, source: run.source.displayName)
        }
        return RecoveryMuscleGroup.allCases.map { group in
            let training = history.compactMap { log -> RecoveryTrainingEvidence? in
                let movements = log.completedExercises.filter {
                    $0.exercise.type == .strength && muscleGroups(for: $0.exerciseName).contains(group)
                }
                let eligible = movements.map { ($0.exerciseName, WorkoutSetMath.workingSets(in: $0).filter { $0.reps > 0 }.count) }
                    .filter { $0.1 > 0 }
                let count = eligible.reduce(0) { $0 + $1.1 }
                guard count > 0 else { return nil }
                return .init(id: log.id ?? "\(log.routineID)|\(log.date.timeIntervalSince1970)", date: log.date,
                             workingSets: count, exerciseNames: Array(Set(eligible.map(\.0))).sorted())
            }.sorted { $0.date > $1.date }
            let regionRuns: [RecoveryRunEvidence] = group == .legs ? runEvidence : []
            let observation = checkIns.filter {
                $0.group == group && $0.observedAt <= now && (try? $0.validate(asOf: now)) != nil
            }.max { $0.observedAt < $1.observedAt }
            let checkInFresh = observation.map { now.timeIntervalSince($0.observedAt) <= 72 * 3_600 } == true
            let sevenDays = training.filter { now.timeIntervalSince($0.date) <= 7 * 86_400 }
            let newest = (training.map(\.date) + regionRuns.map(\.date)).max()
            let state: RecoveryPlanningState
            if let observation, observation.needsPainReview, now.timeIntervalSince(observation.observedAt) <= 7 * 86_400 {
                state = .stopAndChange
            } else if checkInFresh && ((observation?.soreness?.rawValue ?? 0) >= 2 || (observation?.fatigue?.rawValue ?? 0) >= 2)
                || (sleepFreshness == .current && (sleepScore ?? 100) < 40 && newest != nil) {
                state = .reviewCheckIn
            } else if sevenDays.count >= 2 && sevenDays.reduce(0, { $0 + $1.workingSets }) >= 12
                || regionRuns.filter({ now.timeIntervalSince($0.date) <= 3 * 86_400 }).reduce(0, { $0 + $1.movingMinutes }) >= 90 {
                state = .accumulatedExposure
            } else if let newest { state = now.timeIntervalSince(newest) <= 72 * 3_600 ? .recentExposure : .lowerRecentLoad } else { state = .unknown }
            return RecoveryRegionEvidence(modelVersion: "exposure-v2", group: group, asOf: now,
                training: training, runs: regionRuns, sleepScore: validSleep ? sleepScore : nil, sleepDate: sleepDate,
                sleepFreshness: sleepFreshness, checkIn: observation, checkInIsFresh: checkInFresh, state: state)
        }
    }
}
