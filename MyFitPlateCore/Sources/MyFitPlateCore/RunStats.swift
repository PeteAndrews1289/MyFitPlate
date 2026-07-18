import Foundation

/// Personal records and trends over a run history (imported + recorded alike).
public enum RunStats {

    public struct PersonalRecords: Equatable {
        public var longestRun: Run?
        /// Best estimated 5K time: fastest average pace among runs of at least 5 km,
        /// scaled to exactly 5 km. Estimated, not a measured best segment — the UI
        /// labels it that way.
        public var best5KSeconds: Double?
        public var best5KRunID: String?
        public var best10KSeconds: Double?
        public var best10KRunID: String?
    }

    public static func personalRecords(from runs: [Run]) -> PersonalRecords {
        var records = PersonalRecords()

        for run in runs {
            guard run.distanceMeters > 0, run.movingSeconds > 0 else { continue }

            if run.distanceMeters > (records.longestRun?.distanceMeters ?? 0) {
                records.longestRun = run
            }

            if run.distanceMeters >= 5000 {
                let estimated5K = run.movingSeconds * (5000 / run.distanceMeters)
                if estimated5K < (records.best5KSeconds ?? .infinity) {
                    records.best5KSeconds = estimated5K
                    records.best5KRunID = run.id
                }
            }

            if run.distanceMeters >= 10_000 {
                let estimated10K = run.movingSeconds * (10_000 / run.distanceMeters)
                if estimated10K < (records.best10KSeconds ?? .infinity) {
                    records.best10KSeconds = estimated10K
                    records.best10KRunID = run.id
                }
            }
        }

        return records
    }

    /// True when `run` sets at least one record against the rest of the history —
    /// the celebrate-once moment after a recorded run.
    public static func setsRecord(_ run: Run, against history: [Run]) -> Bool {
        let others = history.filter { $0.id != run.id }
        let withoutRun = personalRecords(from: others)
        let withRun = personalRecords(from: others + [run])
        if withRun.longestRun?.id == run.id && withoutRun.longestRun != nil { return true }
        if withoutRun.longestRun == nil && withRun.longestRun?.id == run.id { return true }
        if withRun.best5KRunID == run.id { return true }
        if withRun.best10KRunID == run.id { return true }
        return false
    }

    public struct GhostPaceComparison: Equatable {
        public var isPR: Bool
        public var prPaceSecondsPerKm: Double
        public var averagePaceSecondsPerKm: Double
        public var paceDifferenceVsAverage: Double
        public var paceDifferenceVsPR: Double
        public var matchingRunsCount: Int

        public init(isPR: Bool, prPaceSecondsPerKm: Double, averagePaceSecondsPerKm: Double, paceDifferenceVsAverage: Double, paceDifferenceVsPR: Double, matchingRunsCount: Int) {
            self.isPR = isPR
            self.prPaceSecondsPerKm = prPaceSecondsPerKm
            self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
            self.paceDifferenceVsAverage = paceDifferenceVsAverage
            self.paceDifferenceVsPR = paceDifferenceVsPR
            self.matchingRunsCount = matchingRunsCount
        }
    }

    /// Compares a run against historical runs of similar distance (within 5% distance tolerance)
    /// to determine if it sets a route/distance PR and how its pace compares to average ("Ghost Pace").
    public static func ghostPaceComparison(for run: Run, against history: [Run]) -> GhostPaceComparison? {
        guard let currentPace = run.averagePaceSecondsPerKm, run.distanceMeters >= 500 else { return nil }

        let similarRuns = history.filter { other in
            other.id != run.id &&
            other.distanceMeters >= 500 &&
            other.averagePaceSecondsPerKm != nil &&
            abs(other.distanceMeters - run.distanceMeters) / run.distanceMeters <= 0.05
        }

        guard !similarRuns.isEmpty else { return nil }

        let paces = similarRuns.compactMap { $0.averagePaceSecondsPerKm }
        guard let prPace = paces.min(), !paces.isEmpty else { return nil }

        let avgPace = paces.reduce(0, +) / Double(paces.count)
        let isPR = currentPace < prPace

        return GhostPaceComparison(
            isPR: isPR,
            prPaceSecondsPerKm: prPace,
            averagePaceSecondsPerKm: avgPace,
            paceDifferenceVsAverage: currentPace - avgPace,
            paceDifferenceVsPR: currentPace - prPace,
            matchingRunsCount: similarRuns.count
        )
    }

