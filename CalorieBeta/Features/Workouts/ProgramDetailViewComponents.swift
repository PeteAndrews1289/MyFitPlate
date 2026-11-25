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
    let skippedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(programName)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(statusText)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(completedWorkouts) of \(totalWorkouts) sessions passed")
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.text)
                .accessibilityIdentifier("program_progress_summary")
            if skippedCount > 0 {
                Text("Includes \(skippedCount.formatted()) explicitly skipped sessions")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            AppProgressTrack(progress: progress, role: .effort, height: 6)
                .accessibilityHidden(true)
            Text("\(routineCount.formatted()) routines · \(trainingDays.formatted()) training days per week")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
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
                AppMetricItem(label: "Suggested days", value: "\(daysPerWeek) / week", accent: AppPalette.effort),
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
    var isSaving = false
    var feedback: String?
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
                AppDateField("Start Date", selection: $startDate)
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
                        isSaving ? "Saving schedule…" : isScheduled ? "Update Schedule" : "Save Schedule",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(selectedDays.isEmpty || isSaving)
                .accessibilityIdentifier("program_schedule_save")
                if let feedback { Text(feedback).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .disabled(isSaving)
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
            Image(systemName: exercise.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(exercise.type.color)
                .frame(width: 30, height: 30)
                .background(exercise.type.color.opacity(0.10), in: Circle())

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

    private var primaryType: ExerciseType {
        routine.exercises.first?.type
            ?? RoutineEditorDefaults.inferredType(name: routine.name, category: nil)
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
                        .foregroundStyle(AppPalette.brandText)
                }
                .buttonStyle(.plain)
            }
        }
        .appSurface(.quiet)
    }

    private var routineIdentity: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: primaryType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(primaryType.color)
                .frame(width: 40, height: 40)
                .background(
                    primaryType.color.opacity(0.10),
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
    let onStart: (WorkoutRoutine, Date) -> Void
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
                                onStart(workout, dayEntry.date)
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

struct ProgramBlockReviewCard: View {
    let review: WorkoutBlockReview
    let isLoading: Bool
    let hasLoaded: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Block review").appTextRole(.sectionTitle)
            Text("Your position and your recorded training are shown separately.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if isLoading && !hasLoaded {
                ProgressView("Loading workout evidence").appTextRole(.secondary)
            }
            if hasLoaded {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppSpacing.group) { evidenceMetrics }
                    VStack(alignment: .leading, spacing: AppSpacing.row) { evidenceMetrics }
                }
                .accessibilityIdentifier("program_block_evidence_summary")
                Text("\(review.completedSlots) positions with complete sets · \(review.partialSlots) partial · \(review.unknownSlots) coverage unknown")
                    .appTextRole(.secondary).accessibilityIdentifier("program_block_outcome_summary")
                Text("\(review.movedSlots) explicitly moved positions · \(review.substitutedReceipts) receipts with substitutions")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if review.legacyMatches > 0 {
                    Text("\(review.legacyMatches) older logs matched by routine and date.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if review.loggedAhead > 0 {
                    Text("\(review.loggedAhead) linked logs are ahead of the current position.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if review.logsOnSkippedSlots > 0 {
                    Text("\(review.logsOnSkippedSlots) previously skipped positions also have logs. They appear with the recorded work.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Review by week") {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        ForEach(Array(review.weeks.enumerated()), id: \.element.id) { index, week in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(week.name).appTextRole(.control)
                                Text("\(week.passedSlots) of \(week.totalSlots) positions passed · \(week.linkedLogs) linked logs · \(week.skippedSlots) skipped")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                                Text("\(week.outcomes.filter { $0.state == .completed }.count) completed · \(week.outcomes.filter { $0.state == .partial }.count) partial · \(week.outcomes.filter { $0.state == .unknown }.count) unknown · \(week.outcomes.filter(\.isMoved).count) moved")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                                if week.legacyMatches > 0 {
                                    Text("\(week.legacyMatches) older matched logs").appTextRole(.caption).foregroundStyle(.secondary)
                                }
                                if week.passedWithoutLog > 0 {
                                    Text("\(week.passedWithoutLog) passed without a matching log")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }
                                if week.isDeload {
                                    Text("Lighter-week label").appTextRole(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("program_block_review_week_\(index)")
                            if index < review.weeks.count - 1 { Divider() }
                        }
                    }
                    .padding(.top, AppSpacing.row)
                }
                .appTextRole(.control)
                .accessibilityIdentifier("program_block_review_weeks")
                DisclosureGroup("Inspect position outcomes") {
                    ForEach(review.outcomes) { outcome in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Position \(outcome.slotIndex + 1) · \(outcome.state.title)").appTextRole(.control)
                            if outcome.isMoved, let old = outcome.originalDay?.date(), let new = outcome.scheduledDay?.date() {
                                Text("Reviewed move: \(old.formatted(date: .abbreviated, time: .omitted)) → \(new.formatted(date: .abbreviated, time: .omitted))")
                                    .appTextRole(.secondary)
                            }
                            Text(outcome.explanation).appTextRole(.caption).foregroundStyle(.secondary)
                            ForEach(outcome.sessions) { receipt in
                                Text("\(receipt.date.formatted(date: .abbreviated, time: .omitted)) · \(receipt.title) · \(receipt.substitutionExerciseIDs.count) substitutions")
                                    .appTextRole(.secondary)
                                Text(receipt.explanation).appTextRole(.caption).foregroundStyle(.secondary)
                                Text("Receipt: \(receipt.sessionID)").appTextRole(.caption).textSelection(.enabled)
                            }
                        }.padding(.vertical, AppSpacing.compact)
                    }
                }.buttonStyle(AppListButtonStyle()).frame(minHeight: 44).accessibilityIdentifier("program_block_outcome_details")
                Text("A linked log identifies this program and position. Coverage compares frozen original working sets; it does not mean load, reps or effort targets were achieved. Replacement movements are not assumed equivalent. Older or incomplete evidence stays Unknown.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if review.passedSlots == review.totalSlots && review.totalSlots > 0 {
                    Text("All positions passed. Review skipped sessions and missing logs before planning your next block.")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.brandText)
                }
            }
            if let errorMessage {
                Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("program_block_history_error")
                if hasLoaded {
                    Text("The review still shows your last loaded evidence.").appTextRole(.caption).foregroundStyle(.secondary)
                }
                Button("Retry workout evidence", action: onRetry)
                    .frame(minHeight: 44).disabled(isLoading)
                    .accessibilityIdentifier("program_block_history_retry")
            }
        }
        .appSurface(.quiet).accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_block_review")
    }

    private var evidenceMetrics: some View {
        Group {
            metric("Linked logs", value: review.linkedLogs, identifier: "program_block_linked_logs")
            metric("Skipped", value: review.skippedSlots, identifier: "program_block_skipped")
            metric("Passed, no log", value: review.passedWithoutLog, identifier: "program_block_unlinked_passed")
        }
    }

    private func metric(_ title: String, value: Int, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted()).appTextRole(.sectionTitle).monospacedDigit()
            Text(title).appTextRole(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }
}

