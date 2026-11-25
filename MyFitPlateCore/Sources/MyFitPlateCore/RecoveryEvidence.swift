import Foundation
import HealthKit

/// Descriptive personal trends, not a readiness score or a prescription for training intensity.
public struct RecoveryEvidence: Equatable, Sendable {
    public struct HRVReading: Equatable, Sendable {
        public let date: Date
        public let milliseconds: Double

        public init(date: Date, milliseconds: Double) {
            self.date = date
            self.milliseconds = milliseconds
        }
    }

    public enum HRVComparison: String, Sendable {
        case unavailable, buildingBaseline, stale, belowUsual, withinUsual, aboveUsual
    }

    public let sleepAverageHours: Double?
    public let sleepNightCount: Int
    public let sleepUpdatedAt: Date?
    public let sleepIsCurrent: Bool
    public let hrvRecentAverage: Double?
    public let hrvBaselineAverage: Double?
    public let hrvRecentDays: Int
    public let hrvBaselineDays: Int
    public let hrvUpdatedAt: Date?
    public let hrvComparison: HRVComparison

    public static let unavailable = RecoveryEvidence()

    public init(
        sleepAverageHours: Double? = nil,
        sleepNightCount: Int = 0,
        sleepUpdatedAt: Date? = nil,
        hrvReadings: [HRVReading] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let validSleep = sleepAverageHours.map { $0.isFinite && $0 > 0 && $0 <= 24 } ?? false
        self.sleepAverageHours = validSleep && sleepNightCount > 0 ? sleepAverageHours : nil
        self.sleepNightCount = validSleep ? max(0, sleepNightCount) : 0
        self.sleepUpdatedAt = sleepUpdatedAt
        sleepIsCurrent = validSleep && sleepNightCount >= 3 && Self.isFresh(sleepUpdatedAt, now: now)

        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let baselineStart = calendar.date(byAdding: .day, value: -28, to: recentStart) ?? recentStart
        let validReadings = hrvReadings.filter {
            $0.milliseconds.isFinite && $0.milliseconds > 0 && $0.date >= baselineStart && $0.date <= now
        }
        // Give each recorded day equal weight; a day with many Watch readings must not dominate.
        let dailyMeans = Dictionary(grouping: validReadings) { calendar.startOfDay(for: $0.date) }
            .mapValues { readings in readings.reduce(0) { $0 + $1.milliseconds } / Double(readings.count) }
        let recent = dailyMeans.filter { $0.key >= recentStart }.map(\.value)
        let baseline = dailyMeans.filter { $0.key < recentStart }.map(\.value)
        hrvRecentDays = recent.count
        hrvBaselineDays = baseline.count
        hrvUpdatedAt = validReadings.map(\.date).max()
        hrvRecentAverage = Self.mean(recent)
        hrvBaselineAverage = Self.mean(baseline)

        if validReadings.isEmpty {
            hrvComparison = .unavailable
        } else if !Self.isFresh(hrvUpdatedAt, now: now) {
            hrvComparison = .stale
        } else if recent.count < 3 || baseline.count < 14 {
            hrvComparison = .buildingBaseline
        } else if let recentMean = hrvRecentAverage, let baselineMean = hrvBaselineAverage {
            let variance = baseline.reduce(0) { $0 + pow($1 - baselineMean, 2) } / Double(baseline.count)
            // A descriptive noise band, not a clinically validated threshold. Never raises training intensity.
            let tolerance = max(sqrt(variance), baselineMean * 0.10)
            hrvComparison = recentMean < baselineMean - tolerance ? .belowUsual
                : recentMean > baselineMean + tolerance ? .aboveUsual : .withinUsual
        } else {
            hrvComparison = .unavailable
        }
    }

    public var sleepHoursForGuidance: Double { sleepIsCurrent ? sleepAverageHours ?? 0 : 0 }

    public var dataPoints: [String] {
        var points: [String] = []
        if let hours = sleepAverageHours, let date = sleepUpdatedAt {
            points.append("Sleep: \(String(format: "%.1f", hours)) h/night across \(sleepNightCount) recorded nights")
            points.append("Sleep last recorded \(date.formatted(date: .abbreviated, time: .omitted))")
            if !sleepIsCurrent {
                points.append("Sleep guidance needs 3 recorded nights and a reading in the last 36 hours")
            }
        } else {
            points.append("Sleep: no recent nights available")
        }
        switch hrvComparison {
        case .unavailable:
            points.append("HRV: no recent readings available")
        case .buildingBaseline:
            points.append("HRV: building your usual range (\(hrvBaselineDays) of 14 prior days; \(hrvRecentDays) of 3 recent days)")
        case .stale:
            points.append("HRV: no reading in the last 36 hours; no recovery conclusion")
        case .belowUsual, .withinUsual, .aboveUsual:
            let trend = hrvComparison == .belowUsual ? "below" : hrvComparison == .aboveUsual ? "above" : "within"
            points.append("HRV: \(trend) your usual range")
            if let recent = hrvRecentAverage, let baseline = hrvBaselineAverage {
                points.append("\(Int(recent.rounded()).formatted()) ms over \(hrvRecentDays) days; \(Int(baseline.rounded()).formatted()) ms over \(hrvBaselineDays) prior days")
            }
        }
        if let date = hrvUpdatedAt {
            points.append("HRV last recorded \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return points
    }

    private static func isFresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return (0...(36 * 3600)).contains(now.timeIntervalSince(date))
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

public enum SleepEvidenceRules {
    public static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        return [.asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified].contains(value)
    }

    /// Group evening and following-morning stages together, excluding awake/in-bed records and
    /// merging overlap from multiple sources. The key is the evening on which the night began.
    public static func hoursByNight(
        from samples: [HKCategorySample], now: Date = Date(), calendar: Calendar = .current
    ) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: SleepNightEvidence.normalize(samples, now: now, calendar: calendar)
            .map { ($0.night, $0.timeAsleep / 3600) })
    }

    static func nightKey(for date: Date, calendar: Calendar) -> Date {
        let shifted = calendar.component(.hour, from: date) < 18
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        return calendar.startOfDay(for: shifted)
    }

    static func mergedDuration(_ samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples.filter { $0.endDate > $0.startDate }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }.sorted { $0.start < $1.start }
        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }
}
