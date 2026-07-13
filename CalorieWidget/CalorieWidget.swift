import WidgetKit
import AppIntents
import SwiftUI
import MyFitPlateCore

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

    private var destinationURL: URL {
        guard family != .accessoryCircular,
              let deepLink = entry.data?.nextAction?.deepLink,
              let url = URL(string: deepLink) else { return homeURL }
        return url
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
        .widgetURL(destinationURL)
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
            if let action = data.nextAction {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    Text(action.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted()) cal left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
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
        if let action = data?.nextAction {
            Text("MyFitPlate: \(action.title)")
        } else if let data, data.calorieGoal > 0 {
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
        .description("See your daily totals and the next useful action.")
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

    private var pathEvents: [WidgetPathEvent] {
        data.currentPathEvents
    }

    var body: some View {
        Group {
            if pathEvents.isEmpty {
                legacyBody
            } else {
                livingDayBody
            }
        }
        .padding()
    }

    private var livingDayBody: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Living Day")
                        .font(.caption.weight(.bold))
                    Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted()) cal left")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WidgetPalette.brandPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    Text("P \(Int(max(0, data.proteinGoal - data.protein)).formatted())g")
                        .foregroundStyle(WidgetPalette.accentProtein)
                    Text("C \(Int(max(0, data.carbsGoal - data.carbs)).formatted())g")
                        .foregroundStyle(WidgetPalette.accentCarbs)
                    Text("F \(Int(max(0, data.fatGoal - data.fats)).formatted())g")
                        .foregroundStyle(WidgetPalette.accentFats)
                }
                .font(.caption2.weight(.bold))

                Button(intent: LogWaterIntent()) {
                    Image(systemName: "drop.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(WidgetPalette.accentWater, in: Circle())
                }
                .buttonStyle(.plain)
            }

            WidgetFuelPathStrip(events: Array(pathEvents.prefix(3)))

            if let action = data.nextAction {
                WidgetNextActionRow(action: action, compact: true)
            }
        }
    }

    private var legacyBody: some View {
        VStack(spacing: 9) {
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

                VStack(alignment: .leading, spacing: 7) {
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

            if let action = data.nextAction {
                WidgetNextActionRow(action: action, compact: true)
            }
        }
    }
}

struct SmallWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calories")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted())")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(WidgetPalette.brandPrimary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Protein")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(max(0, data.proteinGoal - data.protein)).formatted()) g")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(WidgetPalette.accentProtein)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
            }

            if let action = data.nextAction {
                SmallWidgetNextActionRow(action: action)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }
}

private struct SmallWidgetNextActionRow: View {
    let action: DailyNextAction

    private var title: String {
        switch action.kind {
        case .preWorkoutFuel: return "Pre-workout fuel"
        case .recoveryMeal: return "Recovery fuel"
        case .proteinCatchUp: return "Protein catch-up"
        case .trustReview: return "Review food data"
        case .steadyDay: return "Stay steady"
        }
    }

    private var icon: String {
        switch action.kind {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "fork.knife"
        case .proteinCatchUp: return "chart.bar.fill"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetPalette.brandPrimary)
                .frame(width: 24, height: 24)
                .background(
                    WidgetPalette.brandPrimary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 1)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            WidgetPalette.brandPrimary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.title). \(action.detail)")
        .accessibilityHint("Opens MyFitPlate")
    }
}

struct LargeWidgetView: View {
    let data: WidgetData
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var pathEvents: [WidgetPathEvent] {
        data.currentPathEvents
    }

    var body: some View {
        Group {
            if pathEvents.isEmpty {
                legacyBody
            } else {
                livingDayBody
            }
        }
        .padding()
    }

    private var livingDayBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Living Day")
                        .font(.headline)
                    Text("Your current path")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(max(0, data.calorieGoal - data.calories)).formatted()) cal left")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WidgetPalette.brandPrimary)
            }

            HStack(spacing: 14) {
                MacroBar(
                    label: "Protein",
                    value: data.protein,
                    goal: data.proteinGoal,
                    color: WidgetPalette.accentProtein
                )
                MacroBar(
                    label: "Carbs",
                    value: data.carbs,
                    goal: data.carbsGoal,
                    color: WidgetPalette.accentCarbs
                )
                MacroBar(
                    label: "Fats",
                    value: data.fats,
                    goal: data.fatGoal,
                    color: WidgetPalette.accentFats
                )
            }

            WidgetFuelPathList(events: Array(pathEvents.prefix(4)))

            if let action = data.nextAction {
                WidgetNextActionRow(action: action)
            }
        }
    }

    private var legacyBody: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 20) {
                ProgressBubble(
                    value: data.calories, goal: data.calorieGoal,
                    percentage: data.calorieGoal > 0 ? (data.calories / data.calorieGoal) : 0,
                    label: "Calories", unit: "cal", color: WidgetPalette.brandPrimary
                )
                .frame(height: 112)
                ProgressBubble(
                    value: data.protein, goal: data.proteinGoal,
                    percentage: data.proteinGoal > 0 ? (data.protein / data.proteinGoal) : 0,
                    label: "Protein", unit: "g", color: WidgetPalette.accentProtein
                )
                .frame(height: 112)
                ProgressBubble(
                    value: data.fats, goal: data.fatGoal,
                    percentage: data.fatGoal > 0 ? (data.fats / data.fatGoal) : 0,
                    label: "Fats", unit: "g", color: WidgetPalette.accentFats
                )
                .frame(height: 112)
                ProgressBubble(
                    value: data.carbs, goal: data.carbsGoal,
                    percentage: data.carbsGoal > 0 ? (data.carbs / data.carbsGoal) : 0,
                    label: "Carbs", unit: "g", color: WidgetPalette.accentCarbs
                )
                .frame(height: 112)
            }

            if let delta = data.macroCalorieDelta, abs(delta) >= 75 {
                Text("Macros imply \(Int(abs(delta).rounded())) cal \(delta > 0 ? "more" : "less").")
                    .font(.caption2)
                    .foregroundColor(WidgetPalette.accentSignal)
                    .lineLimit(1)
            }

            if let action = data.nextAction {
                WidgetNextActionRow(action: action)
            }
        }
    }
}

