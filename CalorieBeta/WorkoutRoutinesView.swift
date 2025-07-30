import SwiftUI

struct WorkoutRoutinesView: View {
    @StateObject private var workoutService = WorkoutService()
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @State private var routineToPlay: WorkoutRoutine?
    @State private var showingAIGenerator = false
    @State private var showingProgramList = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let (program, routine, title) = nextWorkoutInfo {
                    ContinueProgramCard(
                        program: program,
                        nextWorkout: (routine: routine, title: title),
                        onStartWorkout: {
                            self.routineToPlay = routine
                        }
                    )
                } else if workoutService.activeProgram != nil {
                    Text("Program Complete! Great job!")
                        .appFont(size: 17, weight: .semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.backgroundSecondary)
                        .cornerRadius(15)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Program Creator")
                        .appFont(size: 22, weight: .bold)
                    
                    Text("Use our AI to generate a brand new program tailored to your goals, or build your own from scratch.")
                        .appFont(size: 15)
                        .foregroundColor(.secondary)
                    
                    Button("Generate Program with AI") {
                        showingAIGenerator = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                NavigationLink(destination: ProgramListView(workoutService: workoutService)) {
                    HStack {
                        Text("View All Programs")
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
        .fullScreenCover(item: $routineToPlay) { routine in
            WorkoutPlayerView(routine: routine) {
                if let program = workoutService.activeProgram, var currentIndex = program.currentProgressIndex {
                    currentIndex += 1
                    var mutableProgram = program
                    mutableProgram.currentProgressIndex = currentIndex
                    
                    Task {
                        await workoutService.saveProgram(mutableProgram)
                    }
                }
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
        }
        .sheet(isPresented: $showingAIGenerator) {
            AIWorkoutGeneratorView()
                .environmentObject(workoutService)
        }
    }
}

struct ProgramListView: View {
    @ObservedObject var workoutService: WorkoutService
    
    var body: some View {
        List {
            ForEach(workoutService.userPrograms) { program in
                NavigationLink(destination: ProgramDetailView(program: program).environmentObject(workoutService)) {
                    VStack(alignment: .leading) {
                        Text(program.name)
                            .appFont(size: 17, weight: .bold)
                        Text("\(program.routines.count) workouts · \(program.daysOfWeek?.count ?? 0) days/week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.forEach { index in
                    let program = workoutService.userPrograms[index]
                    workoutService.deleteProgram(program)
                }
            }
        }
        .navigationTitle("All Programs")
    }
}
