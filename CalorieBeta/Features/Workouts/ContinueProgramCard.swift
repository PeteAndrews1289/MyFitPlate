import MyFitPlateCore

import SwiftUI

struct ContinueProgramCard: View {
    let program: WorkoutProgram
    let nextWorkout: (routine: WorkoutRoutine, title: String)
    let onStartWorkout: () -> Void
    
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var showingProgramDetail = false
    @State private var showingProgramList = false

    private var totalProgramWorkouts: Int {
        max((program.daysOfWeek?.count ?? 0) * 12, program.routines.count)
    }

    private var completedWorkouts: Int {
        min(program.currentProgressIndex ?? 0, totalProgramWorkouts)
    }

    private var progress: Double {
        guard totalProgramWorkouts > 0 else { return 0 }
        return min(Double(completedWorkouts) / Double(totalProgramWorkouts), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue Program")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(program.name)
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                }

                Spacer()

                Menu {
                    Button("View Program Details") {
                        showingProgramDetail = true
                    }
                    Button("Change Program") {
                        showingProgramList = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                        .background(Color.backgroundPrimary.opacity(0.7), in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(completedWorkouts) of \(totalProgramWorkouts) workouts complete")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    Spacer()

                    Text("\(Int((progress * 100).rounded()))%")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPrimary.opacity(0.12))

                        Capsule()
                            .fill(Color.brandPrimary)
                            .frame(width: geometry.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Next Session")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .textCase(.uppercase)

                Text(nextWorkout.routine.name)
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(.textPrimary)

                VStack(spacing: 8) {
                    ForEach(Array(nextWorkout.routine.exercises.prefix(4))) { exercise in
                        exercisePreviewRow(exercise)
                    }

                    if nextWorkout.routine.exercises.count > 4 {
                        Text("+ \(nextWorkout.routine.exercises.count - 4) more exercises")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Color.backgroundPrimary.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button(action: onStartWorkout) {
                Label(nextWorkout.title, systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .asCard()
        .navigationDestination(isPresented: $showingProgramDetail) {
            ProgramDetailView(program: program)
                .environmentObject(workoutService)
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(achievementService)
        }
        .navigationDestination(isPresented: $showingProgramList) {
            ProgramListView(workoutService: workoutService)
        }
    }

    private func exercisePreviewRow(_ exercise: RoutineExercise) -> some View {
        HStack(spacing: 10) {
            Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                .font(.body)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.10), in: Circle())

            Text(exercise.name)
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Spacer()

            Text("\(exercise.sets.count)x")
                .appFont(size: 12, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            Text(exercise.sets.first?.target ?? "-")
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(.brandPrimary)
                .lineLimit(1)
        }
    }
}
