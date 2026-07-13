import MyFitPlateCore

import SwiftUI
// MARK: - Program slot math (shared by the slider and the program calendar)

extension WorkoutProgram {
    /// How many sessions the program spans (12 weeks of training days, or the routine count if larger).
    var totalSlots: Int {
        max((daysOfWeek?.count ?? 0) * 12, routines.count)
    }

    /// The routine that fills slot `index` (routines rotate).
    func routine(forSlot index: Int) -> WorkoutRoutine? {
        guard !routines.isEmpty else { return nil }
        return routines[index % routines.count]
    }

    /// 1-based (week, day) label for slot `index`.
    func weekAndDay(forSlot index: Int) -> (week: Int, day: Int) {
        let perWeek = max(daysOfWeek?.count ?? 1, 1)
        return (index / perWeek + 1, index % perWeek + 1)
    }

    /// The calendar date the Nth scheduled training day falls on, walking forward from the start date.
    func date(forSlot index: Int) -> Date? {
        guard let start = startDate, let days = daysOfWeek, !days.isEmpty else { return nil }
        let calendar = Calendar.current
        var matched = 0
        for offset in 0..<(7 * 13) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if days.contains(calendar.component(.weekday, from: date)) {
                if matched == index { return calendar.startOfDay(for: date) }
                matched += 1
            }
        }
        return nil
    }
}

// MARK: - Today's Best Next Step

/// A scrubbable replacement for the old "Continue Program" card. It centers on the program's
/// current slot and lets the user swipe back through finished sessions (to review) or forward
/// through upcoming ones (to start early or skip ahead).
struct TodaysNextStepSlider: View {
    let program: WorkoutProgram
    /// Completed session logs keyed by the slot index they belong to.
    let completedLogsByIndex: [Int: WorkoutSessionLog]
    let onStart: (WorkoutRoutine) -> Void
    /// Advance the program pointer to this slot index, marking everything in between as skipped.
    let onSkipTo: (Int) -> Void
    let onReview: (WorkoutSessionLog) -> Void

    @State private var viewedIndex: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(program: WorkoutProgram,
         completedLogsByIndex: [Int: WorkoutSessionLog],
         onStart: @escaping (WorkoutRoutine) -> Void,
         onSkipTo: @escaping (Int) -> Void,
         onReview: @escaping (WorkoutSessionLog) -> Void) {
        self.program = program
        self.completedLogsByIndex = completedLogsByIndex
        self.onStart = onStart
        self.onSkipTo = onSkipTo
        self.onReview = onReview
        self._viewedIndex = State(initialValue: program.currentProgressIndex ?? 0)
    }

