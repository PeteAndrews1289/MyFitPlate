import SwiftUI
import FirebaseFirestore

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Program")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(programName)
                        .appFont(size: 27, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(statusText)
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(spacing: 2) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.brandPrimary)

                    Text("done")
                        .appFont(size: 10, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.10), in: Circle())
                .overlay(
                    Circle()
                        .trim(from: 0, to: max(progress, 0.02))
                        .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(completedWorkouts) of \(totalWorkouts) workouts complete")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    Spacer()
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPrimary.opacity(0.12))

                        Capsule()
                            .fill(Color.brandPrimary)
                            .frame(width: geometry.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.35), value: progress)
                    }
                }
                .frame(height: 8)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ProgramMetricTile(title: "Routines", value: "\(routineCount)", color: .brandPrimary)
                ProgramMetricTile(title: "Days/week", value: "\(trainingDays)", color: .blue)
                ProgramMetricTile(title: "Exercises", value: "\(exerciseCount)", color: .orange)
                ProgramMetricTile(title: "Working sets", value: "\(setCount)", color: .accentPositive)
            }
        }
        .asCard()
    }
}

struct ProgramMetricTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProgramPreviewActionCard: View {
    let daysPerWeek: Int
    let routineCount: Int
    let isSelecting: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Make This Your Plan")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("This copies the program into your account, starts it today, and keeps the suggested training days. You can adjust the schedule later.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                ProgramMetricTile(title: "Suggested days", value: "\(daysPerWeek)/wk", color: .blue)
                ProgramMetricTile(title: "Routine rotation", value: "\(routineCount)", color: .brandPrimary)
            }

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
            .buttonStyle(PrimaryButtonStyle())
            .disabled(onSelect == nil || isSelecting)
            .opacity(onSelect == nil ? 0.55 : 1)
        }
        .asCard()
    }
}

struct ProgramScheduleSetupCard: View {
    @Binding var startDate: Date
    @Binding var selectedDays: [Int]
    let isScheduled: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isScheduled ? "Schedule" : "Schedule Your Program")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(isScheduled ? "Adjust the start date or training days when life moves around." : "Pick when this block starts and which days you want to train.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                .appFont(size: 15, weight: .semibold)
                .tint(.brandPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Training Days")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .textCase(.uppercase)

                WeekDaySelector(selectedDays: $selectedDays)
            }

            Button(action: onSave) {
                Label(isScheduled ? "Update Schedule" : "Save Schedule", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedDays.isEmpty)
            .opacity(selectedDays.isEmpty ? 0.55 : 1)
        }
        .asCard()
    }
}

struct ProgramNextWorkoutCard: View {
    let nextWorkout: (routine: WorkoutRoutine, title: String)
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Session")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(nextWorkout.routine.name)
                        .appFont(size: 22, weight: .bold)
                        .foregroundColor(.textPrimary)
                }

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(nextWorkout.routine.exercises.prefix(5)) { exercise in
                    ProgramExercisePreviewRow(exercise: exercise)
                }

                if nextWorkout.routine.exercises.count > 5 {
                    Text("+ \(nextWorkout.routine.exercises.count - 5) more")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(.brandPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onStart) {
                Label(nextWorkout.title, systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .asCard()
    }
}

struct ProgramExercisePreviewRow: View {
    let exercise: RoutineExercise

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
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("\(setCount) sets • \(targetText)")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

struct ProgramCompleteSummaryCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 21, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 44, height: 44)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Program Complete")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("You finished this block. Keep it for history or build the next phase from what worked.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .asCard()
    }
}

struct ProgramCalendarCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Training Calendar")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Tap a scheduled day to start that workout.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            content
        }
        .asCard()
    }
}

struct ProgramRoutineBreakdownCard: View {
    let routines: [WorkoutRoutine]
    let allowsEditing: Bool
    let allowsStarting: Bool
    let onEdit: (WorkoutRoutine) -> Void
    let onStart: (WorkoutRoutine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout Breakdown")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Inspect, edit, or start any routine in this block.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            if routines.isEmpty {
                GuidanceEmptyState(
                    icon: "list.bullet.rectangle",
                    title: "No routines yet",
                    message: "This program doesn't have any routines yet. Add one to start training."
                )
            } else {
                VStack(spacing: 10) {
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
        .asCard()
    }
}

struct ProgramRoutineCard: View {
    let routine: WorkoutRoutine
    let allowsEditing: Bool
    let allowsStarting: Bool
    let onEdit: () -> Void
    let onStart: () -> Void

    @State private var isExpanded = false

    private var visibleExercises: ArraySlice<RoutineExercise> {
        isExpanded ? routine.exercises.prefix(routine.exercises.count) : routine.exercises.prefix(3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(ExerciseEmojiMapper.getEmoji(for: routine.exercises.first?.name ?? routine.name))
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text("\(routine.exercises.count) exercises")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                if allowsEditing {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.blue)
                            .frame(width: 31, height: 31)
                            .background(Color.blue.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if allowsStarting {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 31, height: 31)
                            .background(Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 8) {
                ForEach(visibleExercises) { exercise in
                    ProgramExercisePreviewRow(exercise: exercise)
                }
            }

            if routine.exercises.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "Show Less" : "Show All Exercises", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CalendarView: View {
    let workoutMap: [Date: WorkoutRoutine]
    let completedLogs: [Date: WorkoutSessionLog]
    let skippedDates: Set<Date>
    @Binding var routineToPlay: WorkoutRoutine?
    let onReview: (WorkoutSessionLog) -> Void
    @State private var month: Date = Date()
    
    private let days = ["S", "M", "T", "W", "T", "F", "S"]
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
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.brandPrimary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(month, formatter: monthYearFormatter)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: 1, to: self.month) ?? self.month }) {
                    Image(systemName: "chevron.right")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.brandPrimary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    Text(day)
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
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
                    }
                }
            }
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
}

