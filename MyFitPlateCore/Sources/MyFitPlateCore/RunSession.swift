import Foundation

/// One GPS fix, decoupled from CoreLocation so the session math is testable.
/// The app layer maps CLLocation → RunLocationFix.
public struct RunLocationFix: Equatable {
    public let latitude: Double
    public let longitude: Double
    /// Meters; negative means invalid (CoreLocation convention).
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

/// Live run state machine: filters GPS noise, accumulates distance, cuts splits at each
/// km/mile boundary, and freezes while paused. Pure logic — no timers, no CoreLocation;
/// callers push fixes in and read the published-style properties out.
public final class RunSession {

    public enum State: Equatable {
        case ready
        case running
        case paused
        case finished
    }

    /// Fixes with accuracy worse than this are noise (parking garages, city canyons).
    public static let accuracyCutoffMeters: Double = 30
    /// Faster than 2:00 min/km is not running — treat as a GPS teleport and drop it.
    public static let maxPlausibleSpeedMetersPerSecond: Double = 8.4
    /// A fix gap longer than this contributes distance but not moving time beyond the cap
    /// (signal loss under a bridge shouldn't count as a 3-minute split effort).
    public static let movingTimeGapCapSeconds: Double = 15

    public private(set) var state: State = .ready
    public private(set) var distanceMeters: Double = 0
    public private(set) var movingSeconds: Double = 0
    public private(set) var completedSplits: [RunSplit] = []
    public private(set) var routePointCount: Int = 0
    public private(set) var startDate: Date?

    /// Optional callback invoked whenever a new split is completed (for audio announcements / haptics).
    public var onSplitCompleted: ((RunSplit) -> Void)?

    /// Meters per split boundary: 1000 (metric) or one mile.
    public let splitDistanceMeters: Double

    private var lastAcceptedFix: RunLocationFix?
    private var distanceIntoCurrentSplit: Double = 0
    private var secondsIntoCurrentSplit: Double = 0
    private var pauseBegan: Date?
    private var recentSegments: [(meters: Double, seconds: Double, at: Date)] = []

    public init(metric: Bool) {
        self.splitDistanceMeters = metric ? 1000 : RunFormat.metersPerMile
    }

    // MARK: Lifecycle

    public func start(at date: Date = Date()) {
        guard state == .ready else { return }
        state = .running
        startDate = date
    }

    public func pause(at date: Date = Date()) {
        guard state == .running else { return }
        state = .paused
        pauseBegan = date
        // The segment leading into a pause is over; don't bridge across it.
        lastAcceptedFix = nil
    }

    public func resume(at date: Date = Date()) {
        guard state == .paused else { return }
        state = .running
        pauseBegan = nil
    }

    /// Ends the session and returns the completed run. The tail of an unfinished split is
    /// kept as a partial split so short runs still show their work.
    public func finish(at date: Date = Date()) -> Run? {
        guard state == .running || state == .paused, let startDate else { return nil }
        state = .finished

        var splits = completedSplits
        if distanceIntoCurrentSplit > 50 {
            splits.append(RunSplit(
                index: splits.count + 1,
                distanceMeters: distanceIntoCurrentSplit,
                seconds: secondsIntoCurrentSplit
            ))
        }

        return Run(
            source: .recorded,
            startDate: startDate,
            endDate: date,
            distanceMeters: distanceMeters,
            movingSeconds: movingSeconds,
            splits: splits,
            hasRoute: routePointCount > 1
        )
    }

    // MARK: Live metrics

    /// Rolling pace over roughly the last minute of movement; nil until there's enough signal.
    public var currentPaceSecondsPerKm: Double? {
        let window = recentSegments.suffix(while: { segment in
            guard let newest = recentSegments.last else { return false }
            return newest.at.timeIntervalSince(segment.at) <= 60
        })
        let meters = window.reduce(0) { $0 + $1.meters }
        let seconds = window.reduce(0) { $0 + $1.seconds }
        guard meters > 25, seconds > 5 else { return nil }
        return seconds / (meters / 1000)
    }

    public var averagePaceSecondsPerKm: Double? {
        guard distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceMeters / 1000)
    }

    // MARK: Fix ingestion

    public func ingest(_ fix: RunLocationFix) {
        guard state == .running else { return }
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.accuracyCutoffMeters else { return }

        guard let previous = lastAcceptedFix else {
            lastAcceptedFix = fix
            routePointCount += 1
            return
        }

        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return }

        let meters = Self.haversineMeters(
            lat1: previous.latitude, lon1: previous.longitude,
            lat2: fix.latitude, lon2: fix.longitude
        )

        // Teleport filter: implausible speed means one of the fixes is garbage.
        guard meters / seconds <= Self.maxPlausibleSpeedMetersPerSecond else {
            lastAcceptedFix = fix
            return
        }

        lastAcceptedFix = fix
        routePointCount += 1

        let countedSeconds = min(seconds, Self.movingTimeGapCapSeconds)
        distanceMeters += meters
        movingSeconds += countedSeconds
        recentSegments.append((meters: meters, seconds: countedSeconds, at: fix.timestamp))
        if recentSegments.count > 120 {
            recentSegments.removeFirst(recentSegments.count - 120)
        }

        accumulateSplit(meters: meters, seconds: countedSeconds)
    }

    private func accumulateSplit(meters: Double, seconds: Double) {
        var remainingMeters = meters
        var remainingSeconds = seconds

        // A single segment can cross a boundary; apportion its time by distance.
        while distanceIntoCurrentSplit + remainingMeters >= splitDistanceMeters {
            let metersToBoundary = splitDistanceMeters - distanceIntoCurrentSplit
            let fraction = remainingMeters > 0 ? metersToBoundary / remainingMeters : 0
            let secondsToBoundary = remainingSeconds * fraction

            let newSplit = RunSplit(
                index: completedSplits.count + 1,
                distanceMeters: splitDistanceMeters,
                seconds: secondsIntoCurrentSplit + secondsToBoundary
            )
            completedSplits.append(newSplit)
            onSplitCompleted?(newSplit)

            remainingMeters -= metersToBoundary
            remainingSeconds -= secondsToBoundary
            distanceIntoCurrentSplit = 0
            secondsIntoCurrentSplit = 0
        }

        distanceIntoCurrentSplit += remainingMeters
        secondsIntoCurrentSplit += remainingSeconds
    }

    // MARK: Geometry

    public static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private extension Array {
    /// Longest suffix whose elements all satisfy the predicate.
    func suffix(while predicate: (Element) -> Bool) -> [Element] {
        var result: [Element] = []
        for element in reversed() {
            guard predicate(element) else { break }
            result.append(element)
        }
        return result.reversed()
    }
}
