

import Foundation
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
       
        var elapsedTime: TimeInterval
        var caloriesBurned: Double
        var heartRate: Double
    }

  
    var workoutName: String
}
