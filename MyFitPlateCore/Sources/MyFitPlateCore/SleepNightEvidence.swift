import Foundation
import HealthKit

/// A reproducible projection of source intervals. It does not diagnose sleep or infer missing stages.
public struct SleepNightEvidence: Codable, Equatable, Identifiable, Sendable {
    public static let calculationVersion = "sleep-interval-union-v1"
    public var id: String { "\(timeZoneIdentifier):\(night.timeIntervalSince1970)" }
    public let night: Date
    public let timeZoneIdentifier: String
    public let timeAsleep: TimeInterval
    public let timeInBed: TimeInterval
    public let timeAwake: TimeInterval
    public let timeCore: TimeInterval
    public let timeDeep: TimeInterval
    public let timeREM: TimeInterval
    public let timeUnspecified: TimeInterval
    public let conflictingStageDuration: TimeInterval
    public let overlappingSourceDuration: TimeInterval
    public let sourceNames: [String]
    public let sourceSampleIDs: [UUID]
    public let sourceTimeZones: [String]
    public let episodes: [DateInterval]
    public let daytimeEpisodeCount: Int
    public var firstSleep: Date? { episodes.first?.start }
    public var lastSleep: Date? { episodes.last?.end }

    /// Local 18:00 boundaries retain the app's established evening-date convention.
    /// An interval crossing that boundary is split, never assigned twice.
    public static func normalize(_ samples: [HKCategorySample], now: Date = Date(), calendar: Calendar = .current) -> [Self] {
        let valid = samples.filter {
            $0.startDate < $0.endDate && $0.endDate <= now && $0.endDate.timeIntervalSince($0.startDate) <= 48 * 3600
                && HKCategoryValueSleepAnalysis(rawValue: $0.value) != nil
        }
        var grouped: [Date: [(HKCategorySample, DateInterval)]] = [:]
        for sample in valid {
            var cursor = sample.startDate
            while cursor < sample.endDate {
                let night = SleepEvidenceRules.nightKey(for: cursor, calendar: calendar)
                guard let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: night),
                      let boundary = calendar.date(byAdding: .day, value: 1, to: evening), boundary > cursor else { break }
                let end = min(boundary, sample.endDate)
                grouped[night, default: []].append((sample, DateInterval(start: cursor, end: end)))
                cursor = end
            }
        }
        return grouped.keys.sorted().compactMap { night in
            guard let entries = grouped[night] else { return nil }
            let boundaries = Set(entries.flatMap { [$0.1.start, $0.1.end] }).sorted()
            var starting: [Date: [Int]] = [:], ending: [Date: [Int]] = [:]
            for (index, entry) in entries.enumerated() {
                starting[entry.1.start, default: []].append(index)
                ending[entry.1.end, default: []].append(index)
            }
            var activeIndices: Set<Int> = []
            var asleep = 0.0, inBed = 0.0, awake = 0.0, core = 0.0, deep = 0.0, rem = 0.0
            var unspecified = 0.0, conflicts = 0.0, overlaps = 0.0
            var episodes: [DateInterval] = []
            for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                for index in ending[start] ?? [] { activeIndices.remove(index) }
                for index in starting[start] ?? [] { activeIndices.insert(index) }
                let active = activeIndices.map { entries[$0] }
                let values = Set(active.map { $0.0.value })
                let duration = end.timeIntervalSince(start)
                if values.contains(HKCategoryValueSleepAnalysis.inBed.rawValue) { inBed += duration }
                let sleeping = active.filter { SleepEvidenceRules.isAsleep($0.0) }
                if !sleeping.isEmpty {
                    asleep += duration
                    if let last = episodes.last, last.end == start {
                        episodes[episodes.count - 1] = DateInterval(start: last.start, end: end)
                    } else { episodes.append(DateInterval(start: start, end: end)) }
                    let detailed = values.intersection(Set([HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]))
                    let awakeConflict = values.contains(HKCategoryValueSleepAnalysis.awake.rawValue)
                    if detailed.count > 1 || awakeConflict {
                        conflicts += duration; unspecified += duration
                    } else if detailed.contains(HKCategoryValueSleepAnalysis.asleepCore.rawValue) { core += duration } else if detailed.contains(HKCategoryValueSleepAnalysis.asleepDeep.rawValue) { deep += duration } else if detailed.contains(HKCategoryValueSleepAnalysis.asleepREM.rawValue) { rem += duration } else { unspecified += duration }
                    if Set(sleeping.map { $0.0.sourceRevision.source.bundleIdentifier }).count > 1 { overlaps += duration }
                } else if values.contains(HKCategoryValueSleepAnalysis.awake.rawValue) { awake += duration }
            }
            guard asleep > 0 else { return nil }
            let sourceSamples = entries.map(\.0)
            return Self(night: night, timeZoneIdentifier: calendar.timeZone.identifier,
                timeAsleep: asleep, timeInBed: inBed, timeAwake: awake, timeCore: core, timeDeep: deep, timeREM: rem,
                timeUnspecified: unspecified, conflictingStageDuration: conflicts, overlappingSourceDuration: overlaps,
                sourceNames: Set(sourceSamples.map { $0.sourceRevision.source.name }).sorted(),
                sourceSampleIDs: Set(sourceSamples.map(\.uuid)).sorted { $0.uuidString < $1.uuidString },
                sourceTimeZones: Set(sourceSamples.compactMap { $0.metadata?[HKMetadataKeyTimeZone] as? String }).sorted(),
                episodes: episodes, daytimeEpisodeCount: episodes.filter {
                    let hour = calendar.component(.hour, from: $0.start)
                    return hour >= 10 && hour < 18
                }.count)
        }
    }
}

