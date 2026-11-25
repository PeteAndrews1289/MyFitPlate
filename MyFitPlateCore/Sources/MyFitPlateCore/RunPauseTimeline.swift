import Foundation

/// An exclusion from the recording clock, preserving its actual timestamp and cause.
public struct RunPauseInterval: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case explicitPause
        case recoveryGap
    }

    public let startDate: Date
    public let endDate: Date
    public let origin: Origin

    public init(startDate: Date, endDate: Date, origin: Origin) {
        self.startDate = startDate
        self.endDate = endDate
        self.origin = origin
    }
}

/// Complete timelines reconcile exactly with active time. Partial timelines retain
/// known exclusions without pretending that older, unrecorded pauses are known.
public struct RunPauseTimeline: Codable, Equatable, Sendable {
    public enum Completeness: String, Codable, Sendable { case complete, partial }

    public struct OpenPause: Codable, Equatable, Sendable {
        public let startDate: Date
        public let origin: RunPauseInterval.Origin

        public init(startDate: Date, origin: RunPauseInterval.Origin) {
            self.startDate = startDate
            self.origin = origin
        }
    }

    public struct Summary: Equatable, Sendable {
        public let excludedSeconds: Double
        public let explicitPauseSeconds: Double
        public let recoveryGapSeconds: Double
        public let completeness: Completeness
    }

    public static let maximumIntervals = 4_096
    public static let toleranceSeconds = 0.01

    public let completeness: Completeness
    public let intervals: [RunPauseInterval]
    public let openPause: OpenPause?

    public init(completeness: Completeness, intervals: [RunPauseInterval] = [], openPause: OpenPause? = nil) {
        self.completeness = completeness
        self.intervals = intervals
        self.openPause = openPause
    }

    /// Nil means invalid, rather than an uninterrupted recording. Valid partial
    /// timelines return only known intervals; callers must retain that limitation.
    public func validatedUnionIntervals(
        startDate: Date, endDate: Date, activeSeconds: Double, allowOpenPause: Bool = false
    ) -> [DateInterval]? {
        guard let known = validatedKnownIntervals(startDate: startDate, endDate: endDate,
                                                  allowOpenPause: allowOpenPause),
              activeSeconds.isFinite, activeSeconds >= 0 else { return nil }
        let union = Self.union(known.map { DateInterval(start: $0.startDate, end: $0.endDate) })
        let availableSeconds = endDate.timeIntervalSince(startDate) - union.reduce(0) { $0 + $1.duration }
        if completeness == .complete {
            guard abs(availableSeconds - activeSeconds) <= Self.toleranceSeconds else { return nil }
        } else {
            guard activeSeconds <= availableSeconds + Self.toleranceSeconds else { return nil }
        }
        return union
    }

    /// Explicit pauses take priority in overlaps; the two causes therefore add up
    /// to the total excluded time without counting a recovery gap twice.
    public func summary(
        startDate: Date, endDate: Date, activeSeconds: Double, allowOpenPause: Bool = false
    ) -> Summary? {
        guard let union = validatedUnionIntervals(startDate: startDate, endDate: endDate,
                                                  activeSeconds: activeSeconds, allowOpenPause: allowOpenPause),
              let known = validatedKnownIntervals(startDate: startDate, endDate: endDate,
                                                  allowOpenPause: allowOpenPause) else { return nil }
        let excluded = union.reduce(0) { $0 + $1.duration }
        let explicitIntervals = known.filter { $0.origin == .explicitPause }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let explicitSeconds = Self.union(explicitIntervals).reduce(0) { $0 + $1.duration }
        return Summary(excludedSeconds: excluded, explicitPauseSeconds: explicitSeconds,
                       recoveryGapSeconds: max(0, excluded - explicitSeconds), completeness: completeness)
    }

    func openingPause(at date: Date, origin: RunPauseInterval.Origin) -> RunPauseTimeline? {
        guard openPause == nil, intervals.count < Self.maximumIntervals,
              date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return RunPauseTimeline(completeness: completeness, intervals: intervals,
                                openPause: OpenPause(startDate: date, origin: origin))
    }

    func closingPause(at date: Date) -> RunPauseTimeline? {
        guard let openPause else { return self }
        guard date.timeIntervalSinceReferenceDate.isFinite, date >= openPause.startDate,
              intervals.count < Self.maximumIntervals else { return nil }
        var closed = intervals
        if date > openPause.startDate {
            closed.append(RunPauseInterval(startDate: openPause.startDate, endDate: date, origin: openPause.origin))
        }
        return RunPauseTimeline(completeness: completeness, intervals: closed)
    }

    private func validatedKnownIntervals(startDate: Date, endDate: Date, allowOpenPause: Bool) -> [RunPauseInterval]? {
        let duration = endDate.timeIntervalSince(startDate)
        guard startDate.timeIntervalSinceReferenceDate.isFinite, endDate.timeIntervalSinceReferenceDate.isFinite,
              duration.isFinite, duration >= 0, intervals.count + (openPause == nil ? 0 : 1) <= Self.maximumIntervals else { return nil }
        var known = intervals
        if let openPause {
            guard allowOpenPause else { return nil }
            known.append(RunPauseInterval(startDate: openPause.startDate, endDate: endDate, origin: openPause.origin))
        }
        guard known.allSatisfy({ interval in
            interval.startDate.timeIntervalSinceReferenceDate.isFinite && interval.endDate.timeIntervalSinceReferenceDate.isFinite
                && interval.startDate >= startDate && interval.endDate >= interval.startDate && interval.endDate <= endDate
        }) else { return nil }
        return known
    }

    private static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let previous = merged.last, interval.start <= previous.end {
                merged[merged.count - 1] = DateInterval(start: previous.start, end: max(previous.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
