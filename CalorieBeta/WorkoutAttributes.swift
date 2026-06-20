

import Foundation
import ActivityKit

public struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // The end time of the timer (dynamic data)
        var restEndTime: Date?
        // True if resting, false if currently working out
        var isResting: Bool
        // Start time of the entire workout for counting up
        var workoutStartTime: Date
    }

    // The name of the workout (static data)
    var routineName: String
}
