#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

struct AYCEActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AYCEActivityAttributes.self) { context in
            // Lock Screen UI
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title3)
                        .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
                    Text(context.attributes.cuisineName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(context.isStale ? "Open meal to refresh" : context.state.statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.achievement)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.buffetPriceText)
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Portions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.itemsCount.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityPalette.caution)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Meal total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.currentValueText)
                            .font(.system(size: 28, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.75))
            .widgetURL(URL(string: "myfitplate://buffet"))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
                        Text(context.attributes.cuisineName)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.currentValueText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "Open meal to refresh" : context.state.statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.achievement)
                }
            } compactLeading: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
            } compactTrailing: {
                Text(context.state.currentValueText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
            } minimal: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(context.state.isBeaten ? LiveActivityPalette.brand : LiveActivityPalette.caution)
            }
            .widgetURL(URL(string: "myfitplate://buffet"))
        }
    }
}
#endif
