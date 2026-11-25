#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import MyFitPlateShared

struct RunActivityWidget: Widget {
    private let brandGreen = Color(red: 0.263, green: 0.678, blue: 0.435)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            let stale = context.isStale || !RunActivityTimerRules.isFresh(reportedAt: context.state.reportedAt)
            // Lock screen
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundColor(brandGreen)
                    Text(heading(for: context.state, stale: stale))
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(stale ? "Pace unavailable" : context.state.paceText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                if !stale, let target = context.state.workoutTargetText {
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
                        Text(stale ? "Last reported active" : context.state.isPaused ? "Paused active time" : "Active estimate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        elapsedText(for: context.state, stale: stale)
                            .font(.system(size: 24, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .frame(minWidth: 100, maxWidth: 128)
                            .multilineTextAlignment(.trailing)
                    }
                }

                reportCaption(for: context.state)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))

            .widgetURL(MyFitPlateLinks.ActivityDestination.run.url(sessionID: context.attributes.recordingID))
        } dynamicIsland: { context in
            let stale = context.isStale || !RunActivityTimerRules.isFresh(reportedAt: context.state.reportedAt)
            return DynamicIsland {
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
                    Text(stale ? "Pace unavailable" : context.state.paceText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !stale, let step = context.state.workoutStepText {
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
                    } else if context.state.isPaused || stale {
                        Text("\(stale ? "Last reported active" : "Paused") · \(context.state.elapsedText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 2) {
                            elapsedText(for: context.state, stale: false)
                                .font(.caption)
                                .monospacedDigit()
                            reportCaption(for: context.state)
                        }
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
            .widgetURL(MyFitPlateLinks.ActivityDestination.run.url(sessionID: context.attributes.recordingID))
        }
    }

    private func heading(for state: RunActivityAttributes.ContentState, stale: Bool) -> String {
        if stale { return "Check recording in app" }
        return state.workoutStepText ?? (state.isPaused ? "Run paused" : "Run recording")
    }

    private func elapsedText(for state: RunActivityAttributes.ContentState, stale: Bool) -> Text {
        guard !state.isPaused, !stale,
              let interval = RunActivityTimerRules.elapsedInterval(startTime: state.startTime, reportedAt: state.reportedAt) else {
            return Text(state.elapsedText)
        }
        // Both the interval and pauseTime have a fixed cutoff carried by this
        // snapshot. OS stale-context delivery may arrive minutes after process death.
        return Text(timerInterval: interval, pauseTime: interval.upperBound, countsDown: false)
    }

    private func reportCaption(for state: RunActivityAttributes.ContentState) -> some View {
        HStack(spacing: 8) {
            Text("Last reported \(state.elapsedText)")
            Spacer(minLength: 0)
            if let reportedAt = state.reportedAt {
                Text("Updated ") + Text(reportedAt, style: .relative)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
}
#endif