    /// Determines if a run achieved a "Negative Split" (running the second half faster than the first half).
    public static func isNegativeSplit(splits: [RunSplit]) -> Bool {
        guard let delta = negativeSplitDeltaSecondsPerKm(splits: splits) else { return false }
        let fullSplitPaces = splits
            .filter { $0.distanceMeters >= 800 }
            .compactMap(\.paceSecondsPerKm)
        if let fastest = fullSplitPaces.min(),
           let slowest = fullSplitPaces.max(),
           fastest > 0,
           slowest / fastest > 1.8 {
            return false
        }
        return delta > 0.5 // At least 0.5s/km faster in the second half
    }

    /// Returns the speedup in seconds per km of the second half compared to the first half, if any.
    public static func negativeSplitDeltaSecondsPerKm(splits: [RunSplit]) -> Double? {
        guard splits.count >= 2 else { return nil }
        let mid = splits.count / 2
        let firstHalf = splits.prefix(mid)
        let secondHalf = splits.suffix(splits.count - mid)

        let dist1 = firstHalf.reduce(0.0) { $0 + $1.distanceMeters }
        let sec1 = firstHalf.reduce(0.0) { $0 + $1.seconds }
        let dist2 = secondHalf.reduce(0.0) { $0 + $1.distanceMeters }
        let sec2 = secondHalf.reduce(0.0) { $0 + $1.seconds }

        guard dist1 > 0, dist2 > 0 else { return nil }
        let pace1 = sec1 / (dist1 / 1000.0)
        let pace2 = sec2 / (dist2 / 1000.0)

        return pace1 - pace2
    }

    /// Identifies the fastest split in a run, ignoring tiny partial tail splits (< 200m) unless no other splits exist.
    public static func fastestSplit(splits: [RunSplit]) -> RunSplit? {
        let validSplits = splits.filter { $0.distanceMeters >= 200 }
        let candidates = validSplits.isEmpty ? splits : validSplits
        return candidates.min(by: { ($0.paceSecondsPerKm ?? .infinity) < ($1.paceSecondsPerKm ?? .infinity) })
    }

    public struct WeekMileage: Equatable {
        public let weekStart: Date
        public let meters: Double
        public let runCount: Int
    }

    /// The last `weeks` calendar weeks (oldest first), zero-filled so charts show the
    /// quiet weeks honestly.
    public static func weeklyMileage(
        runs: [Run],
        weeks: Int,
        endingAt reference: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeekMileage] {
        guard weeks > 0 else { return [] }
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start else { return [] }

        var buckets: [Date: (meters: Double, runs: Int)] = [:]
        for run in runs {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: run.startDate)?.start else { continue }
            let existing = buckets[weekStart] ?? (0, 0)
            buckets[weekStart] = (existing.meters + run.distanceMeters, existing.runs + 1)
        }

        return (0..<weeks).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) else { return nil }
            let bucket = buckets[weekStart] ?? (0, 0)
            return WeekMileage(weekStart: weekStart, meters: bucket.meters, runCount: bucket.runs)
        }
    }
}

/// Keeps map rendering cheap when many routes draw at once.
public enum RouteSimplify {
    /// Evenly thins a trace to at most `maxPoints`, always preserving both endpoints —
    /// a 1 Hz hour-long run (3,600 fixes) becomes a ~200-point line nobody can tell apart
    /// at overview zoom.
    public static func decimate(_ fixes: [RunLocationFix], maxPoints: Int) -> [RunLocationFix] {
        guard maxPoints >= 2, fixes.count > maxPoints else { return fixes }
        let stride = Double(fixes.count - 1) / Double(maxPoints - 1)
        var kept: [RunLocationFix] = []
        kept.reserveCapacity(maxPoints)
        for index in 0..<maxPoints {
            kept.append(fixes[Int((Double(index) * stride).rounded())])
        }
        return kept
    }
}
