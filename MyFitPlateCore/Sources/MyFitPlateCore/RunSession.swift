import Foundation

/// One GPS fix, decoupled from CoreLocation so the session math is testable.
/// The app layer maps CLLocation → RunLocationFix.
public struct RunLocationFix: Codable, Equatable, Sendable {
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

    /// Coordinate-free recovery state. A restored recorder always waits paused for
    /// an explicit resume and a fresh GPS anchor.
    public struct Snapshot: Codable, Equatable {
        public let id: String
        public let recordedAt: Date
        public let startDate: Date
        public let timeAccounting: TimeAccounting
        public let splitDistanceMeters: Double
        public let distanceMeters: Double
        public let movingSeconds: Double
        public let activeElapsedSeconds: Double
        public let completedSplits: [RunSplit]
        public let distanceIntoCurrentSplit: Double
        public let secondsIntoCurrentSplit: Double
        /// Optional so checkpoints written before exact pause tracking remain readable.
        public let pauseTimeline: RunPauseTimeline?
        public var manualLaps: [RunManualLap]?
    }

    public enum State: Equatable {
        case ready
        case running
        case paused
        case finished
    }

    public enum TimeAccounting: String, Codable, Equatable, Sendable {
        /// Live pace ignores most of a long GPS outage so one sparse fix cannot ruin
        /// audio cues or an in-progress split.
        case moving
        /// Historical replay retains the full interval between route fixes so displayed
        /// splits reconcile with the HealthKit workout duration.
        case elapsed
        /// Recorder time comes from the active clock, including time without GPS.
        /// Only an explicit pause excludes time; sparse fixes never invent a fast pace.
        case activeElapsed
    }

    /// Fixes with accuracy worse than this are noise (parking garages, city canyons).
    public static let accuracyCutoffMeters: Double = 30
    /// Faster than 2:00 min/km is not running — treat as a GPS teleport and drop it.
    public static let maxPlausibleSpeedMetersPerSecond: Double = 8.4
    /// A fix gap longer than this contributes distance but not moving time beyond the cap
    /// (signal loss under a bridge shouldn't count as a 3-minute split effort).
    public static let movingTimeGapCapSeconds: Double = 15

    public private(set) var state: State = .ready
    public let id: String
    public private(set) var distanceMeters: Double = 0
    public private(set) var movingSeconds: Double = 0
    public private(set) var completedSplits: [RunSplit] = []
    public private(set) var routePointCount: Int = 0
    public private(set) var manualLaps: [RunManualLap] = []
    /// True only for the most recently accepted point when its map segment needs a new anchor.
    public private(set) var lastIngestStartedSegment = false
    public private(set) var startDate: Date?
    public private(set) var lastAcceptedFixTimestamp: Date?
    public private(set) var pauseTimeline: RunPauseTimeline

    /// Optional callback invoked whenever a new split is completed (for audio announcements / haptics).
    public var onSplitCompleted: ((RunSplit) -> Void)?

    /// Meters per split boundary: 1000 (metric) or one mile.
    public let splitDistanceMeters: Double

    private let timeAccounting: TimeAccounting
    private var lastAcceptedFix: RunLocationFix?
    private var distanceIntoCurrentSplit: Double = 0
    private var secondsIntoCurrentSplit: Double = 0
    private var pauseBegan: Date?
    private var pausedSeconds: Double = 0
    private var activeSegmentStartedAt: Date?
    private var finishedAt: Date?
    private var recentSegments: [(meters: Double, seconds: Double, at: Date)] = []

    public init(metric: Bool, timeAccounting: TimeAccounting = .moving, id: String = UUID().uuidString) {
        self.id = id
        self.splitDistanceMeters = metric ? 1000 : RunFormat.metersPerMile
        self.timeAccounting = timeAccounting
        self.pauseTimeline = RunPauseTimeline(completeness: timeAccounting == .activeElapsed ? .complete : .partial)
    }