    private var currentIndex: Int { program.currentProgressIndex ?? 0 }
    private var totalSlots: Int { max(program.totalSlots, 1) }
    private var skippedIndices: Set<Int> { Set(program.skippedIndices ?? []) }
    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }
    private let visibleExerciseLimit = 3
    private var slotHeight: CGFloat { usesAccessibilityLayout ? 500 : 306 }

    private enum SlotState {
        case completed(WorkoutSessionLog)
        case completedNoDetail
        case skipped
        case current
        case upcoming
    }

    private func state(for index: Int) -> SlotState {
        if let log = completedLogsByIndex[index] { return .completed(log) }
        if skippedIndices.contains(index) { return .skipped }
        if index < currentIndex { return .completedNoDetail }
        if index == currentIndex { return .current }
        return .upcoming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            header

            TabView(selection: $viewedIndex) {
                ForEach(Array(0..<totalSlots), id: \.self) { index in
                    slotCard(for: index)
                        .padding(.horizontal, 2)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: slotHeight)

            positionBar
        }
        .appSurface(.emphasized, radius: AppRadius.hero)
        .accessibilityIdentifier("train_next_step")
        .onChange(of: currentIndex) { _, newValue in
            withAnimation(AppMotion.standard) { viewedIndex = min(max(newValue, 0), totalSlots - 1) }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                headerText
                headerControls
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                headerText
                Spacer()
                headerControls
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today's Best Next Step")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(program.name)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            // DESIGN.md rule 3: progress in words a stranger understands.
            Text("Day \(min(currentIndex + 1, totalSlots)) of \(totalSlots)")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            chevron(systemName: "chevron.left", label: "Previous session", enabled: viewedIndex > 0) {
                withAnimation(AppMotion.standard) { viewedIndex = max(viewedIndex - 1, 0) }
            }
            chevron(systemName: "chevron.right", label: "Next session", enabled: viewedIndex < totalSlots - 1) {
                withAnimation(AppMotion.standard) { viewedIndex = min(viewedIndex + 1, totalSlots - 1) }
            }
        }
    }

    private func chevron(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(AppIconButtonStyle(enabled ? .brand : .neutral))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Slot card

    @ViewBuilder
    private func slotCard(for index: Int) -> some View {
        let routine = program.routine(forSlot: index)
        let wd = program.weekAndDay(forSlot: index)
        let slotState = state(for: index)

        VStack(alignment: .leading, spacing: 12) {
            slotContext(state: slotState, week: wd.week, day: wd.day)

            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 44, height: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine?.name ?? "Rest / Unscheduled")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let routine {
                        Text("\(routine.exercises.count) exercises")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let routine, !usesAccessibilityLayout {
                VStack(spacing: 6) {
                    ForEach(Array(routine.exercises.prefix(visibleExerciseLimit))) { exercise in
                        exercisePreviewRow(exercise)
                    }
                    if routine.exercises.count > visibleExerciseLimit {
                        Text("+ \(routine.exercises.count - visibleExerciseLimit) more")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.brand)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Spacer(minLength: 0)

            actionRow(for: index, state: slotState, routine: routine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func slotContext(state: SlotState, week: Int, day: Int) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                stateChip(for: state)
                Text("Week \(week) · Day \(day)")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                stateChip(for: state)
                Spacer()
                Text("Week \(week) · Day \(day)")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func exercisePreviewRow(_ exercise: RoutineExercise) -> some View {
        if usesAccessibilityLayout {
            HStack(alignment: .top, spacing: 8) {
                exercisePreviewIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(exerciseTargetSummary(exercise))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                exercisePreviewIcon

                Text(exercise.name)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer()

                Text(exerciseTargetSummary(exercise))
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    private var exercisePreviewIcon: some View {
        Image(systemName: "dumbbell.fill")
            .appFont(size: 10, weight: .semibold)
            .foregroundColor(Color(UIColor.secondaryLabel))
            .frame(width: 26, height: 26)
            .background(Color(UIColor.tertiarySystemFill), in: Circle())
    }

    private func exerciseTargetSummary(_ exercise: RoutineExercise) -> String {
        "\(max(exercise.sets.count, exercise.targetSets))×\(exercise.sets.first?.target ?? exercise.targetReps)"
    }

    @ViewBuilder
    private func stateChip(for state: SlotState) -> some View {
        switch state {
        case .completed, .completedNoDetail:
            chip(text: "Completed", icon: "checkmark.circle.fill", color: .accentPositive)
        case .skipped:
            chip(text: "Skipped", icon: "forward.end.fill", color: Color(UIColor.secondaryLabel))
        case .current:
            chip(text: "Next Up", icon: "play.circle.fill", color: .brandPrimary)
        case .upcoming:
            chip(text: "Upcoming", icon: "calendar", color: .blue)
        }
    }

    private func chip(text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .appFont(size: 11, weight: .bold)
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func actionRow(for index: Int, state: SlotState, routine: WorkoutRoutine?) -> some View {
        switch state {
        case .completed(let log):
            Button { onReview(log) } label: {
                Label("Review Session", systemImage: "chart.bar.doc.horizontal")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))

        case .completedNoDetail:
            Text("Logged before detailed analytics were available.")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))

        case .skipped:
            if let routine {
                Button { onStart(routine) } label: {
                    Label("Do It Now", systemImage: "play.fill")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }

        case .current:
            pairedActions(
                primaryTitle: "Start",
                primaryIcon: "play.fill",
                primaryEnabled: routine != nil,
                primaryAction: { if let routine { onStart(routine) } },
                secondaryTitle: "Skip",
                secondaryIcon: "forward.end.fill",
                secondaryAction: { onSkipTo(index + 1) }
            )

        case .upcoming:
            pairedActions(
                primaryTitle: "Start Early",
                primaryIcon: "play.fill",
                primaryEnabled: routine != nil,
                primaryAction: { if let routine { onStart(routine) } },
                secondaryTitle: "Skip to Here",
                secondaryIcon: "forward.fill",
                secondaryAction: { onSkipTo(index) }
            )
        }
    }

    @ViewBuilder
    private func pairedActions(
        primaryTitle: String,
        primaryIcon: String,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryIcon: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        if usesAccessibilityLayout {
            VStack(spacing: AppSpacing.compact) {
                primaryActionButton(
                    title: primaryTitle,
                    icon: primaryIcon,
                    isEnabled: primaryEnabled,
                    action: primaryAction
                )
                secondaryActionButton(title: secondaryTitle, icon: secondaryIcon, action: secondaryAction)
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                primaryActionButton(
                    title: primaryTitle,
                    icon: primaryIcon,
                    isEnabled: primaryEnabled,
                    action: primaryAction
                )
                secondaryActionButton(title: secondaryTitle, icon: secondaryIcon, action: secondaryAction)
            }
        }
    }

    private func primaryActionButton(
        title: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(!isEnabled)
    }

    private func secondaryActionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
    }

    // MARK: Position bar

    private var positionBar: some View {
        VStack(spacing: 6) {
            // Decorative: the "Slot X of Y" text below carries the same info for VoiceOver.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppPalette.brand.opacity(0.12))
                    Capsule()
                        .fill(AppPalette.brand)
                        .frame(width: geo.size.width * CGFloat(Double(currentIndex) / Double(totalSlots)))
                    // Marker for where the user is currently scrubbed.
                    Circle()
                        .fill(AppPalette.brand)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(AppPalette.canvas, lineWidth: 2))
                        .offset(x: max(0, geo.size.width * CGFloat(Double(viewedIndex) / Double(max(totalSlots - 1, 1))) - 5))
                }
            }
            .frame(height: 10)

            positionLabels
        }
    }

    @ViewBuilder
    private var positionLabels: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 2) {
                Text(relativeLabel)
                Text("Slot \(viewedIndex + 1) of \(totalSlots)")
            }
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(relativeLabel)
                Spacer()
                Text("Slot \(viewedIndex + 1) of \(totalSlots)")
            }
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var relativeLabel: String {
        if viewedIndex < currentIndex { return "Swipe ▶ to return to today" }
        if viewedIndex == currentIndex { return "You are here · today's session" }
        let ahead = viewedIndex - currentIndex
        return "\(ahead) session\(ahead == 1 ? "" : "s") ahead"
    }
}
