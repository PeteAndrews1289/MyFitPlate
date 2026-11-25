import Foundation

public enum RecoveryRating: Int, Codable, CaseIterable, Sendable {
    case none = 0, mild, moderate, high
    public var title: String {
        switch self {
        case .none: "None"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }
}

/// A person's dated observation. It is never a diagnosis or a measured tissue-readiness score.
public struct RecoveryCheckIn: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var revisionID: String
    public var group: RecoveryMuscleGroup
    public var observedAt: Date
    public var soreness: RecoveryRating?
    public var fatigue: RecoveryRating?
    public var painOrInjury: Bool
    public var note: String
    public init(id: String = UUID().uuidString, group: RecoveryMuscleGroup, observedAt: Date = Date(),
                soreness: RecoveryRating? = nil, fatigue: RecoveryRating? = nil, painOrInjury: Bool = false, note: String = "") {
        self.id = id; revisionID = UUID().uuidString; self.group = group; self.observedAt = observedAt
        self.soreness = soreness; self.fatigue = fatigue; self.painOrInjury = painOrInjury; self.note = note
    }
    public func validate(asOf now: Date = Date()) throws {
        guard !id.isEmpty, !revisionID.isEmpty, id.count <= 128, revisionID.count <= 128,
              observedAt.timeIntervalSince1970.isFinite, observedAt <= now.addingTimeInterval(60),
              observedAt >= Date(timeIntervalSince1970: 0), note.count <= 500,
              soreness != nil || fatigue != nil || painOrInjury || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecoveryCheckInError.invalid
        }
    }
    public var needsPainReview: Bool {
        let words = note.lowercased()
        return painOrInjury || ["pain", "injur", "hurts", "sharp ache"].contains(where: words.contains)
    }
}

public enum RecoveryCheckInError: LocalizedError {
    case invalid, changed, accountChanged, limit
    public var errorDescription: String? {
        switch self {
        case .invalid: "Choose a past or current observation time and record at least one recovery signal. Notes can contain up to 500 characters."
        case .changed: "This check-in changed in another review. Reopen it before saving; your existing observations are kept."
        case .accountChanged: "Return to the account that opened this check-in before saving."
        case .limit: "The on-device observation library is full. Export or remove an older check-in before adding another."
        }
    }
}

/// Device-only observations, isolated by account and cleared by normal account draft cleanup.
/// Every edit/removal checks the complete expected record; corrupt/newer bytes are never replaced.
@MainActor public final class RecoveryCheckInStore {
    public static let scope = "recovery-check-ins-v1"
    private struct Library: Codable { var version = 1; var observations: [RecoveryCheckIn] = [] }
    private let store: EditorDraftStore
    private let currentUserID: @MainActor () -> String?
    public init(store: EditorDraftStore = EditorDraftStore(),
                currentUserID: @escaping @MainActor () -> String? = { DIContainer.shared.authService.currentUserID }) {
        self.store = store; self.currentUserID = currentUserID
    }
    public func observations(userID: String) throws -> [RecoveryCheckIn] {
        try requireOwner(userID)
        let library = try store.load(Library.self, userID: userID, scope: Self.scope)?.value ?? Library()
        guard library.version == 1, library.observations.count <= 1_000,
              Set(library.observations.map(\.id)).count == library.observations.count else { throw RecoveryCheckInError.invalid }
        for value in library.observations { try value.validate(asOf: .distantFuture) }
        return library.observations.sorted { $0.observedAt > $1.observedAt }
    }
    @discardableResult public func save(_ observation: RecoveryCheckIn, expected: RecoveryCheckIn?, userID: String,
                                        now: Date = Date()) throws -> RecoveryCheckIn {
        try observation.validate(asOf: now)
        var values = try observations(userID: userID)
        guard expected == nil || expected?.id == observation.id,
              values.first(where: { $0.id == observation.id }) == expected else { throw RecoveryCheckInError.changed }
        var saved = observation; saved.revisionID = UUID().uuidString
        values.removeAll { $0.id == observation.id }; values.append(saved)
        guard values.count <= 1_000 else { throw RecoveryCheckInError.limit }
        try store.save(Library(observations: values), userID: userID, scope: Self.scope)
        return saved
    }
    public func remove(_ expected: RecoveryCheckIn, userID: String) throws {
        var values = try observations(userID: userID)
        guard values.first(where: { $0.id == expected.id }) == expected else { throw RecoveryCheckInError.changed }
        values.removeAll { $0.id == expected.id }
        try store.save(Library(observations: values), userID: userID, scope: Self.scope)
    }
    private func requireOwner(_ userID: String) throws {
        guard !userID.isEmpty, currentUserID() == userID else { throw RecoveryCheckInError.accountChanged }
    }
}

public enum RecoveryPlanningState: String, Codable, Sendable {
    case unknown, recentExposure, accumulatedExposure, lowerRecentLoad, reviewCheckIn, stopAndChange
    public var title: String {
        switch self {
        case .unknown: "Unknown"
        case .recentExposure: "Recent training"
        case .accumulatedExposure: "Accumulated training"
        case .lowerRecentLoad: "Lower recent load"
        case .reviewCheckIn: "Check-in needs attention"
        case .stopAndChange: "Stop or change painful work"
        }
    }
}

public enum RecoverySleepFreshness: String, Codable, Sendable { case current, stale, unknown }
public struct RecoveryTrainingEvidence: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let workingSets: Int
    public let exerciseNames: [String]
}
public struct RecoveryRunEvidence: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let movingMinutes: Double
    public let source: String
}
public struct RecoveryRegionEvidence: Identifiable, Sendable {
    public var id: String { group.rawValue }
    public let modelVersion: String
    public let group: RecoveryMuscleGroup
    public let asOf: Date
    public let training: [RecoveryTrainingEvidence]
    public let runs: [RecoveryRunEvidence]
    public let sleepScore: Int?
    public let sleepDate: Date?
    public let sleepFreshness: RecoverySleepFreshness
    public let checkIn: RecoveryCheckIn?
    public let checkInIsFresh: Bool
    public let state: RecoveryPlanningState
    public var sevenDayWorkingSets: Int { training.filter { asOf.timeIntervalSince($0.date) <= 7 * 86_400 }.reduce(0) { $0 + $1.workingSets } }
    public var explanation: String {
        switch state {
        case .unknown: "There is not enough recent training or subjective evidence to suggest a training adjustment. Missing evidence does not mean fully recovered."
        case .recentExposure: "This region has recent measured working sets or a meaningful run. Review how it feels before repeating demanding work."
        case .accumulatedExposure: "Multiple recent sessions contribute to this region's training exposure. Consider your next session alongside the dated evidence below."
        case .lowerRecentLoad: "Less recent training is recorded for this region. This describes your log, not measured tissue readiness."
        case .reviewCheckIn: "Recent soreness, fatigue or low sleep adds a reason to review the next session. You choose whether to keep or change the plan."
        case .stopAndChange: "Your check-in mentions pain or injury. Stop or change movements that hurt; do not use this map to clear an injury. Seek qualified help for persistent or concerning symptoms."
        }
    }
}
