import Foundation

/// Calendar-day windows are half open; a DST week is not assumed to contain 168 hours.
public struct WeeklyRecapWindow: Codable, Equatable {
    public let start: Date
    public let endExclusive: Date
    public let timeZoneID: String

    public init(endingOn day: Date, calendar: Calendar = .current) {
        let ending = calendar.startOfDay(for: day)
        start = calendar.date(byAdding: .day, value: -6, to: ending) ?? ending
        endExclusive = calendar.date(byAdding: .day, value: 1, to: ending) ?? ending
        timeZoneID = calendar.timeZone.identifier
    }
    public var lastDay: Date { Date(timeIntervalSinceReferenceDate: endExclusive.timeIntervalSinceReferenceDate.nextDown) }
    public func contains(_ date: Date) -> Bool { date >= start && date < endExclusive }
    public func preceding(calendar: Calendar = .current) -> Self {
        Self(endingOn: calendar.date(byAdding: .day, value: -1, to: start) ?? start, calendar: calendar)
    }
    public var storageKey: String { "\(start.timeIntervalSince1970)|\(endExclusive.timeIntervalSince1970)|\(timeZoneID)" }
}

public struct WeeklyRecapTargetDay: Codable, Equatable {
    public let date: Date
    public let calories: Double
    public let protein: Double
    public init(date: Date, calories: Double, protein: Double) {
        self.date = date; self.calories = calories; self.protein = protein
    }
}

public enum WeeklyRecapTargetRules {
    /// Historical receipts confirm a target only after the receipt. The day of an
    /// accepted change is excluded because the diary has no per-meal target snapshot.
    /// No current profile value is projected into an undocumented historical day.
    public static func days(in window: WeeklyRecapWindow, decisions: [WeeklyTargetDecision],
                            userID: String, now: Date, calendar: Calendar = .current) -> [WeeklyRecapTargetDay] {
        let valid = decisions.filter { $0.proposal.userID == userID && $0.decidedAt <= now && $0.choice != .deferReview }
            .sorted { $0.decidedAt < $1.decidedAt }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: window.start), day <= now,
                  let receipt = valid.last(where: { $0.decidedAt < day }),
                  !valid.contains(where: { $0.choice == .accept && calendar.isDate($0.decidedAt, inSameDayAs: day) }),
                  receipt.effectiveTargets.calories.isFinite, receipt.effectiveTargets.calories > 0 else { return nil }
            return WeeklyRecapTargetDay(date: day, calories: receipt.effectiveTargets.calories,
                                       protein: receipt.effectiveTargets.macros.protein)
        }
    }
}

/// Immutable aggregate revision. Source hashes stay private; exports can use this
/// revision's calculated aggregates without leaking record IDs or raw Health samples.
public struct WeeklyRecapRevision: Codable, Equatable, Identifiable {
    public let version: Int
    public let id: String
    public let ownerID: String
    public let window: WeeklyRecapWindow
    public let createdAt: Date
    public let sourceFingerprint: String
    public let recap: WeeklyRecap
    public let prior: WeeklyRecap
    public let coverage: String
    public var preparedForSharingAt: Date?

    public init(ownerID: String, window: WeeklyRecapWindow, sourceFingerprint: String,
                recap: WeeklyRecap, prior: WeeklyRecap, coverage: String, now: Date = Date()) throws {
        guard !ownerID.isEmpty, !sourceFingerprint.isEmpty else { throw WeeklyRecapJournalError.changedAccount }
        version = 1; self.ownerID = ownerID; self.window = window; self.createdAt = now
        self.sourceFingerprint = sourceFingerprint; self.recap = recap; self.prior = prior; self.coverage = coverage
        struct Identity: Codable {
            let ownerID: String; let window: WeeklyRecapWindow; let source: String
            let recap: WeeklyRecap; let prior: WeeklyRecap; let coverage: String
        }
        id = try PlanFingerprint.make(Identity(ownerID: ownerID, window: window, source: sourceFingerprint,
                                               recap: recap, prior: prior, coverage: coverage))
    }
}

public struct WeeklyRecapIntention: Codable, Equatable {
    public enum Outcome: String, Codable, CaseIterable {
        case followedThrough, partly, plansChanged
        public var title: String {
            switch self {
            case .followedThrough: "Followed through"
            case .partly: "Partly followed through"
            case .plansChanged: "Plans changed"
            }
        }
    }
    public let ownerID: String
    public let sourceWindow: WeeklyRecapWindow
    public let targetWindow: WeeklyRecapWindow
    public var text: String
    public var outcome: Outcome?
    public var outcomeNote: String?
    public var updatedAt: Date
}