    public convenience init?(snapshot: Snapshot, at date: Date = Date()) {
        guard Self.valid(snapshot: snapshot), date.timeIntervalSinceReferenceDate.isFinite,
              date >= snapshot.recordedAt else { return nil }
        let previousTimeline = snapshot.pauseTimeline ?? RunPauseTimeline(completeness: .partial)
        let recoveredTimeline: RunPauseTimeline
        if previousTimeline.openPause != nil {
            // Keep an existing explicit pause or original recovery checkpoint across
            // repeated restores. Moving it to this restore would lose excluded time.
            recoveredTimeline = previousTimeline
        } else {
            guard let opened = previousTimeline.openingPause(at: snapshot.recordedAt, origin: .recoveryGap) else { return nil }
            recoveredTimeline = opened
        }
        guard recoveredTimeline.validatedUnionIntervals(startDate: snapshot.startDate, endDate: date,
                                                        activeSeconds: snapshot.activeElapsedSeconds,
                                                        allowOpenPause: true) != nil else { return nil }
        self.init(metric: snapshot.splitDistanceMeters == 1000, timeAccounting: snapshot.timeAccounting, id: snapshot.id)
        startDate = snapshot.startDate
        distanceMeters = snapshot.distanceMeters
        movingSeconds = snapshot.movingSeconds
        completedSplits = snapshot.completedSplits
        manualLaps = snapshot.manualLaps ?? []
        distanceIntoCurrentSplit = snapshot.distanceIntoCurrentSplit
        secondsIntoCurrentSplit = snapshot.secondsIntoCurrentSplit
        // Exclude the entire time away, including time between checkpoint and crash.
        pausedSeconds = max(0, date.timeIntervalSince(snapshot.startDate) - snapshot.activeElapsedSeconds)
        pauseBegan = date
        pauseTimeline = recoveredTimeline
        activeSegmentStartedAt = date
        state = .paused
    }

    public func snapshot(at date: Date = Date()) -> Snapshot? {
        guard state == .running || state == .paused, let startDate, validLifecycleDate(date) else { return nil }
        let elapsed = activeElapsedSeconds(at: date)
        let additional = timeAccounting == .activeElapsed ? max(0, elapsed - movingSeconds) : 0
        let result = Snapshot(id: id, recordedAt: date, startDate: startDate, timeAccounting: timeAccounting,
                              splitDistanceMeters: splitDistanceMeters, distanceMeters: distanceMeters,
                              movingSeconds: movingSeconds + additional, activeElapsedSeconds: elapsed,
                              completedSplits: completedSplits, distanceIntoCurrentSplit: distanceIntoCurrentSplit,
                              secondsIntoCurrentSplit: secondsIntoCurrentSplit + additional,
                              pauseTimeline: pauseTimeline, manualLaps: manualLaps.isEmpty ? nil : manualLaps)
        return Self.valid(snapshot: result) ? result : nil
    }

    private static func valid(snapshot: Snapshot) -> Bool {
        guard !snapshot.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.startDate.timeIntervalSinceReferenceDate.isFinite,
              snapshot.recordedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.recordedAt >= snapshot.startDate,
              [1000, RunFormat.metersPerMile].contains(snapshot.splitDistanceMeters),
              [snapshot.distanceMeters, snapshot.movingSeconds, snapshot.activeElapsedSeconds,
               snapshot.distanceIntoCurrentSplit, snapshot.secondsIntoCurrentSplit].allSatisfy({ $0.isFinite && $0 >= 0 }),
              snapshot.activeElapsedSeconds <= snapshot.recordedAt.timeIntervalSince(snapshot.startDate) + 0.001,
              snapshot.distanceIntoCurrentSplit < snapshot.splitDistanceMeters,
              snapshot.completedSplits.count <= 10_000,
              snapshot.completedSplits.enumerated().allSatisfy({ index, split in
                  split.index == index + 1 && split.distanceMeters == snapshot.splitDistanceMeters
                      && split.seconds.isFinite && split.seconds >= 0
              }) else { return false }
        let distance = snapshot.completedSplits.reduce(snapshot.distanceIntoCurrentSplit) { $0 + $1.distanceMeters }
        let seconds = snapshot.completedSplits.reduce(snapshot.secondsIntoCurrentSplit) { $0 + $1.seconds }
        guard abs(distance - snapshot.distanceMeters) < 0.01, abs(seconds - snapshot.movingSeconds) < 0.01,
              snapshot.timeAccounting != .activeElapsed
                || abs(snapshot.movingSeconds - snapshot.activeElapsedSeconds) <= RunPauseTimeline.toleranceSeconds else { return false }
        guard RunManualLap.valid(snapshot.manualLaps ?? [], recordingID: snapshot.id, start: snapshot.startDate,
            end: snapshot.recordedAt, activeSeconds: snapshot.activeElapsedSeconds, distanceMeters: snapshot.distanceMeters) else { return false }
        return snapshot.pauseTimeline.map {
            $0.validatedUnionIntervals(startDate: snapshot.startDate, endDate: snapshot.recordedAt,
                                      activeSeconds: snapshot.activeElapsedSeconds, allowOpenPause: true) != nil
        } ?? true
    }

