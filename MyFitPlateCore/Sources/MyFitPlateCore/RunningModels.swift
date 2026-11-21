import Foundation

/// A completed run — recorded in-app or imported from any watch whose companion app
/// syncs workouts to Apple Health (Garmin Connect, Polar Flow, Coros, Whoop, ...).
public struct Run: Codable, Identifiable, Equatable {
    public enum Source: Codable, Equatable {
        /// Recorded by MyFitPlate's own GPS tracker.
        case recorded
        /// Imported from HealthKit; `appName` is the writing app ("Garmin Connect", "Apple Watch").
        case imported(appName: String)

        public var displayName: String {
            switch self {
            case .recorded: return "MyFitPlate"
            case .imported(let appName): return appName
            }
        }
    }

    public let id: String
    public var source: Source
    public var startDate: Date
    public var endDate: Date
    public var distanceMeters: Double
    /// Seconds actually moving. For imports this is the workout duration; the in-app
    /// recorder excludes paused time.
    public var movingSeconds: Double
    public var activeCalories: Double?
    public var averageHeartRate: Double?
    public var isIndoor: Bool
    public var splits: [RunSplit]
    public var hasRoute: Bool
    public var shoeID: String?
    /// Nil is legacy/import/manual timing with unknown pause locations.
    public var pauseTimeline: RunPauseTimeline?
    /// Original in-app recording identity, retained when Health assigns its UUID.
    public var recordingID: String?
    /// Accepted segment starts; maps and exports must not bridge these boundaries.
    public var routeSegmentStarts: [Date]?
    /// Exact reviewed calendar/program slot, retained through recovery and Health aliases.
    public var scheduledContext: RunScheduledContext?
    /// Exact completed step receipt committed atomically with the local run.
    public var workoutResult: RunWorkoutResult?
    /// A display-only, reversible MyFitPlate correction; original evidence stays in its receipt.
    public var reviewAnnotation: RunReviewAnnotation?
    public var manualLaps: [RunManualLap]?
    public var sensors: RunSensorCheckpoint?
    public var saveReview: RunSaveReview?

    public init(
        id: String = UUID().uuidString,
        source: Source,
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        movingSeconds: Double,
        activeCalories: Double? = nil,
        averageHeartRate: Double? = nil,
        isIndoor: Bool = false,
        splits: [RunSplit] = [],
        hasRoute: Bool = false,
        shoeID: String? = nil,
        pauseTimeline: RunPauseTimeline? = nil,
        recordingID: String? = nil,
        routeSegmentStarts: [Date]? = nil,
        scheduledContext: RunScheduledContext? = nil,
        workoutResult: RunWorkoutResult? = nil,
        reviewAnnotation: RunReviewAnnotation? = nil,
        manualLaps: [RunManualLap]? = nil,
        sensors: RunSensorCheckpoint? = nil,
        saveReview: RunSaveReview? = nil
    ) {
        self.id = id
        self.source = source
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.isIndoor = isIndoor
        self.splits = splits
        self.hasRoute = hasRoute
        self.shoeID = shoeID
        self.pauseTimeline = pauseTimeline
        self.recordingID = recordingID
        self.routeSegmentStarts = routeSegmentStarts
        self.scheduledContext = scheduledContext
        self.workoutResult = workoutResult
        self.reviewAnnotation = reviewAnnotation
        self.manualLaps = manualLaps
        self.sensors = sensors
        self.saveReview = saveReview
    }

    /// Change persistence identity without dropping recording metadata.
    public func reidentified(as newID: String) -> Run {
        var receipt = workoutResult
        receipt?.runID = newID
        return Run(id: newID, source: source, startDate: startDate, endDate: endDate,
            distanceMeters: distanceMeters, movingSeconds: movingSeconds, activeCalories: activeCalories,
            averageHeartRate: averageHeartRate, isIndoor: isIndoor, splits: splits, hasRoute: hasRoute,
            shoeID: shoeID, pauseTimeline: pauseTimeline, recordingID: recordingID, routeSegmentStarts: routeSegmentStarts, scheduledContext: scheduledContext, workoutResult: receipt, reviewAnnotation: reviewAnnotation, manualLaps: manualLaps, sensors: sensors, saveReview: saveReview)
    }

    /// Average pace in seconds per kilometer; nil when the run is too short to be meaningful.
    public var averagePaceSecondsPerKm: Double? {
        guard distanceMeters.isFinite, movingSeconds.isFinite, distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceMeters / 1000)
    }
}

public enum ManualRunEntryRules {
    public static let maximumDistanceMeters: Double = 500_000
    public static let maximumDurationSeconds: Double = 48 * 60 * 60

    public static func buildIndoorRun(
        startDate: Date,
        distanceMeters: Double,
        movingSeconds: Double,
        metric: Bool,
        activeCalories: Double? = nil,
        confirmShortRecording: Bool = false
    ) -> Run? {
        guard startDate.timeIntervalSinceReferenceDate.isFinite,
              distanceMeters.isFinite, (0...maximumDistanceMeters).contains(distanceMeters),
              movingSeconds.isFinite, (RunSaveReviewRules.minimumActiveSeconds...maximumDurationSeconds).contains(movingSeconds),
              activeCalories.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        let review = RunSaveReviewRules.requirement(activeSeconds: movingSeconds, distanceMeters: distanceMeters)
        guard review == .standard || confirmShortRecording else { return nil }
        let safeDistance = max(0, distanceMeters)
        let safeSeconds = max(0, movingSeconds)
        let recordingID = UUID().uuidString

        return Run(
            id: recordingID,
            source: .recorded,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(safeSeconds),
            distanceMeters: safeDistance,
            movingSeconds: safeSeconds,
            activeCalories: activeCalories,
            isIndoor: true,
            splits: splits(distanceMeters: safeDistance, movingSeconds: safeSeconds, metric: metric),
            hasRoute: false,
            recordingID: recordingID,
            saveReview: review == .shortRecording ? .shortRecording : .standard
        )
    }

