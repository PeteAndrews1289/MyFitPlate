import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct FastingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            // 1. Lock Screen UI
            VStack {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
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
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timerInterval: Date()...context.state.targetEndTime, countsDown: true)
                            .font(.system(size: 24, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }

                HStack {
                    Spacer()
                    Button(intent: EndFastIntent()) {
                        Text("End Fast")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            // 2. Dynamic Island UI
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "flame.fill").foregroundColor(.orange)
                            Text("Fasting").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.targetEndTime, countsDown: true)
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Button(intent: EndFastIntent()) {
                            Text("End Fast")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }

            } compactLeading: {
                Image(systemName: "flame.fill").foregroundColor(.orange)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.targetEndTime, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 45)
                    .foregroundColor(.orange)
            } minimal: {
                Image(systemName: "flame.fill").foregroundColor(.orange)
            }
        }
    }
}
