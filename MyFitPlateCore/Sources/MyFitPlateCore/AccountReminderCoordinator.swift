import Foundation
import Combine
import UserNotifications

public extension Notification.Name {
    static let reminderEvidenceChanged = Notification.Name("ReminderEvidenceChanged")
}

public final class ReminderAccountStore {
    public static let scope = "account-reminder-policy-v1"
    private let drafts: EditorDraftStore
    public init(drafts: EditorDraftStore = EditorDraftStore()) { self.drafts = drafts }
    public func load(ownerID: String) throws -> ReminderAccountRecord {
        let value = try drafts.load(ReminderAccountRecord.self, userID: ownerID, scope: Self.scope)?.value ?? .init()
        guard Self.isValid(value, ownerID: ownerID) else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    public func save(_ value: ReminderAccountRecord, ownerID: String, now: Date = Date()) throws {
        guard Self.isValid(value, ownerID: ownerID) else { throw CocoaError(.coderReadCorrupt) }
        try drafts.save(value, userID: ownerID, scope: Self.scope, now: now)
    }
    private static func isValid(_ value: ReminderAccountRecord, ownerID: String) -> Bool {
        value.version == 1 && value.preferences.isValid && value.decisions.allSatisfy { key, decision in
            key == decision.id && decision.id == decision.candidate.id && decision.candidate.target.ownerID == ownerID
        }
    }
}

@MainActor
public final class AccountReminderCoordinator: ObservableObject {
    public static let shared = AccountReminderCoordinator()
    public static let category = "account_reminder_actions_v1"
    public static let snoozeAction = "reminder_snooze_20"
    public static let handledAction = "reminder_handled"
    public static let legacyIDs = ["dailyLogReminder", "weighInReminder", "hydration_0", "hydration_1", "hydration_2", "hydration_3", "dailyBriefing", "smart_ai_nudge"] + TrainingFuelNotificationCandidate.Kind.allCases.map(\.identifier)
    @Published public private(set) var preferences = ReminderPreferences()
    @Published public private(set) var decisions: [ReminderDecision] = []
    @Published public private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pendingTarget: ReminderTarget?
    @Published public private(set) var ownerID: String?
    @Published public private(set) var hasLegacyPreferences = false
    private let center: UserNotificationScheduling
    private let store: ReminderAccountStore
    private let defaults: UserDefaults
    private let currentOwner: @MainActor () -> String?
    private var record = ReminderAccountRecord()
    private var generation = UUID()
    private var activated = false
    private var unreadableRecord = false
    private var pendingResponse: (identifier: String, fingerprint: String, action: String)?
    private var latestEvidence: ReminderEvidence?
    private var latestCalendar = Calendar.current
    private var isSystemCenter: Bool
    private var mayUseCenter: Bool { !isSystemCenter || NSClassFromString("XCTest") == nil }
    private var legacySnapshotKey = "accountReminderLegacyPreferencesForReview.v1"

    public init(center: UserNotificationScheduling = SystemUserNotificationCenter(), store: ReminderAccountStore = .init(),
                defaults: UserDefaults = .standard, currentOwner: @escaping @MainActor () -> String? = { DIContainer.shared.authService?.currentUserID }) {
        self.center = center; self.store = store; self.defaults = defaults; self.currentOwner = currentOwner
        isSystemCenter = center is SystemUserNotificationCenter
    }

    public func activateAccount(_ owner: String?) {
        guard !activated || owner != ownerID else { return }
        activated = true
        generation = UUID(); latestEvidence = nil; pendingTarget = nil; errorMessage = nil; unreadableRecord = false
        if let owner, let pendingResponse,
           !pendingResponse.identifier.hasPrefix(ReminderPolicy.identifierPrefix + ReminderPolicy.accountScope(owner) + ".") { self.pendingResponse = nil }
        let oldIDs = Array(record.decisions.keys)
        if mayUseCenter {
            center.removePendingRequests(withIdentifiers: oldIDs + Self.legacyIDs)
            center.removeDeliveredRequests(withIdentifiers: oldIDs + Self.legacyIDs)
        }
        ownerID = owner; record = .init(); preferences = record.preferences; decisions = []
        if let owner {
            do { record = try store.load(ownerID: owner); publish() } catch { unreadableRecord = true; errorMessage = "Reminder settings could not be opened. Existing records are kept; reminders stay off." }
        }
        hasLegacyPreferences = legacyPreferences() != nil && !preferences.legacyReviewCompleted
        guard mayUseCenter else { return }
        let token = generation
        center.pendingRequests { [weak self] requests in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                let ownedPrefix = owner.map { ReminderPolicy.identifierPrefix + ReminderPolicy.accountScope($0) + "." }
                let stale = requests.filter { request in request.identifier.hasPrefix(ReminderPolicy.identifierPrefix) && (self.unreadableRecord || !(ownedPrefix.map { request.identifier.hasPrefix($0) } ?? false)) }.map(\.identifier)
                self.center.removePendingRequests(withIdentifiers: stale + Self.legacyIDs)
            }
        }
        center.setReminderCategories([UNNotificationCategory(identifier: Self.category, actions: [
            UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 20 min", options: [.foreground]),
            UNNotificationAction(identifier: Self.handledAction, title: "Mark handled", options: [.foreground])
        ], intentIdentifiers: [], options: [])])
        refreshAuthorization()
    }

