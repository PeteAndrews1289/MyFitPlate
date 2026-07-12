import MyFitPlateCore
import SwiftUI

struct LivingDayHomeExperience: View {
    let snapshot: LivingDaySnapshot
    let onEventSelected: (LivingDaySnapshot.Event) -> Void
    let onActionSelected: (DailyNextAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false

    private let collapsedEventLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            LivingDayBudgetView(budget: snapshot.budget)
            LivingDayActionButton(action: snapshot.nextAction) {
                onActionSelected(snapshot.nextAction)
            }
            timeline
        }
        .frame(maxWidth: 520, alignment: .leading)
        .accessibilityIdentifier("livingDayHomeExperience")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Living Day")
                .appFont(size: 24, weight: .bold)
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)

            Label(freshness.title, systemImage: freshness.icon)
                .appFont(size: 11, weight: .bold)
                .foregroundStyle(freshness.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Your Day")
                    .appFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                if snapshot.events.count > collapsedEventLimit {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(isExpanded ? "Show Less" : "Show All")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .appFont(size: 12, weight: .bold)
                        .foregroundStyle(Color.brandPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Show fewer day events" : "Show all day events")
                }
            }
            .padding(.bottom, 12)

            if visibleEvents.isEmpty {
                Text("No meals or training yet")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                    if shouldShowNow(before: event, at: index) {
                        LivingDayNowMarker(currentTime: snapshot.currentTime)
                    }

                    LivingDayTimelineRow(
                        event: event,
                        showsConnector: index < visibleEvents.count - 1
                    ) {
                        onEventSelected(event)
                    }
                }

                if shouldShowNowAfterLastEvent {
                    LivingDayNowMarker(currentTime: snapshot.currentTime)
                }

                if hiddenEventCount > 0, !isExpanded {
                    Text("\(hiddenEventCount) more \(hiddenEventCount == 1 ? "event" : "events")")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 120)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var visibleEvents: [LivingDaySnapshot.Event] {
        let events = snapshot.events
        guard !isExpanded, events.count > collapsedEventLimit else { return events }

        guard let currentTime = snapshot.currentTime else {
            return Array(events.suffix(collapsedEventLimit))
        }

        let nextIndex = events.firstIndex { $0.startDate > currentTime } ?? events.count
        let start = min(max(0, nextIndex - 1), events.count - collapsedEventLimit)
        return Array(events[start..<(start + collapsedEventLimit)])
    }

    private var hiddenEventCount: Int {
        max(0, snapshot.events.count - visibleEvents.count)
    }

    private func shouldShowNow(before event: LivingDaySnapshot.Event, at index: Int) -> Bool {
        guard let currentTime = snapshot.currentTime, event.startDate > currentTime else { return false }
        guard index > 0 else { return true }
        return visibleEvents[index - 1].startDate <= currentTime
    }

    private var shouldShowNowAfterLastEvent: Bool {
        guard let currentTime = snapshot.currentTime,
              let lastEvent = visibleEvents.last else { return false }
        return lastEvent.startDate <= currentTime
    }

    private var freshness: (title: String, icon: String, color: Color) {
        switch snapshot.freshness {
        case .current:
            return ("Current", "checkmark.circle.fill", .brandPrimary)
        case .stale(let lastUpdated):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let relative = formatter.localizedString(for: lastUpdated, relativeTo: snapshot.generatedAt)
            return ("Updated \(relative)", "clock.arrow.circlepath", .orange)
        case .unavailable:
            return ("Limited Data", "exclamationmark.circle", .orange)
        }
    }
}

private struct LivingDayBudgetView: View {
    let budget: LivingDaySnapshot.Budget
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Budget")
                .appFont(size: 13, weight: .bold)
                .foregroundStyle(.secondary)

            ForEach(budget.nutrients, id: \.kind) { nutrient in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(nutrient.title)
                                .foregroundStyle(nutrient.color)
                            Spacer()
                            Text(nutrient.remainingText)
                                .foregroundStyle(Color.textPrimary)
                                .monospacedDigit()
                        }
                        .appFont(size: 12, weight: .bold)
                        LivingDayBudgetBar(nutrient: nutrient)
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(nutrient.shortTitle)
                            .appFont(size: 12, weight: .bold)
                            .foregroundStyle(nutrient.color)
                            .frame(width: 28, alignment: .leading)

