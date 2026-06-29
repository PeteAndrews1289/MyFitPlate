#if os(iOS)



import Foundation
import ActivityKit

public struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var restEndTime: Date?
        public var isResting: Bool
        public var workoutStartTime: Date
        
        public init(restEndTime: Date? = nil, isResting: Bool, workoutStartTime: Date) {
            self.restEndTime = restEndTime
            self.isResting = isResting
            self.workoutStartTime = workoutStartTime
        }
    }

    public var routineName: String
    
    public init(routineName: String) {
        self.routineName = routineName
    }
}

#endif
