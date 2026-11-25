import Foundation
import Combine

public extension Notification.Name {
    static let runningShoeTagsChanged = Notification.Name("runningShoeTagsChanged")
}

public protocol RunningShoeStoreProtocol: AnyObject {
    var shoes: [RunningShoe] { get }
    func addShoe(_ shoe: RunningShoe)
    func updateShoe(_ shoe: RunningShoe)
    func retireShoe(id: String)
    func setDefaultShoe(id: String)
    func defaultShoe() -> RunningShoe?
    func shoe(for id: String) -> RunningShoe?
    func totalMeters(for shoeID: String, across runs: [Run]) -> Double
    func wearPercentage(for shoeID: String, across runs: [Run]) -> Double
    func isWornOut(shoeID: String, across runs: [Run]) -> Bool
    func shoeID(forRunID runID: String) -> String?
    func tagRun(runID: String, withShoeID shoeID: String?)
    func applyTags(to runs: [Run]) -> [Run]
    func averagePaceSecondsPerKm(for shoeID: String, across runs: [Run]) -> Double?
    func runCount(for shoeID: String, across runs: [Run]) -> Int
    func longestRunDistance(for shoeID: String, across runs: [Run]) -> Double?
    func fastestShoeID(across runs: [Run]) -> String?
}

public struct RunningShoeRevision: Codable, Equatable, Identifiable {
    public let id: String
    public let before: RunningShoe?
    public let after: RunningShoe?
    public let changedAt: Date
}

public struct RunShoeAssignment: Codable, Equatable {
    public var shoeID: String?
    public var revision: Int
    public var changedAt: Date
    public var source: String
}

public struct RunShoeAssignmentReview: Codable, Equatable {
    public let operationID: String
    public let userID: String
    public let runs: [Run]
    public let targetShoeID: String?
    public let expected: [String: RunShoeAssignment]
}

public struct RunShoeAssignmentReceipt: Codable, Equatable, Identifiable {
    public let id: String
    public let userID: String
    public let before: [String: RunShoeAssignment]
    public let after: [String: RunShoeAssignment]
    public let changedAt: Date
}

public final class RunningShoeStore: ObservableObject, RunningShoeStoreProtocol {
    public enum StoreError: LocalizedError {
        case accountChanged, unreadable, stale, invalid(String), saveFailed
        public var errorDescription: String? {
            switch self {
            case .accountChanged: return "Your account changed. Reopen gear in the correct account."
            case .unreadable: return "Your gear data could not be read. The original data has been kept unchanged."
            case .stale: return "This shoe or assignment changed after you reviewed it. Reopen it before saving."
            case .invalid(let reason): return reason
            case .saveFailed: return "Gear could not be saved. Your entries are kept; try again."
            }
        }
    }
    private struct InventoryReceipt: Codable {
        let operationID: String
        let requested: RunningShoe
        let revisionID: String
    }
    private struct Snapshot: Codable {
        var schema = 1
        var shoes: [RunningShoe] = []
        var legacyTags: [String: String] = [:]
        var legacyUnassigned: Set<String> = []
        var assignments: [String: RunShoeAssignment] = [:]
        var recordingAliases: [String: String]?
        var inventoryRevisions: [RunningShoeRevision] = []
        var inventoryReceipts: [InventoryReceipt] = []
        var assignmentReceipts: [RunShoeAssignmentReceipt] = []
        var undoneReceipts: Set<String> = []
        var revision = 0
    }

    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.running_shoes"
    private let legacyTagStorageKey = "myfitplate.running_shoe_tags"
    private var activeUserID: String?
    private var tagObserver: NSObjectProtocol?
    @Published private var storedShoes: [RunningShoe] = []
    @Published public private(set) var lastError: String?

