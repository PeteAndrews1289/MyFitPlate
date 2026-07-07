#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

struct RunActivityWidget: Widget {
    private let brandGreen = Color(red: 0.263, green: 0.678, blue: 0.435)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            // Lock screen
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundColor(brandGreen)
                    Text(context.state.workoutStepText ?? (context.state.isPaused ? "Run paused" : "Running"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.paceText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                if let target = context.state.workoutTargetText {
                    Text(target)
                        .font(.caption)
                        .foregroundColor(brandGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.distanceText)
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(brandGreen)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if context.state.isPaused {
                            Text(context.state.elapsedText)
                                .font(.system(size: 24, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        } else {
                            Text(timerInterval: context.state.startTime...Date().addingTimeInterval(86400), countsDown: false)
                                .font(.system(size: 24, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .frame(maxWidth: 90)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .foregroundColor(brandGreen)
                        Text(context.state.distanceText)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.paceText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let step = context.state.workoutStepText {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if let target = context.state.workoutTargetText {
                                Text(target)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else if context.state.isPaused {
                        Text("Paused · \(context.state.elapsedText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(timerInterval: context.state.startTime...Date().addingTimeInterval(86400), countsDown: false)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundColor(brandGreen)
            } compactTrailing: {
                Text(context.state.distanceText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundColor(brandGreen)
            }
        }
    }
}
#endif
