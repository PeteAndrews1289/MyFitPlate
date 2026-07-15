import MyFitPlateCore
import SwiftUI
import UIKit

struct LivingDayTransition: Equatable, Identifiable {
    enum Kind: String {
        case foodLogged = "food_logged"
        case trainingPlanned = "training_planned"
        case trainingCompleted = "training_completed"
        case trainingSkipped = "training_skipped"
    }

    let id: UUID
    let kind: Kind
    let eventID: String?
    let title: String
    let detail: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        eventID: String?,
        title: String,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.eventID = eventID
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }

    static func foodLogged(
        _ foodItem: FoodItem,
        meal: Meal,
        createdAt: Date = Date()
    ) -> LivingDayTransition {
        let mealName = meal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return LivingDayTransition(
            kind: .foodLogged,
            eventID: "meal:\(meal.id.uuidString)",
            title: mealName.isEmpty ? "Food added" : "Added to \(mealName)",
            detail: foodItem.name,
            createdAt: createdAt
        )
    }

    func isRecent(at date: Date = Date(), maximumAge: TimeInterval = 8) -> Bool {
        let age = date.timeIntervalSince(createdAt)
        return age >= -1 && age <= maximumAge
    }
}

enum LivingDayPathDensity: String, CaseIterable, Identifiable {
    case compact
    case detailed

    static let defaultsKey = "living_day_path_density"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact path"
        case .detailed: return "Detailed path"
        }
    }
}

struct LivingDayHomeExperience: View {
    let snapshot: LivingDaySnapshot
    let transition: LivingDayTransition?
    let onEventSelected: (LivingDaySnapshot.Event) -> Void
    let onActionSelected: (DailyNextAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false
    @State private var presentedTransition: LivingDayTransition?
    @State private var emphasizedEventID: String?
    @State private var density: LivingDayPathDensity
    @State private var showingShareOptions = false
    @State private var didLogExposure = false

    private let persistsDensity: Bool

    private let collapsedEventLimit = 2

    init(
        snapshot: LivingDaySnapshot,
        transition: LivingDayTransition?,
        density: LivingDayPathDensity? = nil,
        onEventSelected: @escaping (LivingDaySnapshot.Event) -> Void,
        onActionSelected: @escaping (DailyNextAction) -> Void
    ) {
        self.snapshot = snapshot
        self.transition = transition
        self.onEventSelected = onEventSelected
        self.onActionSelected = onActionSelected
        persistsDensity = density == nil

        let storedDensity = UserDefaults.standard.string(forKey: LivingDayPathDensity.defaultsKey)
            .flatMap(LivingDayPathDensity.init(rawValue:))
        _density = State(initialValue: density ?? storedDensity ?? .compact)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            LivingDayBudgetView(budget: snapshot.budget)
            LivingDayActionButton(action: snapshot.nextAction) {
                onActionSelected(snapshot.nextAction)
            }
            LivingDayMaiaAnnotation(
                annotation: DailyNextActionAnnotationRules.make(for: snapshot.nextAction)
            ) {
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.livingDayMaiaAnnotationOpened.rawValue,
                    parameters: ["action_kind": snapshot.nextAction.kind.rawValue]
                )
                onActionSelected(snapshot.nextAction)
            }
            if let presentedTransition {
                LivingDayTransitionNotice(transition: presentedTransition)
                    .transition(statusTransition)
            }
            timeline
        }
        .frame(maxWidth: 520, alignment: .leading)
        .task(id: transition?.id) {
            await presentTransitionIfNeeded()
        }
        .onAppear(perform: logExposureIfNeeded)
        .onChange(of: density) { _, newValue in
            if persistsDensity {
                UserDefaults.standard.set(newValue.rawValue, forKey: LivingDayPathDensity.defaultsKey)
            }
            if newValue == .compact {
                isExpanded = false
            }
            DIContainer.shared.analyticsManager?.logEvent(
                ProductAnalytics.Event.livingDayDensityChanged.rawValue,
                parameters: ["density": newValue.rawValue]
            )
        }
        .sheet(isPresented: $showingShareOptions) {
            LivingDayShareOptionsView(snapshot: snapshot)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Living Day")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Label(freshness.title, systemImage: freshness.icon)
                    .appTextRole(.caption)
                    .foregroundStyle(freshness.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                showingShareOptions = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(AppIconButtonStyle(.neutral))
            .accessibilityLabel("Share Living Day")
            .accessibilityIdentifier("livingDayShareButton")

            Menu {
                ForEach(LivingDayPathDensity.allCases) { option in
                    Button {
                        density = option
                    } label: {
                        Label(
                            option.title,
                            systemImage: density == option ? "checkmark" : option.icon
                        )
                    }
                }
            } label: {
                Image(systemName: density.icon)
            }
            .buttonStyle(AppIconButtonStyle(.neutral))
            .accessibilityLabel("Path density")
            .accessibilityValue(density.title)
            .accessibilityIdentifier("livingDayDensityMenu")
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Your Day")
                    .appFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                if density == .compact, snapshot.events.count > collapsedEventLimit {
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
                        showsConnector: index < visibleEvents.count - 1,
                        isEmphasized: emphasizedEventID == event.id
                    ) {
                        onEventSelected(event)
                    }
                    .transition(eventTransition)
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
        .animation(eventAnimation, value: snapshot.events.map(\.id))
        .animation(eventAnimation, value: snapshot.events.map(\.state))
    }

    private var visibleEvents: [LivingDaySnapshot.Event] {
        let events = snapshot.events
        guard density == .compact else { return events }
        guard !isExpanded, events.count > collapsedEventLimit else { return events }

        if let emphasizedEventID,
           let emphasizedIndex = events.firstIndex(where: { $0.id == emphasizedEventID }) {
            let start = min(max(0, emphasizedIndex - 1), events.count - collapsedEventLimit)
            return Array(events[start..<(start + collapsedEventLimit)])
        }

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
            return ("Updated \(relative)", "clock.arrow.circlepath", AppPalette.caution)
        case .unavailable:
            return ("Limited Data", "exclamationmark.circle", AppPalette.caution)
        }
    }

