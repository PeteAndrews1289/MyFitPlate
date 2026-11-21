import Foundation

public struct StrengthGymProfileReference: Codable, Equatable, Sendable {
    public let profileID: String
    public let revisionID: String
    public let implementID: String
    public let profileName: String
    public let implementName: String
}

public struct StrengthGymImplement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var equipment: StrengthEquipment

    public init(id: String = UUID().uuidString, name: String, equipment: StrengthEquipment) {
        self.id = id; self.name = name; self.equipment = equipment
        self.equipment.gymProfile = nil
    }
}

public struct StrengthGymProfile: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id: String
    public var revisionID: String
    public var name: String
    public var implements: [StrengthGymImplement]

    public init(id: String = UUID().uuidString, revisionID: String = UUID().uuidString,
                name: String, implements: [StrengthGymImplement] = []) {
        self.id = id; self.revisionID = revisionID; self.name = name; self.implements = implements
    }

    public var isValid: Bool {
        schemaVersion == 1 && !id.isEmpty && !revisionID.isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80
            && (1...24).contains(implements.count) && Set(implements.map(\.id)).count == implements.count
            && implements.allSatisfy { !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 80 && $0.equipment.isValid && $0.equipment.gymProfile == nil }
    }

    public func equipment(for implementID: String) -> StrengthEquipment? {
        guard isValid, let implement = implements.first(where: { $0.id == implementID }) else { return nil }
        var value = implement.equipment
        value.name = implement.name
        value.gymProfile = StrengthGymProfileReference(profileID: id, revisionID: revisionID, implementID: implement.id,
                                                       profileName: name, implementName: implement.name)
        return value
    }
}

public enum StrengthSessionToolsError: LocalizedError {
    case invalid, changed, accountChanged, completed, unavailable, unsupportedWarmup
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the names, equipment and target values before applying."
        case .changed: "This setup or workout changed. Close the review and open it again; your logged sets stay intact."
        case .accountChanged: "Return to the account that opened this review before saving."
        case .completed: "This movement already has logged sets. Its setup stays fixed for this session."
        case .unavailable: "A requested set load is below this equipment's minimum. Review the set loads or choose another implement."
        case .unsupportedWarmup: "Automatic ramps need valid total-load or per-hand equipment and a positive working load. Use manual warm-ups for bodyweight, added or assisted work."
        }
    }
}

/// Device-only, account-scoped library. No implicit import overwrites exercise-local setups.
@MainActor
public final class StrengthGymProfileStore {
    private struct Library: Codable {
        var schemaVersion = 1
        var profiles: [StrengthGymProfile] = []
    }
    private let store: EditorDraftStore
    private let currentUserID: @MainActor () -> String?
    private let scope = "strength-gym-library-v1"

    public init(store: EditorDraftStore = EditorDraftStore(), currentUserID: @escaping @MainActor () -> String? = { DIContainer.shared.authService.currentUserID }) {
        self.store = store; self.currentUserID = currentUserID
    }