    /// Prepare before saving the combined checkpoint. The exact previous boundary
    /// prevents a delayed double-tap from closing a different lap.
    public func proposedManualLap(operationID: String, expectedPreviousID: String?, at date: Date) -> RunManualLap? {
        if let existing = manualLaps.first(where: { $0.id == operationID }) { return existing }
        guard state == .running, timeAccounting == .activeElapsed, validLifecycleDate(date),
              !operationID.isEmpty, manualLaps.count < 1_000, manualLaps.last?.id == expectedPreviousID else { return nil }
        let elapsed = activeElapsedSeconds(at: date)
        guard elapsed - (manualLaps.last?.activeElapsedSeconds ?? 0) >= 1 else { return nil }
        return RunManualLap(id: operationID, recordingID: id, index: manualLaps.count + 1, timestamp: date,
                            activeElapsedSeconds: elapsed, distanceMeters: distanceMeters)
    }

    @discardableResult
    public func acceptManualLap(_ lap: RunManualLap, expectedPreviousID: String?) -> Bool {
        if let existing = manualLaps.first(where: { $0.id == lap.id }) { return existing == lap }
        guard proposedManualLap(operationID: lap.id, expectedPreviousID: expectedPreviousID, at: lap.timestamp) == lap else { return false }
        manualLaps.append(lap)
        return true
    }

    // MARK: Lifecycle

    public func start(at date: Date = Date()) {
        guard state == .ready, date.timeIntervalSinceReferenceDate.isFinite else { return }
        state = .running
        startDate = date
        activeSegmentStartedAt = date
    }

    public func pause(at date: Date = Date()) {
        guard state == .running, validLifecycleDate(date),
              let updatedTimeline = pauseTimeline.openingPause(at: date, origin: .explicitPause) else { return }
        accountActiveTime(through: date)
        state = .paused
        pauseBegan = date
        pauseTimeline = updatedTimeline
        // The segment leading into a pause is over; don't bridge across it.
        lastAcceptedFix = nil
        recentSegments.removeAll()
    }

    public func resume(at date: Date = Date()) {
        guard state == .paused, let pauseBegan, date.timeIntervalSinceReferenceDate.isFinite,
              date >= pauseBegan, let updatedTimeline = pauseTimeline.closingPause(at: date) else { return }
        pausedSeconds += date.timeIntervalSince(pauseBegan)
        pauseTimeline = updatedTimeline
        state = .running
        self.pauseBegan = nil
        activeSegmentStartedAt = date
    }

    /// Wall-clock active duration is independent of GPS delivery and timer callbacks.
    public func activeElapsedSeconds(at date: Date = Date()) -> Double {
        guard let startDate, date.timeIntervalSinceReferenceDate.isFinite else { return 0 }
        let endpoint = finishedAt ?? date
        let activeEndpoint = pauseBegan.map { min(endpoint, $0) } ?? endpoint
        return max(0, activeEndpoint.timeIntervalSince(startDate) - pausedSeconds)
    }

