import Foundation
import Combine

public extension Notification.Name { static let runLibrariesChanged = Notification.Name("RunLibrariesChanged") }

public enum RunCloudScope: String, Codable, CaseIterable { case workouts, blocks, reviews
    public var title: String {
        switch self {
        case .workouts: return "Running workouts"
        case .blocks: return "Training blocks"
        case .reviews: return "Run reviews"
        }
    }
}
public enum RunCloudError: LocalizedError {
    case invalid, accountChanged, changed, protectedEvidence
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Running sync contains an unreadable or mismatched revision. Existing data is kept."
        case .accountChanged: return "Your account changed. Reopen running sync in the correct account."
        case .changed: return "Running data changed during sync. Retry to include the latest saved version."
        case .protectedEvidence: return "Both accepted versions are preserved. Automatic replacement is unavailable for this conflict."
        }
    }
}

public struct RunCloudRevision: Codable, Equatable, Identifiable {
    public let id: String
    public let ownerID: String
    public let scope: RunCloudScope
    public let key: String
    public let parents: [String]
    public let payload: Data?
    private struct Identity: Codable { let ownerID: String; let scope: RunCloudScope; let key: String; let parents: [String]; let payload: Data? }
    public init(ownerID: String, scope: RunCloudScope, key: String, parents: [String], payload: Data?) throws {
        self.ownerID = ownerID; self.scope = scope; self.key = key
        self.parents = Array(Set(parents)).sorted(); self.payload = payload
        id = try PlanFingerprint.make(Identity(ownerID: ownerID, scope: scope, key: key, parents: self.parents, payload: payload))
        try validate(ownerID: ownerID, scope: scope)
    }
    public func validate(ownerID: String, scope: RunCloudScope) throws {
        let immutable = key.hasPrefix("receipt/") || key.hasPrefix("revision/") || key.hasPrefix("abandoned/")
        guard !immutable || payload != nil, self.ownerID == ownerID, !ownerID.isEmpty, self.scope == scope, !key.isEmpty, key.count <= 400,
              parents == Array(Set(parents)).sorted(), parents.count <= 32, !parents.contains(id),
              (payload?.count ?? 0) <= 700_000,
              id == (try PlanFingerprint.make(Identity(ownerID: ownerID, scope: scope, key: key, parents: parents, payload: payload))) else { throw RunCloudError.invalid }
    }
}

/// Per-item immutable history. Concurrent branches remain heads until a checked
/// merge explicitly names all of them. Dates never decide which version wins.
public enum RunCloudGraph {
    public static func validated(_ revisions: [RunCloudRevision], ownerID: String, scope: RunCloudScope) throws -> [String: RunCloudRevision] {
        var index: [String: RunCloudRevision] = [:]
        for revision in revisions {
            try revision.validate(ownerID: ownerID, scope: scope)
            if let existing = index[revision.id], existing != revision { throw RunCloudError.invalid }
            index[revision.id] = revision
        }
        for revision in index.values {
            for parent in revision.parents {
                guard let value = index[parent], value.key == revision.key else { throw RunCloudError.invalid }
                if revision.key.hasPrefix("receipt/") || revision.key.hasPrefix("revision/") || revision.key.hasPrefix("abandoned/") {
                    guard value.payload == revision.payload else { throw RunCloudError.protectedEvidence }
                }
            }
        }
        // A malformed cycle must never be interpreted as an empty remote library.
        var remaining = Set(index.keys), visited = Set<String>()
        while !remaining.isEmpty {
            let ready = remaining.filter { Set(index[$0]!.parents).isSubset(of: visited) }
            guard !ready.isEmpty else { throw RunCloudError.invalid }
            visited.formUnion(ready); remaining.subtract(ready)
        }
        return index
    }
    public static func heads(_ index: [String: RunCloudRevision]) -> [String: [RunCloudRevision]] {
        let parents = Set(index.values.flatMap(\.parents))
        return Dictionary(grouping: index.values.filter { !parents.contains($0.id) }, by: \.key)
            .mapValues { $0.sorted { $0.id < $1.id } }
    }
    public static func ordered(_ index: [String: RunCloudRevision]) throws -> [RunCloudRevision] {
        var pending = index, done = Set<String>(), values: [RunCloudRevision] = []
        while !pending.isEmpty {
            let ready = pending.values.filter { Set($0.parents).isSubset(of: done) }.sorted { $0.id < $1.id }
            guard !ready.isEmpty else { throw RunCloudError.invalid }
            for value in ready { values.append(value); done.insert(value.id); pending[value.id] = nil }
        }
        return values
    }
}

