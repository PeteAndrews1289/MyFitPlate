import Foundation

public enum WeeklyTargetReviewError: LocalizedError {
    case accountChanged, changed, stale, invalid, unavailable, alreadySubmitted
    public var errorDescription: String? {
        switch self {
        case .accountChanged: return "This check-in belongs to a different account. Reopen it after signing in."
        case .changed: return "Your targets or evidence changed. Review a fresh proposal before deciding."
        case .stale: return "This proposal has expired. Refresh it to review the latest evidence."
        case .invalid: return "This proposal is incomplete. Refresh your check-in before continuing."
        case .unavailable: return "The decision could not be confirmed. Your review is saved here; retry to check the same decision."
        case .alreadySubmitted: return "Confirm the pending decision before starting another review."
        }
    }
}

/// Frozen, value-only proposal. The target shown at confirmation is the target submitted.
/// Refreshing an estimate never edits this value or the currently accepted profile.
public struct WeeklyTargetProposal: Codable, Equatable, Identifiable {
    public let id: UUID
    public let userID: String
    public let createdAt: Date
    public let evidenceStart: Date
    public let evidenceEnd: Date
    public let evidenceFingerprint: String
    public let algorithmVersion: String
    public let evidence: AdaptiveGoalService.ExpenditureSnapshot
    public let before: GoalEditorDraft
    public let after: GoalEditorDraft
    public let explanation: AdaptiveGoalService.WeeklyGoalProposal

    public init(userID: String, before: GoalEditorDraft, evidence: AdaptiveGoalService.ExpenditureSnapshot,
                evidenceFingerprint: String, now: Date = Date(), calendar: Calendar = .current) throws {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !evidenceFingerprint.isEmpty, evidence.isActionable,
              let explanation = AdaptiveGoalService.weeklyGoalProposal(
                snapshot: evidence, currentCalories: before.calories, goal: before.goal, gender: before.gender,
                proteinPercentage: before.proteinPercentage, carbsPercentage: before.carbsPercentage,
                fatsPercentage: before.fatsPercentage, weeklyChangeLbs: before.weeklyChangeLbs),
              let start = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: now)) else {
            throw WeeklyTargetReviewError.invalid
        }
        id = UUID(); self.userID = userID; createdAt = now
        evidenceStart = start; evidenceEnd = calendar.startOfDay(for: now)
        self.evidenceFingerprint = evidenceFingerprint
        algorithmVersion = "complete-days-linear-v1"
        self.evidence = evidence; self.before = before; self.explanation = explanation
        var target = before.normalizedForEditing()
        target.method = .dynamicTDEE
        target.calories = explanation.shouldAdjust || before.method != .dynamicTDEE
            ? explanation.proposedCalories : before.calories
        // Validate the frozen amount without recalculating it from a newer estimate.
        var validation = target; validation.method = .custom
        guard try validation.resolved(adaptiveTDEE: nil, manualCaloriesBurned: 0).calories == target.calories else {
            throw WeeklyTargetReviewError.invalid
        }
        after = target
    }

    public func validate(userID: String?, current: GoalEditorDraft, evidenceFingerprint: String,
                         now: Date = Date(), calendar: Calendar = .current) throws {
        guard self.userID == userID else { throw WeeklyTargetReviewError.accountChanged }
        guard createdAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince(createdAt) >= -1, now.timeIntervalSince(createdAt) <= 30 * 60,
              calendar.isDate(now, inSameDayAs: evidenceEnd) else { throw WeeklyTargetReviewError.stale }
        guard before == current, self.evidenceFingerprint == evidenceFingerprint else { throw WeeklyTargetReviewError.changed }
    }

    public func validateDefinition() throws {
        let rebuilt = try WeeklyTargetProposal(userID: userID, before: before, evidence: evidence,
                                               evidenceFingerprint: evidenceFingerprint, now: createdAt)
        guard rebuilt.after == after, rebuilt.explanation == explanation,
              rebuilt.algorithmVersion == algorithmVersion else { throw WeeklyTargetReviewError.invalid }
    }

    public func matchesPersistedTargets(_ data: [String: Any]) -> Bool {
        guard before.matchesPersistedInputs(data) else { return false }
        let goals = data["goals"] as? [String: Any] ?? [:]
        guard let calories = (goals["calories"] ?? data["calories"]) as? NSNumber else { return false }
        return abs(calories.doubleValue - before.calories) < 0.0001
    }
}

public struct WeeklyTargetDecision: Codable, Equatable, Identifiable {
    public enum Choice: String, Codable, CaseIterable {
        case accept, keep, deferReview
        public var title: String {
            switch self {
            case .accept: return "Accepted suggested targets"
            case .keep: return "Kept current targets"
            case .deferReview: return "Deferred review"
            }
        }
    }
    public var id: UUID { proposal.id }
    public let proposal: WeeklyTargetProposal
    public let choice: Choice
    public let decidedAt: Date
    public var effectiveTargets: GoalEditorDraft { choice == .accept ? proposal.after : proposal.before }
    public var nextEligibleDate: Date? {
        choice == .deferReview ? nil : Calendar.current.date(byAdding: .day, value: 7, to: decidedAt)
    }
    public init(proposal: WeeklyTargetProposal, choice: Choice, now: Date = Date()) {
        self.proposal = proposal; self.choice = choice; decidedAt = now
    }