public enum WeeklyRecapJournalError: LocalizedError {
    case changedAccount, invalidIntention, changedRevision
    public var errorDescription: String? {
        switch self {
        case .changedAccount: "Reopen the report for the signed-in account before saving."
        case .invalidIntention: "Write a short intention of 180 characters or fewer."
        case .changedRevision: "This report changed. Review its latest version before continuing."
        }
    }
}

/// Account-scoped local report journal. It cannot alter logs, targets or program
/// progress. Prepared export revisions are retained when later evidence changes.
@MainActor
public final class WeeklyRecapJournal {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    private func scope(_ window: WeeklyRecapWindow) -> String { "weekly-recap-v1|\(window.storageKey)" }
    private func intentionScope(_ window: WeeklyRecapWindow) -> String { "weekly-intention-v1|\(window.storageKey)" }

    public func revisions(ownerID: String, window: WeeklyRecapWindow) throws -> [WeeklyRecapRevision] {
        let values = try store.load([WeeklyRecapRevision].self, userID: ownerID, scope: scope(window))?.value ?? []
        guard values.allSatisfy({ $0.ownerID == ownerID && $0.window == window }) else { throw WeeklyRecapJournalError.changedAccount }
        return values
    }
    public func remember(_ revision: WeeklyRecapRevision, currentUserID: String?) throws {
        guard currentUserID == revision.ownerID else { throw WeeklyRecapJournalError.changedAccount }
        var values = try revisions(ownerID: revision.ownerID, window: revision.window)
        if values.contains(where: { $0.id == revision.id }) { return }
        values = values.filter { $0.preparedForSharingAt != nil }
        values.append(revision)
        try store.save(values, userID: revision.ownerID, scope: scope(revision.window))
    }
    public func prepareForSharing(_ revision: WeeklyRecapRevision, currentUserID: String?, now: Date = Date()) throws {
        guard currentUserID == revision.ownerID else { throw WeeklyRecapJournalError.changedAccount }
        var values = try revisions(ownerID: revision.ownerID, window: revision.window)
        guard let index = values.firstIndex(where: { $0.id == revision.id }) else { throw WeeklyRecapJournalError.changedRevision }
        values[index].preparedForSharingAt = values[index].preparedForSharingAt ?? now
        try store.save(values, userID: revision.ownerID, scope: scope(revision.window))
    }
    public func intention(ownerID: String, targetWindow: WeeklyRecapWindow) throws -> WeeklyRecapIntention? {
        let value = try store.load(WeeklyRecapIntention.self, userID: ownerID, scope: intentionScope(targetWindow))?.value
        guard value == nil || (value?.ownerID == ownerID && value?.targetWindow == targetWindow) else {
            throw WeeklyRecapJournalError.changedAccount
        }
        return value
    }
    public func pin(text: String, from revision: WeeklyRecapRevision, currentUserID: String?,
                    now: Date = Date(), calendar: Calendar = .current) throws -> WeeklyRecapIntention {
        guard currentUserID == revision.ownerID else { throw WeeklyRecapJournalError.changedAccount }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 180 else { throw WeeklyRecapJournalError.invalidIntention }
        let nextEnd = calendar.date(byAdding: .day, value: 7, to: revision.window.lastDay) ?? revision.window.lastDay
        let target = WeeklyRecapWindow(endingOn: nextEnd, calendar: calendar)
        let previous = try intention(ownerID: revision.ownerID, targetWindow: target)
        let value = WeeklyRecapIntention(ownerID: revision.ownerID, sourceWindow: revision.window,
            targetWindow: target, text: cleaned, outcome: previous?.text == cleaned ? previous?.outcome : nil,
            outcomeNote: previous?.text == cleaned ? previous?.outcomeNote : nil, updatedAt: now)
        try store.save(value, userID: revision.ownerID, scope: intentionScope(target))
        return value
    }
    public func reflect(on expected: WeeklyRecapIntention, outcome: WeeklyRecapIntention.Outcome,
                        currentUserID: String?, now: Date = Date()) throws -> WeeklyRecapIntention {
        guard currentUserID == expected.ownerID else { throw WeeklyRecapJournalError.changedAccount }
        guard try intention(ownerID: expected.ownerID, targetWindow: expected.targetWindow) == expected else {
            throw WeeklyRecapJournalError.changedRevision
        }
        var updated = expected; updated.outcome = outcome; updated.updatedAt = now
        try store.save(updated, userID: expected.ownerID, scope: intentionScope(expected.targetWindow))
        return updated
    }
}
