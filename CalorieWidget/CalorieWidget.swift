import WidgetKit
import AppIntents
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: .previewData)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), data: .previewData)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let data = SharedDataManager.shared.loadData()
        let entry = SimpleEntry(date: Date(), data: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

private enum WidgetPalette {
    // Tuned palette (DESIGN.md 2a) — must stay in sync with the app's colorsets.
    static let brandPrimary = Color(red: 0.263, green: 0.678, blue: 0.435)
    static let accentProtein = Color(red: 0.310, green: 0.525, blue: 0.749)
    static let accentCarbs = Color(red: 0.839, green: 0.659, blue: 0.243)
    static let accentFats = Color(red: 0.588, green: 0.427, blue: 0.675)
    static let accentWater = Color(red: 0.290, green: 0.663, blue: 0.741)
    static let accentSignal = Color(red: 0.878, green: 0.541, blue: 0.294)

#if os(iOS)
    static let backgroundPrimary = Color(uiColor: .systemBackground)
#else
    static let backgroundPrimary = Color.black
#endif
}

struct CalorieWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var homeURL: URL {
        URL(string: "myfitplate://home")!
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                AccessoryCircularCaloriesView(data: entry.data)
            case .accessoryRectangular:
                AccessoryRectangularCaloriesView(data: entry.data)
            case .accessoryInline:
                AccessoryInlineCaloriesView(data: entry.data)
            case .systemSmall:
                if let data = entry.data { SmallWidgetView(data: data) } else { emptyInvite }
            case .systemLarge:
                if let data = entry.data { LargeWidgetView(data: data) } else { emptyInvite }
            default:
                if let data = entry.data { MediumWidgetView(data: data) } else { emptyInvite }
            }
        }
        .widgetURL(homeURL)
        .containerBackground(for: .widget) {
            if isAccessory {
                AccessoryWidgetBackground()
            } else {
                ZStack {
                    Rectangle().fill(.thickMaterial)
                    WidgetPalette.backgroundPrimary.opacity(0.2)
                }
            }
        }
    }

    private var emptyInvite: some View {
        VStack(alignment: .center, spacing: 5) {
            Text("MyFitPlate")
                .font(.headline)
            Text("Log a meal to see your day here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }.padding()
    }
}

// Lock screen + watch complications. The system renders these vibrant or tinted,
// so layout carries the meaning — the brand tint is a bonus where it survives.
struct AccessoryCircularCaloriesView: View {
    let data: WidgetData?

    var body: some View {
        if let data, data.calorieGoal > 0 {
            Gauge(value: min(data.calories, data.calorieGoal), in: 0...data.calorieGoal) {
                Text("cal")
            } currentValueLabel: {
                Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted())")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(WidgetPalette.brandPrimary)
        } else {
            VStack(spacing: 1) {
                Image(systemName: "fork.knife")
                Text("Log")
                    .font(.caption2)
            }
        }
    }
}

struct AccessoryRectangularCaloriesView: View {
    let data: WidgetData?

    var body: some View {
        if let data, data.calorieGoal > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted()) cal left")
                    .font(.headline)
                    .widgetAccentable()
                Gauge(value: min(data.calories, data.calorieGoal), in: 0...data.calorieGoal) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(WidgetPalette.brandPrimary)
                Text("P \(Int(data.protein))g · C \(Int(data.carbs))g · F \(Int(data.fats))g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("MyFitPlate")
                    .font(.headline)
                Text("Log a meal to see your day here.")
                    .font(.caption2)
            }
        }
    }
}

struct AccessoryInlineCaloriesView: View {
    let data: WidgetData?

    var body: some View {
        if let data, data.calorieGoal > 0 {
            Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted()) cal left")
        } else {
            Text("MyFitPlate — log a meal")
        }
    }
}

struct CalorieWidget: Widget {
    let kind: String = "CalorieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CalorieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Summary")
        .description("Track your daily calories and macros.")
#if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
#else
        .supportedFamilies([.systemLarge, .systemMedium, .systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
#endif
    }
}

@main
struct CalorieWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalorieWidget()
    }
}

