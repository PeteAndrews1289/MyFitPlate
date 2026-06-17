

import Foundation
import ActivityKit

public struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // The end time of the timer (dynamic data)
        var restEndTime: Date
    }

    // The name of the workout (static data)
    var routineName: String
}
