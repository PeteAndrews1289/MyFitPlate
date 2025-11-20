

import SwiftUI

// High-level comment: This view displays a list of pre-built workout programs
// that a user can view, select, and add to their own list of programs.
struct PreBuiltProgramsView: View {
    @EnvironmentObject var workoutService: WorkoutService
    
    // High-level comment: Environment objects needed for ProgramDetailView sheet
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    // High-level comment: State to show the detail sheet for a selected program
    @State private var showingPreBuiltDetail: WorkoutProgram?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if workoutService.preBuiltPrograms.isEmpty {
                    Text("Loading pre-built programs...")
                         .appFont(size: 15)
                         .foregroundColor(.secondary)
                         .padding()
                } else {
                    // High-level comment: Iterate over pre-built programs and display them using the row builder
                    ForEach(workoutService.preBuiltPrograms, id: \.name) { program in
                        preBuiltProgramRow(program)
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Pre-built Programs")
        .navigationBarTitleDisplayMode(.inline)
        // High-level comment: This sheet shows the ProgramDetailView when a user taps "View"
        .sheet(item: $showingPreBuiltDetail) { program in
             NavigationView {
                 ProgramDetailView(program: program)
                     .environmentObject(workoutService)
                     .environmentObject(goalSettings)
                     .environmentObject(dailyLogService)
                     .environmentObject(achievementService)
                     .navigationBarItems(trailing: Button("Done") { showingPreBuiltDetail = nil })
                     .navigationBarTitleDisplayMode(.inline)
                     .navigationTitle("Program Details")
             }
        }
    }
    
    // High-level comment: This ViewBuilder function was moved from WorkoutRoutinesView
    @ViewBuilder
    private func preBuiltProgramRow(_ program: WorkoutProgram) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(program.name)
                    .appFont(size: 17, weight: .semibold)
                Text("\(program.routines.count) routines · \(program.daysOfWeek?.count ?? 0) days/week")
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("View") {
                showingPreBuiltDetail = program
            }
            .buttonStyle(.bordered)
            .tint(.brandSecondary)

             Button("Select") {
                 Task {
                     await workoutService.selectPreBuiltProgram(program)
                 }
             }
             .buttonStyle(.borderedProminent)
             .tint(.brandPrimary)
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(15)
    }
}
