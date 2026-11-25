#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct FastingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startTime: Date
        public var targetEndTime: Date
        public var revision: Int?
        
        public init(startTime: Date, targetEndTime: Date, revision: Int? = nil) {
            self.startTime = startTime
            self.targetEndTime = targetEndTime
            self.revision = revision
        }
    }

    public var fastType: String // e.g., "16:8 Fast"
    public var sessionID: UUID?
    public var ownerScope: String?

    public init(fastType: String, sessionID: UUID? = nil, ownerScope: String? = nil) {
        self.fastType = fastType
        self.sessionID = sessionID
        self.ownerScope = ownerScope
    }
}
#endif
