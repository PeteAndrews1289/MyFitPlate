import MyFitPlateCore

import SwiftUI
// MARK: - Today's Best Next Step

/// A scrubbable replacement for the old "Continue Program" card. It centers on the program's
/// current slot and lets the user swipe back through finished sessions (to review) or forward
/// through upcoming ones (to start early or skip ahead).
struct TodaysNextStepSlider: View {
    let program: WorkoutProgram
    /// Completed session logs keyed by the slot index they belong to.
    let completedLogsByIndex: [Int: WorkoutSessionLog]
    let onStart: (WorkoutRoutine, Int) -> Void
    /// Advance the program pointer to this slot index, marking everything in between as skipped.
    let onSkipTo: (Int) -> Void
    let onReview: (WorkoutSessionLog) -> Void
    let skipFuelReview: String?
    let showsExercisePreview: Bool

    @State private var viewedIndex: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(program: WorkoutProgram,
         completedLogsByIndex: [Int: WorkoutSessionLog],
         onStart: @escaping (WorkoutRoutine, Int) -> Void,
         onSkipTo: @escaping (Int) -> Void,
         onReview: @escaping (WorkoutSessionLog) -> Void, skipFuelReview: String? = nil,
         showsExercisePreview: Bool = true) {
        self.program = program
        self.completedLogsByIndex = completedLogsByIndex
        self.onStart = onStart
        self.onSkipTo = onSkipTo
        self.onReview = onReview
        self.skipFuelReview = skipFuelReview
        self.showsExercisePreview = showsExercisePreview
        self._viewedIndex = State(initialValue: min(max(program.currentProgressIndex ?? 0, 0), max(program.totalSlots - 1, 0)))
    }

    private var currentIndex: Int { program.currentProgressIndex ?? 0 }
    private var totalSlots: Int { max(program.totalSlots, 1) }
    @State private var pendingSkip: Int?
    @State private var expandedExerciseSlot: Int?