public protocol RunCloudRepository {
    func fetch(userID: String, scope: RunCloudScope) async throws -> [RunCloudRevision]
    /// Idempotent creation of a revision and transactional update of its item heads.
    /// Parents must already exist. A concurrent branch is retained, not overwritten.
    func publish(_ revision: RunCloudRevision) async throws
}

public struct RunCloudConflict: Identifiable {
    public var id: String { key }
    public let key: String
    public let versions: [RunCloudRevision]
}

@MainActor public final class RunCloudSyncEngine: ObservableObject {
    private struct Application: Codable {
        let expectedFingerprint: String
        let values: [String: Data]
        let heads: [String: String]
    }
    private struct Resolution: Codable {
        let expectedFingerprint: String
        let merge: RunCloudRevision
    }
    private struct Checkpoint: Codable {
        var revisions: [RunCloudRevision] = []
        var localHeads: [String: String] = [:]
        var pending: Set<String> = []
        var resolution: Resolution?
        var application: Application?
    }
    @Published public private(set) var conflicts: [RunCloudConflict] = []
    @Published public private(set) var message = "Ready to sync"
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncedAt: Date?
    public let scope: RunCloudScope
    private let repository: RunCloudRepository
    private let drafts: EditorDraftStore
    private let currentOwner: () -> String?
    private let snapshot: (String) throws -> [String: Data]
    private let apply: ([String: Data], String, String) throws -> Void
    private var activeOwner: String?
    private var generation = UUID()
    private var retryAfterCurrent = false
    private var checkpointScope: String { "run-cloud-checkpoint-v1." + scope.rawValue }
    public init(scope: RunCloudScope, repository: RunCloudRepository, drafts: EditorDraftStore = EditorDraftStore(),
                currentOwner: @escaping () -> String?, snapshot: @escaping (String) throws -> [String: Data],
                apply: @escaping ([String: Data], String, String) throws -> Void) {
        self.scope = scope; self.repository = repository; self.drafts = drafts
        self.currentOwner = currentOwner; self.snapshot = snapshot; self.apply = apply
    }
    public func activate(_ owner: String?) {
        guard activeOwner != owner else { return }
        activeOwner = owner; generation = UUID(); conflicts = []; message = "Ready to sync"; lastSyncedAt = nil
    }
    private func load(_ owner: String) throws -> Checkpoint {
        let value = try drafts.load(Checkpoint.self, userID: owner, scope: checkpointScope)?.value ?? .init()
        let index = try RunCloudGraph.validated(value.revisions, ownerID: owner, scope: scope)
        guard value.pending.isSubset(of: Set(index.keys)), value.localHeads.allSatisfy({ key, id in index[id]?.key == key }) else { throw RunCloudError.invalid }
        if let application = value.application {
            guard Set(application.values.keys).isSubset(of: Set(application.heads.keys)),
                  application.heads.allSatisfy({ key, id in index[id]?.key == key && index[id]?.payload == application.values[key] }) else { throw RunCloudError.invalid }
        }
        if let resolution = value.resolution {
            try resolution.merge.validate(ownerID: owner, scope: scope)
        }
        return value
    }
    private func save(_ value: Checkpoint, owner: String) throws {
        guard currentOwner() == owner, activeOwner == owner else { throw RunCloudError.accountChanged }
        try drafts.save(value, userID: owner, scope: checkpointScope)
    }
    private func check(_ owner: String, token: UUID) throws {
        guard currentOwner() == owner, activeOwner == owner, generation == token else { throw RunCloudError.accountChanged }
    }
    public func sync() async {
        guard let owner = currentOwner() else { activate(nil); return }
        activate(owner)
        if isSyncing { retryAfterCurrent = true; return }
        isSyncing = true; let token = generation
        defer {
            isSyncing = false
            if retryAfterCurrent { retryAfterCurrent = false; Task { await self.sync() } }
        }
        do {
            var checkpoint = try completeResolution(try completeApplication(try load(owner), owner: owner), owner: owner)
            let original = try snapshot(owner)
            let originalFingerprint = try PlanFingerprint.make(original)
            var index = try RunCloudGraph.validated(checkpoint.revisions, ownerID: owner, scope: scope)
            // Only a known local removal creates a tombstone. A fresh/empty remote
            // library cannot erase device records.
            for key in Set(original.keys).union(checkpoint.localHeads.keys).sorted() {
                let previous = checkpoint.localHeads[key].flatMap { index[$0] }
                guard original[key] != previous?.payload else { continue }
                let revision = try RunCloudRevision(ownerID: owner, scope: scope, key: key,
                    parents: previous.map { [$0.id] } ?? [], payload: original[key])
                index[revision.id] = revision; checkpoint.localHeads[key] = revision.id; checkpoint.pending.insert(revision.id)
            }
            checkpoint.revisions = Array(index.values)
            try save(checkpoint, owner: owner)
            // Fetch first so a lost response can be acknowledged without republishing.
            let remote = try await repository.fetch(userID: owner, scope: scope)
            try check(owner, token: token)
            let remoteIndex = try RunCloudGraph.validated(remote, ownerID: owner, scope: scope)
            index = try RunCloudGraph.validated(Array(index.values) + remote, ownerID: owner, scope: scope)
            for revision in try RunCloudGraph.ordered(index) where checkpoint.pending.contains(revision.id) {
                if remoteIndex[revision.id] == nil { try await repository.publish(revision) }
                try check(owner, token: token)
                checkpoint.pending.remove(revision.id)
                checkpoint.revisions = Array(index.values); try save(checkpoint, owner: owner)
            }
            let acceptedRemote = try await repository.fetch(userID: owner, scope: scope)
            try check(owner, token: token)
            index = try RunCloudGraph.validated(Array(index.values) + acceptedRemote, ownerID: owner, scope: scope)
            let heads = RunCloudGraph.heads(index)
            var next = original
            var acceptedHeads = checkpoint.localHeads
            var unresolved: [RunCloudConflict] = []
            for (key, branches) in heads {
                if branches.count == 1, let value = branches.first {
                    next[key] = value.payload; acceptedHeads[key] = value.id
                } else { unresolved.append(.init(key: key, versions: branches)) }
            }
            try check(owner, token: token)
            checkpoint.revisions = Array(index.values)
            checkpoint.application = Application(expectedFingerprint: originalFingerprint, values: next, heads: acceptedHeads)
            try save(checkpoint, owner: owner)
            checkpoint = try completeApplication(checkpoint, owner: owner)
            conflicts = unresolved.sorted { $0.key < $1.key }
            lastSyncedAt = Date()
            message = unresolved.isEmpty ? "Synced. Saved run records and strength-program progress are unchanged." : "\(unresolved.count) item(s) have changes from more than one device. Both versions are kept."
        } catch {
            guard activeOwner == owner, generation == token else { return }
            message = error.localizedDescription
            // Keep conflicts visible even when a protected overlay prevents projection.
            if let value = try? load(owner), let index = try? RunCloudGraph.validated(value.revisions, ownerID: owner, scope: scope) {
                conflicts = RunCloudGraph.heads(index).filter { $0.value.count > 1 }.map { .init(key: $0.key, versions: $0.value) }.sorted { $0.key < $1.key }
            }
        }
    }
    private func completeApplication(_ saved: Checkpoint, owner: String) throws -> Checkpoint {
        guard let application = saved.application else { return saved }
        var checkpoint = saved
        let original = try snapshot(owner)
        if try PlanFingerprint.make(original) == application.expectedFingerprint {
            if original != application.values { try apply(application.values, application.expectedFingerprint, owner) }
        } else {
            // The previous attempt may have projected successfully before its final
            // checkpoint write failed. Inactive branch receipts need not materialize.
            let subsetMatches = original.allSatisfy { application.values[$0.key] == $0.value }
            let mutableMatches = application.values.allSatisfy { key, value in
                key.hasPrefix("receipt/") || key.hasPrefix("revision/") || key.hasPrefix("abandoned/") || original[key] == value
            }
            guard subsetMatches && mutableMatches else {
                checkpoint.application = nil
                try save(checkpoint, owner: owner)
                throw RunCloudError.changed
            }
        }
        let materialized = try snapshot(owner)
        let index = try RunCloudGraph.validated(checkpoint.revisions, ownerID: owner, scope: scope)
        var heads = application.heads
        for (key, id) in heads where materialized[key] != index[id]?.payload {
            heads[key] = checkpoint.localHeads[key]
        }
        checkpoint.localHeads = heads; checkpoint.application = nil
        try save(checkpoint, owner: owner)
        return checkpoint
    }

