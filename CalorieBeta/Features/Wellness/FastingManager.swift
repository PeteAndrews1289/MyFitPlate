import Foundation
import ActivityKit
import MyFitPlateCore

@MainActor
public class FastingManager: ObservableObject {
    public static let shared = FastingManager()
    
    @Published public var isFasting: Bool = false
    @Published public var currentFastStartTime: Date?
    @Published public var currentFastTargetEndTime: Date?
    @Published public var fastType: String = "16:8 Fast"
    
    // Store activity ID to ensure we can track it
    private var currentActivityId: String?
    
    private init() {
        // Recover state from existing activities
        recoverState()
    }
    
    public func startFast(hours: Int) {
        guard !isFasting, (1..<24).contains(hours) else { return }
        
        let startTime = Date()
        guard let targetEndTime = Calendar.current.date(byAdding: .hour, value: hours, to: startTime) else {
            return
        }
        self.fastType = "\(hours):\(24 - hours) Fast"
        
        let attributes = FastingActivityAttributes(fastType: self.fastType)
        let contentState = FastingActivityAttributes.ContentState(startTime: startTime, targetEndTime: targetEndTime)
        let content = ActivityContent(
            state: contentState,
            staleDate: targetEndTime.addingTimeInterval(2 * 60 * 60)
        )
        
        do {
            let activity = try Activity<FastingActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            
            self.currentActivityId = activity.id
            self.currentFastStartTime = startTime
            self.currentFastTargetEndTime = targetEndTime
            self.isFasting = true
            
        } catch {
            AppLog.liveActivity.error(
                "Error starting Fasting Live Activity: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    
    public func endFast() {
        Task {
            for activity in Activity<FastingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            
            self.isFasting = false
            self.currentFastStartTime = nil
            self.currentFastTargetEndTime = nil
            self.currentActivityId = nil
        }
    }
    
    public func recoverState() {
        if let activity = Activity<FastingActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            self.isFasting = true
            self.currentFastStartTime = activity.content.state.startTime
            self.currentFastTargetEndTime = activity.content.state.targetEndTime
            self.fastType = activity.attributes.fastType
            self.currentActivityId = activity.id
        } else {
            self.isFasting = false
        }
    }
}
