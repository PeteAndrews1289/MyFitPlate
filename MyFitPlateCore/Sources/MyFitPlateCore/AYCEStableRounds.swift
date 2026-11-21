import Foundation

public struct AYCEStableRound: Codable, Identifiable, Equatable {
    public var id: String
    public var entries: [AYCESessionEntry]
    public var finishedAt: Date?
    public var repeatedFromRoundID: String?
    /// A migrated boundary has no invented historical timestamp.
    public var migrated: Bool?
    public init(id: String = UUID().uuidString, entries: [AYCESessionEntry] = [], finishedAt: Date? = nil,
                repeatedFromRoundID: String? = nil, migrated: Bool? = nil) {
        self.id = id; self.entries = entries; self.finishedAt = finishedAt
        self.repeatedFromRoundID = repeatedFromRoundID; self.migrated = migrated
    }
    public var calories: Double { entries.reduce(0) { $0 + $1.calories } }
}

public struct AYCERoundEdit: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var before: [AYCEStableRound]
    public var after: [AYCEStableRound]
    public var recordedAt: Date
    public init(title: String, before: [AYCEStableRound], after: [AYCEStableRound]) {
        id = UUID().uuidString; self.title = title; self.before = before; self.after = after; recordedAt = Date()
    }
}

public enum AYCEStableRoundRules {
    public static let catalogVersion = "buffet-portions-2026.11"
    public static func migrated(_ session: AYCESession) -> AYCESession {
        guard session.rounds == nil else { return session }
        var next = session
        var completed: [AYCESessionEntry] = []
        var current: [AYCESessionEntry] = []
        for entry in session.entries {
            let baseline = max(0, session.roundBaseline?.first(where: { $0.id == entry.id })?.count ?? 0)
            let completedAmount = min(entry.count, baseline)
            if completedAmount > 0 { completed.append(AYCESessionEntry(id: entry.id + "-migrated", item: entry.item, count: completedAmount)) }
            if entry.count > completedAmount { current.append(AYCESessionEntry(id: entry.id, item: entry.item, count: entry.count - completedAmount)) }
        }
        var rounds: [AYCEStableRound] = []
        if !completed.isEmpty { rounds.append(AYCEStableRound(id: session.id + "-legacy", entries: completed, migrated: true)) }
        // A legacy finished boundary has no known time. A separate empty current round identifies it.
        rounds.append(AYCEStableRound(id: session.id + "-current", entries: current))
        next.rounds = rounds; next.roundEdits = []; next.undoneRoundEditIDs = []
        next.catalogVersion = next.catalogVersion ?? catalogVersion
        return projected(next)
    }
    public static func current(_ session: AYCESession) -> AYCEStableRound? { session.rounds?.last }
    public static func completed(_ session: AYCESession) -> [AYCEStableRound] { Array((session.rounds ?? []).dropLast()) }
    public static func changeQuantity(_ amount: Double, item: AYCECatalogItem, in session: AYCESession) -> AYCESession? {
        guard editable(session), AYCEPortionRules.isValid(amount, allowsZero: true) else { return nil }
        var next = migrated(session)
        let before = next.rounds ?? []
        var rounds = before
        let existing = rounds.flatMap(\.entries).filter { $0.item.id == item.id }.reduce(0) { $0 + $1.count }
        var delta = amount - existing
        if delta > 0 {
            guard let index = rounds.indices.last else { return nil }
            // New portion/cut snapshots never rewrite the nutrition of an earlier round.
            if let entry = rounds[index].entries.firstIndex(where: { $0.item == item }) {
                rounds[index].entries[entry].count += delta
            } else { rounds[index].entries.append(AYCESessionEntry(item: item, count: delta)) }
        } else if delta < 0 {
            for round in rounds.indices.reversed() {
                for entry in rounds[round].entries.indices.reversed() where rounds[round].entries[entry].item.id == item.id {
                    let remove = min(-delta, rounds[round].entries[entry].count)
                    rounds[round].entries[entry].count -= remove; delta += remove
                }
                rounds[round].entries.removeAll { !AYCEPortionRules.isValid($0.count) }
            }
        }
        next.rounds = rounds
        return recorded(next, before: before, title: "Adjust \(item.name)")
    }
    public static func appending(_ items: [AYCECatalogItem], in session: AYCESession) -> AYCESession? {
        guard editable(session), !items.isEmpty else { return nil }
        var next = migrated(session); let before = next.rounds ?? []
        guard let index = next.rounds?.indices.last else { return nil }
        next.rounds?[index].entries.append(contentsOf: items.map { AYCESessionEntry(item: $0, count: 1) })
        return recorded(next, before: before, title: "Add reviewed foods")
    }
    public static func replacingEntry(_ id: String, item: AYCECatalogItem?, in session: AYCESession) -> AYCESession? {
        guard editable(session) else { return nil }
        var next = migrated(session); let before = next.rounds ?? []
        for round in next.rounds?.indices ?? 0..<0 {
            if let index = next.rounds?[round].entries.firstIndex(where: { $0.id == id }) {
                if let item { next.rounds?[round].entries[index].item = item } else { next.rounds?[round].entries.remove(at: index) }
                return recorded(next, before: before, title: item == nil ? "Remove food" : "Edit food")
            }
        }
        return nil
    }
    public static func finishing(_ session: AYCESession, at date: Date = Date()) -> AYCESession? {
        guard editable(session) else { return nil }
        var next = migrated(session); let before = next.rounds ?? []
        guard let index = next.rounds?.indices.last, next.rounds?[index].entries.isEmpty == false else { return nil }
        next.rounds?[index].finishedAt = date
        next.lastRound = next.rounds?[index].entries
        next.rounds?.append(AYCEStableRound())
        next.roundBaseline = next.entries
        return recorded(next, before: before, title: "Finish round")
    }
    public static func replacing(_ reviewed: AYCEStableRound, with entries: [AYCESessionEntry], in session: AYCESession) -> AYCESession? {
        guard editable(session), let index = session.rounds?.firstIndex(where: { $0.id == reviewed.id }),
              session.rounds?[index] == reviewed, valid(entries) else { return nil }
        var next = session; let before = next.rounds ?? []
        next.rounds?[index].entries = entries
        return recorded(next, before: before, title: entries.isEmpty ? "Clear round" : "Edit round")
    }
    public static func repeating(_ reviewed: AYCEStableRound, in session: AYCESession, operationID: String) -> AYCESession? {
        guard editable(session), !reviewed.entries.isEmpty, valid(reviewed.entries),
              session.rounds?.contains(reviewed) == true,
              session.rounds?.contains(where: { $0.id == operationID }) == false else { return nil }
        var next = session; let before = next.rounds ?? []
        let entries = reviewed.entries.enumerated().map { index, entry in
            AYCESessionEntry(id: "\(operationID)-\(index)", item: entry.item, count: entry.count)
        }
        // A repeated reviewed group remains its own finished round even when a current draft exists.
        next.rounds?.insert(AYCEStableRound(id: operationID, entries: entries, finishedAt: Date(), repeatedFromRoundID: reviewed.id), at: max(0, before.count - 1))
        next.lastRound = entries
        return recorded(next, before: before, title: "Repeat reviewed round")
    }
    public static func undo(_ operation: AYCERoundEdit, in session: AYCESession) -> AYCESession? {
        guard editable(session), session.roundEdits?.contains(operation) == true,
              session.undoneRoundEditIDs?.contains(operation.id) != true else { return nil }
        var next = session
        var rounds = next.rounds ?? []
        let before = Dictionary(uniqueKeysWithValues: operation.before.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: operation.after.map { ($0.id, $0) })
        for roundID in Set(before.keys).union(after.keys) {
            let old = before[roundID]; let accepted = after[roundID]
            guard old != accepted else { continue }
            if old == nil {
                guard let index = rounds.firstIndex(where: { $0.id == roundID }), rounds[index] == accepted else { return nil }
                rounds.remove(at: index); continue
            }
            guard var current = rounds.first(where: { $0.id == roundID }), let original = old, let expected = accepted else { return nil }
            if original.finishedAt != expected.finishedAt {
                guard current.finishedAt == expected.finishedAt else { return nil }
                current.finishedAt = original.finishedAt
            }
            let oldEntries = Dictionary(uniqueKeysWithValues: original.entries.map { ($0.id, $0) })
            let newEntries = Dictionary(uniqueKeysWithValues: expected.entries.map { ($0.id, $0) })
            for entryID in Set(oldEntries.keys).union(newEntries.keys) where oldEntries[entryID] != newEntries[entryID] {
                guard current.entries.first(where: { $0.id == entryID }) == newEntries[entryID] else { return nil }
                current.entries.removeAll { $0.id == entryID }
                if let value = oldEntries[entryID] { current.entries.append(value) }
            }
            if let index = rounds.firstIndex(where: { $0.id == roundID }) { rounds[index] = current }
        }
        next.rounds = rounds; next.undoneRoundEditIDs = (next.undoneRoundEditIDs ?? []) + [operation.id]
        next.lastRound = rounds.dropLast().last?.entries
        return projected(next)
    }
    private static func editable(_ session: AYCESession) -> Bool { session.endedAt == nil && session.submittedAt == nil }
    private static func valid(_ entries: [AYCESessionEntry]) -> Bool {
        Set(entries.map(\.id)).count == entries.count && entries.allSatisfy {
            AYCEPortionRules.isValid($0.count) && [$0.item.calories, $0.item.protein, $0.item.carbs, $0.item.fats, $0.item.restaurantPrice, $0.item.homeCost].allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }
    private static func recorded(_ session: AYCESession, before: [AYCEStableRound], title: String) -> AYCESession? {
        guard let after = session.rounds, before != after, valid(after.flatMap(\.entries)), after.count <= 100,
              Set(after.flatMap(\.entries).map(\.id)).count == after.flatMap(\.entries).count else { return nil }
        var next = session
        next.roundEdits = Array(((next.roundEdits ?? []) + [AYCERoundEdit(title: title, before: before, after: after)]).suffix(100))
        return projected(next)
    }
    private static func projected(_ session: AYCESession) -> AYCESession {
        var next = session; next.entries = (session.rounds ?? []).flatMap(\.entries)
        return next
    }
}
