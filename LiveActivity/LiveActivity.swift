#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import MyFitPlateCore

struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // 1. Lock Screen UI
            VStack {
                HStack {
                    Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                        .foregroundColor(context.state.isResting ? .yellow : .blue)
                    Text(context.state.isResting ? "Rest Timer" : "Working Out")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }

                HStack(alignment: .bottom) {
                    Text(context.attributes.routineName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    if context.state.isResting, let endTime = context.state.restEndTime {
                        // This automatically counts down
                        Text(timerInterval: Date()...endTime, countsDown: true)
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.yellow)
                    } else {
                        // This automatically counts up
                        Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.blue)
                    }
                }

                if context.state.isResting {
                    HStack {
                        Spacer()
                        Button(intent: EndRestIntent()) {
                            Text("Skip Rest")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundColor(.yellow)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
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
                        Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                            .font(.title)
                            .foregroundColor(context.state.isResting ? .yellow : .blue)
                        Text(context.state.isResting ? "Resting" : "Active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting, let endTime = context.state.restEndTime {
                        Text(timerInterval: Date()...endTime, countsDown: true)
                            .font(.largeTitle)
                            .monospacedDigit()
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                            .font(.largeTitle)
                            .monospacedDigit()
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.trailing)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.routineName)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isResting {
                        HStack {
                            Spacer()
                            Button(intent: EndRestIntent()) {
                                Text("Skip Rest")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.yellow.opacity(0.2))
                                    .foregroundColor(.yellow)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                }

            } compactLeading: {
                // Collapsed (Left)
                Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundColor(context.state.isResting ? .yellow : .blue)
            } compactTrailing: {
                // Collapsed (Right)
                if context.state.isResting, let endTime = context.state.restEndTime {
                    Text(timerInterval: Date()...endTime, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundColor(.yellow)
                } else {
                    Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundColor(.blue)
                }
            } minimal: {
                // Minimal (When multiple activities are active)
                Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundColor(context.state.isResting ? .yellow : .blue)
            }
        }
    }
}

#endif