public struct SleepHistorySnapshot: Codable, Equatable {
    public let ownerID: String
    public let startDay: Date
    public let endDay: Date
    public let timeZoneIdentifier: String
    public let fetchedAt: Date
    public let nights: [SleepNightEvidence]
    public init(ownerID: String, startDay: Date, endDay: Date, timeZoneIdentifier: String,
                fetchedAt: Date = Date(), nights: [SleepNightEvidence]) {
        self.ownerID = ownerID; self.startDay = startDay; self.endDay = endDay
        self.timeZoneIdentifier = timeZoneIdentifier; self.fetchedAt = fetchedAt; self.nights = nights
    }
}

@MainActor
public final class SleepHistoryStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    private func scope(start: Date, end: Date, zone: String) -> String {
        "sleep-history-v1:\(start.timeIntervalSince1970):\(end.timeIntervalSince1970):\(zone)"
    }
    public func load(userID: String, start: Date, end: Date, zone: String) throws -> SleepHistorySnapshot? {
        let value = try store.load(SleepHistorySnapshot.self, userID: userID, scope: scope(start: start, end: end, zone: zone))?.value
        if let value {
            guard value.ownerID == userID else { throw InsightEvidenceError.accountChanged }
            guard value.startDay == start, value.endDay == end, value.timeZoneIdentifier == zone,
                  Self.isValid(value) else { throw InsightEvidenceError.invalid }
        }
        return value
    }
    public func save(_ value: SleepHistorySnapshot, currentUserID: String?) throws {
        guard currentUserID == value.ownerID else { throw InsightEvidenceError.accountChanged }
        guard Self.isValid(value) else { throw InsightEvidenceError.invalid }
        try store.save(value, userID: value.ownerID, scope: scope(start: value.startDay, end: value.endDay, zone: value.timeZoneIdentifier))
    }
    private static func isValid(_ value: SleepHistorySnapshot) -> Bool {
        guard !value.ownerID.isEmpty, value.startDay <= value.endDay,
              let zone = TimeZone(identifier: value.timeZoneIdentifier), value.fetchedAt.timeIntervalSince1970.isFinite,
              Set(value.nights.map(\.id)).count == value.nights.count else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return value.nights.allSatisfy { night in
            let durations = [night.timeAsleep, night.timeInBed, night.timeAwake, night.timeCore, night.timeDeep,
                night.timeREM, night.timeUnspecified, night.conflictingStageDuration, night.overlappingSourceDuration]
            guard night.night >= value.startDay, night.night <= value.endDay,
                  night.timeZoneIdentifier == value.timeZoneIdentifier,
                  calendar.startOfDay(for: night.night) == night.night,
                  durations.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 26 * 3600 }), night.timeAsleep > 0,
                  !night.sourceSampleIDs.isEmpty, Set(night.sourceSampleIDs).count == night.sourceSampleIDs.count,
                  !night.episodes.isEmpty, night.daytimeEpisodeCount >= 0, night.daytimeEpisodeCount <= night.episodes.count,
                  abs(night.timeCore + night.timeDeep + night.timeREM + night.timeUnspecified - night.timeAsleep) < 0.01,
                  abs(night.episodes.reduce(0) { $0 + $1.duration } - night.timeAsleep) < 0.01,
                  let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: night.night),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
            var previousEnd: Date?
            for episode in night.episodes {
                guard episode.duration.isFinite, episode.duration > 0, episode.start >= start, episode.end <= end,
                      previousEnd.map({ $0 < episode.start }) ?? true else { return false }
                previousEnd = episode.end
            }
            return true
        }
    }
}

public extension SleepNightEvidence {
    /// Positions on the report's civil clock, in hours after 18:00. Split at offset
    /// changes so a skipped clock hour stays blank and a repeated hour can overlap.
    var clockSegments: [Range<Double>] {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: night) else { return [] }
        let initialOffset = zone.secondsFromGMT(for: evening)
        func position(_ date: Date, offset: Int) -> Double {
            min(24, max(0, (date.timeIntervalSince(evening) + Double(offset - initialOffset)) / 3600))
        }
        return episodes.flatMap { interval -> [Range<Double>] in
            var parts: [Range<Double>] = []
            var cursor = interval.start
            while cursor < interval.end {
                let transition = zone.nextDaylightSavingTimeTransition(after: cursor)
                let stop = min(transition.flatMap { $0 > cursor ? $0 : nil } ?? interval.end, interval.end)
                let offset = zone.secondsFromGMT(for: cursor)
                let low = position(cursor, offset: offset), high = position(stop, offset: offset)
                if high > low { parts.append(low..<high) }
                cursor = stop
            }
            return parts
        }
    }
}
