import Foundation

public struct RunHeartRateZoneSettings: Codable, Equatable {
    public enum Method: String, Codable, CaseIterable { case ageEstimate, enteredMaximum, enteredThresholds }
    public var method: Method
    public var maximumBPM: Double
    public var referenceAge: Int?
    /// Four strictly increasing lower bounds for zones 2–5. Nil keeps legacy percentage zones.
    public var thresholdsBPM: [Double]?

    public init(method: Method, maximumBPM: Double, referenceAge: Int? = nil, thresholdsBPM: [Double]? = nil) {
        self.method = method
        self.maximumBPM = maximumBPM
        self.referenceAge = referenceAge
        self.thresholdsBPM = thresholdsBPM
    }

    public static func estimated(age: Int) -> Self {
        Self(method: .ageEstimate, maximumBPM: HeartRateZones.estimatedMaxHR(age: age), referenceAge: age)
    }

    public var isValid: Bool {
        guard maximumBPM.isFinite && (60...240).contains(maximumBPM) else { return false }
        guard method == .enteredThresholds else { return true }
        guard let values = thresholdsBPM, values.count == 4,
              values.allSatisfy({ $0.isFinite && (31...239).contains($0) }) else { return false }
        return zip(values, values.dropFirst()).allSatisfy { $0.0 < $0.1 }
    }
    public func zone(for bpm: Double) -> HeartRateZone? {
        guard isValid, bpm.isFinite, (30...240).contains(bpm) else { return nil }
        if method == .enteredThresholds, let thresholdsBPM {
            return HeartRateZones.zones[thresholdsBPM.filter { bpm >= $0 }.count]
        }
        return HeartRateZones.zone(forHeartRate: bpm, maxHR: maximumBPM)
    }
    public func rangeDescription(zoneNumber: Int) -> String {
        guard (1...5).contains(zoneNumber), isValid else { return "Unavailable" }
        if method == .enteredThresholds, let thresholdsBPM {
            if zoneNumber == 1 { return "Below \(Int(thresholdsBPM[0])) bpm" }
            if zoneNumber == 5 { return "\(Int(thresholdsBPM[3]))+ bpm" }
            return "\(Int(thresholdsBPM[zoneNumber - 2]))–<\(Int(thresholdsBPM[zoneNumber - 1])) bpm"
        }
        let lower = Int(maximumBPM * Double(zoneNumber + 4) / 10)
        return zoneNumber == 1 ? "Below \(Int(maximumBPM * 0.6)) bpm" : zoneNumber == 5 ? "\(lower)+ bpm" : "\(lower)–<\(Int(maximumBPM * Double(zoneNumber + 5) / 10)) bpm"
    }
    public var description: String {
        let maximum = isValid ? Int(maximumBPM.rounded()).description : "Unavailable"
        switch method {
        case .ageEstimate: return "Age-estimated maximum \(maximum) bpm"
        case .enteredMaximum: return "Your entered maximum \(maximum) bpm"
        case .enteredThresholds: return "Your entered zone boundaries"
        }
    }
}

public struct RunHeartRateSample: Codable, Equatable {
    public let date: Date
    public let bpm: Double
    public let sourceID: String
    public let sourceName: String
    public init(date: Date, bpm: Double, sourceID: String, sourceName: String) {
        self.date = date
        self.bpm = bpm
        self.sourceID = sourceID
        self.sourceName = sourceName
    }
}

public enum RunHeartRateEvidence {
    public struct Coverage: Equatable {
        public let zoneSeconds: [Double]
        public let coveredSeconds: Double
        public let averageBPM: Double?
        public let sourceNames: [String]
    }

