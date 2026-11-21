import Foundation

/// Describes saved pace changes without inferring effort, terrain or training quality.
/// Halves contain equal distance; a short final split cannot become the best full split.
public enum RunPacingAnalysis {
    public enum SplitSource: Equatable, Sendable { case saved, routeReplay, manualEstimate }

    public struct Result: Equatable, Sendable {
        public let source: SplitSource
        public let coveredDistanceMeters: Double
        public let halfDistanceMeters: Double
        public let firstHalfSeconds: Double
        public let secondHalfSeconds: Double
        public let splitCount: Int
        public let completeSplitCount: Int
        /// Nil for a single complete split or a tie within half a second per km.
        public let fastestCompleteSplitIndex: Int?
        public let completeSplitPaceSpreadSecondsPerKm: Double?

        public var firstHalfPaceSecondsPerKm: Double { firstHalfSeconds / (halfDistanceMeters / 1_000) }
        public var secondHalfPaceSecondsPerKm: Double { secondHalfSeconds / (halfDistanceMeters / 1_000) }
        /// Positive means the second distance half was faster.
        public var finishDeltaSecondsPerKm: Double { firstHalfPaceSecondsPerKm - secondHalfPaceSecondsPerKm }
    }

    public static func analyze(run: Run, splits: [RunSplit]? = nil, source: SplitSource = .saved) -> Result? {
        guard source != .manualEstimate,
              !(run.isIndoor && run.source == .recorded && run.pauseTimeline?.completeness != .complete),
              run.distanceMeters.isFinite, run.distanceMeters >= 500,
              run.movingSeconds.isFinite, run.movingSeconds > 0,
              run.startDate.timeIntervalSinceReferenceDate.isFinite, run.endDate.timeIntervalSinceReferenceDate.isFinite,
              run.endDate >= run.startDate,
              let validated = validate(splits ?? run.splits) else { return nil }
        // A replay may contain elapsed pause gaps, while Health reports active time.
        // Missing distance or time must not be rescaled to manufacture an insight.
        let distanceTolerance = max(1, run.distanceMeters * 0.001)
        let timeTolerance = max(1, run.movingSeconds * 0.001)
        guard abs(validated.distance - run.distanceMeters) <= distanceTolerance,
              abs(validated.seconds - run.movingSeconds) <= timeTolerance,
              run.movingSeconds <= run.endDate.timeIntervalSince(run.startDate) + timeTolerance,
              let halves = halves(validated) else { return nil }
        if let timeline = run.pauseTimeline,
           timeline.validatedUnionIntervals(startDate: run.startDate, endDate: run.endDate,
                                            activeSeconds: run.movingSeconds) == nil { return nil }
        let fullTolerance = max(0.5, validated.fullDistance * 0.001)
        let complete = validated.splits.filter { abs($0.distanceMeters - validated.fullDistance) <= fullTolerance }
        let paces = complete.compactMap(\.paceSecondsPerKm).sorted()
        let hasComparison = paces.count >= 2
        let uniqueFastest = hasComparison && paces[1] - paces[0] > 0.5
        let fastest = uniqueFastest ? complete.min { ($0.paceSecondsPerKm ?? .infinity) < ($1.paceSecondsPerKm ?? .infinity) }?.index : nil
        let spread = hasComparison ? paces.last.map { $0 - paces[0] } : nil
        return Result(source: source, coveredDistanceMeters: validated.distance, halfDistanceMeters: validated.distance / 2,
                      firstHalfSeconds: halves.first, secondHalfSeconds: halves.second,
                      splitCount: validated.splits.count, completeSplitCount: complete.count,
                      fastestCompleteSplitIndex: fastest, completeSplitPaceSpreadSecondsPerKm: spread)
    }

    /// Shared with the legacy split-only helpers, which cannot assess run coverage or
    /// distinguish measured splits from manual estimates. New UI should use analyze.
    static func equalHalfDeltaSecondsPerKm(splits: [RunSplit]) -> Double? {
        guard let validated = validate(splits), let halves = halves(validated) else { return nil }
        return (halves.first - halves.second) / (validated.distance / 2 / 1_000)
    }

    private struct Validated {
        let splits: [RunSplit]
        let distance: Double
        let seconds: Double
        let fullDistance: Double
    }

    private static func validate(_ splits: [RunSplit]) -> Validated? {
        guard (2...4_096).contains(splits.count), let first = splits.first,
              splits.enumerated().allSatisfy({ index, split in
                  split.index == index + 1 && split.distanceMeters.isFinite && split.distanceMeters > 0
                      && split.seconds.isFinite && split.seconds > 0
                      && (split.paceSecondsPerKm.map { $0.isFinite && $0 > 0 } ?? false)
              }) else { return nil }
        let fullDistance = first.distanceMeters
        let tolerance = max(0.5, fullDistance * 0.001)
        guard splits.dropLast().allSatisfy({ abs($0.distanceMeters - fullDistance) <= tolerance }),
              let last = splits.last, last.distanceMeters <= fullDistance + tolerance else { return nil }
        let distance = splits.reduce(0) { $0 + $1.distanceMeters }
        let seconds = splits.reduce(0) { $0 + $1.seconds }
        guard distance.isFinite, distance > 0, seconds.isFinite, seconds > 0 else { return nil }
        return Validated(splits: splits, distance: distance, seconds: seconds, fullDistance: fullDistance)
    }

    private static func halves(_ validated: Validated) -> (first: Double, second: Double)? {
        let halfDistance = validated.distance / 2
        var remaining = halfDistance
        var firstSeconds = 0.0
        for split in validated.splits {
            let firstMeters = min(max(0, remaining), split.distanceMeters)
            firstSeconds += split.seconds * (firstMeters / split.distanceMeters)
            remaining -= firstMeters
        }
        let secondSeconds = validated.seconds - firstSeconds
        let firstPace = firstSeconds / (halfDistance / 1_000)
        let secondPace = secondSeconds / (halfDistance / 1_000)
        guard firstSeconds.isFinite, firstSeconds > 0, secondSeconds.isFinite, secondSeconds > 0,
              firstPace.isFinite, firstPace > 0, secondPace.isFinite, secondPace > 0 else { return nil }
        return (firstSeconds, secondSeconds)
    }
}
