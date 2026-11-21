import Foundation

public struct AchievementAwardEvidence: Codable, Equatable, Sendable {
    public let kind: String
    public let sourceID: String
    public let sourceFingerprint: String
    public let recordedAt: Date
    public let explanation: String
    public let facts: [String: String]?
    public init(kind: String, sourceID: String, sourceFingerprint: String, recordedAt: Date, explanation: String, facts: [String: String]? = nil) {
        self.kind = kind; self.sourceID = sourceID; self.sourceFingerprint = sourceFingerprint
        self.recordedAt = recordedAt; self.explanation = explanation; self.facts = facts
    }
}

public struct AchievementAwardCommand: Codable, Equatable, Identifiable {
    public var id: String { achievementID }
    public let ownerID: String
    public let achievementID: String
    public let rulesVersion: String
    public let points: Int
    public let evidence: AchievementAwardEvidence
    public let status: UserAchievementStatus

    public init(ownerID: String, definition: AchievementDefinition, evidence: AchievementAwardEvidence, now: Date = Date()) throws {
        guard !ownerID.isEmpty, !evidence.sourceID.isEmpty, !evidence.sourceFingerprint.isEmpty,
              evidence.recordedAt <= now.addingTimeInterval(1), definition.pointsValue >= 0 else { throw AchievementAwardError.invalid }
        self.ownerID = ownerID; achievementID = definition.id; rulesVersion = "achievement-definitions-v1"
        points = definition.pointsValue; self.evidence = evidence
        status = UserAchievementStatus(id: definition.id, achievementID: definition.id, isUnlocked: true,
            unlockedDate: now, currentProgress: definition.criteriaValue, lastProgressUpdate: now,
            awardEvidence: evidence, awardRulesVersion: rulesVersion, awardedPoints: points)
    }
    public func validate(currentUserID: String?) throws {
        guard ownerID == currentUserID else { throw AchievementAwardError.accountChanged }
        guard rulesVersion == "achievement-definitions-v1",
              let definition = AchievementRules.defaultDefinitions().first(where: { $0.id == achievementID }),
              definition.pointsValue == points, status.achievementID == achievementID, status.isUnlocked,
              status.id == achievementID, status.awardEvidence == evidence,
              status.awardRulesVersion == rulesVersion, status.awardedPoints == points,
              status.currentProgress == definition.criteriaValue,
              evidence.recordedAt.timeIntervalSinceReferenceDate.isFinite,
              !evidence.sourceID.isEmpty, !evidence.sourceFingerprint.isEmpty,
              Self.eligibleEvidence(evidence, achievementID: achievementID) else { throw AchievementAwardError.invalid }
    }
    public static func eligibleEvidence(_ evidence: AchievementAwardEvidence, achievementID: String) -> Bool {
        switch achievementID {
        case "first_log": return evidence.kind == "food_entry" && evidence.facts?["foodID"]?.isEmpty == false
        case "scanner_pro", "ai_chef", "picture_perfect":
            return evidence.kind == "food_entry" && evidence.facts?["foodID"]?.isEmpty == false && evidence.facts?["featureAchievement"] == achievementID
        case "calorie_target_hit", "macro_master", "hydration_hero": return evidence.kind == "diary_goals"
        case "on_the_weigh": return evidence.kind == "weight_entry"
        case "first_5_lbs", "target_reached": return evidence.kind == "weight_change"
        case "goal_setter": return evidence.kind == "saved_goals"
        case "log_streak_3", "log_streak_7": return evidence.kind == "logging_days"
        default:
            if AchievementRules.chefAchievementIDs.contains(achievementID) { return evidence.kind == "server_recipe_count" }
            if AchievementRules.workoutAchievementIDs.contains(achievementID) { return evidence.kind == "server_workout_count" }
            return false
        }
    }
}

public struct AchievementAwardResult: Codable {
    public let status: UserAchievementStatus
    public let totalPoints: Int
    public let level: Int
    public let awardedNow: Bool
    public init(status: UserAchievementStatus, totalPoints: Int, level: Int, awardedNow: Bool) {
        self.status = status; self.totalPoints = totalPoints; self.level = level; self.awardedNow = awardedNow
    }
}

public enum AchievementAwardError: Int, LocalizedError, CustomNSError {
    case invalid = 1, accountChanged = 2, unavailable = 3, evidenceUnavailable = 4, evidenceNoLongerEligible = 5
    public static var errorDomain: String { "MyFitPlate.AchievementAward" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "Milestone saving is unavailable."] }
    public static func identifying(_ error: Error) -> Self? {
        if let known = error as? Self { return known }
        let value = error as NSError
        return value.domain == errorDomain ? Self(rawValue: value.code) : nil
    }
    public var errorDescription: String? {
        switch self {
        case .invalid: return "This milestone's evidence could not be verified."
        case .accountChanged: return "This milestone belongs to a different account."
        case .unavailable: return "Milestone saving is unavailable. Your recorded activity is unchanged."
        case .evidenceUnavailable: return "This milestone's saved source could not be confirmed. Its request is kept for retry."
        case .evidenceNoLongerEligible: return "The saved source no longer qualifies for this milestone. A newer eligible activity can be reviewed."
        }
    }
}

