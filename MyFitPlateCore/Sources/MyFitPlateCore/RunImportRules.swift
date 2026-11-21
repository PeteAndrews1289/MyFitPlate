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
    /// HealthKit's active workout duration, which excludes recorded pauses.
    /// Nil preserves the start/end fallback for older adapters and imported fixtures.
    public let durationSeconds: Double?
    /// Original recorder identity read from our Health workout metadata.
    public let recordingID: String?
    public let saveReview: RunSaveReview?

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
        hasRoute: Bool = false,
        durationSeconds: Double? = nil,
        recordingID: String? = nil,
        saveReview: RunSaveReview? = nil
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
        self.durationSeconds = durationSeconds
        self.recordingID = recordingID
        self.saveReview = saveReview
    }
}

/// Rules for turning HealthKit workouts from ANY watch into MyFitPlate runs.
/// Garmin, Polar, Coros, Suunto, Whoop etc. all sync workouts into Apple Health via
/// their companion apps, so reading source-agnostically covers every watch without
/// vendor APIs. The cost is duplicates — handled here.
public enum RunImportRules {

    /// Workouts our own recorder wrote back to HealthKit are still imported from Apple
    /// Health, but shown as MyFitPlate-recorded runs instead of third-party imports.
    public static func isOwnRecording(sourceBundleID: String) -> Bool {
        sourceBundleID.hasPrefix("MyFitPlate.")
    }

    /// Whether this workout should appear in the running feature at all.
    /// Walks/hikes/rides stay out of run stats (they'd wreck pace PRs) — running only,
    /// indoor treadmill included.
    public static func isImportableRun(_ workout: ImportedWorkoutSummary) -> Bool {
        guard workout.activity == .running, workout.startDate.timeIntervalSinceReferenceDate.isFinite,
              workout.endDate.timeIntervalSinceReferenceDate.isFinite, workout.endDate > workout.startDate else { return false }
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        if let active = workout.durationSeconds {
            guard active.isFinite, active >= RunSaveReviewRules.minimumActiveSeconds, active <= elapsed + 0.001 else { return false }
        }
        let active = activeDuration(for: workout), distance = workout.distanceMeters ?? 0
        guard RunSaveReviewRules.requirement(activeSeconds: active, distanceMeters: distance) != .empty else { return false }
        if trustedSaveReview(for: workout) != nil { return true }
        return RunSaveReviewRules.canAutomaticallyImport(activeSeconds: active, distanceMeters: distance)
    }

    public static func run(from workout: ImportedWorkoutSummary) -> Run {
        Run(
            id: workout.uuid,
            source: isOwnRecording(sourceBundleID: workout.sourceBundleID)
                ? .recorded
                : .imported(appName: workout.sourceName),
            startDate: workout.startDate,
            endDate: workout.endDate,
            distanceMeters: workout.distanceMeters ?? 0,
            movingSeconds: activeDuration(for: workout),
            activeCalories: workout.activeCalories,
            averageHeartRate: workout.averageHeartRate,
            isIndoor: workout.isIndoor,
            hasRoute: workout.hasRoute,
            recordingID: isOwnRecording(sourceBundleID: workout.sourceBundleID)
                ? workout.recordingID.flatMap { $0.isEmpty ? nil : $0 } : nil,
            saveReview: trustedSaveReview(for: workout)
        )
    }

    private static func trustedSaveReview(for workout: ImportedWorkoutSummary) -> RunSaveReview? {
        // Health supplies the source bundle identity; arbitrary foreign metadata and
        // prefix lookalikes cannot opt out of automatic-import false-start filtering.
        guard ["MyFitPlate.CalorieBeta", "MyFitPlate.CalorieBeta.watchkitapp"].contains(workout.sourceBundleID),
              let id = workout.recordingID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return workout.saveReview
    }

    private static func activeDuration(for workout: ImportedWorkoutSummary) -> Double {
        let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        guard let duration = workout.durationSeconds, duration.isFinite, duration > 0,
              duration <= elapsed else { return elapsed }
        return duration
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
        return kept.sorted { $0.startDate > $1.startDate }
    }

    static func isDuplicate(_ a: Run, _ b: Run) -> Bool {
        if a.id == b.id { return true }
        if a.source == .recorded, b.source == .recorded,
           (a.recordingID ?? a.id) == (b.recordingID ?? b.id) { return true }
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
        // Zero measured distance supplies no evidence of a shared physical run.
        // A deliberately saved short run may have a long wall window due to pauses.
        // Exact recording/Health identities above still reconcile their copies.
        guard maxDistance > 0 else { return false }
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