    public var shoes: [RunningShoe] { synchronizeAccountIfNeeded(); return storedShoes }

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
        activeUserID = authService.currentUserID
        reload()
        tagObserver = NotificationCenter.default.addObserver(forName: .runningShoeTagsChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, note.object as? String == self.authService.currentUserID else { return }
            self.reload()
        }
    }
    deinit { if let tagObserver { NotificationCenter.default.removeObserver(tagObserver) } }
    @MainActor public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    @discardableResult
    public func saveReviewed(_ shoe: RunningShoe, replacing expected: RunningShoe?, operationID: String, userID: String, now: Date = Date()) throws -> RunningShoeRevision {
        try requireAccount(userID)
        guard !operationID.isEmpty, !shoe.id.isEmpty, !shoe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !shoe.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              shoe.initialMeters.isFinite, (0...10_000_000).contains(shoe.initialMeters),
              shoe.maxMeters.isFinite, (1000...10_000_000).contains(shoe.maxMeters),
              shoe.acquiredDate.map({ $0 <= now }) ?? true else { throw StoreError.invalid("Enter a brand/model, nonnegative initial distance, a reminder of at least 1 km, and an acquisition date that has passed.") }
        var snapshot = try readSnapshot()
        if let receipt = snapshot.inventoryReceipts.first(where: { $0.operationID == operationID }) {
            guard receipt.requested == shoe, let revision = snapshot.inventoryRevisions.first(where: { $0.id == receipt.revisionID }) else { throw StoreError.stale }
            return revision
        }
        let current = snapshot.shoes.first { $0.id == shoe.id }
        guard current == expected, expected.map({ $0.id == shoe.id }) ?? true else { throw StoreError.stale }
        var accepted = shoe
        accepted.ownershipConfirmed = true
        if accepted.isRetired { accepted.isDefault = false }
        if accepted.isDefault { for index in snapshot.shoes.indices { snapshot.shoes[index].isDefault = false } }
        snapshot.shoes.removeAll { $0.id == shoe.id }
        snapshot.shoes.append(accepted)
        let revision = RunningShoeRevision(id: UUID().uuidString, before: current, after: accepted, changedAt: now)
        snapshot.inventoryRevisions.append(revision)
        snapshot.inventoryReceipts.append(InventoryReceipt(operationID: operationID, requested: shoe, revisionID: revision.id))
        try persist(snapshot, userID: userID)
        return revision
    }

    public func revisions(for shoeID: String) -> [RunningShoeRevision] {
        synchronizeAccountIfNeeded()
        return ((try? readSnapshot())?.inventoryRevisions ?? []).filter { $0.before?.id == shoeID || $0.after?.id == shoeID }
    }

    public func addShoe(_ shoe: RunningShoe) {
        mutate { snapshot in
            guard !snapshot.shoes.contains(where: { $0.id == shoe.id }) else { return }
            var accepted = shoe
            if snapshot.shoes.isEmpty { accepted.isDefault = true }
            if accepted.isDefault { for index in snapshot.shoes.indices { snapshot.shoes[index].isDefault = false } }
            snapshot.shoes.append(accepted)
        }
    }
    public func updateShoe(_ shoe: RunningShoe) {
        mutate { snapshot in
            guard let index = snapshot.shoes.firstIndex(where: { $0.id == shoe.id }) else { return }
            let before = snapshot.shoes[index]
            if shoe.isDefault { for other in snapshot.shoes.indices { snapshot.shoes[other].isDefault = false } }
            snapshot.shoes[index] = shoe
            snapshot.inventoryRevisions.append(RunningShoeRevision(id: UUID().uuidString, before: before, after: shoe, changedAt: Date()))
        }
    }
    public func retireShoe(id: String) {
        guard var shoe = shoe(for: id) else { return }
        shoe.isRetired = true
        shoe.isDefault = false
        updateShoe(shoe)
    }
    public func setDefaultShoe(id: String) {
        mutate { snapshot in
            guard id.isEmpty || snapshot.shoes.contains(where: { $0.id == id && !$0.isRetired && !$0.isUnconfirmedPlaceholder }) else { return }
            for index in snapshot.shoes.indices { snapshot.shoes[index].isDefault = snapshot.shoes[index].id == id }
        }
    }
    public func defaultShoe() -> RunningShoe? { shoes.first { $0.isDefault && !$0.isRetired && !$0.isUnconfirmedPlaceholder } }
    public func shoe(for id: String) -> RunningShoe? { shoes.first { $0.id == id } }

    /// Used shoes are archived; only explicitly unused inventory can be removed.
    public func removeUnusedShoe(_ expected: RunningShoe, across reviewedRuns: [Run], userID: String) throws {
        try requireAccount(userID)
        var snapshot = try readSnapshot()
        guard snapshot.shoes.first(where: { $0.id == expected.id }) == expected else { throw StoreError.stale }
        guard !snapshot.legacyTags.values.contains(expected.id), !snapshot.assignments.values.contains(where: { $0.shoeID == expected.id }),
              !applyTags(to: reviewedRuns).contains(where: { $0.shoeID == expected.id }) else {
            throw StoreError.invalid("This shoe has run assignments. Retire it to preserve its history.")
        }
        snapshot.shoes.removeAll { $0.id == expected.id }
        snapshot.inventoryRevisions.append(RunningShoeRevision(id: UUID().uuidString, before: expected, after: nil, changedAt: Date()))
        try persist(snapshot, userID: userID)
    }

    public func reviewAssignment(runs: [Run], shoeID: String?, userID: String, operationID: String = UUID().uuidString) throws -> RunShoeAssignmentReview {
        try requireAccount(userID)
        let snapshot = try readSnapshot()
        if let shoeID, !snapshot.shoes.contains(where: { $0.id == shoeID }) { throw StoreError.invalid("Choose a shoe from this account.") }
        guard !runs.isEmpty, runs.count <= 10_000 else { throw StoreError.invalid("Select at least one run, up to 10,000 at a time.") }
        var expected: [String: RunShoeAssignment] = [:]
        for run in runs {
            let key = Self.canonicalKey(run)
            let current = assignment(for: run, snapshot: snapshot)
            if let earlier = expected[key], earlier != current { throw StoreError.stale }
            expected[key] = current
        }
        return RunShoeAssignmentReview(operationID: operationID, userID: userID, runs: runs, targetShoeID: shoeID, expected: expected)
    }

    @discardableResult
    public func commitAssignment(_ review: RunShoeAssignmentReview, now: Date = Date()) throws -> RunShoeAssignmentReceipt {
        try requireAccount(review.userID)
        var snapshot = try readSnapshot()
        if let receipt = snapshot.assignmentReceipts.first(where: { $0.id == review.operationID }) {
            guard receipt.before == review.expected, receipt.after.values.allSatisfy({ $0.shoeID == review.targetShoeID }) else { throw StoreError.stale }
            return receipt
        }
        if let shoeID = review.targetShoeID, !snapshot.shoes.contains(where: { $0.id == shoeID }) { throw StoreError.stale }
        for run in review.runs {
            guard assignment(for: run, snapshot: snapshot) == review.expected[Self.canonicalKey(run)] else { throw StoreError.stale }
        }
        snapshot.revision += 1
        var after: [String: RunShoeAssignment] = [:]
        for key in review.expected.keys {
            let value = RunShoeAssignment(shoeID: review.targetShoeID, revision: snapshot.revision, changedAt: now, source: review.expected.count > 1 ? "reviewed batch" : "reviewed assignment")
            snapshot.assignments[key] = value
            after[key] = value
        }
        var aliases = snapshot.recordingAliases ?? [:]
        for run in review.runs { aliases[run.id] = Self.canonicalKey(run) }
        snapshot.recordingAliases = aliases
        let receipt = RunShoeAssignmentReceipt(id: review.operationID, userID: review.userID, before: review.expected, after: after, changedAt: now)
        snapshot.assignmentReceipts.append(receipt)
        try persist(snapshot, userID: review.userID)
        return receipt
    }

    public func undoAssignment(_ receipt: RunShoeAssignmentReceipt, now: Date = Date()) throws {
        try requireAccount(receipt.userID)
        var snapshot = try readSnapshot()
        guard snapshot.assignmentReceipts.contains(receipt) else { throw StoreError.stale }
        if snapshot.undoneReceipts.contains(receipt.id) { return }
        guard receipt.after.allSatisfy({ snapshot.assignments[$0.key] == $0.value }) else { throw StoreError.stale }
        snapshot.revision += 1
        for (key, previous) in receipt.before {
            snapshot.assignments[key] = RunShoeAssignment(shoeID: previous.shoeID, revision: snapshot.revision, changedAt: now, source: "undo")
        }
        snapshot.undoneReceipts.insert(receipt.id)
        try persist(snapshot, userID: receipt.userID)
    }

    public var latestUndoableAssignment: RunShoeAssignmentReceipt? {
        synchronizeAccountIfNeeded()
        guard let snapshot = try? readSnapshot() else { return nil }
        return snapshot.assignmentReceipts.reversed().first { receipt in
            !snapshot.undoneReceipts.contains(receipt.id) && receipt.after.allSatisfy { snapshot.assignments[$0.key] == $0.value }
        }
    }

    public func shoeID(forRunID runID: String) -> String? {
        synchronizeAccountIfNeeded()
        guard let snapshot = try? readSnapshot() else { return nil }
        if let assignment = snapshot.assignments[snapshot.recordingAliases?[runID] ?? runID] { return assignment.shoeID }
        return snapshot.legacyUnassigned.contains(runID) ? nil : snapshot.legacyTags[runID]
    }
    public func tagRun(runID: String, withShoeID shoeID: String?) {
        guard !runID.isEmpty else { return }
        mutate { snapshot in
            snapshot.revision += 1
            let key = snapshot.recordingAliases?[runID] ?? runID
            snapshot.assignments[key] = RunShoeAssignment(shoeID: shoeID, revision: snapshot.revision, changedAt: Date(), source: "recorded assignment")
        }
    }
    public func tagRun(_ run: Run, withShoeID shoeID: String?) {
        mutate { snapshot in
            snapshot.revision += 1
            snapshot.assignments[Self.canonicalKey(run)] = RunShoeAssignment(shoeID: shoeID, revision: snapshot.revision, changedAt: Date(), source: "explicit assignment")
        }
    }
    public func explicitShoeID(for run: Run) -> String? { applyTags(to: [run]).first?.shoeID }
    public func applyTags(to runs: [Run]) -> [Run] {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil, let snapshot = try? readSnapshot() else { return runs.map { var copy = $0; copy.shoeID = nil; return copy } }
        return runs.map { run in var copy = run; copy.shoeID = assignment(for: run, snapshot: snapshot).shoeID; return copy }
    }
    private func assignment(for run: Run, snapshot: Snapshot) -> RunShoeAssignment {
        let key = Self.canonicalKey(run)
        let current = [snapshot.assignments[key], snapshot.assignments[run.id]].compactMap { $0 }.max { $0.revision < $1.revision }
        if let current {
            if current.source == "recorded assignment", key != run.id, let embedded = run.shoeID,
               snapshot.assignments[run.id] == nil {
                return RunShoeAssignment(shoeID: embedded, revision: current.revision, changedAt: current.changedAt, source: "embedded assignment")
            }
            return current
        }
        let shoeID: String?
        if snapshot.legacyUnassigned.contains(run.id) || snapshot.legacyUnassigned.contains(key) { shoeID = nil } else {
            shoeID = snapshot.legacyTags[run.id] ?? run.shoeID ?? snapshot.legacyTags[key]
        }
        return RunShoeAssignment(shoeID: shoeID, revision: 0, changedAt: .distantPast, source: "original assignment")
    }
    private static func canonicalKey(_ run: Run) -> String { run.source == .recorded ? (run.recordingID ?? run.id) : run.id }

    public func contributingRuns(for shoeID: String, across runs: [Run]) -> [Run] {
        var seen: Set<String> = []
        return applyTags(to: runs).filter { seen.insert(Self.canonicalKey($0)).inserted && $0.shoeID == shoeID && $0.distanceMeters.isFinite && $0.distanceMeters >= 0 }
            .sorted { $0.startDate > $1.startDate }
    }
    public func totalMeters(for shoeID: String, across runs: [Run]) -> Double {
        guard let shoe = shoe(for: shoeID) else { return 0 }
        return shoe.initialMeters + contributingRuns(for: shoeID, across: runs).reduce(0) { $0 + $1.distanceMeters }
    }
    public func wearPercentage(for shoeID: String, across runs: [Run]) -> Double {
        shoe(for: shoeID)?.wearPercentage(totalMeters: totalMeters(for: shoeID, across: runs)) ?? 0
    }
    public func isWornOut(shoeID: String, across runs: [Run]) -> Bool {
        shoe(for: shoeID)?.isWornOut(totalMeters: totalMeters(for: shoeID, across: runs)) ?? false
    }
    public func averagePaceSecondsPerKm(for shoeID: String, across runs: [Run]) -> Double? {
        let included = contributingRuns(for: shoeID, across: runs).filter { $0.distanceMeters >= 500 && $0.movingSeconds.isFinite && $0.movingSeconds > 0 }
        let distance = included.reduce(0) { $0 + $1.distanceMeters }
        guard distance > 0 else { return nil }
        return included.reduce(0) { $0 + $1.movingSeconds } / (distance / 1000)
    }
    public func runCount(for shoeID: String, across runs: [Run]) -> Int { contributingRuns(for: shoeID, across: runs).count }
    public func longestRunDistance(for shoeID: String, across runs: [Run]) -> Double? { contributingRuns(for: shoeID, across: runs).map(\.distanceMeters).max() }
    public func fastestShoeID(across runs: [Run]) -> String? {
        shoes.filter { !$0.isRetired }.compactMap { shoe -> (String, Double)? in
            guard let pace = averagePaceSecondsPerKm(for: shoe.id, across: runs) else { return nil }
            return (shoe.id, pace)
        }.min { $0.1 < $1.1 }?.0
    }

    private func mutate(_ mutation: (inout Snapshot) -> Void) {
        synchronizeAccountIfNeeded()
        guard let userID = activeUserID else { return }
        do { var snapshot = try readSnapshot(); mutation(&snapshot); try persist(snapshot, userID: userID) } catch { lastError = error.localizedDescription }
    }
    private func requireAccount(_ userID: String) throws {
        synchronizeAccountIfNeeded()
        guard !userID.isEmpty, activeUserID == userID, authService.currentUserID == userID else { throw StoreError.accountChanged }
    }
    private func persist(_ snapshot: Snapshot, userID: String) throws {
        try requireAccount(userID)
        guard let key = storageKey else { throw StoreError.accountChanged }
        let data = try JSONEncoder().encode(snapshot)
        userDefaults.set(data, forKey: key)
        guard userDefaults.data(forKey: key) == data else { throw StoreError.saveFailed }
        storedShoes = snapshot.shoes
        lastError = nil
        NotificationCenter.default.post(name: .runningShoeTagsChanged, object: userID)
    }
    private func readSnapshot() throws -> Snapshot {
        guard activeUserID != nil, let key = storageKey else { return Snapshot() }
        var snapshot = Snapshot()
        if let data = userDefaults.data(forKey: key) ?? userDefaults.data(forKey: legacyStorageKey) {
            if let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.schema == 1 { return saved }
            guard let shoes = try? JSONDecoder().decode([RunningShoe].self, from: data) else { throw StoreError.unreadable }
            snapshot.shoes = shoes
        }
        if let tagKey = AccountScopedStorageKey.make(prefix: legacyTagStorageKey, userID: activeUserID),
           let tags = userDefaults.data(forKey: tagKey) ?? userDefaults.data(forKey: legacyTagStorageKey) {
            guard let decoded = try? JSONDecoder().decode([String: String].self, from: tags) else { throw StoreError.unreadable }
            snapshot.legacyTags = decoded
        }
        if let unassignedKey = AccountScopedStorageKey.make(prefix: "myfitplate.running_shoe_unassigned", userID: activeUserID) {
            snapshot.legacyUnassigned = Set(userDefaults.stringArray(forKey: unassignedKey) ?? [])
        }
        return snapshot
    }
    private func reload() {
        do {
            let snapshot = try readSnapshot()
            if activeUserID != nil, let key = storageKey, userDefaults.data(forKey: key) == nil,
               userDefaults.data(forKey: legacyStorageKey) != nil || userDefaults.data(forKey: legacyTagStorageKey) != nil {
                let encoded = try JSONEncoder().encode(snapshot)
                userDefaults.set(encoded, forKey: key)
                guard userDefaults.data(forKey: key) == encoded else { throw StoreError.saveFailed }
                userDefaults.removeObject(forKey: legacyStorageKey)
                userDefaults.removeObject(forKey: legacyTagStorageKey)
            }
            storedShoes = snapshot.shoes
            lastError = nil
        } catch { storedShoes = []; lastError = error.localizedDescription }
    }
    private var storageKey: String? { AccountScopedStorageKey.make(prefix: legacyStorageKey, userID: activeUserID) }
    private func synchronizeAccountIfNeeded() {
        guard authService.currentUserID != activeUserID else { return }
        activeUserID = authService.currentUserID
        reload()
    }
}
