import Foundation

public enum WorkoutHistoryReadError: LocalizedError {
    case invalidCursor, incompleteCache, unavailable, accountChanged
    public var errorDescription: String? {
        switch self {
        case .invalidCursor: "Refresh workout history before loading the next page."
        case .incompleteCache: "Complete workout history is unavailable offline. Loaded sessions are kept; reconnect and refresh for full comparisons."
        case .unavailable: "This version cannot confirm complete workout history. Loaded coverage is shown separately."
        case .accountChanged: "Return to the account that opened this workout history."
        }
    }
}

/// Exact server Timestamp components avoid dropping sessions tied within the same
/// floating-point Date. The fixed event-date cutoff is shared across pages;
/// newly backdated writes still require a refresh.
public struct WorkoutHistoryCursor: Codable, Equatable, Sendable {
    public let userID: String
    public let upperBound: Date
    public let lastSeconds: Int64
    public let lastNanoseconds: Int32
    public let lastDocumentID: String
    public var lastDate: Date { Date(timeIntervalSince1970: Double(lastSeconds) + Double(lastNanoseconds) / 1_000_000_000) }

    public init(userID: String, upperBound: Date, lastSeconds: Int64, lastNanoseconds: Int32, lastDocumentID: String) throws {
        self.userID = userID; self.upperBound = upperBound; self.lastSeconds = lastSeconds
        self.lastNanoseconds = lastNanoseconds; self.lastDocumentID = lastDocumentID
        try validate(userID: userID)
    }
    public func validate(userID: String) throws {
        guard !userID.isEmpty, self.userID == userID, upperBound.timeIntervalSinceReferenceDate.isFinite,
              (-62_135_596_800...253_402_300_799).contains(lastSeconds),
              (0..<1_000_000_000).contains(lastNanoseconds), !lastDocumentID.isEmpty, !lastDocumentID.contains("/"),
              lastDocumentID.utf8.count <= 1_500, lastDate <= upperBound else { throw WorkoutHistoryReadError.invalidCursor }
    }
}

public struct WorkoutHistoryPage {
    public let logs: [WorkoutSessionLog]
    public let nextCursor: WorkoutHistoryCursor?
    public let isFromCache: Bool
    public init(logs: [WorkoutSessionLog], nextCursor: WorkoutHistoryCursor?, isFromCache: Bool) {
        self.logs = logs; self.nextCursor = nextCursor; self.isFromCache = isFromCache
    }
}

public extension WorkoutRepositoryProtocol {
    func fetchWorkoutHistoryPage(userID: String, cursor: WorkoutHistoryCursor?, pageSize: Int) async throws -> WorkoutHistoryPage {
        throw WorkoutHistoryReadError.unavailable
    }

    /// Full analytics must not silently treat the newest 30/60/200 as lifetime data.
    /// A cached/incomplete page prevents all-history claims rather than inventing zeros.
    func fetchCompleteWorkoutHistory(userID: String, pageSize: Int = 100) async throws -> [WorkoutSessionLog] {
        var cursor: WorkoutHistoryCursor?
        var logs: [WorkoutSessionLog] = []
        var seenCursors = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await fetchWorkoutHistoryPage(userID: userID, cursor: cursor, pageSize: pageSize)
            guard !page.isFromCache else { throw WorkoutHistoryReadError.incompleteCache }
            logs.append(contentsOf: page.logs)
            cursor = page.nextCursor
            if let cursor {
                try cursor.validate(userID: userID)
                let key = "\(cursor.lastSeconds)|\(cursor.lastNanoseconds)|\(cursor.lastDocumentID)"
                guard seenCursors.insert(key).inserted else { throw WorkoutHistoryReadError.invalidCursor }
            }
        } while cursor != nil
        return WorkoutSetMath.uniqueSessions(logs).sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return ($0.id ?? "") > ($1.id ?? "")
        }
    }
}