                        LivingDayBudgetBar(nutrient: nutrient)

                        Text(nutrient.remainingText)
                            .appFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 76, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LivingDayBudgetBar: View {
    let nutrient: LivingDaySnapshot.NutrientBudget

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.13))
                Capsule()
                    .fill(nutrient.color)
                    .frame(width: geometry.size.width * nutrient.consumedWidth)
                Capsule()
                    .fill(nutrient.color.opacity(0.28))
                    .frame(width: geometry.size.width * nutrient.totalWidth)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .padding(.leading, geometry.size.width * nutrient.consumedWidth)
                    }
            }
        }
        .frame(minWidth: 48, minHeight: 8, maxHeight: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nutrient.accessibilitySummary)
    }
}

private struct LivingDayActionButton: View {
    let action: DailyNextAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .appFont(size: 15, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .appFont(size: 15, weight: .bold)
                    Text(action.detail)
                        .appFont(size: 12, weight: .semibold)
                        .opacity(0.84)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(action.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(action.accessibilityHint)
    }
}

private struct LivingDayTimelineRow: View {
    let event: LivingDaySnapshot.Event
    let showsConnector: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if event.destination == .none {
                row
            } else {
                Button(action: onSelect) { row }
                    .buttonStyle(.plain)
                    .accessibilityHint(event.destination.accessibilityHint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.accessibilitySummary)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 74 : 68, alignment: .trailing)

