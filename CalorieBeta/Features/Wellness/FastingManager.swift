import ActivityKit
import Foundation
import MyFitPlateCore

@MainActor
public class FastingManager: ObservableObject {
    public static let shared = FastingManager()

    public struct LegacyTimer: Identifiable {
        public let id: String
        public let startTime: Date
        public let targetEndTime: Date
    }

    @Published public private(set) var session: SavedFastSession?
    @Published public private(set) var lastEndedSession: SavedFastSession?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var projectionMessage: String?
    @Published public private(set) var legacyTimers: [LegacyTimer] = []

    public var isFasting: Bool { session != nil }
    public var currentFastStartTime: Date? { session?.startTime }
    public var currentFastTargetEndTime: Date? { session?.targetEndTime }
    public var fastType: String { session?.fastType ?? "16:8 Fast" }

    private let store: FastingSessionStore
    private var ownerScope: String?
    private var observingActivityID: String?
    private var activityObserver: Task<Void, Never>?
    private let projectsActivities: Bool

    public init(store: FastingSessionStore = FastingSessionStore(), projectsActivities: Bool = true) {
        self.store = store
        self.projectsActivities = projectsActivities
    }

    public func activateAccount(_ userID: String?) {
        let next = FastingSessionStore.ownerScope(userID: userID)
        if next != ownerScope {
            session = nil
            lastEndedSession = nil
            legacyTimers = []
            activityObserver?.cancel()
            observingActivityID = nil
        }
        do {
            try store.activateAccount(userID: userID)
            ownerScope = next
            errorMessage = nil
            recoverState()
            endUnrelatedProjections()
            if let session { project(session) }
        } catch {
            ownerScope = nil
            session = nil
            lastEndedSession = nil
            errorMessage = error.localizedDescription
            endUnrelatedProjections()
        }
    }

    @discardableResult
    public func startFast(hours: Int, source: String = "app") -> Bool {
        guard let ownerScope else {
            if errorMessage == nil { errorMessage = FastingStoreError.accountChanged.localizedDescription }
            return false
        }
        guard ownerScope == FastingSessionStore.ownerScope(userID: DIContainer.shared.authService.currentUserID) else {
            errorMessage = FastingStoreError.accountChanged.localizedDescription
            return false
        }
        guard legacyTimers.isEmpty else {
            errorMessage = "Review the older timer below before starting another fast."
            return false
        }
        do {
            let saved = try store.start(ownerScope: ownerScope, hours: hours, source: source)
            session = saved
            errorMessage = nil
            project(saved)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func endFast() -> Bool {
        guard let ownerScope, ownerScope == FastingSessionStore.ownerScope(userID: DIContainer.shared.authService.currentUserID), let session else {
            errorMessage = "There is no active saved fast in this account."
            return false
        }
        do {
            lastEndedSession = try store.end(ownerScope: ownerScope, sessionID: session.id, expectedRevision: session.revision)
            self.session = nil
            errorMessage = nil
            projectionMessage = nil
            activityObserver?.cancel()
            observingActivityID = nil
            endProjection(sessionID: session.id, ownerScope: ownerScope)
            refreshLegacyTimers()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func recoverLegacyTimer(_ timer: LegacyTimer) -> Bool {
        guard let ownerScope, ownerScope == FastingSessionStore.ownerScope(userID: DIContainer.shared.authService.currentUserID) else { return false }
        do {
            let saved = try store.recoverLegacy(ownerScope: ownerScope, activityID: timer.id, startTime: timer.startTime, targetEndTime: timer.targetEndTime)
            session = saved.isActive ? saved : nil
            if !saved.isActive { lastEndedSession = saved }
            errorMessage = nil
            Task {
                if let legacy = Activity<FastingActivityAttributes>.activities.first(where: { $0.id == timer.id }) {
                    await legacy.end(nil, dismissalPolicy: .immediate)
                }
                refreshLegacyTimers()
                if let current = self.session { project(current) }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func recoverState() {
        guard let ownerScope else { return }
        do {
            let snapshot = try store.load(ownerScope: ownerScope)
            session = snapshot.activeSession
            lastEndedSession = snapshot.lastEndedSession
            errorMessage = nil
            refreshLegacyTimers()
            if projectsActivities, let activity = Activity<FastingActivityAttributes>.activities.first(where: {
                $0.attributes.ownerScope == ownerScope && $0.attributes.sessionID == session?.id
            }) { observe(activity) }
        } catch { errorMessage = error.localizedDescription }
    }

    public func removeAccountData(for userID: String) throws {
        let deletedScope = FastingSessionStore.ownerScope(userID: userID)
        let legacyIDs = try store.removeAccount(userID: userID)
        if ownerScope == deletedScope {
            ownerScope = nil
            session = nil
            lastEndedSession = nil
            legacyTimers = []
            activityObserver?.cancel()
            observingActivityID = nil
        }
        guard projectsActivities else { return }
        Task {
            for activity in Activity<FastingActivityAttributes>.activities
            where activity.attributes.ownerScope == deletedScope || legacyIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func refreshLegacyTimers() {
        guard projectsActivities else { legacyTimers = []; return }
        legacyTimers = Activity<FastingActivityAttributes>.activities.filter {
            $0.attributes.sessionID == nil && $0.attributes.ownerScope == nil && $0.activityState == .active
        }.map { LegacyTimer(id: $0.id, startTime: $0.content.state.startTime, targetEndTime: $0.content.state.targetEndTime) }
    }

    private func project(_ saved: SavedFastSession) {
        guard projectsActivities else { projectionMessage = "Timer saved on this device. Lock Screen display is off."; return }
        if let existing = Activity<FastingActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == saved.id && $0.attributes.ownerScope == saved.ownerScope && $0.activityState == .active
        }) { projectionMessage = nil; observe(existing); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            projectionMessage = "Timer saved on this device. Live Activities are unavailable."
            return
        }
        do {
            let activity = try Activity<FastingActivityAttributes>.request(
                attributes: FastingActivityAttributes(fastType: saved.fastType, sessionID: saved.id, ownerScope: saved.ownerScope),
                content: ActivityContent(state: .init(startTime: saved.startTime, targetEndTime: saved.targetEndTime, revision: saved.revision),
                                         staleDate: saved.targetEndTime.addingTimeInterval(7_200)), pushType: nil)
            projectionMessage = nil
            observe(activity)
        } catch { projectionMessage = "Timer saved on this device. Its Lock Screen display could not start." }
    }

    private func observe(_ activity: Activity<FastingActivityAttributes>) {
        guard observingActivityID != activity.id else { return }
        activityObserver?.cancel()
        observingActivityID = activity.id
        activityObserver = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .ended || state == .dismissed {
                    self?.recoverState()
                    if self?.isFasting == true { self?.projectionMessage = "Timer saved on this device. Its Lock Screen display has ended." }
                    return
                }
            }
        }
    }

    private func endProjection(sessionID: UUID, ownerScope: String) {
        guard projectsActivities else { return }
        Task {
            for activity in Activity<FastingActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID && activity.attributes.ownerScope == ownerScope {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func endUnrelatedProjections() {
        guard projectsActivities else { return }
        let scope = ownerScope
        let sessionID = session?.id
        Task {
            // Keep unowned legacy activities available for explicit recovery.
            for activity in Activity<FastingActivityAttributes>.activities
            where activity.attributes.ownerScope != nil && (activity.attributes.ownerScope != scope || activity.attributes.sessionID != sessionID) {
                guard self.ownerScope == scope, self.session?.id == sessionID else { return }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