    private func completeResolution(_ saved: Checkpoint, owner: String) throws -> Checkpoint {
        guard let resolution = saved.resolution else { return saved }
        var checkpoint = saved
        let merge = resolution.merge
        try merge.validate(ownerID: owner, scope: scope)
        var index = try RunCloudGraph.validated(checkpoint.revisions, ownerID: owner, scope: scope)
        let heads = RunCloudGraph.heads(index)[merge.key] ?? []
        guard Set(heads.map(\.id)) == Set(merge.parents),
              let chosen = heads.first(where: { $0.payload == merge.payload }) else { throw RunCloudError.changed }
        try RunCloudResolutionRules.validate(scope: scope, conflict: .init(key: merge.key, versions: heads),
            chosen: chosen, knownRevisions: index)
        let original = try snapshot(owner)
        if original[merge.key] != merge.payload {
            guard try PlanFingerprint.make(original) == resolution.expectedFingerprint else { throw RunCloudError.changed }
            var next = original; next[merge.key] = merge.payload
            // A safe chosen head may refer to evidence held only in the checkpoint
            // (such as a remote correction or exact abandonment receipt).
            for (key, branches) in RunCloudGraph.heads(index) where branches.count == 1 {
                if key.hasPrefix("receipt/") || key.hasPrefix("revision/") || key.hasPrefix("abandoned/"),
                   let payload = branches.first?.payload { next[key] = payload }
            }
            try apply(next, resolution.expectedFingerprint, owner)
        }
        index[merge.id] = merge; checkpoint.revisions = Array(index.values)
        checkpoint.localHeads[merge.key] = merge.id; checkpoint.pending.insert(merge.id)
        checkpoint.resolution = nil
        try save(checkpoint, owner: owner)
        return checkpoint
    }

