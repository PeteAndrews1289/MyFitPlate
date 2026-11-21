import Foundation

/// A movement identity is distinct from a routine slot. Never inferred while decoding old logs.
public struct WorkoutMovementIdentity: Codable, Equatable, Hashable, Sendable {
    public var catalogVersion: Int
    public var movementID: String
    public var variantID: String
    public var ownerID: String?
    public init(movementID: String, variantID: String, ownerID: String? = nil, catalogVersion: Int = 1) {
        self.catalogVersion = catalogVersion; self.movementID = movementID; self.variantID = variantID; self.ownerID = ownerID
    }
    public var isValid: Bool { catalogVersion == 1 && !movementID.isEmpty && !variantID.isEmpty && ownerID?.isEmpty != true }
}

public enum WorkoutMovementCatalog {
    /// These aliases are curated, not fuzzy matches between similarly named machines.
    public static let aliases = ["bench press": "Barbell Bench Press", "conventional deadlift": "Deadlift (Conventional)",
        "back squat": "Barbell Back Squat", "pushup": "Push-up", "pullup": "Pull-up"]
    public static func canonicalName(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliases[normalized] ?? ExerciseList.entries.first { $0.name.lowercased() == normalized }?.name
    }
    public static func identity(for name: String) -> WorkoutMovementIdentity? {
        guard let canonical = canonicalName(name) else { return nil }
        let key = canonical.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        return WorkoutMovementIdentity(movementID: "mfp.exercise.\(key)", variantID: "standard-v1")
    }
    public static func matches(_ exercise: RoutineExercise, _ other: RoutineExercise) -> Bool {
        if exercise.movementIdentity != nil || other.movementIdentity != nil {
            return exercise.movementIdentity == other.movementIdentity && exercise.movementIdentity?.isValid == true
        }
        return exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(other.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

public struct WorkoutCustomMovement: Codable, Identifiable {
    public var id: String
    public var name: String
    public var type: ExerciseType
    public var cue: String
    public var archived: Bool
    public init(id: String = UUID().uuidString, name: String, type: ExerciseType, cue: String = "", archived: Bool = false) {
        self.id = id; self.name = name; self.type = type; self.cue = cue; self.archived = archived
    }
    public func identity(ownerID: String) -> WorkoutMovementIdentity {
        WorkoutMovementIdentity(movementID: id, variantID: "custom-v1", ownerID: ownerID)
    }
}

@MainActor public final class WorkoutCustomMovementStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func entries(userID: String) throws -> [WorkoutCustomMovement] {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        return try store.load([WorkoutCustomMovement].self, userID: userID, scope: "custom-movements-v1")?.value ?? []
    }
    public func save(_ movement: WorkoutCustomMovement, userID: String) throws {
        var entries = try entries(userID: userID)
        guard !movement.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, movement.name.count <= 120,
              movement.cue.count <= 2_000 else { throw WorkoutBlockError.invalid }
        guard !entries.contains(where: { $0.id != movement.id && !$0.archived && $0.name.caseInsensitiveCompare(movement.name) == .orderedSame }) else {
            throw WorkoutBlockError.changed
        }
        entries.removeAll { $0.id == movement.id }; entries.append(movement)
        try store.save(entries, userID: userID, scope: "custom-movements-v1")
    }
}

/// Device-only discovery preferences. Selection never mutates movement identity or a workout.
@MainActor public final class WorkoutMovementSelectionStore {
    public struct Preferences: Codable, Equatable {
        public var recent: [String] = []
        public var favorites: [String] = []
    }
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    nonisolated public static func key(name: String, identity: WorkoutMovementIdentity?) -> String {
        identity.map { "\($0.ownerID ?? "catalog")|\($0.movementID)|\($0.variantID)" } ?? "legacy|\(name)"
    }
    public func load(userID: String) throws -> Preferences {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        let value = try store.load(Preferences.self, userID: userID, scope: "movement-selection-v1")?.value ?? Preferences()
        guard value.recent.count <= 30, value.favorites.count <= 100,
              (value.recent + value.favorites).allSatisfy({ !$0.isEmpty && $0.count <= 2_000 }),
              Set(value.recent).count == value.recent.count, Set(value.favorites).count == value.favorites.count else { throw WorkoutBlockError.invalid }
        return value
    }
    public func record(_ keys: [String], userID: String) throws {
        var value = try load(userID: userID)
        guard keys.allSatisfy({ !$0.isEmpty && $0.count <= 2_000 }) else { throw WorkoutBlockError.invalid }
        for key in keys { value.recent.removeAll { $0 == key }; value.recent.insert(key, at: 0) }
        value.recent = Array(value.recent.prefix(30))
        try store.save(value, userID: userID, scope: "movement-selection-v1")
    }
    public func setFavorite(_ key: String, enabled: Bool, userID: String) throws {
        var value = try load(userID: userID)
        guard !key.isEmpty, key.count <= 2_000 else { throw WorkoutBlockError.invalid }
        value.favorites.removeAll { $0 == key }
        if enabled { guard value.favorites.count < 100 else { throw WorkoutBlockError.invalid }; value.favorites.append(key) }
        value.favorites.sort()
        try store.save(value, userID: userID, scope: "movement-selection-v1")
    }
}