    public func refreshAuthorization() {
        guard mayUseCenter else { return }
        let token = generation
        center.authorizationStatus { [weak self] status in
            Task { @MainActor in guard let self, self.generation == token else { return }; self.authorization = status }
        }
    }

    @discardableResult public func savePreferences(_ value: ReminderPreferences) -> Bool {
        guard !unreadableRecord, let ownerID, ownerID == currentOwner(), value.isValid else { return false }
        var next = record; next.preferences = value
        do { try store.save(next, ownerID: ownerID); record = next; publish(); errorMessage = nil } catch { errorMessage = "Settings could not be saved on this device. Your previous reminder choices remain."; return false }
        generation = UUID()
        if mayUseCenter { center.removePendingRequests(withIdentifiers: Array(record.decisions.keys)) }
        NotificationCenter.default.post(name: .reminderEvidenceChanged, object: ownerID)
        return true
    }

    public func requestPermission() {
        guard mayUseCenter else { return }
        let token = generation
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.refreshAuthorization()
                NotificationCenter.default.post(name: .reminderEvidenceChanged, object: self.ownerID)
            }
        }
    }

    /// Legacy preferences remain suggestions until the signed-in person explicitly reviews and saves them.
    public func legacyPreferences() -> ReminderPreferences? {
        if let data = defaults.data(forKey: legacySnapshotKey), let value = try? JSONDecoder().decode(ReminderPreferences.self, from: data) { return value }
        let keys = ["notificationHour", "hydrationRemindersEnabled", "weighInReminderEnabled", TrainingFuelNotificationPreferenceKey.preSessionEnabled,
                    TrainingFuelNotificationPreferenceKey.recoveryEnabled, TrainingFuelNotificationPreferenceKey.eveningCatchUpEnabled]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return nil }
        var value = ReminderPreferences()
        value[.dailyLog].enabled = defaults.object(forKey: "notificationHour") != nil
        value[.dailyLog].minutes = [(defaults.object(forKey: "notificationHour") as? Int ?? 20) * 60 + (defaults.object(forKey: "notificationMinute") as? Int ?? 0)]
        value[.hydration].enabled = defaults.bool(forKey: "hydrationRemindersEnabled")
        value[.weighIn].enabled = defaults.bool(forKey: "weighInReminderEnabled")
        let fuel = TrainingFuelNotificationPreferences.load(from: defaults)
        value[.beforeTraining].enabled = fuel.preSessionEnabled; value[.recovery].enabled = fuel.recoveryEnabled
        value[.eveningProtein].enabled = fuel.eveningCatchUpEnabled; value[.eveningProtein].minutes = [fuel.eveningMinutes]
        for kind in ReminderKind.allCases where kind.isFuel { value[kind].quietStart = fuel.quietStartMinutes; value[kind].quietEnd = fuel.quietEndMinutes }
        guard value.isValid else { return nil }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: legacySnapshotKey) }
        return value
    }

    public func reconcile(evidence: ReminderEvidence, now: Date = Date(), calendar: Calendar = .current) async {
        guard let owner = ownerID, owner == currentOwner(), errorMessage == nil else { return }
        if isSystemCenter && NSClassFromString("XCTest") != nil { return }
        latestEvidence = evidence; latestCalendar = calendar
        generation = UUID(); let token = generation
        let status = await withCheckedContinuation { continuation in center.authorizationStatus { continuation.resume(returning: $0) } }
        guard token == generation, owner == currentOwner() else { return }
        authorization = status
        let pending = await withCheckedContinuation { continuation in center.pendingRequests { continuation.resume(returning: $0) } }
        guard token == generation, owner == currentOwner() else { return }
        let delivered = await withCheckedContinuation { continuation in center.deliveredRequestIdentifiers { continuation.resume(returning: $0) } }
        guard token == generation, owner == currentOwner() else { return }
        var next = record
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        next.decisions = next.decisions.filter { $0.value.updatedAt >= cutoff }
        next.reservations.removeAll { $0.reservedAt < cutoff }
        for id in delivered where next.decisions[id]?.state == .scheduled {
            next.decisions[id]?.state = .observedDelivered
            next.decisions[id]?.reason = "Observed in Notification Center; this does not mean it was read."
        }
        let proposed = ReminderPolicy.decisions(ownerID: owner, record: next, evidence: evidence, now: now, calendar: calendar)
        let desired = Set(proposed.filter { $0.state == .ready }.map(\.id))
        let stale = pending.filter { $0.identifier.hasPrefix(ReminderPolicy.identifierPrefix) && !desired.contains($0.identifier) }.map(\.identifier)
        center.removePendingRequests(withIdentifiers: stale + Self.legacyIDs)
        for old in next.decisions.values where !desired.contains(old.id) && old.state == .scheduled {
            next.decisions[old.id]?.state = old.candidate.target.expiresAt <= now ? .expired : .suppressed
            next.decisions[old.id]?.reason = "No longer an eligible action after the latest evidence review."
            next.decisions[old.id]?.updatedAt = now
        }
        for var decision in proposed {
            if decision.state == .ready && !Self.isAuthorized(status) {
                decision.state = .suppressed; decision.reason = status == .denied ? "Notifications are disabled in iOS Settings." : "Notification permission has not been requested."
            }
            if decision.state == .ready, let previous = record.decisions[decision.id],
               previous.candidate.fingerprint == decision.candidate.fingerprint,
               pending.contains(where: { $0.identifier == decision.id }) {
                decision.state = .scheduled; decision.reason = "Scheduled with iOS; delivery is not guaranteed."
            }
            next.decisions[decision.id] = decision
            if decision.state == .ready && !next.reservations.contains(where: { $0.key == decision.candidate.budgetKey }) {
                next.reservations.append(.init(key: decision.candidate.budgetKey,
                    dayKey: ReminderPolicy.dayKey(decision.candidate.fireDate, calendar: calendar), kind: decision.candidate.target.kind, reservedAt: now))
            }
        }
        do { try store.save(next, ownerID: owner, now: now); record = next; publish() } catch { center.removePendingRequests(withIdentifiers: Array(next.decisions.keys)); errorMessage = "The reminder ledger could not be saved. No new reminders were scheduled."; return }
        for decision in proposed where record.decisions[decision.id]?.state == .ready {
            guard token == generation, owner == currentOwner() else { return }
            let candidate = decision.candidate
            let content = UNMutableNotificationContent()
            content.title = candidate.title; content.body = candidate.body; content.sound = .default; content.categoryIdentifier = Self.category
            content.userInfo = ["reminder_id": candidate.id, "reminder_fingerprint": candidate.fingerprint]
            let components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: candidate.fireDate)
            let request = UNNotificationRequest(identifier: candidate.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            let error: Error? = await withCheckedContinuation { continuation in center.add(request) { continuation.resume(returning: $0) } }
            guard token == generation, owner == currentOwner() else { retireLateRequest(candidate); return }
            record.decisions[candidate.id]?.state = error == nil ? .scheduled : .failed
            record.decisions[candidate.id]?.reason = error == nil ? "Scheduled with iOS; delivery is not guaranteed." : "iOS could not schedule this request. Refresh to retry."
            do { try store.save(record, ownerID: owner, now: now); publish() } catch { center.removePendingRequests(withIdentifiers: [candidate.id]); errorMessage = "The scheduling receipt could not be kept. This reminder was cancelled."; return }
        }
        if let pending = pendingResponse {
            pendingResponse = nil
            let accepted = await respond(identifier: pending.identifier, fingerprint: pending.fingerprint, action: pending.action, now: now)
            if !accepted { errorMessage = "This reminder is no longer available for this account or its evidence changed." }
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        #if os(iOS)
        return status == .authorized || status == .provisional || status == .ephemeral
        #else
        return status == .authorized || status == .provisional
        #endif
    }

    private func retireLateRequest(_ candidate: ReminderCandidate) {
        guard ownerID == candidate.target.ownerID else { center.removePendingRequests(withIdentifiers: [candidate.id]); return }
        center.pendingRequests { [weak self] requests in
            Task { @MainActor in
                guard let self,
                      requests.first(where: { $0.identifier == candidate.id })?.content.userInfo["reminder_fingerprint"] as? String == candidate.fingerprint else { return }
                let current = self.record.decisions[candidate.id]
                let stillWantsRequest = current?.candidate.fingerprint == candidate.fingerprint
                    && (current?.state == .ready || current?.state == .scheduled)
                guard !stillWantsRequest else { return }
                self.center.removePendingRequests(withIdentifiers: [candidate.id])
            }
        }
    }

    public func queueResponse(identifier: String, fingerprint: String, action: String) {
        pendingResponse = (identifier, fingerprint, action)
        NotificationCenter.default.post(name: .reminderEvidenceChanged, object: ownerID)
    }

    public func retry() {
        guard let ownerID, ownerID == currentOwner() else { return }
        do { record = try store.load(ownerID: ownerID); unreadableRecord = false; errorMessage = nil; publish() } catch { errorMessage = "Reminder records still could not be opened. They have been kept." }
        NotificationCenter.default.post(name: .reminderEvidenceChanged, object: ownerID)
    }

    /// All actions resolve an exact local ledger entry. They never create a diary or session record.
    @discardableResult public func respond(identifier: String, fingerprint: String, action: String, now: Date = Date()) async -> Bool {
        guard [Self.snoozeAction, Self.handledAction, UNNotificationDefaultActionIdentifier].contains(action),
              let owner = ownerID, owner == currentOwner(), var decision = record.decisions[identifier],
              decision.candidate.fingerprint == fingerprint, decision.candidate.target.isAvailable(ownerID: owner, now: now),
              let evidence = latestEvidence else { return false }
        guard decision.state != .handled,
              ReminderPolicy.actionIsCurrent(decision.candidate, ownerID: owner, preferences: preferences,
                evidence: evidence, now: now, calendar: latestCalendar) else { return false }
        if action == Self.snoozeAction {
            let fire = max(now, decision.candidate.fireDate).addingTimeInterval(20 * 60), target = decision.candidate.target
            let schedule = preferences[target.kind]
            guard fire < target.expiresAt, !schedule.isQuiet(fire, calendar: latestCalendar),
                  schedule.weekdays.contains(latestCalendar.component(.weekday, from: fire)) else { return false }
            let day = ReminderPolicy.dayKey(fire, calendar: latestCalendar)
            let used = record.reservations.filter { $0.dayKey == day }
            guard used.count < preferences.maximumPerDay, !target.kind.isFuel || used.filter({ $0.kind.isFuel }).count < 2 else { return false }
            decision.snoozeCount += 1; decision.candidate.fireDate = fire
            decision.candidate.budgetKey = identifier + ".snooze.\(decision.snoozeCount).\(day)"
            decision.state = .snoozed; decision.reason = "Snoozed for 20 minutes; still subject to the current evidence and budget."
        } else if action == Self.handledAction {
            decision.state = .handled; decision.reason = "Marked handled; no diary entry was created."
        } else {
            decision.state = .opened; decision.reason = "Opened the exact reminder task."
        }
        decision.updatedAt = now
        var next = record; next.decisions[identifier] = decision
        do {
            try store.save(next, ownerID: owner, now: now)
            // A scheduling callback already in flight must not resurrect this response.
            generation = UUID(); record = next; publish()
        } catch { errorMessage = "The reminder response could not be saved. Try again in Settings."; return false }
        center.removePendingRequests(withIdentifiers: [identifier]); center.removeDeliveredRequests(withIdentifiers: [identifier])
        if action == Self.snoozeAction { await reconcile(evidence: evidence, now: now, calendar: latestCalendar) } else if action != Self.handledAction { pendingTarget = decision.candidate.target }
        return true
    }

    public func takePendingTarget() -> ReminderTarget? {
        defer { pendingTarget = nil }
        return pendingTarget?.isAvailable(ownerID: currentOwner(), now: Date()) == true ? pendingTarget : nil
    }
    private func publish() {
        preferences = record.preferences
        decisions = record.decisions.values.sorted { $0.candidate.fireDate > $1.candidate.fireDate }
        hasLegacyPreferences = !preferences.legacyReviewCompleted && legacyPreferences() != nil
    }
}
