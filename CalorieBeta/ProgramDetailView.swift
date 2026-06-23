import SwiftUI
import FirebaseFirestore

struct ProgramDetailView: View {
    @State private var program: WorkoutProgram
    let isPreview: Bool
    let isSelectingProgram: Bool
    let onSelectProgram: (() -> Void)?

    @EnvironmentObject var workoutService: WorkoutService

    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var nextRoutineToPlay: WorkoutRoutine?
    @State private var calendarRoutineToPlay: WorkoutRoutine?
    @State private var completedSessions: [Date: Bool] = [:]
    @State private var routineToEdit: WorkoutRoutine?

    init(program: WorkoutProgram, isPreview: Bool = false, isSelectingProgram: Bool = false, onSelectProgram: (() -> Void)? = nil) {
        self._program = State(initialValue: program)
        self.isPreview = isPreview
        self.isSelectingProgram = isSelectingProgram
        self.onSelectProgram = onSelectProgram
    }

    private var totalProgramWorkouts: Int {
        max((program.daysOfWeek?.count ?? 0) * 12, program.routines.count)
    }

    private var completedWorkouts: Int {
        min(program.currentProgressIndex ?? 0, totalProgramWorkouts)
    }

    private var programProgress: Double {
        guard totalProgramWorkouts > 0 else { return 0 }
        return min(Double(completedWorkouts) / Double(totalProgramWorkouts), 1)
    }

    private var totalExerciseCount: Int {
        program.routines.reduce(0) { $0 + $1.exercises.count }
    }

    private var totalSetCount: Int {
        program.routines.reduce(0) { partial, routine in
            partial + routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
        }
    }

    private var statusText: String {
        if isPreview {
            return "Preview the structure, then select it to schedule your own copy."
        }

        if program.startDate == nil {
            return "Schedule this plan when you are ready to begin."
        }

        if nextWorkoutInfo == nil {
            return "Program complete. Review the work or build your next phase."
        }

        return "Active plan. Keep the next session clear and easy to start."
    }
    
    private var calendarWorkoutMap: [Date: WorkoutRoutine] {
        guard let startDate = program.startDate?.dateValue(), let daysOfWeek = program.daysOfWeek, !daysOfWeek.isEmpty else { return [:] }
        
        var map: [Date: WorkoutRoutine] = [:]
        let calendar = Calendar.current
        var routineIndex = 0
        
        for dayOffset in 0..<(7 * 12) {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                let weekday = calendar.component(.weekday, from: date)
                if daysOfWeek.contains(weekday) {
                    if !program.routines.isEmpty {
                        let routine = program.routines[routineIndex % program.routines.count]
                        map[calendar.startOfDay(for: date)] = routine
                        routineIndex += 1
                    }
                }
            }
        }
        return map
    }
    
    private var nextWorkoutInfo: (routine: WorkoutRoutine, title: String)? {
        guard let progressIndex = program.currentProgressIndex,
              !program.routines.isEmpty,
              let daysPerWeek = program.daysOfWeek?.count, daysPerWeek > 0 else {
            return nil
        }
        
        let totalWorkoutsInProgram = daysPerWeek * 12
        guard progressIndex < totalWorkoutsInProgram else {
            return nil
        }
        
        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }
        let routine = program.routines[routineIndex]
        
        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Begin Week \(weekNumber), Day \(dayNumber)"
        
        return (routine, title)
    }
    
    private var startDateBinding: Binding<Date> {
        Binding<Date>(
            get: { self.program.startDate?.dateValue() ?? Date() },
            set: { self.program.startDate = Timestamp(date: $0) }
        )
    }
    
    private var daysOfWeekBinding: Binding<[Int]> {
        Binding<[Int]>(
            get: { self.program.daysOfWeek ?? [] },
            set: { self.program.daysOfWeek = $0.sorted() }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProgramDetailHeroCard(
                    programName: program.name,
                    statusText: statusText,
                    progress: programProgress,
                    completedWorkouts: completedWorkouts,
                    totalWorkouts: totalProgramWorkouts,
                    routineCount: program.routines.count,
                    trainingDays: program.daysOfWeek?.count ?? 0,
                    exerciseCount: totalExerciseCount,
                    setCount: totalSetCount
                )

                if isPreview {
                    ProgramPreviewActionCard(
                        daysPerWeek: program.daysOfWeek?.count ?? 0,
                        routineCount: program.routines.count,
                        isSelecting: isSelectingProgram,
                        onSelect: onSelectProgram
                    )
                } else {
                    ProgramScheduleSetupCard(
                        startDate: startDateBinding,
                        selectedDays: daysOfWeekBinding,
                        isScheduled: program.startDate != nil,
                        onSave: {
                            Task { await workoutService.saveProgram(program) }
                        }
                    )
                }

                if program.startDate != nil {
                    if let nextWorkout = nextWorkoutInfo {
                        ProgramNextWorkoutCard(
                            nextWorkout: nextWorkout,
                            onStart: { self.nextRoutineToPlay = nextWorkout.routine }
                        )
                    } else {
                        ProgramCompleteSummaryCard()
                    }

                    ProgramCalendarCard {
                        CalendarView(
                            workoutMap: calendarWorkoutMap,
                            completedSessions: completedSessions,
                            routineToPlay: $calendarRoutineToPlay
                        )
                    }
                }

                ProgramRoutineBreakdownCard(
                    routines: program.routines,
                    allowsEditing: !isPreview,
                    allowsStarting: !isPreview,
                    onEdit: { self.routineToEdit = $0 },
                    onStart: { self.calendarRoutineToPlay = $0 }
                )
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                onSave: { updatedRoutine in
                    if let index = self.program.routines.firstIndex(where: { $0.id == updatedRoutine.id }) {
                        self.program.routines[index] = updatedRoutine
                        Task {
                            await workoutService.saveProgram(self.program)
                        }
                    }
                }
            )
        }
        .fullScreenCover(item: $nextRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                if let currentIndex = program.currentProgressIndex {
                    program.currentProgressIndex = currentIndex + 1
                    Task {
                        await workoutService.saveProgram(program)
                    }
                }
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
            .environmentObject(achievementService)
        }
        .fullScreenCover(item: $calendarRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {}
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
        }
        .onAppear {
            guard !isPreview else { return }
            Task {
                let logs = await workoutService.fetchSessionLogs(for: program)
                var completedMap: [Date: Bool] = [:]
                let calendar = Calendar.current
                for log in logs {
                    let date = calendar.startOfDay(for: log.date.dateValue())
                    completedMap[date] = true
                }
                self.completedSessions = completedMap
            }
        }
    }
}

