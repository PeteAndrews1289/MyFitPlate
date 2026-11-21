#if os(iOS)



import Foundation
import ActivityKit
import MyFitPlateShared

@MainActor
public class LiveActivityManager {
    public static let shared = LiveActivityManager()

    private var activity: Activity<WorkoutAttributes>?
    private var activeRestID: UUID?
    private var activeRestDeadline: Date?
    private var workoutStartTime: Date?
    private var retiringActivityIDs: Set<String> = []

    private init() {}

    public func startWorkout(routineName: String, sessionID: String? = nil, workoutStartTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activity = nil
            activeRestID = nil
            activeRestDeadline = nil
            self.workoutStartTime = nil
            retire(Activity<WorkoutAttributes>.activities.filter {
                $0.activityState == .active || $0.activityState == .stale
            })
            return
        }

        self.workoutStartTime = workoutStartTime

        let existing = Activity<WorkoutAttributes>.activities.filter {
            ($0.activityState == .active || $0.activityState == .stale) && !retiringActivityIDs.contains($0.id)
        }
        let reconciliation = WorkoutActivitySessionRules.reconcile(
            sessionID: sessionID,
            activities: existing.map { .init(id: $0.id, sessionID: $0.attributes.sessionID) }
        )
        if let id = reconciliation.reusableID,
           let restored = existing.first(where: { $0.id == id }) {
            activity = restored
            activeRestID = restored.content.state.restID
            activeRestDeadline = restored.content.state.restEndTime
            refreshWorkoutClock(on: restored)
            retire(existing.filter { reconciliation.retiredIDs.contains($0.id) })
            return
        }
        // A failed new-session request must not leave rest updates targeting the
        // previous session's Activity or leave its information visible after a switch.
        activity = nil
        activeRestID = nil
        activeRestDeadline = nil
        retire(existing)
        let attributes = WorkoutAttributes(routineName: routineName, sessionID: sessionID)
        let contentState = WorkoutAttributes.ContentState(restEndTime: nil, isResting: false, workoutStartTime: workoutStartTime)

        do {
            let activity = try Activity<WorkoutAttributes>.request(
                attributes: attributes,
                content: .init(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(8 * 60 * 60)
                ),
                pushType: nil
            )
            self.activity = activity
            activeRestID = nil
            activeRestDeadline = nil
            AppLog.liveActivity.debug("Live Activity started for workout: \(activity.id, privacy: .public)")
        } catch {
            AppLog.liveActivity.error("Error starting Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func startRestTimer(endingAt endTime: Date, restID: UUID) {
        guard let activity = activity else { return }
        activeRestID = restID
        activeRestDeadline = endTime
        var newState = activity.content.state
        newState.isResting = true
        newState.restEndTime = endTime
        newState.restID = restID
        newState.workoutStartTime = workoutStartTime ?? newState.workoutStartTime

        Task {
            guard self.activity?.id == activity.id, self.activeRestID == restID,
                  self.activeRestDeadline == endTime,
                  !WorkoutRestSkipStore().wasRequested(restID: restID) else { return }
            await activity.update(
                ActivityContent(
                    state: newState,
                    staleDate: endTime.addingTimeInterval(5 * 60)
                )
            )
        }
    }

    public func endRestTimer(restID: UUID? = nil, sessionID: String? = nil) {
        guard restID != nil || sessionID != nil else { return }
        guard let activity = activity else { return }
        if let sessionID, activity.attributes.sessionID != sessionID { return }
        if let restID, activeRestID != restID { return }
        activeRestID = nil
        activeRestDeadline = nil
        var newState = activity.content.state
        newState.isResting = false
        newState.restEndTime = nil
        newState.restID = nil
        newState.workoutStartTime = workoutStartTime ?? newState.workoutStartTime

        Task {
            guard self.activity?.id == activity.id, self.activeRestID == nil else { return }
            await activity.update(
                ActivityContent(
                    state: newState,
                    staleDate: Date().addingTimeInterval(8 * 60 * 60)
                )
            )
        }
    }

    public func endActivity(sessionID: String? = nil) {
        guard let activity = activity else { return }
        if let sessionID, activity.attributes.sessionID != sessionID { return }

        let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
        self.activity = nil
        activeRestID = nil
        activeRestDeadline = nil
        workoutStartTime = nil
        retiringActivityIDs.insert(activity.id)

        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self.retiringActivityIDs.remove(activity.id)
            AppLog.liveActivity.debug("Live Activity ended")
        }
    }

    private func refreshWorkoutClock(on restored: Activity<WorkoutAttributes>) {
        let restID = activeRestID
        let restDeadline = activeRestDeadline
        Task {
            guard self.activity?.id == restored.id, self.activeRestID == restID,
                  self.activeRestDeadline == restDeadline,
                  let workoutStartTime = self.workoutStartTime else { return }
            let content = restored.content
            // A concurrent Skip or a new rest retains its own state. Those rest
            // updates also carry the recovered workout clock.
            guard content.state.restID == restID else { return }
            var state = content.state
            state.workoutStartTime = workoutStartTime
            await restored.update(ActivityContent(state: state, staleDate: content.staleDate))
        }
    }

    private func retire(_ activities: [Activity<WorkoutAttributes>]) {
        for old in activities {
            guard retiringActivityIDs.insert(old.id).inserted else { continue }
            Task {
                await old.end(ActivityContent(state: old.content.state, staleDate: nil), dismissalPolicy: .immediate)
                self.retiringActivityIDs.remove(old.id)
            }
        }
    }
}

#endif
