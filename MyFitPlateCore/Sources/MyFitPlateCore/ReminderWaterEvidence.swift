import Foundation

/// A local receipt of a real diary/outbox acceptance, not a guessed drinking time.
public struct ReminderWaterAcceptance: Codable, Equatable {
    public let id: String
    public let dayKey: String
    public let acceptedAt: Date
    public let totalAfterOunces: Double
}

@MainActor public final class ReminderWaterEvidenceStore {
    public static let shared = ReminderWaterEvidenceStore()
    private struct Record: Codable {
        let ownerID: String
        var entries: [ReminderWaterAcceptance]
    }
    private let drafts: EditorDraftStore
    private let scope = "reminder-water-acceptance-v1"
    public init(drafts: EditorDraftStore = .init()) { self.drafts = drafts }

    public func recordAccepted(ownerID: String, currentUserID: String?, entryID: String, dayKey: String,
                               totalAfterOunces: Double, acceptedAt: Date = Date()) throws {
        guard currentUserID == ownerID, !ownerID.isEmpty, !entryID.isEmpty,
              DiaryDayContext(userID: ownerID, date: acceptedAt, dayKey: dayKey) != nil,
              totalAfterOunces.isFinite, totalAfterOunces > 0,
              acceptedAt.timeIntervalSinceReferenceDate.isFinite else { throw CocoaError(.coderInvalidValue) }
        var record = try load(ownerID: ownerID)
        // A repeated receipt never pretends another glass was just logged.
        guard !record.entries.contains(where: { $0.id == entryID }) else { return }
        record.entries.removeAll { $0.acceptedAt < acceptedAt.addingTimeInterval(-7 * 86_400) }
        record.entries.append(.init(id: entryID, dayKey: dayKey, acceptedAt: acceptedAt, totalAfterOunces: totalAfterOunces))
        record.entries = Array(record.entries.sorted { $0.acceptedAt > $1.acceptedAt }.prefix(128))
        try drafts.save(record, userID: ownerID, scope: scope, now: acceptedAt)
    }

    public func recentAcceptedTimes(ownerID: String, logs: [String: DailyLog], now: Date = Date()) throws -> [String: Date] {
        var result: [String: Date] = [:]
        for entry in try load(ownerID: ownerID).entries {
            guard entry.acceptedAt <= now, now.timeIntervalSince(entry.acceptedAt) < 45 * 60,
                  let total = logs[entry.dayKey]?.waterTracker?.totalOunces, total.isFinite,
                  total >= entry.totalAfterOunces else { continue }
            // A lower corrected/undone total cannot reuse the receipt as proof of recent water.
            result[entry.dayKey] = max(result[entry.dayKey] ?? .distantPast, entry.acceptedAt)
        }
        return result
    }

    private func load(ownerID: String) throws -> Record {
        let value = try drafts.load(Record.self, userID: ownerID, scope: scope)?.value ?? .init(ownerID: ownerID, entries: [])
        guard value.ownerID == ownerID, Set(value.entries.map(\.id)).count == value.entries.count,
              value.entries.allSatisfy({ !$0.id.isEmpty && DiaryDayContext(userID: ownerID, date: $0.acceptedAt, dayKey: $0.dayKey) != nil
                  && $0.acceptedAt.timeIntervalSinceReferenceDate.isFinite && $0.totalAfterOunces.isFinite && $0.totalAfterOunces > 0 }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }
}