    private var eventAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private func logExposureIfNeeded() {
        guard !didLogExposure else { return }
        didLogExposure = true
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.livingDayViewed.rawValue,
            parameters: [
                "path_event_count": snapshot.events.count,
                "has_training": snapshot.trainingWindow != nil,
                "freshness": analyticsFreshness,
                "next_action_kind": snapshot.nextAction.kind.rawValue,
                "density": density.rawValue
            ]
        )
    }

    private var analyticsFreshness: String {
        switch snapshot.freshness {
        case .current: return "current"
        case .stale: return "stale"
        case .unavailable: return "unavailable"
        }
    }

    private var eventTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var statusTransition: AnyTransition {
        .opacity
    }

    @MainActor
    private func presentTransitionIfNeeded() async {
        guard let transition, transition.isRecent() else { return }

        withAnimation(eventAnimation) {
            presentedTransition = transition
            emphasizedEventID = transition.eventID
        }
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.livingDayTransitionPresented.rawValue,
            parameters: [
                "kind": transition.kind.rawValue,
                "matched_event": snapshot.events.contains(where: { $0.id == transition.eventID })
            ]
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(transition.title). \(transition.detail)"
        )

        do {
            try await Task.sleep(nanoseconds: 2_400_000_000)
        } catch {
            return
        }
        guard presentedTransition?.id == transition.id else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.22)) {
            presentedTransition = nil
            emphasizedEventID = nil
        }
    }
}

private struct LivingDayTransitionNotice: View {
    let transition: LivingDayTransition

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transition.icon)
                .appFont(size: 14, weight: .bold)
                .foregroundStyle(transition.color)
                .frame(width: 32, height: 32)
                .background(transition.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transition.title)
                    .appFont(size: 13, weight: .bold)
                    .foregroundStyle(Color.textPrimary)
                Text(transition.detail)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .appFont(size: 12, weight: .bold)
                .foregroundStyle(transition.color)
        }
        .padding(.vertical, 7)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(transition.color)
                .frame(width: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transition.title). \(transition.detail)")
    }
}

private struct LivingDayMaiaAnnotation: View {
    let annotation: DailyNextActionAnnotation
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.brandPrimary.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Maia")
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(Color.brandPrimary)
                    Text(annotation.text)
                        .appFont(size: 12, weight: .medium)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Maia. \(annotation.text)")
        .accessibilityHint("Opens the current action")
        .accessibilityIdentifier("livingDayMaiaAnnotation")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.28),
            value: nutrient
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nutrient.accessibilitySummary)
    }
}

