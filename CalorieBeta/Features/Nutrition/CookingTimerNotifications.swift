import MyFitPlateCore
import SwiftUI
import UserNotifications

@MainActor final class CookingNotificationCoordinator: ObservableObject {
    static let shared = CookingNotificationCoordinator()
    @Published private(set) var message = "Cooking alerts have not been enabled. Timers remain available in the app."
    private var generation = UUID()
    private var lastOwner: String?
    func requestAlerts() async {
        guard let owner = DIContainer.shared.authService.currentUserID,
              let key = AccountScopedStorageKey.make(prefix: "cooking-alerts-opt-in", userID: owner) else { return }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } catch { message = "Alerts could not be enabled. Your timers still work in the app." }
        guard DIContainer.shared.authService.currentUserID == owner else {
            await reconcile(userID: DIContainer.shared.authService.currentUserID); return
        }
        UserDefaults.standard.set(true, forKey: key)
        await reconcile(userID: owner)
    }
    func reconcile(userID: String?) async {
        let token = UUID(); generation = token
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let settings = await center.notificationSettings()
        guard token == generation, DIContainer.shared.authService.currentUserID == userID else { return }
        let optedIn = userID.flatMap { AccountScopedStorageKey.make(prefix: "cooking-alerts-opt-in", userID: $0) }
            .map { UserDefaults.standard.bool(forKey: $0) } ?? false
        let allowed = optedIn && [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let timers: [CookingTimerInspection]
        do { timers = try userID.map { try CookingTimerRegistry.shared.checkedTimers(userID: $0) } ?? [] } catch {
            if lastOwner != userID || !allowed {
                center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("mfp.cooking.") }.map(\.identifier))
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("mfp.cooking.") }.map { $0.request.identifier })
            }
            lastOwner = userID; message = "The timer index could not be opened. Cooking checkpoints are kept; alert reconciliation needs retry."; return
        }
        let capacity = CookingNotificationRules.alertCapacity(otherPendingCount: existing.filter { !$0.identifier.hasPrefix("mfp.cooking.") }.count)
        let desired = userID.map { Array(CookingNotificationRules.requests(userID: $0, timers: timers).prefix(capacity)) } ?? []
        let active = allowed ? desired : []
        let identifiers = Set(active.map(\.id))
        let retainedIDs = Set(userID.map { owner in timers.map { CookingNotificationRules.identifier(userID: owner, timer: $0) } } ?? [])
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("mfp.cooking.") && !identifiers.contains($0.identifier) }.map(\.identifier))
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.request.identifier.hasPrefix("mfp.cooking.") && (lastOwner != userID || !allowed || !retainedIDs.contains($0.request.identifier) || identifiers.contains($0.request.identifier))
        }.map { $0.request.identifier })
        lastOwner = userID
        guard userID != nil else { return }
        message = !optedIn ? "Cooking alerts are off for this account. Enable them below; timers remain available in the app."
            : allowed ? "Alerts enabled. iOS notification settings and Focus determine delivery." : "Alerts unavailable. Use the in-app timer display; enable notifications in Settings."
        if timers.filter({ $0.deadline.map { $0 > Date() } ?? false }).count > capacity {
            message += " Only the nearest \(capacity) cooking alerts fit the notification budget (at most 48); later timers remain saved in the app. Other app alerts are preserved."
        }
        for timer in active {
            guard token == generation, DIContainer.shared.authService.currentUserID == userID else { return }
            let content = UNMutableNotificationContent(); content.title = "Cooking timer finished"
            content.body = timer.title; content.sound = .default
            let delay = max(1, timer.deadline.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: timer.id, content: content, trigger: trigger))
                if token != generation || DIContainer.shared.authService.currentUserID != userID {
                    center.removePendingNotificationRequests(withIdentifiers: [timer.id])
                    center.removeDeliveredNotifications(withIdentifiers: [timer.id])
                    await reconcile(userID: DIContainer.shared.authService.currentUserID); return
                }
            } catch { message = "An alert could not be scheduled. The saved timer remains available in the app." }
        }
    }
}

struct CookingTimersInspectionView: View {
    @ObservedObject private var registry = CookingTimerRegistry.shared
    @ObservedObject private var notifications = CookingNotificationCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    private let owner = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(notifications.message).appTextRole(.secondary)
                    if let error = registry.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                    Button("Enable cooking alerts") { Task { await notifications.requestAlerts() } }.frame(minHeight: 44)
                        .accessibilityIdentifier("cooking_enable_alerts")
                }
                if let owner {
                    ForEach(registry.timers(userID: owner)) { timer in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(timer.name).appTextRole(.control)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(timer.finished || timer.remaining(now: context.date) <= 0 ? "Finished" : MealPrepTimerRules.display(timer.remaining(now: context.date)))
                                    .appTextRole(.metric).monospacedDigit()
                            }
                            if timer.stepID != nil { Text("Linked to a cooking step").appTextRole(.caption) }
                            ViewThatFits(in: .horizontal) {
                                HStack { controls(timer, owner: owner) }
                                VStack(alignment: .leading) { controls(timer, owner: owner) }
                            }
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("cooking_inspect_\(timer.id)")
                    }
                }
            }.appFormStyle()
            .navigationTitle("Cooking timers").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await notifications.reconcile(userID: owner) }
        .onReceive(NotificationCenter.default.publisher(for: .cookingTimersChanged)) { _ in Task { await notifications.reconcile(userID: owner) } }
        .onChange(of: phase) { _, value in if value == .active { Task { await notifications.reconcile(userID: owner) } } }
    }
    @ViewBuilder private func controls(_ timer: CookingTimerInspection, owner: String) -> some View {
        Button(timer.deadline == nil ? "Resume" : "Pause") { change(timer, owner: owner, action: 0) }
            .frame(minWidth: 44, minHeight: 44).buttonStyle(AppListButtonStyle()).disabled(timer.finished || timer.remaining() <= 0)
        Button("+1 min") { change(timer, owner: owner, action: 1) }.frame(minWidth: 44, minHeight: 44).buttonStyle(AppListButtonStyle())
        Button("Cancel", role: .destructive) { change(timer, owner: owner, action: 2) }.frame(minWidth: 44, minHeight: 44).buttonStyle(AppListButtonStyle())
    }
    private func change(_ timer: CookingTimerInspection, owner: String, action: Int) {
        guard DIContainer.shared.authService.currentUserID == owner else { return }
        let session = MealCookingCheckpointSession(userID: owner, contextID: timer.contextID)
        if let id = timer.timerID {
            if action == 1 { _ = session.adjustNamedTimer(id: id, seconds: 60) } else { _ = session.changeNamedTimer(id: id, remove: action == 2) }
        } else if action == 2 { _ = session.clearTimer() } else if action == 1 { _ = session.adjustTimer(seconds: 60) } else if session.isRunning { _ = session.pauseTimer() } else { _ = session.resumeTimer() }
    }
}
