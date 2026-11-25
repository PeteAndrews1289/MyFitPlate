import Foundation

/// Descriptive chart projection using the same elapsed-civil-day slopes as the adaptive shadow comparison.
/// Raw measurements and the active calorie estimator are never changed by this calculation.
public enum WeightTrendRules {
    public static let version = "elapsed-day-robust-trend-v1"
    public struct Point: Equatable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let pounds: Double
        public let segment: Int
    }
    public struct Projection: Equatable {
        public let points: [Point]
        public let measuredDays: Int
        public let spanDays: Int
        public let largestGapDays: Int
        public let ratePerDay: Double?
        public let sampledDays: Int
        public var change: Double? { guard let first = points.first, let last = points.last, points.count > 1 else { return nil }; return last.pounds - first.pounds }
        public var description: String {
            let scope = "\(measuredDays) measured days across \(spanDays) calendar days."
            if measuredDays < 2 { return scope + " At least two distinct days are needed for a trend." }
            return scope + (largestGapDays > 7 ? " Gaps longer than a week are left unconnected." : " The line is a descriptive estimate; dots are measurements.")
                + (sampledDays < measuredDays ? " Long-range estimates use evenly spaced measured days." : "")
        }
    }

    public static func dailySamples(_ input: [AdaptiveWeightEvidence], calendar: Calendar = .current) -> [AdaptiveWeightEvidence] {
        var byDay: [Date: AdaptiveWeightEvidence] = [:]
        for value in input.filter({ $0.date.timeIntervalSinceReferenceDate.isFinite && $0.pounds.isFinite && $0.pounds > 0 })
            .sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
            let day = calendar.startOfDay(for: value.date)
            byDay[day] = .init(id: value.id, date: day, pounds: value.pounds)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Bounded pair sampling affects only ranges over 181 measured days. The 42-day shadow keeps every day/pair.
    public static func sortedSlopes(_ input: [AdaptiveWeightEvidence], minimumSeparationDays: Int = 7,
                                    calendar: Calendar = .current) -> [Double] {
        let days = bounded(dailySamples(input, calendar: calendar))
        var slopes: [Double] = []
        for left in days.indices {
            for right in days.indices where right > left {
                let elapsed = calendar.dateComponents([.day], from: days[left].date, to: days[right].date).day ?? 0
                guard elapsed >= max(1, minimumSeparationDays) else { continue }
                let slope = (days[right].pounds - days[left].pounds) / Double(elapsed)
                if slope.isFinite { slopes.append(slope) }
            }
        }
        return slopes.sorted()
    }

    public static func project(_ input: [AdaptiveWeightEvidence], calendar: Calendar = .current) -> Projection {
        let days = dailySamples(input, calendar: calendar)
        guard let first = days.first, let last = days.last else {
            return .init(points: [], measuredDays: 0, spanDays: 0, largestGapDays: 0, ratePerDay: nil, sampledDays: 0)
        }
        let span = calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        let gaps = zip(days, days.dropFirst()).map { calendar.dateComponents([.day], from: $0.date, to: $1.date).day ?? 0 }
        let slopes = sortedSlopes(days, minimumSeparationDays: span >= 7 ? 7 : 1, calendar: calendar)
        guard !slopes.isEmpty else {
            return .init(points: [], measuredDays: days.count, spanDays: span + 1, largestGapDays: gaps.max() ?? 0, ratePerDay: nil, sampledDays: days.count)
        }
        let slope = slopes[(slopes.count - 1) / 2]
        let sample = bounded(days)
        let intercepts = sample.map { $0.pounds - slope * Double(calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0) }.sorted()
        let intercept = intercepts[(intercepts.count - 1) / 2]
        var segment = 0
        var points: [Point] = []
        for (index, day) in days.enumerated() {
            if index > 0 && gaps[index - 1] > 7 { segment += 1 }
            let pounds = intercept + slope * Double(calendar.dateComponents([.day], from: first.date, to: day.date).day ?? 0)
            guard pounds.isFinite, pounds > 0 else {
                return .init(points: [], measuredDays: days.count, spanDays: span + 1, largestGapDays: gaps.max() ?? 0, ratePerDay: nil, sampledDays: sample.count)
            }
            points.append(.init(date: day.date, pounds: pounds, segment: segment))
        }
        return .init(points: points, measuredDays: days.count, spanDays: span + 1, largestGapDays: gaps.max() ?? 0,
                     ratePerDay: slope, sampledDays: sample.count)
    }

    private static func bounded(_ values: [AdaptiveWeightEvidence]) -> [AdaptiveWeightEvidence] {
        guard values.count > 181 else { return values }
        return (0..<181).map { values[Int((Double($0) * Double(values.count - 1) / 180).rounded())] }
    }
}
