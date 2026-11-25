import Foundation

/// Measured records at saved full-split boundaries, never whole-run pace estimates.
/// Imported, treadmill, recovered and discontinuous runs are excluded when their
/// original measurement provenance cannot prove uninterrupted recording.
public enum RunMeasuredRecords {
    public struct Record: Equatable, Identifiable {
        public var id: Double { distanceMeters }
        public let distanceMeters: Double
        public let seconds: Double
        public let runID: String
        public let recordingID: String
        public let firstSplit: Int
        public let lastSplit: Int
    }

    public struct Summary: Equatable {
        public let records: [Record]
        public let eligibleRuns: Int
    }

    public static func summarize(_ runs: [Run]) -> Summary {
        var best: [Double: Record] = [:]
        var seen = Set<String>()
        var eligible = 0
        for run in runs {
            guard let unit = eligibleSplitUnit(run), seen.insert(run.recordingID ?? run.id).inserted else { continue }
            eligible += 1
            let full = run.splits.filter { abs($0.distanceMeters - unit) <= 0.001 }
            for target in [1000.0, RunFormat.metersPerMile, 5000.0, 10_000.0] {
                let count = Int((target / unit).rounded())
                guard count > 0, count <= full.count, abs(Double(count) * unit - target) <= 0.001 else { continue }
                var seconds = full.prefix(count).reduce(0) { $0 + $1.seconds }
                for start in 0...(full.count - count) {
                    if start > 0 { seconds += full[start + count - 1].seconds - full[start - 1].seconds }
                    if seconds < (best[target]?.seconds ?? .infinity) {
                        best[target] = Record(distanceMeters: target, seconds: seconds, runID: run.id,
                            recordingID: run.recordingID ?? run.id, firstSplit: full[start].index, lastSplit: full[start + count - 1].index)
                    }
                }
            }
        }
        return Summary(records: best.values.sorted { $0.distanceMeters < $1.distanceMeters }, eligibleRuns: eligible)
    }

    private static func eligibleSplitUnit(_ run: Run) -> Double? {
        guard run.source == .recorded, !run.isIndoor, run.routeSegmentStarts?.count == 1,
              run.distanceMeters.isFinite, run.distanceMeters > 0, run.movingSeconds.isFinite, run.movingSeconds > 0,
              let timeline = run.pauseTimeline, timeline.completeness == .complete, timeline.intervals.isEmpty,
              timeline.validatedUnionIntervals(startDate: run.startDate, endDate: run.endDate, activeSeconds: run.movingSeconds) != nil,
              !run.splits.isEmpty, run.splits.count <= 10_000,
              let unit = [1000.0, RunFormat.metersPerMile].first(where: { abs($0 - run.splits[0].distanceMeters) <= 0.001 }) else { return nil }
        var meters = 0.0
        var seconds = 0.0
        for (index, split) in run.splits.enumerated() {
            guard split.index == index + 1, split.distanceMeters.isFinite, split.seconds.isFinite,
                  split.distanceMeters > 0, split.seconds > 0,
                  abs(split.distanceMeters - unit) <= 0.001 || (index == run.splits.count - 1 && split.distanceMeters < unit) else { return nil }
            meters += split.distanceMeters
            seconds += split.seconds
        }
        guard meters <= run.distanceMeters + 0.01, seconds <= run.movingSeconds + 0.01 else { return nil }
        return unit
    }
}
