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
        VStack(alignment: .leading, spacing: 14) {
            header

            TabView(selection: $viewedIndex) {
                ForEach(Array(0..<totalSlots), id: \.self) { index in
                    slotCard(for: index)
                        .padding(.horizontal, 2)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 318)

            positionBar
        }
        .asCard()
        .onChange(of: currentIndex) { _, newValue in
            withAnimation(.easeInOut) { viewedIndex = min(max(newValue, 0), totalSlots - 1) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Best Next Step")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .textCase(.uppercase)

                Text(program.name)
                    .appFont(size: 21, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                // DESIGN.md rule 3: progress in words a stranger understands.
                Text("Day \(min(currentIndex + 1, totalSlots)) of \(totalSlots)")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            HStack(spacing: 8) {
                chevron(systemName: "chevron.left", label: "Previous session", enabled: viewedIndex > 0) {
                    withAnimation { viewedIndex = max(viewedIndex - 1, 0) }
                }
                chevron(systemName: "chevron.right", label: "Next session", enabled: viewedIndex < totalSlots - 1) {
                    withAnimation { viewedIndex = min(viewedIndex + 1, totalSlots - 1) }
                }
            }
        }
    }

    private func chevron(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(enabled ? .brandPrimary : Color(UIColor.tertiaryLabel))
                .frame(width: 34, height: 34)
                .background(Color.brandPrimary.opacity(enabled ? 0.10 : 0.04), in: Circle())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                stateChip(for: slotState)
                Spacer()
                Text("Week \(wd.week) · Day \(wd.day)")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            HStack(spacing: 10) {
                Text(ExerciseEmojiMapper.getEmoji(for: routine?.exercises.first?.name ?? routine?.name ?? "💪"))
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine?.name ?? "Rest / Unscheduled")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let routine {
                        Text("\(routine.exercises.count) exercises")
                            .appFont(size: 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
                Spacer(minLength: 0)
            }

            if let routine {
                VStack(spacing: 6) {
                    ForEach(Array(routine.exercises.prefix(3))) { exercise in
                        HStack(spacing: 8) {
                            Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                                .font(.footnote)
                                .frame(width: 26, height: 26)
                                .background(Color(UIColor.tertiarySystemFill), in: Circle())
                            Text(exercise.name)
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(max(exercise.sets.count, exercise.targetSets))×\(exercise.sets.first?.target ?? exercise.targetReps)")
                                .appFont(size: 11, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .lineLimit(1)
                        }
                    }
                    if routine.exercises.count > 3 {
                        Text("+ \(routine.exercises.count - 3) more")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(Color.backgroundPrimary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer(minLength: 0)

            actionRow(for: index, state: slotState, routine: routine)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.backgroundSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .buttonStyle(SecondaryButtonStyle())

        case .completedNoDetail:
            Text("Logged before detailed analytics were available.")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))

        case .skipped:
            if let routine {
                Button { onStart(routine) } label: {
                    Label("Do It Now", systemImage: "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

        case .current:
            HStack(spacing: 10) {
                Button { if let routine { onStart(routine) } } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(routine == nil)

                Button { onSkipTo(index + 1) } label: {
                    Label("Skip", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

        case .upcoming:
            HStack(spacing: 10) {
                Button { if let routine { onStart(routine) } } label: {
                    Label("Start Early", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(routine == nil)

                Button { onSkipTo(index) } label: {
                    Label("Skip to Here", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Position bar

    private var positionBar: some View {
        VStack(spacing: 6) {
            // Decorative: the "Slot X of Y" text below carries the same info for VoiceOver.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.brandPrimary.opacity(0.12))
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: geo.size.width * CGFloat(Double(currentIndex) / Double(totalSlots)))
                    // Marker for where the user is currently scrubbed.
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.backgroundPrimary, lineWidth: 2))
                        .offset(x: max(0, geo.size.width * CGFloat(Double(viewedIndex) / Double(max(totalSlots - 1, 1))) - 5))
                }
            }
            .frame(height: 10)

            HStack {
                Text(relativeLabel)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Spacer()
                Text("Slot \(viewedIndex + 1) of \(totalSlots)")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
    }

    private var relativeLabel: String {
        if viewedIndex < currentIndex { return "Swipe ▶ to return to today" }
        if viewedIndex == currentIndex { return "You are here · today's session" }
        let ahead = viewedIndex - currentIndex
        return "\(ahead) session\(ahead == 1 ? "" : "s") ahead"
    }
}