    /// Ends the session and returns the completed run. The tail of an unfinished split is
    /// kept as a partial split so short runs still show their work.
    public func finish(at date: Date = Date()) -> Run? {
        guard state == .running || state == .paused, let startDate, validLifecycleDate(date),
              let closedTimeline = pauseTimeline.closingPause(at: date) else { return nil }
        let finalSeconds = timeAccounting == .activeElapsed ? activeElapsedSeconds(at: date) : movingSeconds
        guard closedTimeline.validatedUnionIntervals(startDate: startDate, endDate: date,
                                                     activeSeconds: finalSeconds) != nil else { return nil }
        accountActiveTime(through: date)
        pauseTimeline = closedTimeline
        finishedAt = date
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
            id: id,
            source: .recorded,
            startDate: startDate,
            endDate: date,
            distanceMeters: distanceMeters,
            movingSeconds: movingSeconds,
            splits: splits,
            hasRoute: routePointCount > 1,
            pauseTimeline: closedTimeline,
            recordingID: id,
            manualLaps: manualLaps.isEmpty ? nil : manualLaps
        )
    }

    // MARK: Live metrics

    /// Rolling pace over roughly the last minute of movement; nil until there's enough signal.
    public var currentPaceSecondsPerKm: Double? {
        guard state == .running else { return nil }
        let window = recentSegments.suffix(while: { segment in
            guard let newest = recentSegments.last else { return false }
            return newest.at.timeIntervalSince(segment.at) <= 60
        })
        let meters = window.reduce(0) { $0 + $1.meters }
        let seconds = window.reduce(0) { $0 + $1.seconds }
        guard meters > 25, seconds > 5 else { return nil }
        return seconds / (meters / 1000)
    }

    /// Live consumers should use this overload so an old pace disappears after signal loss.
    public func currentPaceSecondsPerKm(at date: Date = Date()) -> Double? {
        guard date.timeIntervalSinceReferenceDate.isFinite, let newest = recentSegments.last,
              (0...Self.movingTimeGapCapSeconds).contains(date.timeIntervalSince(newest.at)) else { return nil }
        return currentPaceSecondsPerKm
    }

    public var averagePaceSecondsPerKm: Double? {
        guard distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceMeters / 1000)
    }

    // MARK: Fix ingestion

    @discardableResult
    public func ingest(_ fix: RunLocationFix) -> Bool {
        guard state == .running, fix.latitude.isFinite, (-90...90).contains(fix.latitude),
              fix.longitude.isFinite, (-180...180).contains(fix.longitude),
              fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= Self.accuracyCutoffMeters,
              fix.timestamp.timeIntervalSinceReferenceDate.isFinite,
              let activeSegmentStartedAt, fix.timestamp >= activeSegmentStartedAt,
              lastAcceptedFixTimestamp.map({ fix.timestamp > $0 }) ?? true else { return false }

        guard let previous = lastAcceptedFix else {
            lastIngestStartedSegment = true
            lastAcceptedFix = fix
            lastAcceptedFixTimestamp = fix.timestamp
            routePointCount += 1
            accountActiveTime(through: fix.timestamp)
            return true
        }

        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds.isFinite, seconds > 0 else { return false }

        let meters = Self.haversineMeters(
            lat1: previous.latitude, lon1: previous.longitude,
            lat2: fix.latitude, lon2: fix.longitude
        )

        // Teleport filter: implausible speed means one of the fixes is garbage.
        guard meters.isFinite, meters / seconds <= Self.maxPlausibleSpeedMetersPerSecond else {
            // An outlier must not become the route or distance anchor. Re-anchor on
            // the next valid fix instead of drawing either leg of the teleport.
            lastAcceptedFix = nil
            recentSegments.removeAll()
            return false
        }

        lastIngestStartedSegment = seconds > Self.movingTimeGapCapSeconds
        lastAcceptedFix = fix
        lastAcceptedFixTimestamp = fix.timestamp
        routePointCount += 1

        let countedSeconds = switch timeAccounting {
        case .moving:
            min(seconds, Self.movingTimeGapCapSeconds)
        case .elapsed:
            seconds
        case .activeElapsed:
            max(0, activeElapsedSeconds(at: fix.timestamp) - movingSeconds)
        }
        distanceMeters += meters
        movingSeconds += countedSeconds
        if timeAccounting == .activeElapsed, seconds > Self.movingTimeGapCapSeconds {
            recentSegments.removeAll()
        } else {
            recentSegments.append((meters: meters, seconds: countedSeconds, at: fix.timestamp))
        }
        if recentSegments.count > 120 {
            recentSegments.removeFirst(recentSegments.count - 120)
        }

        accumulateSplit(meters: meters, seconds: countedSeconds)
        return true
    }

    private func validLifecycleDate(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let beginning = pauseBegan ?? activeSegmentStartedAt, date >= beginning else { return false }
        return lastAcceptedFixTimestamp.map { date >= $0 } ?? true
    }

    private func accountActiveTime(through date: Date) {
        guard timeAccounting == .activeElapsed else { return }
        let elapsed = activeElapsedSeconds(at: date)
        let additional = max(0, elapsed - movingSeconds)
        movingSeconds += additional
        secondsIntoCurrentSplit += additional
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
        let bounded = min(1, max(0, a))
        return earthRadius * 2 * atan2(sqrt(bounded), sqrt(1 - bounded))
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
