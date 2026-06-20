

import Foundation
import ActivityKit

class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private var activity: Activity<WorkoutAttributes>?
    
    private init() {}
    
    func startRestTimer(routineName: String, duration: TimeInterval) {
        // Verify Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let endTime = Date().addingTimeInterval(duration)
        let attributes = WorkoutAttributes(routineName: routineName)
        let contentState = WorkoutAttributes.ContentState(restEndTime: endTime)
        
        do {
            let activity = try Activity<WorkoutAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            self.activity = activity
            AppLog.liveActivity.debug("Live Activity started: \(activity.id, privacy: .public)")
        } catch {
            AppLog.liveActivity.error("Error starting Live Activity: \(error.localizedDescription, privacy: .public)")
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
