import ActivityKit
import WidgetKit 
import SwiftUI

struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // 1. Lock Screen UI
            VStack {
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.yellow)
                    Text("Rest Timer")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                
                HStack(alignment: .bottom) {
                    Text(context.attributes.routineName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // This automatically counts down
                    Text(timerInterval: Date()...context.state.restEndTime, countsDown: true)
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.yellow)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            // 2. Dynamic Island UI
            DynamicIsland {
                // Expanded UI (When you long press the island)
                DynamicIslandExpandedRegion(.leading) {
                    VStack {
                        Image(systemName: "timer")
                            .font(.title)
                            .foregroundColor(.yellow)
                        Text("Resting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.restEndTime, countsDown: true)
                        .font(.largeTitle)
                        .monospacedDigit()
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.trailing)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.routineName)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    // Optional: Add a button here to skip rest if you want to add AppIntents later
                }
                
            } compactLeading: {
                // Collapsed (Left)
                Image(systemName: "timer")
                    .foregroundColor(.yellow)
            } compactTrailing: {
                // Collapsed (Right)
                Text(timerInterval: Date()...context.state.restEndTime, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 40)
                    .foregroundColor(.yellow)
            } minimal: {
                // Minimal (When multiple activities are active)
                Image(systemName: "timer")
                    .foregroundColor(.yellow)
            }
        }
    }
}
