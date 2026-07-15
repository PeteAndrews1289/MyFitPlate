#if DEBUG
import MyFitPlateCore
import SwiftUI

enum LivingDayPrototypeStyle: String, CaseIterable, Hashable, Identifiable {
    case rail
    case timeline
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rail: return "Rail"
        case .timeline: return "Timeline"
        case .clock: return "Clock"
        }
    }

    static func initial(for screen: String) -> Self {
        if screen.contains("vertical") || screen.contains("timeline") { return .timeline }
        if screen.contains("clock") { return .clock }
        return .rail
    }
}

struct LivingDayPrototypeGallery: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var style: LivingDayPrototypeStyle
    private let snapshot = LivingDayPrototypeFixture.snapshot

    init(initialStyle: LivingDayPrototypeStyle = .rail) {
        _style = State(initialValue: initialStyle)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LivingDayBudgetRibbon(budget: snapshot.budget)

                Picker("Fuel Path layout", selection: $style) {
                    ForEach(LivingDayPrototypeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("livingDayPrototypePicker")

                if dynamicTypeSize.isAccessibilitySize, style != .clock {
                    LivingDayCurrentAction(action: snapshot.nextAction)
                }

                Group {
                    switch style {
                    case .rail:
                        LivingDayRailPrototype(snapshot: snapshot)
                    case .timeline:
                        LivingDayTimelinePrototype(snapshot: snapshot)
                    case .clock:
                        LivingDayClockPrototype(snapshot: snapshot)
                    }
                }
                .accessibilityIdentifier("livingDayPrototype\(style.title)")

                if !dynamicTypeSize.isAccessibilitySize, style != .clock {
                    LivingDayCurrentAction(action: snapshot.nextAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 64 : 0)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .appFont(size: 32, weight: .bold)
                    .foregroundStyle(Color.textPrimary)
                Text(LivingDayPrototypeFixture.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .appFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("Synced", systemImage: "checkmark.icloud.fill")
                .appFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityLabel("Nutrition and training data synced")
        }
    }
}

private struct LivingDayBudgetRibbon: View {
    let budget: LivingDaySnapshot.Budget

    var body: some View {
        VStack(spacing: 10) {
            ForEach(budget.nutrients, id: \.kind) { nutrient in
                HStack(spacing: 10) {
                    Text(nutrient.shortTitle)
                        .appFont(size: 12, weight: .bold)
                        .foregroundStyle(nutrient.color)
                        .frame(width: 28, alignment: .leading)

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
                    .frame(height: 8)

                    Text(nutrient.remainingText)
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 64, alignment: .trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nutrient.accessibilitySummary)
            }
        }
    }
}

private struct LivingDayRailPrototype: View {
    let snapshot: LivingDaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Fuel Path")
                    .appFont(size: 20, weight: .bold)
                Spacer()
                Text("6 AM – 10 PM")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.24))
                        .frame(width: geometry.size.width, height: 2)
                        .offset(y: 60)

                    if let training = snapshot.trainingWindow {
                        let start = snapshot.pathWindow.position(for: training.windowStart)
                        let end = snapshot.pathWindow.position(for: training.windowEnd)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppPalette.effort.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppPalette.effort.opacity(0.45), lineWidth: 1))
                            .frame(width: max(34, geometry.size.width * (end - start)), height: 54)
                            .offset(x: geometry.size.width * start, y: 34)
                            .accessibilityHidden(true)
                    }

                    ForEach(Array(snapshot.events.enumerated()), id: \.element.id) { index, event in
                        LivingDayRailNode(event: event, labelAbove: index.isMultiple(of: 2))
                            .position(
                                x: min(
                                    max(38, geometry.size.width * snapshot.pathWindow.position(for: event.startDate)),
                                    geometry.size.width - 38
                                ),
                                y: 60
                            )
                    }

                    if let currentTime = snapshot.currentTime {
                        let position = geometry.size.width * snapshot.pathWindow.position(for: currentTime)
                        VStack(spacing: 3) {
                            Text("NOW")
                                .appFont(size: 9, weight: .bold)
                                .foregroundStyle(Color.brandPrimary)
                            Rectangle().fill(Color.brandPrimary).frame(width: 2, height: 80)
                        }
                        .offset(x: position, y: 4)
                        .accessibilityLabel("Current time, 3:10 PM")
                    }
                }
            }
            .frame(height: 124)

            HStack(spacing: 18) {
                Label("Logged", systemImage: "circle.fill")
                Label("Planned", systemImage: "circle")
                Label("Training window", systemImage: "rectangle.fill")
            }
            .appFont(size: 11, weight: .semibold)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LivingDayRailNode: View {
    let event: LivingDaySnapshot.Event
    let labelAbove: Bool

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(event.state == .planned ? Color.backgroundPrimary : event.color)
                    .overlay(Circle().stroke(event.color, lineWidth: event.evidence == .correction ? 3 : 2))
                    .frame(width: 40, height: 40)
                Image(systemName: event.icon)
                    .appFont(size: 15, weight: .bold)
                    .foregroundStyle(event.state == .planned ? event.color : .white)
            }
            .position(x: 38, y: 60)

            VStack(spacing: 1) {
                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                    .appFont(size: 9, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(event.shortTitle)
                    .appFont(size: 9, weight: .bold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .position(x: 38, y: labelAbove ? 17 : 103)
        }
        .frame(width: 76, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilitySummary)
    }
}