    /// Only workout-associated samples may enter this reducer. Never fills a dropout,
    /// crosses sensor ownership, or charges an identified pause to a previous sample.
    public static func coverage(samples: [RunHeartRateSample], run: Run,
                                settings: RunHeartRateZoneSettings, maximumGap: TimeInterval = 30) -> Coverage {
        let empty = Coverage(zoneSeconds: Array(repeating: 0, count: 5), coveredSeconds: 0, averageBPM: nil, sourceNames: [])
        guard settings.isValid, maximumGap.isFinite, maximumGap > 0,
              run.startDate < run.endDate, run.movingSeconds.isFinite, run.movingSeconds > 0 else { return empty }
        let pauses: [DateInterval]
        if let timeline = run.pauseTimeline {
            guard let valid = timeline.validatedUnionIntervals(startDate: run.startDate, endDate: run.endDate, activeSeconds: run.movingSeconds) else { return empty }
            pauses = valid
        } else { pauses = [] }
        let candidates = samples.filter { $0.date.timeIntervalSinceReferenceDate.isFinite && $0.date >= run.startDate && $0.date <= run.endDate }
        let grouped = Dictionary(grouping: candidates, by: \.date)
        // Conflicting samples are a boundary, not a value to choose arbitrarily.
        let ordered = grouped.keys.sorted().map { date -> RunHeartRateSample in
            let values = grouped[date] ?? []
            let first = values[0]
            if values.allSatisfy({ $0.sourceID == first.sourceID && $0.bpm == first.bpm }) { return first }
            return RunHeartRateSample(date: date, bpm: .nan, sourceID: "", sourceName: "")
        }
        guard ordered.count > 1 else { return empty }
        var zones = Array(repeating: 0.0, count: 5)
        var weightedBPM = 0.0
        var sources: Set<String> = []
        for (current, next) in zip(ordered, ordered.dropFirst()) {
            let seconds = next.date.timeIntervalSince(current.date)
            guard current.bpm.isFinite, next.bpm.isFinite, (30...240).contains(current.bpm), (30...240).contains(next.bpm),
                  !current.sourceID.isEmpty, current.sourceID == next.sourceID,
                  seconds > 0, seconds <= maximumGap,
                  let zone = settings.zone(for: current.bpm) else { continue }
            let excluded = pauses.reduce(0.0) { total, pause in
                total + max(0, min(pause.end, next.date).timeIntervalSince(max(pause.start, current.date)))
            }
            let covered = max(0, seconds - excluded)
            zones[zone.number - 1] += covered
            weightedBPM += covered * current.bpm
            if covered > 0 { sources.insert(current.sourceName) }
        }
        let total = zones.reduce(0, +)
        return Coverage(zoneSeconds: zones, coveredSeconds: total,
                        averageBPM: total > 0 ? weightedBPM / total : nil, sourceNames: sources.sorted())
    }
}

public struct RunHeartRateZoneReview: Codable, Equatable {
    public let originalMethod: RunHeartRateZoneSettings
    public let originalReviewedAt: Date
    public var displayedMethod: RunHeartRateZoneSettings
    public var updatedAt: Date
}

/// A display recalculation cannot erase the first method used to interpret this run.
public final class RunHeartRateZoneStore {
    private let drafts: EditorDraftStore
    public init(directory: URL? = nil) { drafts = EditorDraftStore(directory: directory) }

    public func settings(userID: String, age: Int) throws -> RunHeartRateZoneSettings {
        guard let saved = try drafts.load(RunHeartRateZoneSettings.self, userID: userID, scope: "run-zones.settings.v1") else { return .estimated(age: age) }
        guard saved.value.isValid else { throw CocoaError(.coderReadCorrupt) }
        return saved.value.method == .ageEstimate ? .estimated(age: age) : saved.value
    }

    public func saveSettings(_ settings: RunHeartRateZoneSettings, userID: String) throws {
        guard settings.isValid else { throw CocoaError(.coderInvalidValue) }
        try drafts.save(settings, userID: userID, scope: "run-zones.settings.v1")
    }

    @discardableResult
    public func review(runID: String, settings: RunHeartRateZoneSettings, userID: String, now: Date = Date()) throws -> RunHeartRateZoneReview {
        guard settings.isValid, !runID.isEmpty else { throw CocoaError(.coderInvalidValue) }
        let scope = "run-zones.review.\(runID)"
        var review = try drafts.load(RunHeartRateZoneReview.self, userID: userID, scope: scope)?.value
            ?? RunHeartRateZoneReview(originalMethod: settings, originalReviewedAt: now, displayedMethod: settings, updatedAt: now)
        review.displayedMethod = settings
        review.updatedAt = now
        try drafts.save(review, userID: userID, scope: scope, now: now)
        return review
    }
}