struct MediumWidgetView: View {
    let data: WidgetData
    private var hasMacroWarning: Bool {
        abs(data.macroCalorieDelta ?? 0) >= 75
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text("Remaining")
                    .font(.caption2)
                Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted())")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(WidgetPalette.brandPrimary)
                Text("cal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 5)

            VStack(alignment: .leading, spacing: 8) {
                MacroBar(label: "Protein", value: data.protein, goal: data.proteinGoal, color: WidgetPalette.accentProtein)
                MacroBar(label: "Carbs", value: data.carbs, goal: data.carbsGoal, color: WidgetPalette.accentCarbs)
                MacroBar(label: "Fats", value: data.fats, goal: data.fatGoal, color: WidgetPalette.accentFats)

                HStack {
                    if hasMacroWarning {
                        Label("Check macros", systemImage: "info.circle.fill")
                            .font(.caption2)
                            .foregroundColor(WidgetPalette.accentSignal)
                    }

                    Spacer()

                    Button(intent: LogWaterIntent()) {
                        Image(systemName: "drop.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(WidgetPalette.accentWater)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
    }
}

struct SmallWidgetView: View {
    let data: WidgetData
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 8) {
                MiniProgressBubble(
                    value: data.calories, goal: data.calorieGoal,
                    percentage: data.calorieGoal > 0 ? (data.calories / data.calorieGoal) : 0,
                    label: "Calories", color: WidgetPalette.brandPrimary
                )
                MiniProgressBubble(
                    value: data.protein, goal: data.proteinGoal,
                    percentage: data.proteinGoal > 0 ? (data.protein / data.proteinGoal) : 0,
                    label: "Protein", color: WidgetPalette.accentProtein
                )
                MiniProgressBubble(
                    value: data.fats, goal: data.fatGoal,
                    percentage: data.fatGoal > 0 ? (data.fats / data.fatGoal) : 0,
                    label: "Fats", color: WidgetPalette.accentFats
                )
                MiniProgressBubble(
                    value: data.carbs, goal: data.carbsGoal,
                    percentage: data.carbsGoal > 0 ? (data.carbs / data.carbsGoal) : 0,
                    label: "Carbs", color: WidgetPalette.accentCarbs
                )
            }
        }
        .padding(8)
    }
}

struct LargeWidgetView: View {
    let data: WidgetData
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 20) {
                ProgressBubble(
                    value: data.calories, goal: data.calorieGoal,
                    percentage: data.calorieGoal > 0 ? (data.calories / data.calorieGoal) : 0,
                    label: "Calories", unit: "cal", color: WidgetPalette.brandPrimary
                )
                ProgressBubble(
                    value: data.protein, goal: data.proteinGoal,
                    percentage: data.proteinGoal > 0 ? (data.protein / data.proteinGoal) : 0,
                    label: "Protein", unit: "g", color: WidgetPalette.accentProtein
                )
                ProgressBubble(
                    value: data.fats, goal: data.fatGoal,
                    percentage: data.fatGoal > 0 ? (data.fats / data.fatGoal) : 0,
                    label: "Fats", unit: "g", color: WidgetPalette.accentFats
                )
                ProgressBubble(
                    value: data.carbs, goal: data.carbsGoal,
                    percentage: data.carbsGoal > 0 ? (data.carbs / data.carbsGoal) : 0,
                    label: "Carbs", unit: "g", color: WidgetPalette.accentCarbs
                )
            }

            if let delta = data.macroCalorieDelta, abs(delta) >= 75 {
                Text("Macros imply \(Int(abs(delta).rounded())) cal \(delta > 0 ? "more" : "less").")
                    .font(.caption2)
                    .foregroundColor(WidgetPalette.accentSignal)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}

struct MiniProgressBubble: View {
    let value: Double
    let goal: Double
    let percentage: Double
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(lineWidth: 5).opacity(0.2).foregroundColor(color)
                Circle().trim(from: 0, to: CGFloat(percentage)).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)).foregroundColor(color).rotationEffect(.degrees(-90))
                VStack {
                    Text("\(Int(value).formatted())")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).bold()
                Spacer()
                Text("\(Int(value)) / \(Int(goal))g").font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
        }
    }
}

struct ProgressBubble: View {
    let value: Double
    let goal: Double
    let percentage: Double
    let label: String
    let unit: String
    let color: Color

    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.2).foregroundColor(color)
                Circle().trim(from: 0, to: CGFloat(percentage)).stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)).foregroundColor(color).rotationEffect(.degrees(-90))
                VStack {
                    Text("\(Int(value).formatted())")
                        .font(.body.weight(.medium))
                    Text("/ \(Int(goal).formatted()) \(unit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text(label).font(.caption).bold()
        }
    }
}