struct ProgramBlockPerformanceCard: View {
    let evidence: WorkoutBlockPerformance

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Comparable lifting").appTextRole(.sectionTitle)
            Text("First and latest linked sessions, at the same reps and in the same exercise and equipment context.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            if evidence.comparisons.isEmpty {
                Text("Two comparable linked sessions are needed. Missing logs and different equipment are not counted as zero performance.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Review \(evidence.comparisons.count) exercise comparisons") {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        ForEach(evidence.comparisons) { comparison in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(comparison.name).appTextRole(.control)
                                Text(comparison.context).appTextRole(.caption).foregroundStyle(.secondary)
                                Text("\(comparison.unit.displayWeight(comparison.firstWeightPounds).formatted(.number.precision(.fractionLength(0...2)))) → \(comparison.unit.displayWeight(comparison.latestWeightPounds).formatted(.number.precision(.fractionLength(0...2)))) \(comparison.unit.rawValue) × \(comparison.repetitions) reps")
                                    .appTextRole(.secondary).monospacedDigit()
                                Text("\(comparison.firstDate.formatted(date: .abbreviated, time: .omitted)) to \(comparison.latestDate.formatted(date: .abbreviated, time: .omitted)) · \(comparison.comparableSessions) comparable sessions")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                        }
                    }.padding(.top, AppSpacing.row)
                }
                .accessibilityIdentifier("program_block_load_comparisons")
            }
            Text("Effort recorded on \(evidence.effortRecordedSets) of \(evidence.workingSets) eligible working sets. Warm-ups are excluded.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            if let gap = evidence.longestGapDays, gap > 0 {
                Text("Longest gap between linked logs: \(gap) days.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet).accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_block_performance")
    }
}

struct ProgramPlanningReviewCard: View {
    let program: WorkoutProgram
    private var summary: WorkoutProgramPlanningSummary { WorkoutProgramPlanningSummary.make(program) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Plan fit").appTextRole(.sectionTitle)
            Text("Equipment families inferred from the listed movements: \(summary.equipment.isEmpty ? "review each movement" : summary.equipment.joined(separator: ", ")).")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if !summary.ambiguousMovements.isEmpty {
                Text("Confirm the implement for: \(summary.ambiguousMovements.prefix(3).joined(separator: ", "))\(summary.ambiguousMovements.count > 3 ? " and \(summary.ambiguousMovements.count - 3) more" : "").")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if let minimum = summary.minimumEstimatedMinutes, let maximum = summary.maximumEstimatedMinutes {
                Text(minimum == maximum ? "Planning estimate: \(maximum) min per session" : "Planning estimate: \(minimum)–\(maximum) min per session")
                    .appTextRole(.control)
            } else {
                Text("Session time needs review because some targets are open-ended or manual.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if summary.manualTargetSets > 0 {
                Text("\(summary.manualTargetSets) sets have manual or open-ended targets. Review them before starting or automating progression.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            Text("Time estimates include 5 minutes warm-up, setup, upper-target reps and prescribed rest. Actual time varies. Automatic progression is not inferred from a program's name.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
        .appSurface(.quiet).accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_planning_review")
    }
}