private struct WidgetFuelPathStrip: View {
    let events: [WidgetPathEvent]

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 30)
                .offset(y: 25)

            HStack(alignment: .top, spacing: 0) {
                ForEach(events) { event in
                    VStack(spacing: 2) {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        WidgetFuelPathNode(event: event, size: 24)
                        Text(event.kind.shortTitle)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(event.accessibilitySummary)
                }
            }
        }
        .frame(height: 52)
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetFuelPathList: View {
    let events: [WidgetPathEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 9) {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)

                    VStack(spacing: 0) {
                        WidgetFuelPathNode(event: event, size: 26)
                        if index < events.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 1, height: 10)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.kind.title)
                            .font(.caption.weight(.bold))
                        Text(event.state.title)
                            .font(.caption2)
                            .foregroundStyle(event.needsTrustReview ? WidgetPalette.accentSignal : .secondary)
                    }

                    Spacer(minLength: 0)

                    if event.needsTrustReview {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WidgetPalette.accentSignal)
                            .accessibilityLabel("Trust review needed")
                    }
                }
                .frame(minHeight: 34)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(event.accessibilitySummary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetFuelPathNode: View {
    let event: WidgetPathEvent
    let size: CGFloat

    var body: some View {
        ZStack {
            nodeBackground
            Image(systemName: event.kind.icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(event.state == .planned ? event.kind.color : .white)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var nodeBackground: some View {
        switch event.state {
        case .completed:
            Circle().fill(event.kind.color)
        case .planned:
            Circle()
                .fill(WidgetPalette.backgroundPrimary)
                .overlay(Circle().stroke(event.kind.color, lineWidth: 1.5))
        case .active:
            RoundedRectangle(cornerRadius: 6)
                .fill(event.kind.color)
        }
    }
}

struct WidgetNextActionRow: View {
    let action: DailyNextAction
    var compact = false

    private var color: Color {
        switch action.kind {
        case .preWorkoutFuel: return WidgetPalette.brandPrimary
        case .recoveryMeal: return WidgetPalette.accentCarbs
        case .proteinCatchUp: return WidgetPalette.accentProtein
        case .trustReview: return WidgetPalette.accentSignal
        case .steadyDay: return WidgetPalette.brandPrimary
        }
    }

    private var icon: String {
        switch action.kind {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "fork.knife"
        case .proteinCatchUp: return "chart.bar.fill"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(systemName: icon)
                .font(.system(size: compact ? 12 : 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .lineLimit(1)
                Text(action.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 3)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 7 : 9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens MyFitPlate")
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

private extension WidgetData {
    var currentPathEvents: [WidgetPathEvent] {
        guard let pathDate,
              Calendar.current.isDateInToday(pathDate) else { return [] }
        return (pathEvents ?? []).sorted {
            if $0.startDate == $1.startDate { return $0.sequence < $1.sequence }
            return $0.startDate < $1.startDate
        }
    }
}

private extension WidgetPathEvent.Kind {
    var title: String {
        switch self {
        case .meal: return "Meal"
        case .strength: return "Strength"
        case .run: return "Run"
        case .activity: return "Activity"
        case .recovery: return "Recovery"
        }
    }

    var shortTitle: String {
        switch self {
        case .meal: return "Meal"
        case .strength: return "Lift"
        case .run: return "Run"
        case .activity: return "Move"
        case .recovery: return "Recover"
        }
    }

    var icon: String {
        switch self {
        case .meal: return "fork.knife"
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .activity: return "figure.mixed.cardio"
        case .recovery: return "bolt.heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .meal: return WidgetPalette.brandPrimary
        case .strength: return .indigo
        case .run: return .cyan
        case .activity: return .blue
        case .recovery: return WidgetPalette.accentSignal
        }
    }
}

private extension WidgetPathEvent.State {
    var title: String {
        switch self {
        case .completed: return "Completed"
        case .planned: return "Planned"
        case .active: return "In progress"
        }
    }
}

private extension WidgetPathEvent {
    var accessibilitySummary: String {
        let approximation = isApproximate ? "approximately " : ""
        let trust = needsTrustReview ? ", Trust review needed" : ""
        return "\(kind.title), \(state.title), \(approximation)\(startDate.formatted(date: .omitted, time: .shortened))\(trust)"
    }
}
