import MyFitPlateCore

import SwiftUI
struct ProgramDetailHeroCard: View {
    let programName: String
    let statusText: String
    let progress: Double
    let completedWorkouts: Int
    let totalWorkouts: Int
    let routineCount: Int
    let trainingDays: Int
    let exerciseCount: Int
    let setCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Training Program",
                title: programName,
                subtitle: statusText
            ) {
                Text("\(Int((progress * 100).rounded()))% complete")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brand)
                    .padding(.horizontal, AppSpacing.row)
                    .frame(minHeight: 36)
                    .background(
                        AppPalette.brand.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                    .accessibilityLabel("\(Int((progress * 100).rounded())) percent complete")
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("\(completedWorkouts) of \(totalWorkouts) sessions complete")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppPalette.brand.opacity(0.12))

                        Capsule()
                            .fill(AppPalette.brand)
                            .frame(width: geometry.size.width * CGFloat(progress))
                            .animation(AppMotion.standard, value: progress)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)

                AppMetricStrip(items: [
                    AppMetricItem(label: "Routines", value: routineCount.formatted()),
                    AppMetricItem(label: "Days / week", value: trainingDays.formatted(), accent: .blue),
                    AppMetricItem(label: "Exercises", value: exerciseCount.formatted(), accent: .orange),
                    AppMetricItem(label: "Working sets", value: setCount.formatted(), accent: .accentPositive)
                ])
            }
            .appSurface(.emphasized)
        }
    }
}

struct ProgramPreviewActionCard: View {
    let daysPerWeek: Int
    let routineCount: Int
    let isSelecting: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Make This Your Plan",
                subtitle: "Copy this structure into your account, then adjust the schedule whenever you need."
            )

            AppMetricStrip(items: [
                AppMetricItem(label: "Suggested days", value: "\(daysPerWeek) / week", accent: .blue),
                AppMetricItem(label: "Routine rotation", value: routineCount.formatted())
            ])

            Button(action: { onSelect?() }) {
                if isSelecting {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Selecting Plan")
                    }
                } else {
                    Label("Select Plan", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(onSelect == nil || isSelecting)
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("program_detail_select")
    }
}

struct ProgramScheduleSetupCard: View {
    @Binding var startDate: Date
    @Binding var selectedDays: [Int]
    let isScheduled: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: isScheduled ? "Schedule" : "Schedule Your Program",
                subtitle: isScheduled
                    ? "Adjust the start date or training days when life moves around."
                    : "Pick when this block starts and which days you want to train."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    .appTextRole(.control)
                    .tint(AppPalette.brand)

                Divider()

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Training Days")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)

                    WeekDaySelector(selectedDays: $selectedDays)
                }

                Button(action: onSave) {
                    Label(
                        isScheduled ? "Update Schedule" : "Save Schedule",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(selectedDays.isEmpty)
            }
            .appSurface(.quiet)
        }
        .accessibilityIdentifier("program_detail_schedule")
    }
}

struct ProgramExercisePreviewRow: View {
    let exercise: RoutineExercise

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var setCount: Int {
        max(exercise.sets.count, exercise.targetSets)
    }

    private var targetText: String {
        exercise.sets.first?.target ?? exercise.targetReps
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                .font(.body)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .appTextRole(.body)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                Text("\(setCount) sets · \(targetText)")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }

            Spacer(minLength: 0)
        }
    }
}

struct ProgramCalendarCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Training Calendar",
                subtitle: "Tap a completed day to review it or a scheduled day to start."
            )

            content
                .appSurface(.quiet)
        }
        .accessibilityIdentifier("program_detail_calendar")
    }
}

struct ProgramRoutineBreakdownCard: View {
    let routines: [WorkoutRoutine]
    let allowsEditing: Bool
    let allowsStarting: Bool
    let onEdit: (WorkoutRoutine) -> Void
    let onStart: (WorkoutRoutine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Routine Rotation",
                subtitle: allowsEditing
                    ? "Inspect, edit, or start any routine in this block."
                    : "Preview the routines in the order they repeat."
            )

