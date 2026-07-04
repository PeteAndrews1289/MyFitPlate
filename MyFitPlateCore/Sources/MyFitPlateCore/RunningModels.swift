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
        hasRoute: Bool = false
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
    }

    /// Average pace in seconds per kilometer; nil when the run is too short to be meaningful.
    public var averagePaceSecondsPerKm: Double? {
        guard distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceMeters / 1000)
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
}
