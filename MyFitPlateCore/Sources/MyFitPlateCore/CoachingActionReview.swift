import Foundation

/// A coaching action opens an existing reviewed operation; it never executes advice text.
public struct CoachingActionReview: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case foodLog, meal, sessionTargets, lighterWeek, scheduledRun }
    public let id: UUID
    public let kind: Kind
    public let day: DiaryDayContext
    public let targetID: String?
    public let targetFingerprint: String?
    public let createdAt: Date
    public let evidence: [String]

    public init(kind: Kind, day: DiaryDayContext, targetID: String? = nil, targetFingerprint: String? = nil,
                evidence: [String], now: Date = Date()) {
        id = UUID()
        self.kind = kind
        self.day = day
        self.targetID = targetID
        self.targetFingerprint = targetFingerprint
        self.evidence = evidence
        createdAt = now
    }

    public func validate(userID: String?, now: Date = Date(), currentTargetID: String? = nil,
                         currentFingerprint: String? = nil) throws {
        guard day.isOwned(by: userID) else { throw CoachingActionReviewError.accountChanged }
        let age = now.timeIntervalSince(createdAt)
        guard age >= -1, age <= 30 * 60, day.isToday(now: now) else { throw CoachingActionReviewError.stale }
        guard targetID == currentTargetID, targetFingerprint == currentFingerprint else {
            throw CoachingActionReviewError.changed
        }
    }
}

public enum CoachingActionReviewError: LocalizedError {
    case accountChanged, stale, changed, missingReceipt

    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "This review belongs to a different account. Open a new suggestion."
        case .stale: return "This suggestion needs a fresh look. Refresh coaching before continuing."
        case .changed: return "The plan changed after this suggestion. Review the current plan again."
        case .missingReceipt: return "There is no accepted operation to record yet."
        }
    }
}

/// Local outcome metadata references the real domain operation. The existing diary,
/// program and planning save sessions remain the only writers of those records.
public struct CoachingActionOutcome: Codable, Equatable, Identifiable {
    public enum State: String, Codable { case opened, closed, accepted }
    public var id: UUID { review.id }
    public let review: CoachingActionReview
    public private(set) var state: State
    public private(set) var operationID: String?
    public private(set) var updatedAt: Date

    public init(review: CoachingActionReview, now: Date = Date()) {
        self.review = review; state = .opened; updatedAt = now
    }

    public mutating func close(now: Date = Date()) {
        guard state == .opened else { return }
        state = .closed; updatedAt = now
    }

    public mutating func accept(operationID: String, now: Date = Date()) throws {
        guard !operationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoachingActionReviewError.missingReceipt
        }
        if state == .accepted {
            guard self.operationID == operationID else { throw CoachingActionReviewError.changed }
            return
        }
        self.operationID = operationID; state = .accepted; updatedAt = now
    }
}

@MainActor
public final class CoachingActionHistory {
    private let store: EditorDraftStore
    private let scope = "coaching-action-history-v1"

    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }

    public func outcomes(userID: String) throws -> [CoachingActionOutcome] {
        try store.load([CoachingActionOutcome].self, userID: userID, scope: scope)?.value ?? []
    }

    public func record(_ outcome: CoachingActionOutcome, currentUserID: String?) throws {
        let owner = outcome.review.day.userID
        guard currentUserID == owner else { throw CoachingActionReviewError.accountChanged }
        var values = try outcomes(userID: owner)
        if let index = values.firstIndex(where: { $0.id == outcome.id }) {
            // Dismissal and late UI callbacks cannot overwrite an accepted operation receipt.
            if values[index].state == .accepted { return }
            values[index] = outcome
        } else { values.append(outcome) }
        values.sort { $0.updatedAt > $1.updatedAt }
        try store.save(Array(values.prefix(100)), userID: owner, scope: scope)
    }
}
