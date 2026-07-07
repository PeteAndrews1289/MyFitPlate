import Foundation

/// One heart-rate training zone, expressed as a fraction of max HR.
public struct HeartRateZone: Equatable, Sendable {
    public let number: Int
    public let name: String
    public let lowerPercent: Double
    public let upperPercent: Double

    public init(number: Int, name: String, lowerPercent: Double, upperPercent: Double) {
        self.number = number
        self.name = name
        self.lowerPercent = lowerPercent
        self.upperPercent = upperPercent
    }

    /// The bpm range of this zone for a given max HR.
    public func bounds(maxHR: Double) -> (lower: Int, upper: Int) {
        (Int((lowerPercent * maxHR).rounded()), Int((upperPercent * maxHR).rounded()))
    }
}

public enum HeartRateZones {
    /// The common 5-zone model as fractions of max HR.
    public static let zones: [HeartRateZone] = [
        HeartRateZone(number: 1, name: "Recovery", lowerPercent: 0.50, upperPercent: 0.60),
        HeartRateZone(number: 2, name: "Easy", lowerPercent: 0.60, upperPercent: 0.70),
        HeartRateZone(number: 3, name: "Aerobic", lowerPercent: 0.70, upperPercent: 0.80),
        HeartRateZone(number: 4, name: "Tempo", lowerPercent: 0.80, upperPercent: 0.90),
        HeartRateZone(number: 5, name: "Threshold", lowerPercent: 0.90, upperPercent: 1.02)
    ]

    /// Age-predicted max HR (Fox formula) — the fallback when the user hasn't measured their own.
    /// Floored so an implausible age can't produce a dangerously low max.
    public static func estimatedMaxHR(age: Int) -> Double {
        max(140, 220 - Double(age))
    }

    /// Classify a single heart rate (bpm) into its zone. A HR below Z1's floor still
    /// reports Z1 (it's simply very easy); nil only when the inputs are non-positive.
    public static func zone(forHeartRate hr: Double, maxHR: Double) -> HeartRateZone? {
        guard hr > 0, maxHR > 0 else { return nil }
        let fraction = hr / maxHR
        return zones.last(where: { fraction >= $0.lowerPercent }) ?? zones.first
    }

    /// Seconds spent in each zone `[Z1…Z5]` from a heart-rate series. Each sample holds
    /// its zone until the next sample; gaps longer than `maxGapSeconds` (a pause or a
    /// dropout) are skipped so they don't get charged to whatever zone came before.
    public static func timeInZones(
        samples: [(date: Date, bpm: Double)],
        maxHR: Double,
        maxGapSeconds: Double = 600
    ) -> [Double] {
        var seconds = [Double](repeating: 0, count: zones.count)
        guard samples.count >= 2, maxHR > 0 else { return seconds }
        let sorted = samples.sorted { $0.date < $1.date }
        for i in 0..<(sorted.count - 1) {
            let dt = sorted[i + 1].date.timeIntervalSince(sorted[i].date)
            guard dt > 0, dt <= maxGapSeconds else { continue }
            guard let zone = zone(forHeartRate: sorted[i].bpm, maxHR: maxHR) else { continue }
            let index = zone.number - 1
            if index >= 0, index < seconds.count { seconds[index] += dt }
        }
        return seconds
    }
}
