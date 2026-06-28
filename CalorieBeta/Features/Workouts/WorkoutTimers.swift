import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import ActivityKit

class TotalWorkoutTimer: ObservableObject {
    @Published var totalTimeElapsed: TimeInterval = 0
    private var timer: Timer?
    private var startTime: Date?
    private let userDefaultsKey: String

    init(routineId: String) {
        self.userDefaultsKey = "totalWorkoutTimer_\(routineId)"
        loadTimerState()
    }

    func start() {
        guard timer == nil else { return }
        if startTime == nil {
            startTime = Date().addingTimeInterval(-totalTimeElapsed)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTotalTime()
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
        guard let startTime = startTime else { return }
        UserDefaults.standard.set(startTime, forKey: userDefaultsKey)
    }

    private func loadTimerState() {
        if let savedStartTime = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date {
            self.startTime = savedStartTime
            updateTotalTime()
            start()
        }
    }

    private func clearTimerState() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
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

