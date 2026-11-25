import Foundation

public struct RunCadenceSample: Codable, Equatable {
    public let date: Date
    public let stepsPerMinute: Double
    public let sourceName: String
    public init(date: Date, stepsPerMinute: Double, sourceName: String = "iPhone motion") {
        self.date = date; self.stepsPerMinute = stepsPerMinute; self.sourceName = sourceName
    }
}

/// Timestamped evidence only. A recovery never fills gaps or presents the last
/// checkpoint value as a current sensor reading.
public struct RunSensorCheckpoint: Codable, Equatable {
    public let recordingID: String
    public var heartRate: [RunHeartRateSample]
    public var cadence: [RunCadenceSample]
    public init(recordingID: String, heartRate: [RunHeartRateSample] = [], cadence: [RunCadenceSample] = []) {
        self.recordingID = recordingID; self.heartRate = heartRate; self.cadence = cadence
    }
    public func isValid(recordingID: String, startDate: Date, endDate: Date) -> Bool {
        guard self.recordingID == recordingID, !recordingID.isEmpty,
              heartRate.count <= 86_400, cadence.count <= 86_400 else { return false }
        func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite && date >= startDate && date <= endDate }
        return heartRate.allSatisfy { valid($0.date) && $0.bpm.isFinite && (30...240).contains($0.bpm) && !$0.sourceID.isEmpty }
            && cadence.allSatisfy { valid($0.date) && $0.stepsPerMinute.isFinite && (0...300).contains($0.stepsPerMinute) && !$0.sourceName.isEmpty }
            && zip(heartRate, heartRate.dropFirst()).allSatisfy { $0.date <= $1.date }
            && zip(cadence, cadence.dropFirst()).allSatisfy { $0.date <= $1.date }
    }
    public func latestHeartRate(at now: Date, after resumedAt: Date) -> RunHeartRateSample? {
        guard let value = heartRate.last, value.date >= resumedAt, value.date <= now, now.timeIntervalSince(value.date) <= 30 else { return nil }
        guard heartRate.filter({ $0.date == value.date }).allSatisfy({ $0.sourceID == value.sourceID && $0.bpm == value.bpm }) else { return nil }
        return value
    }
    public func latestCadence(at now: Date, after resumedAt: Date) -> RunCadenceSample? {
        guard let value = cadence.last, value.date >= resumedAt, value.date <= now, now.timeIntervalSince(value.date) <= 10 else { return nil }
        return value
    }
    @discardableResult public mutating func append(_ sample: RunHeartRateSample, after resumedAt: Date, now: Date) -> Bool {
        guard heartRate.count < 86_400, sample.date >= resumedAt, sample.date <= now,
              sample.date.timeIntervalSinceReferenceDate.isFinite, sample.bpm.isFinite, (30...240).contains(sample.bpm),
              !sample.sourceID.isEmpty, heartRate.last.map({ $0.date <= sample.date }) ?? true,
              !heartRate.suffix(16).contains(sample) else { return false }
        heartRate.append(sample); return true
    }
    @discardableResult public mutating func append(_ sample: RunCadenceSample, after resumedAt: Date, now: Date) -> Bool {
        guard cadence.count < 86_400, sample.date >= resumedAt, sample.date <= now,
              sample.date.timeIntervalSinceReferenceDate.isFinite, sample.stepsPerMinute.isFinite, (0...300).contains(sample.stepsPerMinute),
              !sample.sourceName.isEmpty, cadence.last.map({ $0.date < sample.date }) ?? true else { return false }
        cadence.append(sample); return true
    }
}
