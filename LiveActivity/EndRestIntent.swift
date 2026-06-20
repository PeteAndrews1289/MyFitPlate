import AppIntents
import ActivityKit

struct EndRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Rest"
    static var description = IntentDescription("Skip the rest timer and continue the workout.")
    
    // Empty init is required
    init() {}
    
    func perform() async throws -> some IntentResult {
        // Find the active workout live activity
        if let activity = Activity<WorkoutAttributes>.activities.first {
            // Update the state to indicate rest is over
            var newState = activity.content.state
            newState.restEndTime = Date() // Set to now
            
            let updatedContent = ActivityContent(state: newState, staleDate: nil)
            await activity.update(updatedContent)
        }
        
        return .result()
    }
}