    private var skippedIndices: Set<Int> { Set(program.skippedIndices ?? []) }
    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }
    private let visibleExerciseLimit = 2

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

            slotCard(for: min(max(viewedIndex, 0), totalSlots - 1))
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > max(70, abs(value.translation.height) * 2) else { return }
                    withAnimation(AppMotion.standard) {
                        viewedIndex = min(max(viewedIndex + (value.translation.width < 0 ? 1 : -1), 0), totalSlots - 1)
                    }
                })

            positionBar
        }
        .appSurface(.quiet, radius: AppRadius.hero)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppPalette.effort)
                .frame(width: 4)
                .padding(.vertical, AppSpacing.group)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("train_next_step")
        .onChange(of: program.id) { _, _ in
            expandedExerciseSlot = nil
            viewedIndex = min(max(currentIndex, 0), totalSlots - 1)
        }
        .onChange(of: viewedIndex) { _, _ in expandedExerciseSlot = nil }
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
            Text(program.name)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .buttonStyle(AppIconButtonStyle(.neutral))
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
                    .foregroundStyle(AppPalette.effort)
                    .frame(width: 44, height: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine?.name ?? "Rest / Unscheduled")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let routine, !routine.exercises.isEmpty {
                        Button {
                            expandedExerciseSlot = expandedExerciseSlot == index ? nil : index
                        } label: {
                            HStack(spacing: 5) {
                                Text("\(routine.exercises.count) exercises")
                                Image(systemName: expandedExerciseSlot == index ? "chevron.up" : "chevron.down")
                                    .appTextRole(.caption)
                            }
                            .appTextRole(.secondary).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                        .accessibilityValue(expandedExerciseSlot == index ? "Expanded" : "Collapsed")
                        .accessibilityIdentifier("train_exercise_preview")
                    }
                }
                Spacer(minLength: 0)
            }

            if let routine, expandedExerciseSlot == index || (showsExercisePreview && !usesAccessibilityLayout) {
                VStack(spacing: 6) {
                    ForEach(Array(routine.exercises.prefix(expandedExerciseSlot == index ? routine.exercises.count : visibleExerciseLimit))) { exercise in
                        exercisePreviewRow(exercise)
                    }
                    if expandedExerciseSlot != index, routine.exercises.count > visibleExerciseLimit {
                        Text("+ \(routine.exercises.count - visibleExerciseLimit) more")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.effort)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            actionRow(for: index, state: slotState, routine: routine)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            AppStatusBadge("Completed", icon: "checkmark.circle.fill", role: .positive)
        case .skipped:
            AppStatusBadge("Skipped", icon: "forward.end.fill", role: .neutral)
        case .current:
            AppStatusBadge("Next Up", icon: "play.circle.fill", role: .current)
        case .upcoming:
            AppStatusBadge("Upcoming", icon: "calendar", role: .effort)
        }
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
                Button { onStart(routine, index) } label: {
                    Label("Do It Now", systemImage: "play.fill")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }

        case .current:
            pairedActions(
                primaryTitle: "Start workout",
                primaryIcon: "play.fill",
                primaryEnabled: routine != nil,
                primaryAction: { if let routine { onStart(routine, index) } },
                secondaryTitle: "Skip",
                secondaryIcon: "forward.end.fill",
                secondaryAction: { pendingSkip = index + 1 }
            )

        case .upcoming:
            pairedActions(
                primaryTitle: "Start early",
                primaryIcon: "play.fill",
                primaryEnabled: routine != nil,
                primaryAction: { if let routine { onStart(routine, index) } },
                secondaryTitle: "Skip to Here",
                secondaryIcon: "forward.fill",
                secondaryAction: { pendingSkip = index }
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
        HStack(spacing: AppSpacing.compact) {
            primaryActionButton(title: primaryTitle, icon: primaryIcon, isEnabled: primaryEnabled, action: primaryAction)
            Menu {
                Button(secondaryTitle, systemImage: secondaryIcon, action: secondaryAction)
            } label: {
                Image(systemName: "ellipsis")
                    .appTextRole(.control)
                    .frame(width: 48, height: 48)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
            .accessibilityLabel("Workout options")
            .accessibilityIdentifier("workout_slot_options")
        }
        .sheet(isPresented: Binding(get: { pendingSkip != nil }, set: { if !$0 { pendingSkip = nil } })) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Review skipped sessions").appTextRole(.sectionTitle)
                        Text("Completed receipts stay saved. Only uncompleted slots in this reviewed range are marked skipped. Undo is available until later work or a conflicting plan change; it never removes completed history.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        if let skipFuelReview { Text(skipFuelReview).appTextRole(.secondary).foregroundStyle(.secondary) }
                        let end = min(pendingSkip ?? currentIndex, program.totalSlots)
                        ForEach(Array(currentIndex..<max(currentIndex, end)), id: \.self) { slot in
                            let completed = completedLogsByIndex[slot] != nil
                            Text("Session \(slot + 1): \(program.routine(forSlot: slot)?.name ?? "Session") · \(program.date(forSlot: slot)?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled") · \(completed ? "already recorded, kept" : "will skip")")
                                .appTextRole(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        Button("Skip workouts", role: .destructive) {
                            if let target = pendingSkip { onSkipTo(target) }; pendingSkip = nil
                        }.buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("workout_skip_confirm")
                    }.padding(AppSpacing.screenHorizontal)
                }
                .accessibilityIdentifier("workout_skip_review")
                .navigationTitle("Review skip").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep current plan") { pendingSkip = nil } } }
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

    // MARK: Position bar

    private var positionBar: some View {
        VStack(spacing: 6) {
            // Decorative: the "Slot X of Y" text below carries the same info for VoiceOver.
            GeometryReader { geo in
                AppProgressTrack(
                    progress: Double(min(currentIndex, totalSlots)) / Double(totalSlots),
                    role: .effort,
                    height: 8
                )
                .overlay(alignment: .leading) {
                    // Marker for where the user is currently scrubbed.
                    Circle()
                        .fill(AppPalette.effort)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(AppPalette.canvas, lineWidth: 2))
                        .offset(x: max(0, geo.size.width * CGFloat(Double(viewedIndex) / Double(max(totalSlots - 1, 1))) - 5))
                }
            }
            .frame(height: 10)

            positionLabels
        }
    }

    private var positionLabels: some View {
        let layout = usesAccessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
            : AnyLayout(HStackLayout(spacing: AppSpacing.row))
        return layout {
            Text("Session \(viewedIndex + 1) of \(totalSlots)")
                .monospacedDigit()
            if (0..<totalSlots).contains(currentIndex), viewedIndex != currentIndex {
                if !usesAccessibilityLayout { Spacer(minLength: 0) }
                Button {
                    withAnimation(AppMotion.standard) { viewedIndex = currentIndex }
                } label: {
                    Label("Back to current", systemImage: "arrow.uturn.backward")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                .accessibilityIdentifier("train_return_to_current")
            }
        }
        .appTextRole(.caption)
        .foregroundStyle(.secondary)
    }
}
