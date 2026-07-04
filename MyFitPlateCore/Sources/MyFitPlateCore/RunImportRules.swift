import Foundation

/// A HealthKit workout flattened to plain values so import logic is testable.
/// The app layer maps HKWorkout → ImportedWorkoutSummary (sourceName comes from
/// sourceRevision.source.name — "Garmin Connect", "Polar Flow", "Apple Watch", ...).
public struct ImportedWorkoutSummary: Equatable {
    public enum Activity: Equatable {
        case running
        case walking
        case hiking
        case cycling
        case other
    }

    public let uuid: String
    public let activity: Activity
    public let startDate: Date
    public let endDate: Date
    public let distanceMeters: Double?
    public let activeCalories: Double?
    public let averageHeartRate: Double?
    public let sourceName: String
    public let sourceBundleID: String
    public let isIndoor: Bool
    public let hasRoute: Bool

    public init(
        uuid: String,
        activity: Activity,
        startDate: Date,
        endDate: Date,
        distanceMeters: Double?,
        activeCalories: Double? = nil,
        averageHeartRate: Double? = nil,
        sourceName: String,
        sourceBundleID: String,
        isIndoor: Bool = false,
        hasRoute: Bool = false
    ) {
        self.uuid = uuid
        self.activity = activity
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.isIndoor = isIndoor
        self.hasRoute = hasRoute
    }
}

/// Rules for turning HealthKit workouts from ANY watch into MyFitPlate runs.
/// Garmin, Polar, Coros, Suunto, Whoop etc. all sync workouts into Apple Health via
/// their companion apps, so reading source-agnostically covers every watch without
/// vendor APIs. The cost is duplicates — handled here.
public enum RunImportRules {

    /// Workouts our own recorder wrote back to HealthKit must not be re-imported.
    public static func isOwnRecording(sourceBundleID: String) -> Bool {
        sourceBundleID.hasPrefix("MyFitPlate.")
    }

    /// Whether this workout should appear in the running feature at all.
    /// Walks/hikes/rides stay out of run stats (they'd wreck pace PRs) — running only,
    /// indoor treadmill included.
    public static func isImportableRun(_ workout: ImportedWorkoutSummary) -> Bool {
        guard workout.activity == .running else { return false }
        guard !isOwnRecording(sourceBundleID: workout.sourceBundleID) else { return false }
        guard workout.endDate > workout.startDate else { return false }
        // A "run" with no distance and under 2 minutes is a false start / watch fumble.
        let duration = workout.endDate.timeIntervalSince(workout.startDate)
        if (workout.distanceMeters ?? 0) < 100 && duration < 120 { return false }
        return true
    }

    public static func run(from workout: ImportedWorkoutSummary) -> Run {
        Run(
            id: workout.uuid,
            source: .imported(appName: workout.sourceName),
            startDate: workout.startDate,
            endDate: workout.endDate,
            distanceMeters: workout.distanceMeters ?? 0,
            movingSeconds: workout.endDate.timeIntervalSince(workout.startDate),
            activeCalories: workout.activeCalories,
            averageHeartRate: workout.averageHeartRate,
            isIndoor: workout.isIndoor,
            hasRoute: workout.hasRoute
        )
    }

    /// Collapses the same physical run recorded by two devices worn at once (Apple Watch
    /// on one wrist, Garmin on the other — a real MyFitPlate-user scenario). Two runs are
    /// duplicates when their time windows overlap ≥ 70% of the shorter one and distances
    /// agree within 15%. The richer recording wins: route > heart rate > longer distance.
    public static func deduplicated(_ runs: [Run]) -> [Run] {
        var kept: [Run] = []
        for candidate in runs.sorted(by: { $0.startDate < $1.startDate }) {
            if let index = kept.firstIndex(where: { isDuplicate($0, candidate) }) {
                if richness(of: candidate) > richness(of: kept[index]) {
                    kept[index] = candidate
                }
            } else {
                kept.append(candidate)
            }
        }
        return kept
    }

    static func isDuplicate(_ a: Run, _ b: Run) -> Bool {
        let overlapStart = max(a.startDate, b.startDate)
        let overlapEnd = min(a.endDate, b.endDate)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }

        let shorter = min(
            a.endDate.timeIntervalSince(a.startDate),
            b.endDate.timeIntervalSince(b.startDate)
        )
        guard shorter > 0, overlap / shorter >= 0.7 else { return false }

        let maxDistance = max(a.distanceMeters, b.distanceMeters)
        guard maxDistance > 0 else { return true }
        return abs(a.distanceMeters - b.distanceMeters) / maxDistance <= 0.15
    }

    private static func richness(of run: Run) -> Int {
        var score = 0
        if run.hasRoute { score += 4 }
        if run.averageHeartRate != nil { score += 2 }
        if run.activeCalories != nil { score += 1 }
        // In-app recordings carry splits; prefer them over a bare import at equal richness.
        if case .recorded = run.source { score += 1 }
        return score
    }
}
