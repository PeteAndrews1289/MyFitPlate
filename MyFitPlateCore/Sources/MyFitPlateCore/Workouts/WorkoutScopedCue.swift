import Foundation

public enum WorkoutCueScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case session, routineSlot, movementVariant, equipmentSetup
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .session: "This session only"
        case .routineSlot: "This routine slot"
        case .movementVariant: "This exercise variant"
        case .equipmentSetup: "This equipment setup"
        }
    }
}
public struct WorkoutCueSnapshot: Codable, Equatable, Sendable {
    public var text: String
    public var scope: WorkoutCueScope
    public var updatedAt: Date
    public var recordID: String?
    public init(text: String, scope: WorkoutCueScope, updatedAt: Date = Date(), recordID: String? = nil) {
        self.text = text; self.scope = scope; self.updatedAt = updatedAt; self.recordID = recordID
    }
}
public struct WorkoutScopedCue: Codable, Equatable, Sendable {
    public var id: String
    public var revisionID: String
    public var ownerID: String
    public var snapshot: WorkoutCueSnapshot
}
@MainActor public final class WorkoutScopedCueStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func key(exercise: RoutineExercise, routineID: String, scope: WorkoutCueScope, userID: String) throws -> String {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID,
              exercise.movementIdentity?.ownerID == nil || exercise.movementIdentity?.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        let movement = exercise.movementIdentity.map { "\($0.ownerID ?? "catalog")|\($0.movementID)|\($0.variantID)" }
            ?? "unmapped-slot|\(routineID)|\(exercise.id)|\(exercise.name)"
        let suffix: String
        switch scope {
        case .session: throw WorkoutBlockError.invalid
        case .routineSlot: suffix = "\(routineID)|\(exercise.id)|\(movement)"
        case .movementVariant: suffix = movement
        case .equipmentSetup: suffix = WorkoutEvidenceReportRules.setupKey(exercise)
        }
        return "workout-cue-\(scope.rawValue)-" + (try PlanFingerprint.make(suffix))
    }
    public func load(exercise: RoutineExercise, routineID: String, scope: WorkoutCueScope, userID: String) throws -> WorkoutScopedCue? {
        let key = try key(exercise: exercise, routineID: routineID, scope: scope, userID: userID)
        let value = try store.load(WorkoutScopedCue.self, userID: userID, scope: key)?.value
        guard value == nil || (value?.ownerID == userID && value?.id == key && value?.snapshot.scope == scope) else { throw WorkoutBlockError.invalid }
        return value
    }
    public func best(exercise: RoutineExercise, routineID: String, userID: String) throws -> WorkoutScopedCue? {
        for scope in [WorkoutCueScope.routineSlot, .equipmentSetup, .movementVariant] {
            if let value = try load(exercise: exercise, routineID: routineID, scope: scope, userID: userID) { return value }
        }
        return nil
    }
    public func save(text: String, exercise: RoutineExercise, routineID: String, scope: WorkoutCueScope,
                     expected: WorkoutScopedCue?, userID: String) throws -> WorkoutScopedCue? {
        guard text.count <= 8_000, try load(exercise: exercise, routineID: routineID, scope: scope, userID: userID) == expected else { throw WorkoutBlockError.changed }
        let key = try key(exercise: exercise, routineID: routineID, scope: scope, userID: userID)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try store.remove(userID: userID, scope: key); return nil }
        let value = WorkoutScopedCue(id: key, revisionID: UUID().uuidString, ownerID: userID,
            snapshot: WorkoutCueSnapshot(text: text, scope: scope, recordID: key))
        try store.save(value, userID: userID, scope: key)
        return value
    }
}
