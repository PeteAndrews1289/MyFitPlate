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
        shoeID: String? = nil
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
    }

    /// Average pace in seconds per kilometer; nil when the run is too short to be meaningful.
    public var averagePaceSecondsPerKm: Double? {
        guard distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceMeters / 1000)
    }
}

public enum ManualRunEntryRules {
    public static func buildIndoorRun(
        startDate: Date,
        distanceMeters: Double,
        movingSeconds: Double,
        metric: Bool,
        activeCalories: Double? = nil
    ) -> Run? {
        guard distanceMeters >= 100, movingSeconds >= 60 else { return nil }
        let safeDistance = max(0, distanceMeters)
        let safeSeconds = max(0, movingSeconds)

        return Run(
            source: .recorded,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(safeSeconds),
            distanceMeters: safeDistance,
            movingSeconds: safeSeconds,
            activeCalories: activeCalories,
            isIndoor: true,
            splits: splits(distanceMeters: safeDistance, movingSeconds: safeSeconds, metric: metric),
            hasRoute: false
        )
    }

    public static func splits(distanceMeters: Double, movingSeconds: Double, metric: Bool) -> [RunSplit] {
        guard distanceMeters > 50, movingSeconds > 0 else { return [] }
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
        guard distanceMeters > 0 else { return nil }
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

    public init(
        id: String = UUID().uuidString,
        name: String,
        brand: String,
        initialMeters: Double = 0,
        maxMeters: Double = 563270.4, // ~350 miles
        isRetired: Bool = false,
        isDefault: Bool = false,
        addedDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.initialMeters = initialMeters
        self.maxMeters = maxMeters
        self.isRetired = isRetired
        self.isDefault = isDefault
        self.addedDate = addedDate
    }

    /// Returns wear percentage (0.0 to 1.0+) given total accumulated meters.
    public func wearPercentage(totalMeters: Double) -> Double {
        guard maxMeters > 0 else { return 0 }
        return totalMeters / maxMeters
    }

    /// True if the shoe has exceeded its recommended mileage limit.
    public func isWornOut(totalMeters: Double) -> Bool {
        totalMeters >= maxMeters
    }
}
