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
    @State private var completedLogs: [Date: WorkoutSessionLog] = [:]
    @State private var sessionLogs: [WorkoutSessionLog] = []
    @State private var reviewLog: WorkoutSessionLog?
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

    private var skippedDates: Set<Date> {
        guard let skipped = program.skippedIndices else { return [] }
        var dates: Set<Date> = []
        for index in skipped {
            if let date = program.date(forSlot: index) { dates.insert(date) }
        }
        return dates
    }

    private var completedLogsByIndex: [Int: WorkoutSessionLog] {
        let current = program.currentProgressIndex ?? 0
        let skipped = Set(program.skippedIndices ?? [])
        let completedSlots = (0..<current).filter { !skipped.contains($0) }
        let sortedLogs = sessionLogs.sorted { $0.date.dateValue() < $1.date.dateValue() }
        var result: [Int: WorkoutSessionLog] = [:]
        for (slot, log) in zip(completedSlots, sortedLogs) { result[slot] = log }
        return result
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
                    TodaysNextStepSlider(
                        program: program,
                        completedLogsByIndex: completedLogsByIndex,
                        onStart: { routine in self.nextRoutineToPlay = routine },
                        onSkipTo: { target in
                            Task {
                                if let updated = await workoutService.skipToIndex(target, in: program) {
                                    program = updated
                                }
                            }
                        },
                        onReview: { log in self.reviewLog = log }
                    )

                    ProgramCalendarCard {
                        CalendarView(
                            workoutMap: calendarWorkoutMap,
                            completedLogs: completedLogs,
                            skippedDates: skippedDates,
                            routineToPlay: $calendarRoutineToPlay,
                            onReview: { log in self.reviewLog = log }
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
                    var programToSave = program
                    programToSave.currentProgressIndex = currentIndex + 1
                    program = programToSave
                    let expectedLogCount = sessionLogs.count + 1

                    Task {
                        let savedProgram = await workoutService.saveProgram(programToSave) ?? programToSave
                        program = savedProgram
                        await refreshSessionLogs(for: savedProgram, expectingAtLeast: expectedLogCount)
                    }
                }
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
            .environmentObject(achievementService)
        }
        .fullScreenCover(item: $calendarRoutineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                let programForRefresh = program
                let expectedLogCount = sessionLogs.count + 1
                Task {
                    await refreshSessionLogs(for: programForRefresh, expectingAtLeast: expectedLogCount)
                }
            }
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
        }
        .sheet(item: $reviewLog) { log in
            NavigationStack {
                WorkoutCompleteAnalyticsView(log: log)
                    .navigationTitle("Session Review")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { reviewLog = nil }
                        }
                    }
            }
        }
        .onAppear {
            guard !isPreview else { return }
            Task { await refreshSessionLogs(for: program) }
        }
    }

    private func refreshSessionLogs(for program: WorkoutProgram, expectingAtLeast expectedCount: Int? = nil) async {
        var logs = await workoutService.fetchSessionLogs(for: program)
        if let expectedCount, logs.count < expectedCount {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let retryLogs = await workoutService.fetchSessionLogs(for: program)
            if retryLogs.count > logs.count {
                logs = retryLogs
            }
        }

        self.sessionLogs = logs
        var completedMap: [Date: WorkoutSessionLog] = [:]
        let calendar = Calendar.current
        for log in logs {
            let date = calendar.startOfDay(for: log.date.dateValue())
            completedMap[date] = log
        }
        self.completedLogs = completedMap
    }
}
