import SwiftUI
import FirebaseFirestore

struct ProgramDetailView: View {
    @State var program: WorkoutProgram
    @EnvironmentObject var workoutService: WorkoutService
    
    // Services needed for the WorkoutPlayer
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var nextRoutineToPlay: WorkoutRoutine?
    @State private var calendarRoutineToPlay: WorkoutRoutine?
    
    // High-level comment: State for completed workout checkmarks on the calendar
    @State private var completedSessions: [Date: Bool] = [:]
    // High-level comment: State for the routine editor sheet
    @State private var routineToEdit: WorkoutRoutine?
    
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
            set: { self.program.daysOfWeek = $0 }
        )
    }

    var body: some View {
        List {
            if program.startDate == nil {
                Section(header: Text("Schedule Your Program")) {
                    DatePicker("Start Date", selection: startDateBinding, displayedComponents: .date)
                    WeekDaySelector(selectedDays: daysOfWeekBinding)
                    
                    Button("Save Schedule") {
                        Task { await workoutService.saveProgram(program) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                if let (routine, title) = nextWorkoutInfo {
                    Section {
                        Button(action: {
                            self.nextRoutineToPlay = routine
                        }) {
                            Text(title)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                } else {
                    Section {
                        Text("Program Complete!")
                            .appFont(size: 17, weight: .semibold)
                    }
                }
                
                Section(header: Text("Program Calendar")) {
                    // High-level comment: Pass the completed sessions map to the calendar
                    CalendarView(
                        workoutMap: calendarWorkoutMap,
                        completedSessions: completedSessions,
                        routineToPlay: $calendarRoutineToPlay
                    )
                }
            }
            
            // High-level comment: This section now allows expanding routines,
            // editing them, and starting them individually.
            Section(header: Text("Workouts in this Program")) {
                ForEach($program.routines) { $routine in
                    DisclosureGroup(
                        content: {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(routine.exercises) { exercise in
                                    Text("- \(exercise.name) (\(exercise.targetSets) sets x \(exercise.targetReps) reps)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading)
                        },
                        label: {
                            HStack {
                                Text(routine.name)
                                    .appFont(size: 17, weight: .semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                // High-level comment: "Edit" button for quick edits
                                Button("Edit") {
                                    self.routineToEdit = routine
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                                
                                // High-level comment: "Start" button for any workout
                                Button("Start") {
                                    self.calendarRoutineToPlay = routine
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.brandPrimary)
                            }
                            .buttonStyle(PlainButtonStyle()) // Prevents the whole row from toggling
                        }
                    )
                    .tint(.primary) // High-level comment: Makes the disclosure arrow use the primary color
                }
            }
        }
        .navigationTitle(program.name)
        // High-level comment: This sheet handles editing a routine
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                onSave: { updatedRoutine in
                    // High-level comment: This updates the routine in the local @State
                    if let index = self.program.routines.firstIndex(where: { $0.id == updatedRoutine.id }) {
                        self.program.routines[index] = updatedRoutine
                        // High-level comment: This saves the change to the entire program
                        Task {
                            await workoutService.saveProgram(self.program)
                        }
                    }
                }
            )
        }
        // High-level comment: This sheet is for the "Next Workout" button (increments progress)
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
        // High-level comment: This sheet is for the calendar/individual "Start" buttons (no progress)
        .fullScreenCover(item: $calendarRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                // This completion handler is EMPTY. No progress is incremented.
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
            .environmentObject(achievementService)
        }
        // High-level comment: Fetches completed session data when the view appears
        .onAppear {
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


private struct CalendarView: View {
    let workoutMap: [Date: WorkoutRoutine]
    // High-level comment: Receives the map of completed session dates
    let completedSessions: [Date: Bool]
    @Binding var routineToPlay: WorkoutRoutine?
    @State private var month: Date = Date()
    
    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    // High-level comment: Calendar day model now includes completion status
    private struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let workout: WorkoutRoutine?
        let isCompleted: Bool
    }

    var body: some View {
        VStack {
            HStack {
                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: -1, to: self.month)! }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text(month, formatter: monthYearFormatter)
                    .font(.headline)
                Spacer()
                Button(action: { self.month = Calendar.current.date(byAdding: .month, value: 1, to: self.month)! }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            HStack {
                ForEach(days, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns) {
                ForEach(daysForMonth()) { dayEntry in
                    Button(action: {
                        if let workout = dayEntry.workout {
                            self.routineToPlay = workout
                        }
                    }) {
                        // High-level comment: ZStack allows overlaying the checkmark
                        ZStack {
                            Text("\(dayOfMonth(dayEntry.date))")
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(dayEntry.workout != nil ? Color.brandPrimary.opacity(0.3) : Color.clear)
                                )
                                .foregroundColor(isSameDay(dayEntry.date, Date()) ? .brandPrimary : .primary)
                            
                            if dayEntry.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.accentPositive)
                                    .offset(x: 12, y: -12)
                            }
                        }
                    }
                    .disabled(dayEntry.workout == nil)
                }
            }
        }
    }
    
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
    
    // High-level comment: Now populates the DayEntry with completion status
    private func daysForMonth() -> [DayEntry] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDayOfMonth = monthInterval.start
        
        var entries: [DayEntry] = []
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        if firstWeekday > 1 {
            for _ in 1..<firstWeekday {
                // High-level comment: Ensure isCompleted is false for empty days
                entries.append(DayEntry(date: Date.distantPast, workout: nil, isCompleted: false))
            }
        }

        if let numberOfDays = calendar.range(of: .day, in: .month, for: month)?.count {
            for day in 1...numberOfDays {
                var components = calendar.dateComponents([.year, .month], from: firstDayOfMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    let normalizedDate = calendar.startOfDay(for: date)
                    // High-level comment: Check the completedSessions map for this date
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
}
