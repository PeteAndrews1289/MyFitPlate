import Foundation

/// A person's report about advice, separate from the receipt of an actual saved operation.
public struct CoachingFeedback: Codable, Equatable, Identifiable, Sendable {
    public enum Disposition: String, Codable, CaseIterable, Sendable {
        case tried, declined, notRelevant
        public var title: String {
            switch self {
            case .tried: return "I tried it"
            case .declined: return "Not this time"
            case .notRelevant: return "Not relevant"
            }
        }
    }
    public enum Barrier: String, Codable, CaseIterable, Sendable {
        case none, time, foodAvailability, equipment, recovery, preference
        public var title: String {
            switch self {
            case .none: return "No barrier"
            case .time: return "Time"
            case .foodAvailability: return "Food available"
            case .equipment: return "Equipment"
            case .recovery: return "How I felt"
            case .preference: return "Personal preference"
            }
        }
    }
    public enum Result: String, Codable, CaseIterable, Sendable {
        case notRecorded, helpful, noDifference, harder
        public var title: String {
            switch self {
            case .notRecorded: return "Not recorded"
            case .helpful: return "Helpful"
            case .noDifference: return "No difference"
            case .harder: return "Made things harder"
            }
        }
    }
    public let id: UUID
    public let userID: String
    public let planFingerprint: String
    public let actionKind: AdaptiveCoachingPlan.ActionKind
    public let actionTitle: String
    public let planGeneratedAt: Date
    public let recordedAt: Date
    public let disposition: Disposition
    public let barrier: Barrier
    public let result: Result
    public let note: String
    public let actionReviewID: UUID?

    public init(id: UUID = UUID(), userID: String, plan: AdaptiveCoachingPlan,
                disposition: Disposition, barrier: Barrier = .none, result: Result = .notRecorded,
                note: String = "", actionReviewID: UUID? = nil, now: Date = Date()) throws {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              now.timeIntervalSinceReferenceDate.isFinite, now >= plan.generatedAt,
              now.timeIntervalSince(plan.generatedAt) <= 14 * 86_400,
              note.count <= 500, disposition == .tried || result == .notRecorded else { throw CoachingFeedbackError.invalid }
        self.id = id; self.userID = userID; planFingerprint = try Self.fingerprint(plan)
        actionKind = plan.actionKind; actionTitle = plan.primaryAction; planGeneratedAt = plan.generatedAt
        recordedAt = now; self.disposition = disposition; self.barrier = barrier; self.result = result
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines); self.actionReviewID = actionReviewID
    }

    public static func fingerprint(_ plan: AdaptiveCoachingPlan) throws -> String {
        struct Input: Encodable { let kind: String; let title: String; let action: String; let generatedAt: Date; let evidence: [String] }
        return try PlanFingerprint.make(Input(kind: plan.actionKind.rawValue, title: plan.title,
            action: plan.primaryAction, generatedAt: plan.generatedAt, evidence: plan.dataPoints))
    }
}

public enum CoachingFeedbackError: LocalizedError {
    case accountChanged, invalid, changed
    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "Return to the account that opened this coaching review."
        case .invalid: return "Review the feedback before saving. Nothing has changed."
        case .changed: return "This feedback was already saved differently. Open a fresh review."
        }
    }
}

@MainActor
public final class CoachingFeedbackStore {
    private let store: EditorDraftStore
    private let scope = "coaching-feedback-v1"
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func history(userID: String) throws -> [CoachingFeedback] {
        let values = try store.load([CoachingFeedback].self, userID: userID, scope: scope)?.value ?? []
        guard values.allSatisfy({ $0.userID == userID }) else { throw CoachingFeedbackError.accountChanged }
        return values.sorted { $0.recordedAt > $1.recordedAt }
    }
    public func record(_ feedback: CoachingFeedback, currentUserID: String?) throws {
        guard feedback.userID == currentUserID else { throw CoachingFeedbackError.accountChanged }
        var values = try history(userID: feedback.userID)
        if let existing = values.first(where: { $0.id == feedback.id }) {
            guard existing == feedback else { throw CoachingFeedbackError.changed }
            return
        }
        values.append(feedback)
        try store.save(values, userID: feedback.userID, scope: scope)
    }
}

public enum CoachingFeedbackRules {
    /// Changes the practical suggestion only. Targets, prescriptions, evidence and saved
    /// records are unchanged. User-reported helpfulness is never inferred from logging.
    public static func applying(_ feedback: [CoachingFeedback], to plan: AdaptiveCoachingPlan,
                                userID: String, now: Date = Date()) -> AdaptiveCoachingPlan {
        guard let latest = feedback.filter({ $0.userID == userID && $0.actionKind == plan.actionKind
            && $0.recordedAt <= now && now.timeIntervalSince($0.recordedAt) <= 7 * 86_400 })
            .max(by: { $0.recordedAt < $1.recordedAt }),
              latest.barrier != .none || latest.disposition != .tried || latest.result == .harder else { return plan }
        let adjustment: String
        switch latest.barrier {
        case .time: adjustment = plan.actionKind == .reviewTraining
            ? "Review a session that fits the time you have; shorten it explicitly before starting."
            : "Use a familiar meal or leftovers that fit the time you have."
        case .foodAvailability: adjustment = "Review food you already have before planning another meal."
        case .equipment: adjustment = "Review your equipment and exercise alternatives before the next session."
        case .recovery: adjustment = "Check how you feel and review a manageable option; make any plan change yourself."
        case .preference: adjustment = "Choose a familiar alternative you enjoy when reviewing this suggestion."
        case .none: adjustment = latest.result == .harder
            ? "You said this made things harder. Review a simpler option before repeating it."
            : "You declined similar advice. Review an alternative that fits today."
        }
        return AdaptiveCoachingPlan(title: plan.title, subtitle: plan.subtitle,
            patternNote: plan.patternNote, primaryAction: adjustment,
            mealMove: plan.actionKind == .reviewMeal ? adjustment : plan.mealMove,
            trainingMove: plan.actionKind == .reviewTraining ? adjustment : plan.trainingMove,
            recoveryMove: plan.recoveryMove, confidence: plan.confidence,
            dataPoints: plan.dataPoints + ["Your feedback: \(latest.disposition.title) · \(latest.barrier.title) (\(latest.recordedAt.formatted(date: .abbreviated, time: .omitted)))"],
            actionKind: plan.actionKind, generatedAt: plan.generatedAt)
    }
}
