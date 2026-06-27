
import SwiftUI
import FirebaseAuth

struct WorkoutRoutinesView: View {
    @StateObject private var workoutService = WorkoutService()
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService

    @State private var routineToPlay: WorkoutRoutine?
    @State private var showingAIGenerator = false
    @State private var routineToEdit: WorkoutRoutine?
    @State private var reviewLog: WorkoutSessionLog?

    @StateObject private var viewModel = WorkoutDashboardViewModel()

    private let planLibraryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]



    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let nextWorkout = viewModel.nextWorkoutInfo(for: workoutService.activeProgram)

                    TrainingHeroCard(
                        activeProgramName: workoutService.activeProgram?.name,
                        routineCount: workoutService.userRoutines.count,
                        programCount: workoutService.userPrograms.count
                    )

                    let todayLog = dailyLogService.currentDailyLog.flatMap { log in
                        Calendar.current.isDateInToday(log.date) ? log : nil
                    }
                    TrainingReadinessCard(brief: viewModel.trainingBrief(todayLog: todayLog, goalSettings: goalSettings))

                    if workoutService.activeProgram != nil {
                        MuscleRecoveryMapView()
                    }

                    TrainingDecisionCard(
                        nextWorkout: nextWorkout,
                        activeProgramName: workoutService.activeProgram?.name,
                        routineCount: workoutService.userRoutines.count,
                        onStartWorkout: {
                            if let nextWorkout {
                                self.routineToPlay = nextWorkout.routine
                            }
                        }
                    )

                    if let program = workoutService.activeProgram {
                        TrainingWeekPreviewCard(program: program, nextWorkout: nextWorkout)
                    }

                    if let program = workoutService.activeProgram {
                        TodaysNextStepSlider(
                            program: program,
                            completedLogsByIndex: viewModel.completedLogsByIndex(for: program),
                            onStart: { routine in self.routineToPlay = routine },
                            onSkipTo: { target in
                                Task { await workoutService.skipToIndex(target, in: program) }
                            },
                            onReview: { log in self.reviewLog = log }
                        )
                    }

                    if workoutService.activeProgram == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            TrainingSectionHeader(
                                title: "Plan Library",
                                subtitle: "Choose a ready-made plan, generate one, or build your own."
                            )

                        LazyVGrid(columns: planLibraryColumns, spacing: 12) {
                            NavigationLink(destination: PreBuiltProgramsView()
                                .environmentObject(workoutService)
                                .environmentObject(goalSettings)
                                .environmentObject(dailyLogService)
                                .environmentObject(achievementService)
                            ) {
                                TrainingActionTile(
                                    icon: "rectangle.stack.fill",
                                    title: "Pre-built",
                                    subtitle: "Preview proven plans",
                                    color: .orange
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("prebuilt_programs_button")

                            Button {
                                showingAIGenerator = true
                            } label: {
                                TrainingActionTile(
                                    icon: "sparkles",
                                    title: "AI Program",
                                    subtitle: "Create from goals",
                                    color: .brandPrimary
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ai_program_button")

                            NavigationLink(destination: ProgramCreatorView(workoutService: workoutService)) {
                                TrainingActionTile(
                                    icon: "square.and.pencil",
                                    title: "Manual Build",
                                    subtitle: "Design your split",
                                    color: .blue
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ProgramListView(workoutService: workoutService)
                                .environmentObject(goalSettings)
                                .environmentObject(dailyLogService)
                                .environmentObject(achievementService)
                            ) {
                                TrainingActionTile(
                                    icon: "folder.fill",
                                    title: "Saved Plans",
                                    subtitle: "Manage programs",
                                    color: .accentPositive
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    }

                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: WorkoutHistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.brandPrimary)
                    }
                }
            }
            .onAppear {
                workoutService.fetchRoutinesAndPrograms()
            }
            .task(id: workoutService.activeProgram?.id) {
                await viewModel.refreshSessionLogs(for: workoutService.activeProgram, workoutService: workoutService)
            }
            .fullScreenCover(item: $routineToPlay) { routine in
                WorkoutPlayerView(routine: routine, onWorkoutComplete: {
                    if let program = workoutService.activeProgram, var currentIndex = program.currentProgressIndex {
                        currentIndex += 1
                        var mutableProgram = program
                        mutableProgram.currentProgressIndex = currentIndex
                        let expectedLogCount = viewModel.sessionLogs.count + 1

                        Task {
                            let savedProgram = await workoutService.saveProgram(mutableProgram) ?? mutableProgram
                            if savedProgram.id == workoutService.activeProgram?.id {
                                workoutService.activeProgram = savedProgram
                            }
                            await viewModel.refreshSessionLogs(for: savedProgram, workoutService: workoutService, expectingAtLeast: expectedLogCount)
                        }
                    }
                })
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
            }
            .sheet(isPresented: $showingAIGenerator) {
                AIWorkoutGeneratorView()
                    .environmentObject(workoutService)
                    .environmentObject(goalSettings)
            }
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
        }
    }



    @ViewBuilder
    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        HStack(spacing: 12) {
            Text(ExerciseEmojiMapper.getEmoji(for: routine.exercises.first?.name ?? routine.name))
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("\(routine.exercises.count) exercises • \(routine.exercises.reduce(0) { $0 + $1.sets.count }) sets")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            Button {
                routineToPlay = routine
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary, in: Circle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit") {
                    routineToEdit = routine
                }
                Button("Delete", role: .destructive) {
                    workoutService.deleteRoutine(routine)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(Color.backgroundPrimary.opacity(0.68), in: Circle())
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
