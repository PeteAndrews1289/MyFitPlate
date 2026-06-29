#if canImport(ActivityKit)
import AppIntents
import ActivityKit

public struct EndFastIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "End Fast"
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        // End the activity
        for activity in Activity<FastingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        return .result()
    }
}
#endif
