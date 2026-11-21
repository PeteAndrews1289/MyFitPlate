import Foundation

/// A batch is a collection of independent, revision-bound assertions, never a
/// range write. Successful dates are retained when another date needs attention.
public struct NutritionDayBatchReview: Codable {
    public enum Result: String, Codable { case awaitingReview, saving, saved, retry, changed }
    public struct Entry: Codable, Identifiable {
        public let id: String
        public var reviewedLog: DailyLog
        public var result: Result
    }
    public static let scope = "nutrition-day-batch-review"
    public let ownerID: String
    public let status: NutritionDayStatus
    public private(set) var entries: [Entry]
    public init(ownerID: String, status: NutritionDayStatus, logs: [DailyLog], now: Date = Date()) throws {
        guard !ownerID.isEmpty, !logs.isEmpty, logs.count <= 31 else { throw NutritionDayReviewError.changed }
        var keys = Set<String>()
        entries = try logs.map { log in
            guard let day = DiaryDayContext(userID: ownerID, date: log.date, dayKey: log.id),
                  !day.isFuture(now: now), keys.insert(day.dayKey).inserted else { throw NutritionDayReviewError.changed }
            return Entry(id: day.dayKey, reviewedLog: log, result: .awaitingReview)
        }
        self.ownerID = ownerID; self.status = status
    }
    public var unresolvedCount: Int { entries.filter { $0.result != .saved }.count }
    public mutating func mark(_ id: String, result: Result) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].result != .saved else { return }
        entries[index].result = result
    }
    /// A retry first reconciles with saved evidence. A lost response is not a new
    /// write; changed food/reviews require a new explicit inspection.
    public mutating func reconcile(with latest: [DailyLog], currentOwner: String) throws {
        guard currentOwner == ownerID else { throw NutritionDayReviewError.changed }
        for index in entries.indices where entries[index].result != .saved {
            guard let log = latest.first(where: { NutritionDayReviewRules.key($0) == entries[index].id }) else {
                entries[index].result = .retry; continue
            }
            if let receipt = log.nutritionDayReview, receipt.ownerID == ownerID, receipt.status == status,
               NutritionDayReviewRules.isCurrent(receipt, in: log),
               (try? NutritionDayReviewRules.fingerprint(log)) == (try? NutritionDayReviewRules.fingerprint(entries[index].reviewedLog)) {
                entries[index].result = .saved
            } else if NutritionDayReviewRules.sameReviewedState(log, entries[index].reviewedLog) {
                entries[index].result = .retry
            } else { entries[index].result = .changed }
        }
    }
    public mutating func reviewLatest(_ log: DailyLog, currentOwner: String) throws {
        guard currentOwner == ownerID, let id = NutritionDayReviewRules.key(log),
              let index = entries.firstIndex(where: { $0.id == id && $0.result == .changed }) else { throw NutritionDayReviewError.changed }
        entries[index].reviewedLog = log; entries[index].result = .awaitingReview
    }
}
