import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: .previewData)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), data: .previewData)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let data = SharedDataManager.shared.loadData()
        let entry = SimpleEntry(date: Date(), data: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

struct CalorieWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var homeURL: URL {
        URL(string: "myfitplate://home")!
    }

    @ViewBuilder
    var body: some View {
        VStack {
            if let data = entry.data {
                switch family {
                case .systemSmall:
                    SmallWidgetView(data: data)
                case .systemLarge:
                    LargeWidgetView(data: data)
                default:
                    MediumWidgetView(data: data)
                }
            } else {
                VStack(alignment: .center, spacing: 5) {
                    Text("MyFitPlate")
                        .font(.headline)
                    Text("Log a meal to see your stats here!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }.padding()
            }
        }
        .widgetURL(homeURL)
        .containerBackground(for: .widget) {
            ZStack {
                Rectangle().fill(.thickMaterial)
                Color.black.opacity(0.2)
            }
        }
    }
}

@main
struct CalorieWidget: Widget {
    let kind: String = "CalorieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CalorieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Summary")
        .description("Track your daily calories and macros.")
        .supportedFamilies([.systemLarge, .systemMedium, .systemSmall])
    }
}

struct MediumWidgetView: View {
    let data: WidgetData

    var body: some View {
        HStack(spacing: 20) {
            VStack {
                Text("Remaining")
                    .font(.caption2)
                Text(String(format: "%.0f", max(0, data.calorieGoal - data.calories)))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                Text("kcal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 5)

            VStack(alignment: .leading, spacing: 8) {
                MacroBar(label: "Protein", value: data.protein, goal: data.proteinGoal, color: .blue)
                MacroBar(label: "Carbs", value: data.carbs, goal: data.carbsGoal, color: .orange)
                MacroBar(label: "Fats", value: data.fats, goal: data.fatGoal, color: .green)
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
                    label: "Calories", color: .red
                )
                MiniProgressBubble(
                    value: data.protein, goal: data.proteinGoal,
                    percentage: data.proteinGoal > 0 ? (data.protein / data.proteinGoal) : 0,
                    label: "Protein", color: .blue
                )
                MiniProgressBubble(
                    value: data.fats, goal: data.fatGoal,
                    percentage: data.fatGoal > 0 ? (data.fats / data.fatGoal) : 0,
                    label: "Fats", color: .green
                )
                MiniProgressBubble(
                    value: data.carbs, goal: data.carbsGoal,
                    percentage: data.carbsGoal > 0 ? (data.carbs / data.carbsGoal) : 0,
                    label: "Carbs", color: .orange
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
        VStack {
            LazyVGrid(columns: columns, spacing: 20) {
                ProgressBubble(
                    value: data.calories, goal: data.calorieGoal,
                    percentage: data.calorieGoal > 0 ? (data.calories / data.calorieGoal) : 0,
                    label: "Calories", unit: "cal", color: .red
                )
                ProgressBubble(
                    value: data.protein, goal: data.proteinGoal,
                    percentage: data.proteinGoal > 0 ? (data.protein / data.proteinGoal) : 0,
                    label: "Protein", unit: "g", color: .blue
                )
                ProgressBubble(
                    value: data.fats, goal: data.fatGoal,
                    percentage: data.fatGoal > 0 ? (data.fats / data.fatGoal) : 0,
                    label: "Fats", unit: "g", color: .green
                )
                ProgressBubble(
                    value: data.carbs, goal: data.carbsGoal,
                    percentage: data.carbsGoal > 0 ? (data.carbs / data.carbsGoal) : 0,
                    label: "Carbs", unit: "g", color: .orange
                )
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
                    Text("\(String(format: "%.0f", value))")
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.2).foregroundColor(color)
                Circle().trim(from: 0, to: CGFloat(percentage)).stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)).foregroundColor(color).rotationEffect(.degrees(-90))
                VStack {
                    Text("\(String(format: "%.0f", value))")
                        .font(.body.weight(.medium))
                    Text("/ \(String(format: "%.0f", goal)) \(unit)")
                         .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Text(label).font(.caption).bold()
        }
    }
}
