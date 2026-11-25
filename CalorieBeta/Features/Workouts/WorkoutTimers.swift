import SwiftUI
import ActivityKit
import MyFitPlateCore

@MainActor
class TotalWorkoutTimer: ObservableObject {
    static let maximumRestorableDuration: TimeInterval = 12 * 60 * 60

    @Published var totalTimeElapsed: TimeInterval = 0
    private var timer: Timer?
    private var startTime: Date?
    private let userDefaults: UserDefaults
    private let legacyUserDefaultsKey: String
    private let userDefaultsKey: String?

    /// The Live Activity uses the player's running clock, including recovered elapsed
    /// time. A draft's original creation date would include time paused after leaving.
    var activityStartTime: Date { startTime ?? Date().addingTimeInterval(-totalTimeElapsed) }

    init(
        routineId: String,
        userDefaults: UserDefaults = .standard,
        userID: String? = nil
    ) {
        let resolvedUserID = userID ?? DIContainer.shared.authService?.currentUserID
        let legacyKey = "totalWorkoutTimer_\(routineId)"
        self.userDefaults = userDefaults
        self.legacyUserDefaultsKey = legacyKey
        self.userDefaultsKey = AccountScopedStorageKey.make(
            prefix: legacyKey,
            userID: resolvedUserID
        )
        migrateLegacyStorageIfNeeded()
        loadTimerState()
    }

