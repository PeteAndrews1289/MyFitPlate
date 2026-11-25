#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents
import MyFitPlateShared

struct FastingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            // 1. Lock Screen UI
            VStack {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(LiveActivityPalette.caution)
                    Text("Fasting")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(context.attributes.fastType)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text("Elapsed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timerInterval: context.state.startTime...Date().addingTimeInterval(86400 * 7), countsDown: false)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityPalette.caution)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timerInterval: context.state.startTime...max(context.state.startTime, context.state.targetEndTime), countsDown: true)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }

                HStack {
                    Spacer()
                    Button(intent: EndFastIntent(sessionID: context.attributes.sessionID, ownerScope: context.attributes.ownerScope, revision: context.state.revision)) {
                        Text("End fast")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(LiveActivityPalette.caution.opacity(0.2))
                            .foregroundStyle(LiveActivityPalette.caution)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)

            .widgetURL(MyFitPlateLinks.ActivityDestination.fast.url(sessionID: context.attributes.sessionID?.uuidString))
        } dynamicIsland: { context in
            // 2. Dynamic Island UI
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "flame.fill").foregroundStyle(LiveActivityPalette.caution)
                            Text("Fasting").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startTime...max(context.state.startTime, context.state.targetEndTime), countsDown: true)
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundStyle(LiveActivityPalette.caution)
                        .multilineTextAlignment(.trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Button(intent: EndFastIntent(sessionID: context.attributes.sessionID, ownerScope: context.attributes.ownerScope, revision: context.state.revision)) {
                            Text("End fast")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(LiveActivityPalette.caution.opacity(0.2))
                                .foregroundStyle(LiveActivityPalette.caution)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }

            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(LiveActivityPalette.caution)
            } compactTrailing: {
                Text(timerInterval: context.state.startTime...max(context.state.startTime, context.state.targetEndTime), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 45)
                    .foregroundStyle(LiveActivityPalette.caution)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(LiveActivityPalette.caution)
            }
            .widgetURL(MyFitPlateLinks.ActivityDestination.fast.url(sessionID: context.attributes.sessionID?.uuidString))
        }
    }
}

#endif
