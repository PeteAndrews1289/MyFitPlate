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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTotalTime()
            }
        }
        saveTimerState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        totalTimeElapsed = 0
        clearTimerState()
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

class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    private var timer: Timer?
    private var endTime: Date?

    // Starts the timer AND the Live Activity
    func start(duration: TimeInterval, routineName: String) {
        guard timeRemaining == 0 else { return }
        self.timeRemaining = duration
        self.endTime = Date().addingTimeInterval(duration)

        // Update Live Activity on Lock Screen
        LiveActivityManager.shared.startRestTimer(duration: duration)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    // Stops the timer AND removes the Live Activity
    func stop() {
        timer?.invalidate()
        timer = nil
        endTime = nil
        timeRemaining = 0

        // End Rest state on Live Activity
        LiveActivityManager.shared.endRestTimer()
    }

    private func updateTimer() {
        guard let endTime = endTime else {
            stop()
            return
        }

        let remaining = endTime.timeIntervalSinceNow
        self.timeRemaining = max(0, remaining)

        if self.timeRemaining == 0 {
            stop()
        }
    }

    func formattedTime() -> String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}