    public static func splits(distanceMeters: Double, movingSeconds: Double, metric: Bool) -> [RunSplit] {
        guard distanceMeters.isFinite, distanceMeters > 50, distanceMeters <= maximumDistanceMeters,
              movingSeconds.isFinite, movingSeconds > 0, movingSeconds <= maximumDurationSeconds else { return [] }
        let splitDistance = metric ? 1000.0 : RunFormat.metersPerMile
        let fullSplitCount = Int(distanceMeters / splitDistance)
        let remainingMeters = distanceMeters - (Double(fullSplitCount) * splitDistance)
        let secondsPerMeter = movingSeconds / distanceMeters

        var splits: [RunSplit] = (0..<fullSplitCount).map { index in
            RunSplit(
                index: index + 1,
                distanceMeters: splitDistance,
                seconds: splitDistance * secondsPerMeter
            )
        }

        if remainingMeters > 50 {
            splits.append(RunSplit(
                index: splits.count + 1,
                distanceMeters: remainingMeters,
                seconds: remainingMeters * secondsPerMeter
            ))
        }

        return splits
    }
}

/// One completed distance interval (per km or per mile, by the user's unit setting).
public struct RunSplit: Codable, Equatable {
    /// 1-based split number.
    public let index: Int
    public let distanceMeters: Double
    public let seconds: Double

    public init(index: Int, distanceMeters: Double, seconds: Double) {
        self.index = index
        self.distanceMeters = distanceMeters
        self.seconds = seconds
    }

    public var paceSecondsPerKm: Double? {
        guard distanceMeters.isFinite, seconds.isFinite, distanceMeters > 0, seconds >= 0 else { return nil }
        return seconds / (distanceMeters / 1000)
    }
}

/// Formatting for distance and pace, honoring the app's metric preference.
/// DESIGN.md rule 3: units attached, no bare numbers, no raw doubles.
public enum RunFormat {
    public static let metersPerMile = 1609.344

    public static func distanceText(meters: Double, metric: Bool) -> String {
        if metric {
            let km = meters / 1000
            return km >= 10
                ? String(format: "%.1f km", km)
                : String(format: "%.2f km", km)
        }
        let miles = meters / metersPerMile
        return miles >= 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.2f mi", miles)
    }

    /// "5:32 /km" or "8:54 /mi". Returns nil for paces too slow/fast to be a run reading.
    public static func paceText(secondsPerKm: Double?, metric: Bool) -> String? {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return nil }
        let perUnit = metric ? secondsPerKm : secondsPerKm * (metersPerMile / 1000)
        guard perUnit < 40 * 60 else { return nil }
        let whole = Int(perUnit.rounded())
        return String(format: "%d:%02d %@", whole / 60, whole % 60, metric ? "/km" : "/mi")
    }

    public static func durationText(seconds: Double) -> String {
        guard seconds.isFinite, (0...Double(Int32.max - 1)).contains(seconds) else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func paceDiffText(secondsPerKmDiff: Double, metric: Bool) -> String {
        guard secondsPerKmDiff.isFinite else { return "" }
        let perUnitDiff = metric ? secondsPerKmDiff : secondsPerKmDiff * (metersPerMile / 1000)
        guard perUnitDiff.isFinite, abs(perUnitDiff) <= Double(Int32.max - 1) else { return "" }
        let absSec = abs(Int(perUnitDiff.rounded()))
        let sign = perUnitDiff < -0.5 ? "-" : (perUnitDiff > 0.5 ? "+" : "")
        let mins = absSec / 60
        let secs = absSec % 60
        return String(format: "%@%d:%02d %@", sign, mins, secs, metric ? "/km" : "/mi")
    }
}

/// A pair of running shoes tracked for mileage and wear-and-tear replacement alerts.
public struct RunningShoe: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var brand: String
    /// Initial mileage already on the shoe when added to the app (in meters).
    public var initialMeters: Double
    /// Maximum recommended mileage before replacement (default ~350 miles / ~563,270 meters).
    public var maxMeters: Double
    public var isRetired: Bool
    public var isDefault: Bool
    public var addedDate: Date
    public var nickname: String?
    public var acquiredDate: Date?
    public var ownershipConfirmed: Bool?
    public var isUnconfirmedPlaceholder: Bool { ownershipConfirmed != true && brand == "Default" && name == "Road Trainer" }
    public var displayName: String {
        if let nickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty { return nickname }
        return "\(brand) \(name)"
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        brand: String,
        initialMeters: Double = 0,
        maxMeters: Double = 563270.4, // ~350 miles
        isRetired: Bool = false,
        isDefault: Bool = false,
        addedDate: Date = Date(),
        nickname: String? = nil,
        acquiredDate: Date? = nil,
        ownershipConfirmed: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.initialMeters = initialMeters
        self.maxMeters = maxMeters
        self.isRetired = isRetired
        self.isDefault = isDefault
        self.addedDate = addedDate
        self.nickname = nickname
        self.acquiredDate = acquiredDate
        self.ownershipConfirmed = ownershipConfirmed
    }

    /// Returns wear percentage (0.0 to 1.0+) given total accumulated meters.
    public func wearPercentage(totalMeters: Double) -> Double {
        guard maxMeters.isFinite, totalMeters.isFinite, maxMeters > 0 else { return 0 }
        return max(0, totalMeters / maxMeters)
    }

    /// True if the shoe has exceeded its recommended mileage limit.
    public func isWornOut(totalMeters: Double) -> Bool {
        totalMeters >= maxMeters
    }
}