private struct LivingDayActionButton: View {
    let action: DailyNextAction
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .contentTransition(.opacity)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.24),
            value: action
        )
        .accessibilityHint(action.accessibilityHint)
        .accessibilityIdentifier("livingDayCurrentAction")
    }
}

private struct LivingDayTimelineRow: View {
    let event: LivingDaySnapshot.Event
    let showsConnector: Bool
    let isEmphasized: Bool
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
        .accessibilityIdentifier("livingDayEvent")
    }

    @ViewBuilder
    private var rowLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityRow
        } else {
            standardRow
        }
    }

    private var row: some View {
        rowLayout
            .contentShape(Rectangle())
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
                if isEmphasized {
                    Rectangle()
                        .fill(event.color)
                        .frame(width: 3)
                        .transition(.opacity)
                }
            }
    }

    private var standardRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 68, alignment: .trailing)

            VStack(spacing: 0) {
                LivingDayEventNode(event: event, isEmphasized: isEmphasized)
                if showsConnector {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2, height: 42)
                }
            }

            eventContent

            Spacer(minLength: 0)

            if event.destination != .none {
                Image(systemName: "chevron.right")
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .padding(.top, 11)
            }
        }
    }

    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                if event.timing == .approximate {
                    Text("Approximate time")
                        .appFont(size: 9, weight: .bold)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if event.destination != .none {
                    Image(systemName: "chevron.right")
                        .appFont(size: 10, weight: .bold)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    LivingDayEventNode(event: event, isEmphasized: isEmphasized)
                    if showsConnector {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.22))
                            .frame(width: 2, height: 72)
                    }
                }

                eventContent

                Spacer(minLength: 0)
            }
        }
    }

    private var eventContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            eventHeading

            Text(event.detail)
                .appFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            eventMetadata
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var eventHeading: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(event.title)
                .appFont(size: 15, weight: .bold)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
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
        }
    }

    @ViewBuilder
    private var eventMetadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if event.evidence != .notApplicable {
                    Label(event.evidence.title, systemImage: event.evidence.icon)
                        .foregroundStyle(event.evidence.color)
                }
                Text(event.state.title)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .appFont(size: 10, weight: .bold)
        } else {
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
    }
}

private struct LivingDayEventNode: View {
    let event: LivingDaySnapshot.Event
    let isEmphasized: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            nodeBackground
            Image(systemName: event.icon)
                .appFont(size: 13, weight: .bold)
                .foregroundStyle(event.state == .planned || event.state == .skipped ? event.color : .white)
        }
        .frame(width: 36, height: 36)
        .overlay {
            Circle()
                .stroke(event.color.opacity(isEmphasized ? 0.55 : 0), lineWidth: 3)
                .padding(-5)
        }
        .scaleEffect(isEmphasized && !reduceMotion ? 1.08 : 1)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.7),
            value: isEmphasized
        )
        .animation(.easeInOut(duration: reduceMotion ? 0.14 : 0.22), value: event.state)
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

private extension LivingDayPathDensity {
    var icon: String {
        switch self {
        case .compact: return "line.3.horizontal.decrease"
        case .detailed: return "list.bullet"
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

private extension LivingDayTransition {
    var icon: String {
        switch kind {
        case .foodLogged: return "fork.knife"
        case .trainingPlanned: return "calendar.badge.checkmark"
        case .trainingCompleted: return "bolt.heart.fill"
        case .trainingSkipped: return "forward.fill"
        }
    }

    var color: Color {
        switch kind {
        case .foodLogged, .trainingCompleted: return .brandPrimary
        case .trainingPlanned: return AppPalette.effort
        case .trainingSkipped: return AppPalette.caution
        }
    }
}

private extension LivingDaySnapshot.Event {
    var color: Color {
        switch kind {
        case .meal: return .brandPrimary
        case .plannedMeal: return .accentCarbs
        case .strength: return AppPalette.effort
        case .run: return AppPalette.effort
        case .walk: return AppPalette.positive
        case .recovery: return AppPalette.recovery
        case .activity: return AppPalette.achievement
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
        case .review: return AppPalette.caution
        case .correction: return AppPalette.critical
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
        case .trustReview: return AppPalette.caution
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