    public func profiles(userID: String) throws -> [StrengthGymProfile] {
        guard currentUserID() == userID, !userID.isEmpty else { throw StrengthSessionToolsError.accountChanged }
        let library = try store.load(Library.self, userID: userID, scope: scope)?.value ?? Library()
        guard library.schemaVersion == 1, library.profiles.allSatisfy(\.isValid),
              Set(library.profiles.map(\.id)).count == library.profiles.count else { throw StrengthSessionToolsError.invalid }
        return library.profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    public func save(_ profile: StrengthGymProfile, expected: StrengthGymProfile?, userID: String) throws -> StrengthGymProfile {
        guard profile.isValid else { throw StrengthSessionToolsError.invalid }
        var profiles = try profiles(userID: userID)
        let current = profiles.first { $0.id == profile.id }
        guard current == expected, expected == nil || expected?.id == profile.id else { throw StrengthSessionToolsError.changed }
        var updated = profile
        updated.revisionID = UUID().uuidString
        profiles.removeAll { $0.id == profile.id }; profiles.append(updated)
        guard profiles.count <= 24 else { throw StrengthSessionToolsError.invalid }
        try store.save(Library(profiles: profiles), userID: userID, scope: scope)
        return updated
    }

    public func remove(_ expected: StrengthGymProfile, userID: String) throws {
        var profiles = try profiles(userID: userID)
        guard profiles.first(where: { $0.id == expected.id }) == expected else { throw StrengthSessionToolsError.changed }
        profiles.removeAll { $0.id == expected.id }
        try store.save(Library(profiles: profiles), userID: userID, scope: scope)
    }

    public func mappings(profile: StrengthGymProfile, routineID: String, userID: String) throws -> [String: String] {
        _ = try profiles(userID: userID)
        let values = try store.load([String: String].self, userID: userID,
            scope: "strength-gym-mappings-\(profile.id)-\(routineID)")?.value ?? [:]
        let valid = Set(profile.implements.map(\.id))
        return values.filter { valid.contains($0.value) }
    }

    public func rememberMappings(_ mappings: [String: String], profile: StrengthGymProfile, routineID: String, userID: String) throws {
        guard try profiles(userID: userID).first(where: { $0.id == profile.id }) == profile,
              Set(mappings.values).isSubset(of: Set(profile.implements.map(\.id))) else { throw StrengthSessionToolsError.changed }
        try store.save(mappings, userID: userID, scope: "strength-gym-mappings-\(profile.id)-\(routineID)")
    }
}

public struct StrengthSessionChange: Codable, Identifiable {
    public enum Kind: String, Codable { case equipment, progression }
    public let id: String
    public let kind: Kind
    public let title: String
    public let before: [RoutineExercise]
    public let after: [RoutineExercise]
    public let profile: StrengthGymProfile?
    public let policyVersion: Int?
    public let reasons: [String: String]?

    public init(kind: Kind, title: String, before: [RoutineExercise], after: [RoutineExercise], profile: StrengthGymProfile? = nil, reasons: [String: String]? = nil) {
        id = UUID().uuidString; self.kind = kind; self.title = title
        self.before = before; self.after = after; self.profile = profile; self.reasons = reasons; policyVersion = 1
    }
}

public enum StrengthSessionToolsRules {
    public static func fingerprint(_ exercises: [RoutineExercise]) throws -> String { try PlanFingerprint.make(exercises) }

    /// Values are changed only after reviewing this complete before/after snapshot.
    /// A movement with performed sets is excluded because its equipment belongs to all its sets.
    public static func equipmentChange(profile: StrengthGymProfile, mappings: [String: String], exercises: [RoutineExercise]) throws -> StrengthSessionChange {
        guard profile.isValid, !mappings.isEmpty,
              Set(mappings.keys).isSubset(of: Set(exercises.map(\.id))) else { throw StrengthSessionToolsError.invalid }
        var updated = exercises
        for index in updated.indices {
            guard let implement = mappings[updated[index].id] else { continue }
            guard updated[index].type == .strength, !updated[index].sets.contains(where: \.isCompleted) else { throw StrengthSessionToolsError.completed }
            guard let equipment = profile.equipment(for: implement) else { throw StrengthSessionToolsError.invalid }
            let previousEquipment = updated[index].loadEquipment
            let sameExplicitMeaning = previousEquipment?.loadingMeaning == equipment.loadingMeaning
                && equipment.loadingMeaning != .asLogged
            let mayCarryLoad = StrengthEquipment.historyCompatible(current: equipment, previous: previousEquipment)
                || (sameExplicitMeaning && (equipment.kind == .barbell || equipment.loadingMeaning == .perHand))
            // Equipment belongs to the entire movement, including warm-ups, drop and
            // failure sets. Leaving those loads behind would silently reinterpret them
            // under the new convention or recommend plates the new gym does not have.
            for set in updated[index].sets.indices {
                let previous = updated[index].sets[set].weight
                guard previous.isFinite, previous >= 0 else { throw StrengthSessionToolsError.invalid }
                if !mayCarryLoad { updated[index].sets[set].weight = 0; continue }
                if previous > 0 {
                    guard let available = equipment.atOrBelow(previous) else { throw StrengthSessionToolsError.unavailable }
                    updated[index].sets[set].weight = available
                }
            }
            updated[index].loadEquipment = equipment
        }
        return StrengthSessionChange(kind: .equipment, title: "\(profile.name) setup applied", before: exercises, after: updated, profile: profile)
    }