    public func validateForNewCommit(now: Date = Date()) throws {
        try proposal.validateDefinition()
        try proposal.validate(userID: proposal.userID, current: proposal.before,
                              evidenceFingerprint: proposal.evidenceFingerprint, now: now)
        guard decidedAt.timeIntervalSince1970.isFinite,
              decidedAt >= proposal.createdAt.addingTimeInterval(-1), decidedAt <= now.addingTimeInterval(1),
              decidedAt.timeIntervalSince(proposal.createdAt) <= 30 * 60 else { throw WeeklyTargetReviewError.stale }
    }

    /// Target patch is deliberately empty on defer. Keeping a target only records check-in timing.
    public var profilePatch: [String: Any] {
        guard choice != .deferReview else { return [:] }
        if choice == .keep { return ["goals": ["lastCheckInDate": decidedAt]] }
        var patch = proposal.after.payload(updatedAt: decidedAt)
        var goals = patch["goals"] as? [String: Any] ?? [:]
        goals["lastCheckInDate"] = decidedAt; patch["goals"] = goals
        return patch
    }
}

public struct WeeklyTargetCheckpoint: Codable, Equatable {
    public let proposal: WeeklyTargetProposal
    public private(set) var submittedDecision: WeeklyTargetDecision?
    public init(proposal: WeeklyTargetProposal) { self.proposal = proposal }
    public mutating func submit(_ choice: WeeklyTargetDecision.Choice, now: Date = Date()) throws -> WeeklyTargetDecision {
        if let submittedDecision {
            guard submittedDecision.choice == choice else { throw WeeklyTargetReviewError.alreadySubmitted }
            return submittedDecision
        }
        let decision = WeeklyTargetDecision(proposal: proposal, choice: choice, now: now)
        submittedDecision = decision
        return decision
    }
}

/// Uses the shared account-scoped draft store. Network uncertainty keeps the original command.
@MainActor
public final class WeeklyTargetReviewStore {
    private let store: EditorDraftStore
    private let scope = "weekly-target-review-v1"
    private let historyScope = "weekly-target-history-v1"
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func load(userID: String) throws -> WeeklyTargetCheckpoint? {
        let value = try store.load(WeeklyTargetCheckpoint.self, userID: userID, scope: scope)?.value
        guard value == nil || value?.proposal.userID == userID else { throw WeeklyTargetReviewError.accountChanged }
        return value
    }
    public func save(_ checkpoint: WeeklyTargetCheckpoint, currentUserID: String?) throws {
        let owner = checkpoint.proposal.userID
        guard owner == currentUserID else { throw WeeklyTargetReviewError.accountChanged }
        if let current = try load(userID: owner), let pending = current.submittedDecision,
           pending != checkpoint.submittedDecision { throw WeeklyTargetReviewError.alreadySubmitted }
        try store.save(checkpoint, userID: owner, scope: scope)
    }
    public func history(userID: String) throws -> [WeeklyTargetDecision] {
        let values = try store.load([WeeklyTargetDecision].self, userID: userID, scope: historyScope)?.value ?? []
        guard values.allSatisfy({ $0.proposal.userID == userID }) else { throw WeeklyTargetReviewError.accountChanged }
        return values
    }
    public func legacyCompletion(userID: String) throws -> Date? {
        try store.load(Date.self, userID: userID, scope: "weekly-target-legacy-completion-v1")?.value
    }
    public func preserveLegacyCompletion(_ date: Date, userID: String) throws {
        if let existing = try legacyCompletion(userID: userID) {
            guard existing == date else { throw WeeklyTargetReviewError.changed }
            return
        }
        try store.save(date, userID: userID, scope: "weekly-target-legacy-completion-v1")
    }
    public func mergeHistory(_ values: [WeeklyTargetDecision], currentUserID: String) throws {
        guard values.allSatisfy({ $0.proposal.userID == currentUserID }) else { throw WeeklyTargetReviewError.accountChanged }
        var merged = Dictionary(uniqueKeysWithValues: try history(userID: currentUserID).map { ($0.id, $0) })
        for value in values {
            if let existing = merged[value.id], existing != value { throw WeeklyTargetReviewError.changed }
            merged[value.id] = value
        }
        try store.save(merged.values.sorted { $0.decidedAt > $1.decidedAt }, userID: currentUserID, scope: historyScope)
    }
    public func finish(_ accepted: WeeklyTargetDecision, currentUserID: String?) throws {
        let owner = accepted.proposal.userID
        guard owner == currentUserID else { throw WeeklyTargetReviewError.accountChanged }
        try mergeHistory([accepted], currentUserID: owner)
        guard let checkpoint = try load(userID: owner), checkpoint.submittedDecision == accepted else { return }
        _ = try store.removeIfUnchanged(WeeklyTargetCheckpoint.self, userID: owner, scope: scope,
                                       fingerprint: PlanFingerprint.make(checkpoint))
    }
}