    private func prepareForResolution(_ saved: Checkpoint, owner: String) throws -> Checkpoint {
        guard let application = saved.application else { return saved }
        do { return try completeApplication(saved, owner: owner) } catch let error as RunCloudError {
            switch error {
            case .invalid, .protectedEvidence:
                // A rejected projection can be replaced by an explicit review only
                // when its exact original snapshot proves no local write occurred.
                guard try PlanFingerprint.make(snapshot(owner)) == application.expectedFingerprint else { throw error }
                var checkpoint = saved; checkpoint.application = nil
                try save(checkpoint, owner: owner)
                return checkpoint
            case .accountChanged, .changed: throw error
            }
        }
    }

    public func resolutionIssue(_ conflict: RunCloudConflict, choosing chosen: RunCloudRevision) -> String? {
        do {
            guard let owner = currentOwner(), activeOwner == owner else { throw RunCloudError.accountChanged }
            let checkpoint = try load(owner)
            let index = try RunCloudGraph.validated(checkpoint.revisions, ownerID: owner, scope: scope)
            guard RunCloudGraph.heads(index)[conflict.key] == conflict.versions else { throw RunCloudError.changed }
            try RunCloudResolutionRules.validate(scope: scope, conflict: conflict, chosen: chosen, knownRevisions: index)
            return nil
        } catch { return error.localizedDescription }
    }

    public func knownPayload(for key: String) -> Data? {
        guard let owner = currentOwner(), activeOwner == owner,
              let saved = try? load(owner),
              let index = try? RunCloudGraph.validated(saved.revisions, ownerID: owner, scope: scope),
              let values = RunCloudGraph.heads(index)[key], values.count == 1 else { return nil }
        return values.first?.payload
    }

    /// A review is bound to the exact visible head set. It cannot silently absorb
    /// another device's change arriving after the user opened the comparison.
    public func resolve(_ conflict: RunCloudConflict, choosing chosen: RunCloudRevision) async throws {
        guard !isSyncing, let owner = currentOwner(), activeOwner == owner else { throw RunCloudError.accountChanged }
        var checkpoint = try prepareForResolution(try load(owner), owner: owner)
        let index = try RunCloudGraph.validated(checkpoint.revisions, ownerID: owner, scope: scope)
        let heads = RunCloudGraph.heads(index)[conflict.key] ?? []
        guard heads == conflict.versions, heads.contains(chosen) else { throw RunCloudError.changed }
        try RunCloudResolutionRules.validate(scope: scope, conflict: conflict, chosen: chosen, knownRevisions: index)
        let original = try snapshot(owner)
        let merged = try RunCloudRevision(ownerID: owner, scope: scope, key: conflict.key, parents: heads.map(\.id), payload: chosen.payload)
        checkpoint.resolution = Resolution(expectedFingerprint: try PlanFingerprint.make(original), merge: merged)
        // Journal the reviewed choice before any projection or remote mutation.
        try save(checkpoint, owner: owner)
        // An error may mean projection succeeded but the final checkpoint did not.
        // Keep the durable review for recovery; a fresh explicit choice may replace it.
        _ = try completeResolution(checkpoint, owner: owner)
        await sync()
    }
}

public enum RunCloudCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
    public static func preserveImmutable(old: [String: Data], new: [String: Data]) throws {
        for (key, data) in old where key.hasPrefix("receipt/") || key.hasPrefix("revision/") || key.hasPrefix("abandoned/") {
            guard new[key] == data else { throw RunCloudError.protectedEvidence }
        }
    }
}