            if routines.isEmpty {
                GuidanceEmptyState(
                    icon: "list.bullet.rectangle",
                    title: "No routines yet",
                    message: "This program doesn't have any routines yet. Add one to start training."
                )
            } else {
                VStack(spacing: AppSpacing.row) {
                    ForEach(routines) { routine in
                        ProgramRoutineCard(
                            routine: routine,
                            allowsEditing: allowsEditing,
                            allowsStarting: allowsStarting,
                            onEdit: { onEdit(routine) },
                            onStart: { onStart(routine) }
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("program_detail_routines")
    }
}

struct ProgramRoutineCard: View {
    let routine: WorkoutRoutine
    let allowsEditing: Bool
    let allowsStarting: Bool
    let onEdit: () -> Void
    let onStart: () -> Void

    @State private var isExpanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visibleExercises: ArraySlice<RoutineExercise> {
        isExpanded ? routine.exercises.prefix(routine.exercises.count) : routine.exercises.prefix(3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        routineIdentity
                        routineActions
                    }
                } else {
                    HStack(spacing: AppSpacing.row) {
                        routineIdentity
                        Spacer(minLength: AppSpacing.compact)
                        routineActions
                    }
                }
            }

            VStack(spacing: AppSpacing.compact) {
                ForEach(Array(visibleExercises.enumerated()), id: \.element.id) { index, exercise in
                    ProgramExercisePreviewRow(exercise: exercise)

                    if index < visibleExercises.count - 1 {
                        Divider()
                    }
                }
            }

            if routine.exercises.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "Show Less" : "Show All Exercises", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .appTextRole(.caption)
                        .foregroundStyle(AppPalette.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .appSurface(.quiet)
    }

    private var routineIdentity: some View {
        HStack(spacing: AppSpacing.row) {
            Text(ExerciseEmojiMapper.getEmoji(for: routine.exercises.first?.name ?? routine.name))
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.brand.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                Text("\(routine.exercises.count) exercises")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var routineActions: some View {
        HStack(spacing: AppSpacing.compact) {
            if allowsEditing {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Edit \(routine.name)")
            }

            if allowsStarting {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Start \(routine.name)")
            }
        }
    }
}

struct CalendarView: View {
    let workoutMap: [Date: WorkoutRoutine]
    let completedLogs: [Date: WorkoutSessionLog]
    let skippedDates: Set<Date>
    @Binding var routineToPlay: WorkoutRoutine?
    let onReview: (WorkoutSessionLog) -> Void
    @State private var month: Date = Date()
    
    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let workout: WorkoutRoutine?
        let completedLog: WorkoutSessionLog?
        let isSkipped: Bool

        var isCompleted: Bool {
            completedLog != nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: -1, to: self.month) ?? self.month }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Previous month")

                Spacer()

                Text(month, formatter: monthYearFormatter)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: 1, to: self.month) ?? self.month }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Next month")
            }

            HStack(spacing: 6) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, weekday in
                    Text(String(weekday.prefix(1)))
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(weekday)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysForMonth()) { dayEntry in
                    if dayEntry.date == Date.distantPast {
                        Color.clear
                            .frame(height: 38)
                    } else {
                        Button(action: {
                            if let log = dayEntry.completedLog {
                                onReview(log)
                            } else if let workout = dayEntry.workout {
                                self.routineToPlay = workout
                            }
                        }) {
                            ZStack(alignment: .topTrailing) {
                                Text(dayOfMonth(dayEntry.date))
                                    .appFont(size: 13, weight: dayEntry.workout == nil ? .medium : .bold)
                                    .foregroundColor(dayColor(for: dayEntry))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(dayBackground(for: dayEntry))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(isSameDay(dayEntry.date, Date()) ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
                                    )

                                if dayEntry.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .appFont(size: 12, weight: .bold)
                                        .foregroundColor(.accentPositive)
                                        .background(Color.backgroundPrimary, in: Circle())
                                        .offset(x: 1, y: -1)
                                } else if dayEntry.isSkipped {
                                    Image(systemName: "forward.end.fill")
                                        .appFont(size: 10, weight: .bold)
                                        .foregroundColor(Color(UIColor.secondaryLabel))
                                        .background(Color.backgroundPrimary, in: Circle())
                                        .offset(x: 1, y: -1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(dayEntry.workout == nil && dayEntry.completedLog == nil)
                        .accessibilityLabel(dayAccessibilityLabel(for: dayEntry))
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
    
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
    
    private func daysForMonth() -> [DayEntry] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDayOfMonth = monthInterval.start
        
        var entries: [DayEntry] = []
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        if firstWeekday > 1 {
            for _ in 1..<firstWeekday {
                entries.append(DayEntry(date: Date.distantPast, workout: nil, completedLog: nil, isSkipped: false))
            }
        }

        if let numberOfDays = calendar.range(of: .day, in: .month, for: month)?.count {
            for day in 1...numberOfDays {
                var components = calendar.dateComponents([.year, .month], from: firstDayOfMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    let normalizedDate = calendar.startOfDay(for: date)
                    entries.append(
                        DayEntry(
                            date: normalizedDate,
                            workout: workoutMap[normalizedDate],
                            completedLog: completedLogs[normalizedDate],
                            isSkipped: skippedDates.contains(normalizedDate)
                        )
                    )
                }
            }
        }
        return entries
    }
    
    private func dayOfMonth(_ date: Date) -> String {
        guard date != Date.distantPast else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        guard date1 != Date.distantPast, date2 != Date.distantPast else { return false }
        return Calendar.current.isDate(date1, inSameDayAs: date2)
    }

    private func dayBackground(for dayEntry: DayEntry) -> Color {
        if dayEntry.isCompleted {
            return Color.accentPositive.opacity(0.14)
        }

        if dayEntry.isSkipped {
            return Color(UIColor.secondaryLabel).opacity(0.12)
        }

        if dayEntry.workout != nil {
            return Color.brandPrimary.opacity(0.14)
        }

        return Color.backgroundSecondary.opacity(0.50)
    }

    private func dayColor(for dayEntry: DayEntry) -> Color {
        if dayEntry.isCompleted {
            return .accentPositive
        }

        if dayEntry.isSkipped {
            return Color(UIColor.secondaryLabel)
        }

        if dayEntry.workout != nil || isSameDay(dayEntry.date, Date()) {
            return .brandPrimary
        }

        return Color(UIColor.secondaryLabel)
    }

    private func dayAccessibilityLabel(for entry: DayEntry) -> String {
        let date = entry.date.formatted(date: .long, time: .omitted)
        if entry.isCompleted {
            return "\(date), completed workout. Double tap to review."
        }
        if entry.isSkipped {
            return "\(date), skipped workout."
        }
        if let workout = entry.workout {
            return "\(date), \(workout.name). Double tap to start."
        }
        return date
    }
}