    public static func progressionChange(plans: [ProgressionPlan], exercises: [RoutineExercise]) throws -> StrengthSessionChange {
        guard !plans.isEmpty, Set(plans.map(\.exerciseID)).count == plans.count else { throw StrengthSessionToolsError.invalid }
        var updated = exercises
        for plan in plans {
            guard let index = updated.firstIndex(where: { $0.id == plan.exerciseID }), plan.isValid,
                  plan.loadEquipment == updated[index].loadEquipment else { throw StrengthSessionToolsError.changed }
            let result = ProgressionRules.applying(plan, to: updated[index])
            // A stale prescription can return the unchanged movement. Require every eligible reviewed target to agree.
            for target in plan.targets {
                guard let set = result.sets.first(where: { $0.id == target.id }) else { throw StrengthSessionToolsError.changed }
                if !set.isCompleted && set.resolvedSetType == .normal {
                    guard set.weight == target.weight, set.reps == target.reps else { throw StrengthSessionToolsError.changed }
                }
            }
            updated[index] = result
        }
        return StrengthSessionChange(kind: .progression, title: "Reviewed session targets applied", before: exercises, after: updated,
            reasons: Dictionary(uniqueKeysWithValues: plans.map { ($0.exerciseID, $0.headline + ". " + $0.rationale) }))
    }

    public static func applying(_ change: StrengthSessionChange, to current: [RoutineExercise]) throws -> [RoutineExercise] {
        guard try fingerprint(change.before) == fingerprint(current),
              change.before.map(\.id) == change.after.map(\.id) else { throw StrengthSessionToolsError.changed }
        for (before, after) in zip(change.before, change.after) {
            guard before.name == after.name, before.type == after.type,
                  before.sets.map(\.id) == after.sets.map(\.id) else { throw StrengthSessionToolsError.changed }
            for (original, proposed) in zip(before.sets, after.sets) where original.isCompleted {
                guard try PlanFingerprint.make(original) == PlanFingerprint.make(proposed) else { throw StrengthSessionToolsError.completed }
            }
        }
        return change.after
    }

    /// Manual changes and completed work win. Equipment Undo cannot relabel a movement after logging starts.
    public static func undo(_ change: StrengthSessionChange, current: [RoutineExercise]) -> [RoutineExercise] {
        current.map { exercise in
            guard let before = change.before.first(where: { $0.id == exercise.id }),
                  let after = change.after.first(where: { $0.id == exercise.id }), before.name == exercise.name,
                  after.loadEquipment == exercise.loadEquipment else { return exercise }
            if change.kind == .equipment {
                guard !exercise.sets.contains(where: \.isCompleted),
                      (try? fingerprint([exercise])) == (try? fingerprint([after])) else { return exercise }
            }
            guard after.targetReps == exercise.targetReps else { return exercise }
            var result = exercise
            for index in result.sets.indices where !result.sets[index].isCompleted {
                guard let original = before.sets.first(where: { $0.id == result.sets[index].id }),
                      let accepted = after.sets.first(where: { $0.id == result.sets[index].id }),
                      accepted.resolvedSetType == result.sets[index].resolvedSetType,
                      accepted.target == result.sets[index].target,
                      accepted.prescription == result.sets[index].prescription else { continue }
                if result.sets[index].weight == accepted.weight { result.sets[index].weight = original.weight }
                if result.sets[index].reps == accepted.reps { result.sets[index].reps = original.reps }
            }
            if change.kind == .equipment { result.loadEquipment = before.loadEquipment }
            if result.progressionIncrement == after.progressionIncrement { result.progressionIncrement = before.progressionIncrement }
            return result
        }
    }
}
