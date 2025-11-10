import SwiftUI
import FirebaseFirestore

struct ProgramDetailView: View {
    @State var program: WorkoutProgram
    @EnvironmentObject var workoutService: WorkoutService
    
    // Services needed for the WorkoutPlayer
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    // We now use TWO state variables to track what's being played
    @State private var nextRoutineToPlay: WorkoutRoutine? // This one will increment progress
    @State private var calendarRoutineToPlay: WorkoutRoutine? // This one will NOT
    
    // ... (calendarWorkoutMap computed property remains the same) ...
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
    
    // ... (nextWorkoutInfo computed property remains the same) ...
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
    
    // ... (startDateBinding remains the same) ...
    private var startDateBinding: Binding<Date> {
        Binding<Date>(
            get: { self.program.startDate?.dateValue() ?? Date() },
            set: { self.program.startDate = Timestamp(date: $0) }
        )
    }
    
    // ... (daysOfWeekBinding remains the same) ...
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
                            // Set the "next" routine variable
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
                    // Pass the binding for the "calendar" routine
                    CalendarView(workoutMap: calendarWorkoutMap, routineToPlay: $calendarRoutineToPlay)
                }
            }
            
            Section(header: Text("Workouts in this Program")) {
                ForEach(program.routines) { routine in
                    Text(routine.name)
                }
            }
        }
        .navigationTitle(program.name)
        // This sheet is for the "Next Workout" button and WILL increment progress
        .fullScreenCover(item: $nextRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                // This completion handler increments the progress
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
        // This sheet is for the CALENDAR and will NOT increment progress
        .fullScreenCover(item: $calendarRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                // This completion handler is EMPTY. No progress is incremented.
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
            .environmentObject(achievementService)
        }
    }
}


private struct CalendarView: View {
    let workoutMap: [Date: WorkoutRoutine]
    @Binding var routineToPlay: WorkoutRoutine?
    @State private var month: Date = Date()
    
    private let days = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let workout: WorkoutRoutine?
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
                        Text("\(dayOfMonth(dayEntry.date))")
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(dayEntry.workout != nil ? Color.brandPrimary.opacity(0.3) : Color.clear)
                            )
                            .foregroundColor(isSameDay(dayEntry.date, Date()) ? .brandPrimary : .primary)
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
    
    private func daysForMonth() -> [DayEntry] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDayOfMonth = monthInterval.start
        
        var entries: [DayEntry] = []
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        if firstWeekday > 1 {
            for _ in 1..<firstWeekday {
                entries.append(DayEntry(date: Date.distantPast, workout: nil))
            }
        }

        if let numberOfDays = calendar.range(of: .day, in: .month, for: month)?.count {
            for day in 1...numberOfDays {
                var components = calendar.dateComponents([.year, .month], from: firstDayOfMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    let normalizedDate = calendar.startOfDay(for: date)
                    entries.append(DayEntry(date: normalizedDate, workout: workoutMap[normalizedDate]))
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
