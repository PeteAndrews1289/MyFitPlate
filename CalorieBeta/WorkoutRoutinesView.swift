import SwiftUI

// High-level comment: Main view for workout routines and programs
struct WorkoutRoutinesView: View {
    @StateObject private var workoutService = WorkoutService()
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService

    @State private var routineToPlay: WorkoutRoutine?
    @State private var showingAIGenerator = false
    @State private var routineToEdit: WorkoutRoutine?
    // High-level comment: The state for the pre-built detail sheet has been removed.

    // High-level comment: Computed property for the next workout remains unchanged.
    private var nextWorkoutInfo: (program: WorkoutProgram, routine: WorkoutRoutine, title: String)? {
        guard let program = workoutService.activeProgram,
              let progressIndex = program.currentProgressIndex,
              !program.routines.isEmpty,
              let daysPerWeek = program.daysOfWeek?.count, daysPerWeek > 0 else {
            return nil
        }

        let totalWorkoutsInProgram = daysPerWeek * 12
        guard progressIndex < totalWorkoutsInProgram else { return nil }

        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }

        let routine = program.routines[routineIndex]
        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Start Week \(weekNumber) · Day \(dayNumber)"

        return (program, routine, title)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    // Section: Continue Active Program
                    if let (program, routine, title) = nextWorkoutInfo {
                        ContinueProgramCard(
                            program: program,
                            nextWorkout: (routine: routine, title: title),
                            onStartWorkout: {
                                self.routineToPlay = routine
                            }
                        )
                        .environmentObject(workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                        
                    } else if workoutService.activeProgram != nil {
                        Text("Program Complete! Great job!")
                            .appFont(size: 17, weight: .semibold)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.backgroundSecondary)
                            .cornerRadius(15)
                    }

                    // Section: Workout Creator (AI & Manual)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workout Creator")
                            .appFont(size: 22, weight: .bold)

                        Text("Use our AI to generate a brand new program tailored to your goals, or build your own from scratch.")
                            .appFont(size: 15)
                            .foregroundColor(.secondary)

                        Button("Generate Program with AI") {
                            showingAIGenerator = true
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        NavigationLink(destination: ProgramCreatorView(workoutService: workoutService)) {
                            Text("Create Program Manually")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    // High-level comment: This section is replaced with a NavigationLink
                    // to the new PreBuiltProgramsView.
                    NavigationLink(destination: PreBuiltProgramsView()
                        .environmentObject(workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                    ) {
                        HStack {
                            Text("Pre-built Programs")
                                .appFont(size: 22, weight: .bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color.backgroundSecondary)
                        .cornerRadius(15)
                    }

                    // Section: User's Manual Routines
                    VStack(alignment: .leading, spacing: 10) {
                        Text("My Routines")
                            .appFont(size: 22, weight: .bold)

                        if workoutService.userRoutines.isEmpty {
                            Text("You haven't created any manual routines yet. Tap 'Create Program Manually' to build a routine.")
                                .appFont(size: 15)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.backgroundSecondary)
                                .cornerRadius(15)

                        } else {
                            ForEach(workoutService.userRoutines) { routine in
                                routineRow(routine)
                            }
                        }
                    }

                    // Section: Link to All User Programs
                    NavigationLink(destination: ProgramListView(workoutService: workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                    ) {
                        HStack {
                            Text("View All My Programs")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .appFont(size: 17, weight: .semibold)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color.backgroundSecondary)
                        .cornerRadius(15)
                    }
                }
                .padding()
            }
            .navigationTitle("Train")
            .onAppear {
                workoutService.fetchRoutinesAndPrograms()
            }
            // Fullscreen cover for playing a workout
            .fullScreenCover(item: $routineToPlay) { routine in
                WorkoutPlayerView(routine: routine, onWorkoutComplete: {
                    if let program = workoutService.activeProgram, var currentIndex = program.currentProgressIndex {
                        currentIndex += 1
                        var mutableProgram = program
                        mutableProgram.currentProgressIndex = currentIndex

                        Task {
                            await workoutService.saveProgram(mutableProgram)
                        }
                    }
                })
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
            }
            // Sheet for AI program generator
            .sheet(isPresented: $showingAIGenerator) {
                AIWorkoutGeneratorView()
                    .environmentObject(workoutService)
                    .environmentObject(goalSettings)
            }
            // Sheet for editing a user routine
            .sheet(item: $routineToEdit) { routine in
                RoutineEditorView(
                    workoutService: workoutService,
                    routine: routine,
                    onSave: { updatedRoutine in
                        Task {
                            try? await workoutService.saveRoutine(updatedRoutine)
                        }
                    }
                )
            }
            // High-level comment: The .sheet modifier for showing pre-built program
            // details has been removed and moved to PreBuiltProgramsView.
        }
    }

    // High-level comment: This ViewBuilder function for a single routine row is unchanged.
    @ViewBuilder
    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(routine.name)
                    .appFont(size: 17, weight: .semibold)
                Text("\(routine.exercises.count) exercises")
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Start") {
                routineToPlay = routine
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)

            Menu {
                Button("Edit") {
                    routineToEdit = routine
                }
                Button("Delete", role: .destructive) {
                    workoutService.deleteRoutine(routine)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(15)
    }
    
    // High-level comment: This ViewBuilder function is no longer needed here
    // as it has been moved to PreBuiltProgramsView.
}


// High-level comment: This struct for ProgramListView remains unchanged.
struct ProgramListView: View {
    @ObservedObject var workoutService: WorkoutService
    
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var showingProgramCreator = false
    @State private var programToEdit: WorkoutProgram? = nil

    var body: some View {
        List {
            if workoutService.userPrograms.isEmpty {
                Text("You haven't created or selected any programs yet.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(workoutService.userPrograms) { program in
                    NavigationLink(destination: ProgramDetailView(program: program)
                        .environmentObject(workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                    ) {
                        VStack(alignment: .leading) {
                            Text(program.name)
                                .appFont(size: 17, weight: .bold)
                            Text("\(program.routines.count) routines · \(program.daysOfWeek?.count ?? 0) days/week")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            workoutService.deleteProgram(program)
                        }
                        Button("Edit") {
                            programToEdit = program
                            showingProgramCreator = true
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("My Programs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    programToEdit = nil
                    showingProgramCreator = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingProgramCreator) {
            ProgramCreatorView(workoutService: workoutService, programToEdit: programToEdit)
        }
    }
}