private struct ProgramDetailHeroCard: View {
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

private struct ProgramMetricTile: View {
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

private struct ProgramPreviewActionCard: View {
    let daysPerWeek: Int
    let routineCount: Int
    let isSelecting: Bool
    let onSelect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
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

private struct ProgramScheduleSetupCard: View {
    @Binding var startDate: Date
    @Binding var selectedDays: [Int]
    let isScheduled: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 17, weight: .bold))
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

private struct ProgramNextWorkoutCard: View {
    let nextWorkout: (routine: WorkoutRoutine, title: String)
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20, weight: .bold))
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

private struct ProgramExercisePreviewRow: View {
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

private struct ProgramCompleteSummaryCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 21, weight: .bold))
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

private struct ProgramCalendarCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .bold))
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

private struct ProgramRoutineBreakdownCard: View {
    let routines: [WorkoutRoutine]
    let allowsEditing: Bool
    let allowsStarting: Bool
    let onEdit: (WorkoutRoutine) -> Void
    let onStart: (WorkoutRoutine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 17, weight: .bold))
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

private struct ProgramRoutineCard: View {
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 31, height: 31)
                            .background(Color.blue.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if allowsStarting {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
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


private struct CalendarView: View {
    let workoutMap: [Date: WorkoutRoutine]
    let completedSessions: [Date: Bool]
    @Binding var routineToPlay: WorkoutRoutine?
    @State private var month: Date = Date()
    
    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let workout: WorkoutRoutine?
        let isCompleted: Bool
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: -1, to: self.month) ?? self.month }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
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
                        .font(.system(size: 12, weight: .bold))
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
                            if let workout = dayEntry.workout {
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
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.accentPositive)
                                        .background(Color.backgroundPrimary, in: Circle())
                                        .offset(x: 1, y: -1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(dayEntry.workout == nil)
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
                entries.append(DayEntry(date: Date.distantPast, workout: nil, isCompleted: false))
            }
        }

        if let numberOfDays = calendar.range(of: .day, in: .month, for: month)?.count {
            for day in 1...numberOfDays {
                var components = calendar.dateComponents([.year, .month], from: firstDayOfMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    let normalizedDate = calendar.startOfDay(for: date)
                    let isCompleted = completedSessions[normalizedDate] ?? false
                    entries.append(DayEntry(date: normalizedDate, workout: workoutMap[normalizedDate], isCompleted: isCompleted))
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

        if dayEntry.workout != nil {
            return Color.brandPrimary.opacity(0.14)
        }

        return Color.backgroundSecondary.opacity(0.50)
    }

    private func dayColor(for dayEntry: DayEntry) -> Color {
        if dayEntry.isCompleted {
            return .accentPositive
        }

        if dayEntry.workout != nil || isSameDay(dayEntry.date, Date()) {
            return .brandPrimary
        }

        return Color(UIColor.secondaryLabel)
    }
}
