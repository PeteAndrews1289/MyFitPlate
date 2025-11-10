import SwiftUI

struct ContinueProgramCard: View {
    let program: WorkoutProgram
    let nextWorkout: (routine: WorkoutRoutine, title: String)
    let onStartWorkout: () -> Void
    
    // Access all necessary services
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    // State to control navigation
    @State private var showingProgramDetail = false
    @State private var showingProgramList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Hidden NavigationLinks that are triggered by the menu buttons
            NavigationLink(
                destination: ProgramDetailView(program: program)
                    // Inject all services into the destination view
                    .environmentObject(workoutService)
                    .environmentObject(goalSettings)
                    .environmentObject(dailyLogService)
                    .environmentObject(achievementService),
                isActive: $showingProgramDetail
            ) { EmptyView() }
            
            NavigationLink(
                destination: ProgramListView(workoutService: workoutService),
                isActive: $showingProgramList
            ) { EmptyView() }

            
            Text("Continue Program")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(program.name)
                        .appFont(size: 24, weight: .bold)
                        .lineLimit(2)
                    Spacer()
                    Menu {
                        Button("View Program Details") {
                            // Triggers the first NavigationLink
                            showingProgramDetail = true
                        }
                        Button("Change Program") {
                            // Triggers the second NavigationLink
                            showingProgramList = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                    }
                }
                
                Text(nextWorkout.routine.name)
                    .appFont(size: 15, weight: .medium)
                    .foregroundColor(.secondary)

                Divider()

                VStack(spacing: 8) {
                    HStack {
                        Text("Exercise").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                        Spacer()
                        Text("Sets").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                        Text("Target").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)

                    ForEach(nextWorkout.routine.exercises) { exercise in
                        HStack {
                            Text(exercise.name).appFont(size: 15).lineLimit(1)
                            Spacer()
                            Text("\(exercise.sets.count)").appFont(size: 15)
                            Text(exercise.sets.first?.target ?? "-").appFont(size: 15)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                Button(action: onStartWorkout) {
                    Text(nextWorkout.title)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)

            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(20)
        }
    }
}
