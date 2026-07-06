#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

struct AYCEActivityWidget: Widget {
    private let brandOrange = Color(red: 0.95, green: 0.45, blue: 0.2)
    private let brandGreen = Color(red: 0.26, green: 0.80, blue: 0.45)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AYCEActivityAttributes.self) { context in
            // Lock Screen UI
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title3)
                        .foregroundColor(context.state.isBeaten ? brandGreen : brandOrange)
                    Text(context.attributes.cuisineName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(context.state.statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(context.state.isBeaten ? brandGreen : .yellow)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buffet Price")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.buffetPriceText)
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 2) {
                        Text("Plates/Items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(context.state.itemsCount)")
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(brandOrange)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Current Value")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(context.state.currentValueText)
                            .font(.system(size: 28, weight: .heavy))
                            .monospacedDigit()
                            .foregroundColor(context.state.isBeaten ? brandGreen : .orange)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.75))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "fork.knife")
                            .foregroundColor(context.state.isBeaten ? brandGreen : brandOrange)
                        Text(context.attributes.cuisineName)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.currentValueText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundColor(context.state.isBeaten ? brandGreen : .orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(context.state.isBeaten ? brandGreen : .yellow)
                }
            } compactLeading: {
                Image(systemName: "fork.knife")
                    .foregroundColor(context.state.isBeaten ? brandGreen : brandOrange)
            } compactTrailing: {
                Text(context.state.currentValueText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(context.state.isBeaten ? brandGreen : .orange)
            } minimal: {
                Image(systemName: "fork.knife")
                    .foregroundColor(context.state.isBeaten ? brandGreen : brandOrange)
            }
        }
    }
}
#endif
