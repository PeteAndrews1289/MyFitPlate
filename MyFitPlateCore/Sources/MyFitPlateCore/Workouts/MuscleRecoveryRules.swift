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

    public init(
        group: RecoveryMuscleGroup,
        lastTrained: Date?,
        lastSessionSets: Int,
        recoveryHours: Double,
        sleepMultiplier: Double,
        asOf: Date
    ) {
        self.group = group
        self.lastTrained = lastTrained
        self.lastSessionSets = lastSessionSets
        self.recoveryHours = recoveryHours
        self.sleepMultiplier = sleepMultiplier
        self.asOf = asOf
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
        return MuscleRecoveryEstimate(
            group: group,
            lastTrained: lastTrained,
            lastSessionSets: sets ?? 0,
            recoveryHours: recoveryWindowHours(
                group: group,
                sets: sets,
                wellnessMultiplier: multiplier
            ),
            sleepMultiplier: multiplier,
            asOf: asOf
        )
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
