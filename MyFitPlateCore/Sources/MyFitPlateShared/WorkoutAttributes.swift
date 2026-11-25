#if os(iOS)



import Foundation
import ActivityKit

public struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var restEndTime: Date?
        public var isResting: Bool
        public var workoutStartTime: Date
        public var restID: UUID?
        
        public init(restEndTime: Date? = nil, isResting: Bool, workoutStartTime: Date, restID: UUID? = nil) {
            self.restEndTime = restEndTime
            self.isResting = isResting
            self.workoutStartTime = workoutStartTime
            self.restID = restID
        }
    }

    public var routineName: String
    public var sessionID: String?
    
    public init(routineName: String, sessionID: String? = nil) {
        self.routineName = routineName
        self.sessionID = sessionID
    }
}

#endif
