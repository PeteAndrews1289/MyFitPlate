import ActivityKit
import Foundation

public struct FastingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startTime: Date
        public var targetEndTime: Date
        
        public init(startTime: Date, targetEndTime: Date) {
            self.startTime = startTime
            self.targetEndTime = targetEndTime
        }
    }

    public var fastType: String // e.g., "16:8 Fast"

    public init(fastType: String) {
        self.fastType = fastType
    }
}
