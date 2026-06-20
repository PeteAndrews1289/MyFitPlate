

import Foundation
import ActivityKit

class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<WorkoutAttributes>?

    private init() {}

    func startWorkout(routineName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WorkoutAttributes(routineName: routineName)
        let contentState = WorkoutAttributes.ContentState(restEndTime: nil, isResting: false, workoutStartTime: Date())

        do {
            let activity = try Activity<WorkoutAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            self.activity = activity
            AppLog.liveActivity.debug("Live Activity started for workout: \(activity.id, privacy: .public)")
        } catch {
            AppLog.liveActivity.error("Error starting Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startRestTimer(duration: TimeInterval) {
        guard let activity = activity else { return }
        let endTime = Date().addingTimeInterval(duration)
        var newState = activity.content.state
        newState.isResting = true
        newState.restEndTime = endTime

        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    func endRestTimer() {
        guard let activity = activity else { return }
        var newState = activity.content.state
        newState.isResting = false
        newState.restEndTime = nil

        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    func endActivity() {
        guard let activity = activity else { return }

        let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)

        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self.activity = nil
            AppLog.liveActivity.debug("Live Activity ended")
        }
    }
}