            VStack(spacing: 0) {
                LivingDayEventNode(event: event)
                if showsConnector {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2, height: dynamicTypeSize.isAccessibilitySize ? 62 : 42)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.title)
                        .appFont(size: 15, weight: .bold)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if event.timing == .approximate {
                        Text("Approx.")
                            .appFont(size: 9, weight: .bold)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(event.detail)
                    .appFont(size: 12, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                HStack(spacing: 8) {
                    if event.evidence != .notApplicable {
                        Label(event.evidence.title, systemImage: event.evidence.icon)
                            .foregroundStyle(event.evidence.color)
                    }
                    Text(event.state.title)
                        .foregroundStyle(.secondary)
                }
                .appFont(size: 10, weight: .bold)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)

            if event.destination != .none {
                Image(systemName: "chevron.right")
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .padding(.top, 11)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct LivingDayEventNode: View {
    let event: LivingDaySnapshot.Event

    var body: some View {
        ZStack {
            nodeBackground
            Image(systemName: event.icon)
                .appFont(size: 13, weight: .bold)
                .foregroundStyle(event.state == .planned || event.state == .skipped ? event.color : .white)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var nodeBackground: some View {
        switch event.state {
        case .completed:
            Circle().fill(event.color)
        case .planned:
            Circle()
                .fill(Color.backgroundPrimary)
                .overlay(Circle().stroke(event.color, lineWidth: 2))
        case .active:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(event.color)
        case .skipped:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.backgroundPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(event.color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                )
        }
    }
}

private struct LivingDayNowMarker: View {
    let currentTime: Date?

    var body: some View {
        if let currentTime {
            HStack(spacing: 12) {
                Text(currentTime.formatted(date: .omitted, time: .shortened))
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(Color.brandPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 68, alignment: .trailing)
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: 9, height: 9)
                    .frame(width: 36)
                Text("Now")
                    .appFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.brandPrimary)
                Rectangle()
                    .fill(Color.brandPrimary.opacity(0.28))
                    .frame(height: 1)
            }
            .frame(minHeight: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current time, \(currentTime.formatted(date: .omitted, time: .shortened))")
        }
    }
}

private extension LivingDaySnapshot.NutrientBudget {
    var title: String {
        switch kind {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fats: return "Fat"
        }
    }

    var shortTitle: String {
        switch kind {
        case .calories: return "Cal"
        case .protein: return "P"
        case .carbs: return "C"
        case .fats: return "F"
        }
    }

    var color: Color {
        switch kind {
        case .calories: return .brandPrimary
        case .protein: return .accentProtein
        case .carbs: return .accentCarbs
        case .fats: return .accentFats
        }
    }

    var consumedWidth: Double { min(1, consumedFraction ?? 0) }
    var totalWidth: Double { min(1, consumedWidth + (plannedFraction ?? 0)) }

    var remainingText: String {
        guard let remaining else { return "Unavailable" }
        let value = Int(abs(remaining).rounded())
        let suffix = kind == .calories ? "cal" : "g"
        return remaining >= 0 ? "\(value) \(suffix) left" : "\(value) \(suffix) over"
    }

    var accessibilitySummary: String {
        guard let consumed, let planned, let target else { return "\(title) budget unavailable" }
        let unit = kind == .calories ? "calories" : "grams"
        return "\(title), \(Int(consumed.rounded())) \(unit) consumed, \(Int(planned.rounded())) planned, target \(Int(target.rounded()))"
    }
}

private extension LivingDaySnapshot.Event {
    var color: Color {
        switch kind {
        case .meal: return .brandPrimary
        case .plannedMeal: return .accentCarbs
        case .strength: return .indigo
        case .run: return .cyan
        case .walk: return .blue
        case .recovery: return .orange
        case .activity: return .purple
        }
    }

    var icon: String {
        switch kind {
        case .meal: return "fork.knife"
        case .plannedMeal: return "calendar"
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .recovery: return "bolt.heart.fill"
        case .activity: return "figure.mixed.cardio"
        }
    }

    var accessibilitySummary: String {
        let timingText = timing == .approximate ? "approximately" : "at"
        let evidenceText = evidence == .notApplicable ? "" : ", evidence \(evidence.title)"
        return "\(title), \(state.title), \(timingText) \(startDate.formatted(date: .omitted, time: .shortened)), \(detail)\(evidenceText)"
    }
}

private extension LivingDaySnapshot.EventState {
    var title: String {
        switch self {
        case .completed: return "Logged"
        case .planned: return "Planned"
        case .active: return "In Progress"
        case .skipped: return "Skipped"
        }
    }
}

private extension LivingDaySnapshot.Evidence {
    var title: String {
        switch self {
        case .excellent: return "Cross-Checked"
        case .supported: return "Supported"
        case .review: return "Review"
        case .correction: return "Fix Data"
        case .unavailable: return "Unavailable"
        case .notApplicable: return ""
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .supported: return "checkmark.circle"
        case .review: return "exclamationmark.circle"
        case .correction: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle"
        case .notApplicable: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .excellent, .supported: return .brandPrimary
        case .review: return .orange
        case .correction: return .red
        case .unavailable, .notApplicable: return .secondary
        }
    }
}

private extension LivingDaySnapshot.Destination {
    var accessibilityHint: String {
        switch self {
        case .diary: return "Moves to this day's food diary"
        case .mealPlan: return "Opens Meal Plan"
        case .workouts: return "Opens Training"
        case .runs: return "Opens run and walk history"
        case .trainingFuel: return "Opens Training Fuel"
        case .none: return ""
        }
    }
}

private extension DailyNextAction {
    var icon: String {
        switch kind {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "bolt.heart.fill"
        case .proteinCatchUp: return "fork.knife"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark"
        }
    }

    var color: Color {
        switch kind {
        case .preWorkoutFuel, .recoveryMeal, .steadyDay: return .brandPrimary
        case .proteinCatchUp: return .accentProtein
        case .trustReview: return .orange
        }
    }

    var accessibilityHint: String {
        switch kind {
        case .preWorkoutFuel, .recoveryMeal: return "Opens the current Training Fuel target"
        case .proteinCatchUp: return "Opens food search"
        case .trustReview: return "Opens today's Food Trust review"
        case .steadyDay:
            return deepLink.contains("meal-plan") ? "Opens Meal Plan" : "Moves to today's food diary"
        }
    }
}