public struct RetiredAchievementEvidence: Codable, Equatable, Identifiable {
    public let id: String
    public let command: AchievementAwardCommand
    public let retiredAt: Date
    public let reason: String
}

@MainActor
public final class AchievementAwardStore {
    private struct Snapshot: Codable {
        var pending: [AchievementAwardCommand] = []
        var successors: [String: AchievementAwardCommand] = [:]
        var retired: [RetiredAchievementEvidence] = []
        private enum CodingKeys: String, CodingKey { case pending, successors, retired }
        init() {}
        init(from decoder: Decoder) throws {
            // Earlier builds used the same protected envelope with a plain array.
            if let legacy = try? decoder.singleValueContainer().decode([AchievementAwardCommand].self) {
                pending = legacy; return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pending = try container.decode([AchievementAwardCommand].self, forKey: .pending)
            successors = try container.decode([String: AchievementAwardCommand].self, forKey: .successors)
            retired = try container.decode([RetiredAchievementEvidence].self, forKey: .retired)
        }
    }
    private let store: EditorDraftStore
    private let scope = "achievement-award-outbox-v1"
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    private func load(userID: String) throws -> Snapshot {
        let value = try store.load(Snapshot.self, userID: userID, scope: scope)?.value ?? Snapshot()
        guard Set(value.pending.map(\.id)).count == value.pending.count,
              Set(value.retired.map(\.id)).count == value.retired.count,
              value.successors.allSatisfy({ key, command in key == command.id && value.pending.contains { $0.id == key } }) else { throw AchievementAwardError.invalid }
        for command in value.pending + Array(value.successors.values) + value.retired.map(\.command) {
            try command.validate(currentUserID: userID)
        }
        return value
    }
    public func pending(userID: String) throws -> [AchievementAwardCommand] { try load(userID: userID).pending }
    public func retiredEvidence(userID: String) throws -> [RetiredAchievementEvidence] { try load(userID: userID).retired }

    public func stage(_ command: AchievementAwardCommand, currentUserID: String?) throws -> AchievementAwardCommand {
        try command.validate(currentUserID: currentUserID)
        var value = try load(userID: command.ownerID)
        if let existing = value.pending.first(where: { $0.id == command.id }) {
            if existing.evidence != command.evidence {
                // At most one latest alternate per lifetime milestone. It is only
                // promoted after the server definitively retires the older source.
                value.successors[command.id] = command
                try store.save(value, userID: command.ownerID, scope: scope)
            }
            return existing
        }
        value.pending.append(command)
        try store.save(value, userID: command.ownerID, scope: scope)
        return command
    }

    public func acknowledge(_ command: AchievementAwardCommand, currentUserID: String?) throws {
        try command.validate(currentUserID: currentUserID)
        var value = try load(userID: command.ownerID)
        guard value.pending.first(where: { $0.id == command.id }).map({ $0 == command }) ?? true else { throw AchievementAwardError.invalid }
        value.pending.removeAll { $0.id == command.id }
        value.successors.removeValue(forKey: command.id)
        try store.save(value, userID: command.ownerID, scope: scope)
    }

    /// Call only after the server reports an authoritative no-longer-eligible source.
    /// The exact request remains in the audit; a concurrent new candidate survives.
    public func retireObsoleteEvidence(_ command: AchievementAwardCommand, currentUserID: String?, now: Date = Date()) throws {
        try command.validate(currentUserID: currentUserID)
        var value = try load(userID: command.ownerID)
        let fingerprint = try PlanFingerprint.make(command)
        if value.retired.contains(where: { $0.id == fingerprint }) { return }
        guard value.pending.first(where: { $0.id == command.id }) == command, now.timeIntervalSinceReferenceDate.isFinite else { throw AchievementAwardError.invalid }
        value.retired.append(RetiredAchievementEvidence(id: fingerprint, command: command, retiredAt: now,
            reason: "The server confirmed that this exact source no longer qualifies. No points were granted for this request."))
        value.pending.removeAll { $0.id == command.id }
        if let successor = value.successors.removeValue(forKey: command.id) { value.pending.append(successor) }
        try store.save(value, userID: command.ownerID, scope: scope)
    }
}

public struct AchievementAwardReceipt: Codable {
    public let command: AchievementAwardCommand
    public let result: AchievementAwardResult
    public init(command: AchievementAwardCommand, result: AchievementAwardResult) { self.command = command; self.result = result }
}
