#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import MyFitPlateCore

enum LiveActivityPalette {
    static let brand = Color(red: 0.263, green: 0.678, blue: 0.435)
    static let effort = Color(red: 0.310, green: 0.525, blue: 0.749)
    static let recovery = Color(red: 0.290, green: 0.663, blue: 0.741)
    static let caution = Color(red: 0.878, green: 0.541, blue: 0.294)
    static let achievement = Color(red: 0.839, green: 0.659, blue: 0.243)
}

struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // 1. Lock Screen UI
            VStack {
                HStack {
                    Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                        .foregroundStyle(context.state.isResting ? LiveActivityPalette.recovery : LiveActivityPalette.effort)
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
                            .foregroundStyle(LiveActivityPalette.recovery)
                    } else {
                        // This automatically counts up
                        Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityPalette.effort)
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
                                .background(LiveActivityPalette.recovery.opacity(0.2))
                                .foregroundStyle(LiveActivityPalette.recovery)
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
                            .foregroundStyle(context.state.isResting ? LiveActivityPalette.recovery : LiveActivityPalette.effort)
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
                            .foregroundStyle(LiveActivityPalette.recovery)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                            .font(.largeTitle)
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityPalette.effort)
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
                                    .background(LiveActivityPalette.recovery.opacity(0.2))
                                    .foregroundStyle(LiveActivityPalette.recovery)
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
                    .foregroundStyle(context.state.isResting ? LiveActivityPalette.recovery : LiveActivityPalette.effort)
            } compactTrailing: {
                // Collapsed (Right)
                if context.state.isResting, let endTime = context.state.restEndTime {
                    Text(timerInterval: Date()...endTime, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundStyle(LiveActivityPalette.recovery)
                } else {
                    Text(timerInterval: context.state.workoutStartTime...Date().addingTimeInterval(86400), countsDown: false)
                        .monospacedDigit()
                        .frame(width: 40)
                        .foregroundStyle(LiveActivityPalette.effort)
                }
            } minimal: {
                // Minimal (When multiple activities are active)
                Image(systemName: context.state.isResting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(context.state.isResting ? LiveActivityPalette.recovery : LiveActivityPalette.effort)
            }
        }
    }
}

#endif
