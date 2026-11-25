#if canImport(ActivityKit)
import AppIntents
import ActivityKit
import Foundation
import MyFitPlateShared

struct EndRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Rest"
    static var description = IntentDescription("Skip the rest timer and continue the workout.")

    @Parameter(title: "Rest identifier")
    var restID: String?

    init() {}

    init(restID: UUID?) {
        self.restID = restID?.uuidString
    }
    
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let restID, let identity = UUID(uuidString: restID) else { return .result() }
        // The rendered button carries this rest's identity, even if the intent arrives later.
        if let activity = Activity<WorkoutAttributes>.activities.first(where: { $0.content.state.restID == identity }) {
            guard WorkoutRestSkipStore().request(restID: identity) else {
                throw NSError(domain: "MyFitPlate.RestTimer", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Open MyFitPlate to stop this rest timer."])
            }
            var newState = activity.content.state
            // Receipt I/O and ActivityKit delivery can overlap another rest update.
            // Clear only the captured rest; a newer rest keeps its visible badge.
            guard newState.restID == identity else { return .result() }
            newState.isResting = false
            newState.restEndTime = nil
            newState.restID = nil
            
            let updatedContent = ActivityContent(
                state: newState,
                staleDate: Date().addingTimeInterval(8 * 60 * 60)
            )
            await activity.update(updatedContent)
        }
        
        return .result()
    }
}

#endif
