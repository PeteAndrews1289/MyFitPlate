import Combine
import Foundation

public struct RecipeVersionRecord: Codable, Identifiable, Sendable {
    public enum Phase: String, Codable, Sendable { case before, saved, restored }
    public let id: String
    public let recipeID: String
    public let operationID: UUID
    public let phase: Phase
    public let recordedAt: Date
    public let snapshot: Recipe
    public let snapshotFingerprint: String
    public init(id: String, recipeID: String, operationID: UUID, phase: Phase, recordedAt: Date, snapshot: Recipe) throws {
        self.id = id; self.recipeID = recipeID; self.operationID = operationID; self.phase = phase
        self.recordedAt = recordedAt; self.snapshot = snapshot
        snapshotFingerprint = try PlanFingerprint.make(snapshot)
        try validate()
    }
    public func validate() throws {
        guard PlanningDocumentRules.validID(id), PlanningDocumentRules.validID(recipeID), snapshot.id == recipeID,
              recordedAt.timeIntervalSince1970.isFinite, snapshotFingerprint == (try PlanFingerprint.make(snapshot)),
              (try JSONEncoder().encode(snapshot)).count <= 500_000 else { throw RecipeRevisionError.invalid }
    }
}

public struct RecipeVersionRestoreProposal: Codable, Identifiable {
    public let schemaVersion: Int
    public let userID: String
    public let id: UUID
    public let version: RecipeVersionRecord
    public let expected: Recipe
    public init(userID: String, id: UUID = UUID(), version: RecipeVersionRecord, expected: Recipe) {
        schemaVersion = 1; self.userID = userID; self.id = id; self.version = version; self.expected = expected
    }
    public var updated: Recipe { get throws { try RecipeVersionHistoryRules.restored(version: version, current: expected) } }
    public func validate() throws {
        guard schemaVersion == 1, !userID.isEmpty, expected.id == version.recipeID,
              (try JSONEncoder().encode(self)).count <= 1_100_000 else { throw RecipeRevisionError.invalid }
        try version.validate(); try RecipeRevisionRules.validate(expected: expected, updated: updated)
    }
    public var fingerprint: String { get throws { try validate(); return try PlanFingerprint.make(self) } }
}
public enum RecipeVersionHistoryRules {
    public static func restored(version: RecipeVersionRecord, current: Recipe) throws -> Recipe {
        try version.validate()
        guard current.id == version.recipeID else { throw RecipeRevisionError.changed }
        var restored = version.snapshot
        restored.id = current.id
        // Library organization is independent from the recipe's cooking/nutrition version.
        restored.libraryMetadata = current.libraryMetadata
        restored.revisionID = try RecipePortionRules.revisionID(for: restored)
        try RecipeRevisionRules.validate(expected: current, updated: restored)
        return restored
    }
}

public struct RecipeVersionRestoreCheckpoint: Codable {
    public var proposal: RecipeVersionRestoreProposal
    public var submitted: Bool
    public var resolution: PlanningDocumentSaveResolution
    public init(proposal: RecipeVersionRestoreProposal, submitted: Bool = false, resolution: PlanningDocumentSaveResolution = .pending) {
        self.proposal = proposal; self.submitted = submitted; self.resolution = resolution
    }
}

/// Exact selected version and opening snapshot survive lost acknowledgements and relaunch.
@MainActor public final class RecipeVersionRestoreSession: ObservableObject, Identifiable {
    public let id = UUID()
    public static let scope = "recipe-version-restore"
    public let userID: String?
    @Published public private(set) var checkpoint: RecipeVersionRestoreCheckpoint?
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?
    private let store: EditorDraftStore
    private var expectedFingerprint: String?
    private var unreadable = false
    public init(userID: String?, proposal: RecipeVersionRestoreProposal? = nil, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        guard active, let userID else { return }
        do {
            checkpoint = try store.load(RecipeVersionRestoreCheckpoint.self, userID: userID, scope: Self.scope)?.value
            if let checkpoint { try checkpoint.proposal.validate(); guard checkpoint.proposal.userID == userID else { throw RecipeRevisionError.accountChanged } }
            expectedFingerprint = try checkpoint.map(PlanFingerprint.make)
            if checkpoint == nil, let proposal { try proposal.validate(); try persist(.init(proposal: proposal)) }
        } catch { unreadable = true; errorMessage = "The earlier version-restore review is preserved and could not be opened. " + error.localizedDescription }
    }
    public var finished: Bool { checkpoint?.resolution != .pending && checkpoint != nil }
    public func save(using service: RecipeService) async {
        guard active, !isWorking, var value = checkpoint, !finished else { return }
        do {
            value.submitted = true; try persist(value); isWorking = true; defer { isWorking = false }
            _ = try await service.restoreRecipeVersion(value.proposal)
            guard active else { throw RecipeRevisionError.accountChanged }
            value.resolution = .accepted; try persist(value)
        } catch { errorMessage = "The exact restore is kept. Check status or retry before choosing another version. " + error.localizedDescription }
    }
    public func resolve(using service: RecipeService, cancelIfUnaccepted: Bool) async {
        guard active, !isWorking, var value = checkpoint else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let result = try await service.resolveRecipeVersionRestore(value.proposal, cancelIfUnaccepted: cancelIfUnaccepted)
            guard active else { throw RecipeRevisionError.accountChanged }
            switch result {
            case .pending: errorMessage = "No accepted restore receipt yet. Retry this exact review or cancel its pending save."; return
            case .cancelled: value.resolution = .cancelled
            case .accepted: value.resolution = .accepted
            }
            try persist(value)
        } catch { errorMessage = "The restore review is kept until its status can be confirmed. " + error.localizedDescription }
    }
    public func finish() -> Bool {
        guard active, !isWorking, let userID, let checkpoint, !checkpoint.submitted || finished else { return false }
        do {
            guard try store.load(RecipeVersionRestoreCheckpoint.self, userID: userID, scope: Self.scope).map({ try PlanFingerprint.make($0.value) }) == expectedFingerprint else { throw RecipeRevisionError.changed }
            try store.remove(userID: userID, scope: Self.scope); self.checkpoint = nil; return true
        } catch { errorMessage = "A newer restore review was preserved. Close and reopen it."; return false }
    }
    private var active: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ value: RecipeVersionRestoreCheckpoint) throws {
        guard active, let userID else { throw RecipeRevisionError.accountChanged }
        let previous = try store.load(RecipeVersionRestoreCheckpoint.self, userID: userID, scope: Self.scope)?.value
        guard try previous.map(PlanFingerprint.make) == expectedFingerprint else { throw RecipeRevisionError.changed }
        try store.save(value, userID: userID, scope: Self.scope); checkpoint = value
        expectedFingerprint = try PlanFingerprint.make(value); errorMessage = nil
    }
}