    func start() {
        guard timer == nil else { return }
        if startTime == nil {
            startTime = Date().addingTimeInterval(-totalTimeElapsed)
        }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTotalTime()
            }
        }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
        saveTimerState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        totalTimeElapsed = 0
        clearTimerState()
    }

    func pause() {
        updateTotalTime()
        timer?.invalidate()
        timer = nil
        startTime = nil
        clearTimerState()
    }

    func resume(elapsed: TimeInterval) {
        pause()
        totalTimeElapsed = max(0, elapsed)
        start()
    }

    private func updateTotalTime() {
        guard let startTime = startTime else { return }
        totalTimeElapsed = Date().timeIntervalSince(startTime)
    }

    private func saveTimerState() {
        guard let startTime, let userDefaultsKey else { return }
        userDefaults.set(startTime, forKey: userDefaultsKey)
    }

    private func loadTimerState() {
        guard let userDefaultsKey,
              let savedStartTime = userDefaults.object(forKey: userDefaultsKey) as? Date else {
            return
        }

        guard Self.isRestorable(startTime: savedStartTime) else {
            clearTimerState()
            return
        }

        self.startTime = savedStartTime
        updateTotalTime()
        start()
    }

    private func clearTimerState() {
        guard let userDefaultsKey else { return }
        userDefaults.removeObject(forKey: userDefaultsKey)
    }

    private func migrateLegacyStorageIfNeeded() {
        guard let userDefaultsKey else { return }
        if userDefaults.object(forKey: userDefaultsKey) == nil,
           let legacyStart = userDefaults.object(forKey: legacyUserDefaultsKey) {
            userDefaults.set(legacyStart, forKey: userDefaultsKey)
        }
        userDefaults.removeObject(forKey: legacyUserDefaultsKey)
    }

    static func isRestorable(startTime: Date, now: Date = Date()) -> Bool {
        let elapsed = now.timeIntervalSince(startTime)
        return elapsed >= 0 && elapsed <= maximumRestorableDuration
    }

    func formattedTime() -> String {
        let hours = Int(totalTimeElapsed) / 3600
        let minutes = (Int(totalTimeElapsed) % 3600) / 60
        let seconds = Int(totalTimeElapsed) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WorkoutRestCompletion: Equatable {
    enum Outcome: Equatable { case elapsed, skipped, shortened, unavailable }
    let id: UUID
    let outcome: Outcome
    let wasRecovered: Bool
}

@MainActor
class RestTimer: ObservableObject {
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var state: WorkoutRestState?
    @Published private(set) var isRecovered = false
    @Published private(set) var completion: WorkoutRestCompletion?
    @Published private(set) var errorMessage: String?
    private var timer: Timer?
    private let skipStore: WorkoutRestSkipStore
    private let currentDate: () -> Date
    // Completion callbacks are synchronous in the player. Retain their accepted
    // identities even after expiry/Skip so a repeated callback cannot restart rest.
    // A deliberate Reopen/Undo resets only that set's identity.
    private var automaticallyRestedSetIDs: Set<String> = []

    var deadline: Date? { state?.deadline }

    init(skipStore: WorkoutRestSkipStore = WorkoutRestSkipStore(), currentDate: @escaping () -> Date = Date.init) {
        self.skipStore = skipStore
        self.currentDate = currentDate
    }

    deinit { timer?.invalidate() }

    func start(duration: TimeInterval, routineName: String, exerciseID: String? = nil, setID: String? = nil) {
        refresh()
        guard state == nil,
              let rest = WorkoutRestState(duration: duration, routineName: routineName,
                                          exerciseID: exerciseID, setID: setID, now: currentDate()) else { return }
        apply(rest, recovered: false)
    }

    /// A newly completed set owns its full rest, even if the person started the
    /// next set before the previous countdown ended. Zero is an intentional group
    /// transition without rest and durably ends the preceding countdown. Manual
    /// Start remains a no-op while another rest is active.
    func startAfterCompletedSet(duration: TimeInterval, routineName: String, exerciseID: String, setID: String) {
        refresh()
        let now = currentDate()
        guard !setID.isEmpty, !automaticallyRestedSetIDs.contains(setID),
              duration.isFinite, duration >= 0, duration <= WorkoutRestState.maximumDuration,
              now.timeIntervalSinceReferenceDate.isFinite else { return }
        let next: WorkoutRestState?
        if duration > 0 {
            guard let rest = WorkoutRestState(duration: duration, routineName: routineName,
                                              exerciseID: exerciseID, setID: setID, now: now) else { return }
            next = rest
        } else {
            next = nil
        }
        let previous = state
        if let previous {
            guard previous.setID != setID, recordEnd(previous) else { return }
        }
        automaticallyRestedSetIDs.insert(setID)
        if let next {
            apply(next, recovered: false)
        } else {
            // No new timer or completed-rest receipt is invented for a zero-rest
            // transition. Replaying this set cannot cancel the next member's rest.
            clearUpdates()
            state = nil
            isRecovered = false
            completion = nil
            errorMessage = nil
            if let previous { LiveActivityManager.shared.endRestTimer(restID: previous.id) }
        }
    }

    /// Correcting a set is independent of cancelling its rest. If the rest receipt
    /// fails, leave that timer running with its visible error rather than claiming
    /// cancellation. Other sets' countdowns and duplicate guards are untouched.
    @discardableResult
    func cancelRestForReopenedSet(_ setID: String) -> Bool {
        if let rest = state, rest.setID == setID {
            guard recordEnd(rest) else { return false }
            clearUpdates()
            state = nil
            isRecovered = false
            completion = nil
            errorMessage = nil
            LiveActivityManager.shared.endRestTimer(restID: rest.id)
        }
        automaticallyRestedSetIDs.remove(setID)
        return true
    }

    /// Uses the saved deadline, never a fresh duration. A late recovery callback cannot
    /// replace a newer active rest owned by this player.
    func restore(_ rest: WorkoutRestState?, sessionID: String? = nil) {
        guard let rest else {
            stop()
            if let sessionID { LiveActivityManager.shared.endRestTimer(sessionID: sessionID) }
            return
        }
        guard state == nil || state?.id == rest.id else { return }
        if let setID = rest.setID { automaticallyRestedSetIDs.insert(setID) }
        let now = currentDate()
        if rest.remaining(at: now) == 0 {
            finish(rest, outcome: endedOutcome(for: rest, at: now), recovered: true, sessionID: sessionID)
        } else if skipStore.wasRequested(restID: rest.id, now: now) {
            finish(rest, outcome: .skipped, recovered: true, sessionID: sessionID)
        } else {
            apply(rest, recovered: state == nil || isRecovered)
        }
    }

    /// UI controls capture the identity they displayed. A stale menu action cannot
    /// shorten or extend the next set's rest.
    func adjust(by adjustment: TimeInterval, for restID: UUID) {
        guard state?.id == restID else { return }
        adjust(by: adjustment)
    }

    func adjust(by adjustment: TimeInterval) {
        guard adjustment.isFinite, adjustment != 0 else { return }
        refresh()
        guard let rest = state else { return }
        guard let adjusted = rest.adjusted(by: adjustment, at: currentDate()) else {
            guard recordEnd(rest) else { return }
            finish(rest, outcome: .shortened, recovered: isRecovered)
            return
        }
        apply(adjusted, recovered: isRecovered)
    }

    /// An explicit Skip is acknowledged only after its exact-rest tombstone is durable.
    /// Lifecycle cleanup can still use stop() after its session draft was removed.
    func skip(restID: UUID) {
        guard state?.id == restID else { return }
        refresh()
        guard let rest = state, rest.id == restID, recordEnd(rest) else { return }
        finish(rest, outcome: .skipped, recovered: isRecovered)
    }

    func dismissCompletion() { completion = nil }

    /// Leaving the player stops UI ticks, while its account-scoped draft retains the deadline.
    func suspendUpdates() {
        refresh()
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let state else { return }
        let now = currentDate()
        if skipStore.wasRequested(restID: state.id, now: now) {
            finish(state, outcome: .skipped, recovered: isRecovered)
            return
        }
        timeRemaining = state.remaining(at: now)
        if timeRemaining == 0 {
            finish(state, outcome: endedOutcome(for: state, at: now), recovered: isRecovered)
        } else {
            // Foreground refresh also resumes UI ticks after a covered/left player
            // suspended them. The saved wall-clock deadline never changes.
            scheduleUpdates()
        }
    }

    func stop() {
        let identity = state?.id
        if let identity { skipStore.request(restID: identity, now: currentDate()) }
        clearUpdates()
        state = nil
        isRecovered = false
        completion = nil
        errorMessage = nil
        if let identity { LiveActivityManager.shared.endRestTimer(restID: identity) }
    }

    private func apply(_ rest: WorkoutRestState, recovered: Bool) {
        let didChange = state != rest
        timeRemaining = rest.remaining(at: currentDate())
        isRecovered = recovered
        completion = nil
        errorMessage = nil
        if didChange {
            state = rest
            LiveActivityManager.shared.startRestTimer(endingAt: rest.deadline, restID: rest.id)
        }
        scheduleUpdates()
    }

    private func recordEnd(_ rest: WorkoutRestState) -> Bool {
        guard skipStore.request(restID: rest.id, now: currentDate()) else {
            errorMessage = "The rest change couldn't be saved. Your timer is still running; try again."
            return false
        }
        return true
    }

    private func finish(_ rest: WorkoutRestState, outcome: WorkoutRestCompletion.Outcome, recovered: Bool, sessionID: String? = nil) {
        // Expired time cannot restart even if storage is unavailable. For an explicit
        // Skip/shorten action recordEnd has already required a durable receipt.
        if !skipStore.wasRequested(restID: rest.id, now: currentDate()) {
            _ = skipStore.request(restID: rest.id, now: currentDate())
        }
        clearUpdates()
        state = nil
        isRecovered = false
        errorMessage = nil
        completion = WorkoutRestCompletion(id: rest.id, outcome: outcome, wasRecovered: recovered)
        LiveActivityManager.shared.endRestTimer(restID: rest.id, sessionID: sessionID)
    }

    private func endedOutcome(for rest: WorkoutRestState, at now: Date) -> WorkoutRestCompletion.Outcome {
        let duration = rest.deadline.timeIntervalSince(rest.startedAt)
        guard duration.isFinite, duration > 0, duration <= WorkoutRestState.maximumDuration,
              now.timeIntervalSinceReferenceDate.isFinite, now >= rest.deadline else { return .unavailable }
        return .elapsed
    }

    private func clearUpdates() {
        timer?.invalidate()
        timer = nil
        timeRemaining = 0
    }

    private func scheduleUpdates() {
        guard timer == nil else { return }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.receiveScheduledTick() }
        }
        timer = ticker
        // Keep the displayed countdown moving while the user scrolls the workout
        // or adjusts a field. The deadline remains authoritative in every mode.
        RunLoop.main.add(ticker, forMode: .common)
    }

    /// A Timer may already have enqueued its actor hop when the player suspends.
    /// Only an explicit foreground refresh may reactivate a suspended ticker.
    func receiveScheduledTick() {
        guard timer != nil else { return }
        refresh()
    }

    func formattedTime() -> String {
        let remainingSeconds = Int(ceil(timeRemaining))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}