private struct LivingDayTimelinePrototype: View {
    let snapshot: LivingDaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your day")
                .appFont(size: 20, weight: .bold)
                .padding(.bottom, 12)

            ForEach(Array(snapshot.events.enumerated()), id: \.element.id) { index, event in
                if shouldShowNow(before: event, at: index), let currentTime = snapshot.currentTime {
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
                    .frame(height: 28)
                    .accessibilityLabel("Current time, \(currentTime.formatted(date: .omitted, time: .shortened))")
                }

                HStack(alignment: .top, spacing: 14) {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 68, alignment: .trailing)

                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(event.state == .planned ? Color.backgroundPrimary : event.color)
                                .overlay(Circle().stroke(event.color, lineWidth: 2))
                                .frame(width: 36, height: 36)
                            Image(systemName: event.icon)
                                .appFont(size: 14, weight: .bold)
                                .foregroundStyle(event.state == .planned ? event.color : .white)
                        }
                        if index < snapshot.events.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.22))
                                .frame(width: 2, height: 46)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(event.title)
                                .appFont(size: 15, weight: .bold)
                                .foregroundStyle(Color.textPrimary)
                            if event.timing == .approximate {
                                Text("Approx.")
                                    .appFont(size: 9, weight: .bold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(event.detail)
                            .appFont(size: 12, weight: .medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        LivingDayEvidenceLabel(evidence: event.evidence)
                    }
                    .padding(.top, 1)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func shouldShowNow(before event: LivingDaySnapshot.Event, at index: Int) -> Bool {
        guard let currentTime = snapshot.currentTime, event.startDate > currentTime else { return false }
        guard index > 0 else { return true }
        return snapshot.events[index - 1].startDate <= currentTime
    }
}

private struct LivingDayClockPrototype: View {
    let snapshot: LivingDaySnapshot

    var body: some View {
        VStack(spacing: 18) {
            Text("Today at a glance")
                .appFont(size: 20, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .fill(Color.backgroundPrimary)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 1))

                Circle()
                    .trim(from: 0.08, to: 0.91)
                    .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                if let currentTime = snapshot.currentTime {
                    Circle()
                        .trim(from: 0.08, to: max(0.08, snapshot.pathWindow.position(for: currentTime)))
                        .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 3) {
                    Text("FUEL BEFORE TRAINING")
                        .appFont(size: 9, weight: .bold)
                        .foregroundStyle(Color.brandPrimary)
                    Text("22 g protein")
                        .appFont(size: 18, weight: .bold)
                        .foregroundStyle(Color.accentProtein)
                    Text("42 g carbs")
                        .appFont(size: 18, weight: .bold)
                        .foregroundStyle(Color.accentCarbs)
                    HStack(spacing: 4) {
                        Text("570 cal left")
                        Image(systemName: "chevron.right")
                    }
                    .appFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }

                GeometryReader { geometry in
                    ForEach(snapshot.events) { event in
                        let angle = Angle.degrees(snapshot.pathWindow.position(for: event.startDate) * 300 - 240)
                        let radius = min(geometry.size.width, geometry.size.height) * 0.43
                        ZStack {
                            Circle()
                                .fill(event.state == .planned ? Color.backgroundPrimary : event.color)
                                .overlay(Circle().stroke(event.color, lineWidth: 2))
                                .frame(width: 36, height: 36)
                            Image(systemName: event.icon)
                                .appFont(size: 13, weight: .bold)
                                .foregroundStyle(event.state == .planned ? event.color : .white)
                        }
                        .position(
                            x: geometry.size.width / 2 + CGFloat(cos(angle.radians)) * radius,
                            y: geometry.size.height / 2 + CGFloat(sin(angle.radians)) * radius
                        )
                        .accessibilityLabel(event.accessibilitySummary)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Circular Fuel Path for today. Fuel before training, 22 grams protein and 42 grams carbs")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(snapshot.events) { event in
                    HStack(spacing: 8) {
                        Image(systemName: event.icon)
                            .foregroundStyle(event.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.shortTitle)
                                .appFont(size: 12, weight: .bold)
                                .lineLimit(1)
                            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                .appFont(size: 10, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct LivingDayEvidenceLabel: View {
    let evidence: LivingDaySnapshot.Evidence

    var body: some View {
        if evidence != .notApplicable {
            Label(evidence.title, systemImage: evidence.icon)
                .appFont(size: 10, weight: .bold)
                .foregroundStyle(evidence.color)
        }
    }
}

private struct LivingDayCurrentAction: View {
    let action: DailyNextAction

    var body: some View {
        Button {} label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .appFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .appFont(size: 16, weight: .bold)
                    Text(action.detail)
                        .appFont(size: 12, weight: .semibold)
                        .opacity(0.82)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(size: 13, weight: .bold)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the exact Training Fuel target")
    }
}

private enum LivingDayPrototypeFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static let day = calendar.startOfDay(for: Date())

    static let snapshot: LivingDaySnapshot = {
        let date: (Int, Int) -> Date = { hour, minute in
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let events: [LivingDaySnapshot.Event] = [
            .init(
                id: "breakfast",
                kind: .meal,
                state: .completed,
                title: "Protein oats",
                detail: "410 cal · 34 g protein",
                startDate: date(8, 5),
                timing: .exact,
                evidence: .excellent,
                nutrition: .init(calories: 410, protein: 34, carbs: 52, fats: 10),
                destination: .diary(mealID: "breakfast")
            ),
            .init(
                id: "lunch",
                kind: .meal,
                state: .completed,
                title: "Chicken bowl",
                detail: "580 cal · Database supported",
                startDate: date(12, 22),
                timing: .exact,
                evidence: .supported,
                nutrition: .init(calories: 580, protein: 48, carbs: 66, fats: 15),
                destination: .diary(mealID: "lunch")
            ),
            .init(
                id: "strength",
                kind: .strength,
                state: .planned,
                title: "Lower body",
                detail: "60 min · Hard",
                startDate: date(17, 30),
                endDate: date(18, 30),
                timing: .exact,
                evidence: .notApplicable,
                destination: .trainingFuel
            ),
            .init(
                id: "dinner",
                kind: .plannedMeal,
                state: .planned,
                title: "Salmon dinner",
                detail: "640 cal planned",
                startDate: date(19, 15),
                timing: .approximate,
                evidence: .supported,
                nutrition: .init(calories: 640, protein: 46, carbs: 58, fats: 24),
                destination: .mealPlan
            )
        ]
        return LivingDaySnapshot(
            date: day,
            generatedAt: date(15, 10),
            pathWindow: .init(start: date(6, 0), end: date(22, 0)),
            budget: .init(
                calories: .init(kind: .calories, consumed: 990, planned: 640, target: 2_200),
                protein: .init(kind: .protein, consumed: 82, planned: 46, target: 165),
                carbs: .init(kind: .carbs, consumed: 118, planned: 58, target: 245),
                fats: .init(kind: .fats, consumed: 25, planned: 24, target: 70)
            ),
            events: events,
            trainingWindow: .init(
                planID: "lower-body",
                title: "Lower body",
                sessionStart: date(17, 30),
                sessionEnd: date(18, 30),
                windowStart: date(16, 0),
                windowEnd: date(20, 30),
                status: .upcoming
            ),
            nextAction: .init(
                kind: .preWorkoutFuel,
                title: "Fuel before training",
                detail: "22 g protein + 42 g carbs",
                deepLink: "myfitplate://training-fuel",
                proteinGrams: 22,
                carbGrams: 42
            ),
            freshness: .current(updatedAt: date(15, 8)),
            currentTime: date(15, 10)
        )
    }()
}

private extension LivingDaySnapshot.NutrientBudget {
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

    var consumedWidth: Double {
        min(1, consumedFraction ?? 0)
    }

    var totalWidth: Double {
        min(1, consumedWidth + (plannedFraction ?? 0))
    }

    var remainingText: String {
        guard let remaining else { return "Unavailable" }
        let value = Int(max(0, remaining).rounded())
        return kind == .calories ? "\(value) left" : "\(value) g left"
    }

    var accessibilitySummary: String {
        guard let consumed, let planned, let target else {
            return "\(shortTitle) budget unavailable"
        }
        let unit = kind == .calories ? "calories" : "grams"
        return "\(shortTitle), \(Int(consumed.rounded())) \(unit) consumed, \(Int(planned.rounded())) planned, target \(Int(target.rounded()))"
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

    var shortTitle: String {
        switch kind {
        case .meal: return title
        case .plannedMeal: return "Dinner"
        case .strength: return "Strength"
        case .run: return "Run"
        case .walk: return "Walk"
        case .recovery: return "Recovery"
        case .activity: return "Activity"
        }
    }

    var accessibilitySummary: String {
        let timingText = timing == .approximate ? "approximately" : "at"
        return "\(title), \(state.rawValue), \(timingText) \(startDate.formatted(date: .omitted, time: .shortened)), \(detail)"
    }
}

private extension LivingDaySnapshot.Evidence {
    var title: String {
        switch self {
        case .excellent: return "Cross-checked"
        case .supported: return "Supported"
        case .review: return "Review"
        case .correction: return "Fix data"
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
#endif
