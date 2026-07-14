import MyFitPlateCore

import SwiftUI

struct WorkoutRoutinesView: View {
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore

    @State private var routineToPlay: WorkoutRoutine?
    @State private var showingAIGenerator = false
    @State private var routineToEdit: WorkoutRoutine?
    @State private var reviewLog: WorkoutSessionLog?
    @State private var showingDeleteCurrentProgramAlert = false
    @State private var showingProgramBuilder = false
    @State private var showingSavedPrograms = false
    @State private var screenshotProgramToEdit: WorkoutProgram?
    @State private var showingScreenshotProgramDetail = false
    @State private var showingScreenshotWorkoutHistory = false
    @State private var screenshotProgramDetail: WorkoutProgram?
    @State private var screenshotHistoryLogs: [WorkoutSessionLog]?

    @StateObject private var viewModel = WorkoutDashboardViewModel()

    private let planLibraryColumns = [GridItem(.flexible())]

    #if DEBUG
    init() {
        let screen = ScreenshotDemoData.requestedScreen
        _showingProgramBuilder = State(initialValue: screen == "program-builder")
        _showingSavedPrograms = State(initialValue: screen == "saved-programs")
        _screenshotProgramToEdit = State(
            initialValue: screen == "program-builder" ? ScreenshotDemoData.workoutBuilderProgram : nil
        )
        _routineToEdit = State(
            initialValue: screen == "routine-builder" ? ScreenshotDemoData.routineBuilderRoutine : nil
        )
        _showingScreenshotProgramDetail = State(initialValue: screen == "program-detail")
        _showingScreenshotWorkoutHistory = State(initialValue: screen == "workout-history")
        _screenshotProgramDetail = State(
            initialValue: screen == "program-detail" ? ScreenshotDemoData.programDetailProgram : nil
        )
        _screenshotHistoryLogs = State(
            initialValue: screen == "workout-history" ? ScreenshotDemoData.workoutHistoryLogs : nil
        )
        _reviewLog = State(
            initialValue: screen == "workout-summary" ? ScreenshotDemoData.workoutSummaryLog : nil
        )
    }
    #endif

    static let trainTourSteps: [SpotlightTourStep] = [
        SpotlightTourStep(id: "train-next-step", title: "Training hub",
                          text: "Follow your active program or choose a workout routine tailored to your goals."),
        SpotlightTourStep(id: "train-library", title: "Plan library",
                          text: "Pick ready-made programs, generate AI plans, or build your own custom workouts.")
    ]

    var body: some View {
        SpotlightTourScaffold(steps: WorkoutRoutinesView.trainTourSteps) { isActive in
        let isNextStepSpotlightActive = isActive("train-next-step")
        let isLibrarySpotlightActive = isActive("train-library")
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    let nextWorkout = viewModel.nextWorkoutInfo(for: workoutService.activeProgram)

                    let todayLog = dailyLogService.currentDailyLog.flatMap { log in
                        Calendar.current.isDateInToday(log.date) ? log : nil
                    }

                    AppScreenHeader(
                        title: "Train",
                        subtitle: "Your next workout, readiness, and recovery."
                    ) {
                        NavigationLink(destination: WorkoutHistoryView()) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .buttonStyle(AppIconButtonStyle(.neutral))
                        .accessibilityLabel("Workout history")
                    }
                    .accessibilityIdentifier("train_screen_header")

                    // DESIGN.md rule 1: the Train screen answers "what do I do right now?"
                    // With a program, the slider is the single hero; the Training Hub banner
                    // and path-chooser card only appear in the no-program empty state.
                    VStack(alignment: .leading, spacing: 14) {
                        if let program = workoutService.activeProgram {
                            TodaysNextStepSlider(
                                program: program,
                                completedLogsByIndex: viewModel.completedLogsByIndex(for: program),
                                onStart: { routine in self.routineToPlay = routine },
                                onSkipTo: { target in
                                    Task {
                                        if let updated = await workoutService.skipToIndex(target, in: program),
                                           updated.currentProgressIndex != program.currentProgressIndex {
                                            recordTrainingFuelSkip(for: program)
                                        }
                                    }
                                },
                                onReview: { log in self.reviewLog = log }
                            )

                            TrainingWeekPreviewCard(program: program, nextWorkout: nextWorkout)
                        } else {
                            TrainingHeroCard(
                                activeProgramName: nil,
                                routineCount: workoutService.userRoutines.count,
                                programCount: workoutService.userPrograms.count
                            )

                            TrainingDecisionCard(
                                nextWorkout: nextWorkout,
                                activeProgramName: nil,
                                routineCount: workoutService.userRoutines.count,
                                onStartWorkout: {
                                    if let nextWorkout {
                                        self.routineToPlay = nextWorkout.routine
                                    }
                                },
                                onChoosePlan: {
                                    withAnimation { scrollProxy.scrollTo("plan-library", anchor: .top) }
                                },
                                onChooseOneOff: {
                                    withAnimation { scrollProxy.scrollTo("one-off-workouts", anchor: .top) }
                                }
                            )
                        }
                    }
                    .featureSpotlight(isActive: isNextStepSpotlightActive)

                    TrainingReadinessCard(brief: viewModel.trainingBrief(todayLog: todayLog, goalSettings: goalSettings))

                    if workoutService.activeProgram != nil {
                        MuscleRecoveryMapView()
                    }

                    if let program = workoutService.activeProgram {
                        ActiveProgramManagementCard(
                            program: program,
                            onDelete: {
                                showingDeleteCurrentProgramAlert = true
                            }
                        ) {
                            ProgramListView(workoutService: workoutService)
                                .environmentObject(goalSettings)
                                .environmentObject(dailyLogService)
                                .environmentObject(achievementService)
                        }
                        .featureSpotlight(isActive: isLibrarySpotlightActive)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TrainingSectionHeader(
                            title: "Running",
                            subtitle: "Every run from every watch, in one place."
                        )

                        NavigationLink(destination: RunHistoryView()) {
                            TrainingActionTile(
                                icon: "figure.run",
                                title: "Your runs",
                                subtitle: "History, splits, routes",
                                color: Color(UIColor.secondaryLabel)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("running_history_button")
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
                                    color: Color(UIColor.secondaryLabel)
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
                                    subtitle: "Generate tailored plan",
                                    color: Color.brandPrimary
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ai_workout_generator_button")

                            NavigationLink(destination: ProgramCreatorView(workoutService: workoutService)) {
                                TrainingActionTile(
                                    icon: "square.and.pencil",
                                    title: "Manual Build",
                                    subtitle: "Design your split",
                                    color: Color(UIColor.secondaryLabel)
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
                        .featureSpotlight(isActive: isLibrarySpotlightActive)
                        .id("plan-library")

                        VStack(alignment: .leading, spacing: 12) {
                            TrainingSectionHeader(
                                title: "One-off Workouts",
                                subtitle: "Start a saved routine without committing to a program."
                            )

                            if workoutService.userRoutines.isEmpty {
                                Button {
                                    routineToEdit = WorkoutRoutine(
                                        userID: DIContainer.shared.authService.currentUserID ?? "",
                                        name: "",
                                        dateCreated: Date()
                                    )
                                } label: {
                                    Label("Create a Routine", systemImage: "plus")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            } else {
                                ForEach(workoutService.userRoutines) { routine in
                                    routineRow(routine)
                                }
                            }
                        }
                        .id("one-off-workouts")
                    }

                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingScreenshotProgramDetail) {
                if let screenshotProgramDetail {
                    ProgramDetailView(program: screenshotProgramDetail)
                }
            }
            .navigationDestination(isPresented: $showingScreenshotWorkoutHistory) {
                WorkoutHistoryView(fixtureLogs: screenshotHistoryLogs)
            }
            .alert("Delete Current Program?", isPresented: $showingDeleteCurrentProgramAlert) {
                Button("Delete Program", role: .destructive) {
                    if let program = workoutService.activeProgram {
                        Task {
                            let result = await workoutService.deleteProgram(program)
                            if result.didDelete {
                                viewModel.sessionLogs = []
                            }
                            ToastManager.shared.showToast(message: result.userMessage)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the active plan from your saved programs. Workout history stays saved.")
            }
            .onAppear {
                workoutService.fetchRoutinesAndPrograms()
            }
            .task(id: workoutService.activeProgram?.id) {
                await viewModel.refreshSessionLogs(for: workoutService.activeProgram, workoutService: workoutService)
            }
            .fullScreenCover(item: $routineToPlay) { routine in
                WorkoutPlayerView(routine: routine, onWorkoutComplete: {
                    if let program = workoutService.activeProgram {
                        let mutableProgram = WorkoutRules.advanceAfterCompletion(
                            in: program,
                            completedRoutineID: routine.id
                        )
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
                .environmentObject(trainingFuelPlanStore)
            }
            .sheet(isPresented: $showingAIGenerator) {
                AIWorkoutGeneratorView()
                    .environmentObject(workoutService)
                    .environmentObject(goalSettings)
            }
            .sheet(isPresented: $showingProgramBuilder) {
                NavigationStack {
                    ProgramCreatorView(
                        workoutService: workoutService,
                        programToEdit: screenshotProgramToEdit,
                        isPresentedModally: true
                    )
                }
            }
            .sheet(isPresented: $showingSavedPrograms) {
                NavigationStack {
                    ProgramListView(workoutService: workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                }
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
                }
            }
        }
        }
    }

    private func recordTrainingFuelSkip(for program: WorkoutProgram) {
        let index = program.currentProgressIndex ?? 0
        guard !program.routines.isEmpty else { return }
        let routine = program.routines[index % program.routines.count]
        let today = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDateInToday(log.date) ? log : nil
        }
        guard trainingFuelPlanStore.recordProgramSkip(
            programID: program.id,
            routineID: routine.id,
            today: today,
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
            parameters: ["outcome": "skipped", "source": "program_skip"]
        )
    }

    @ViewBuilder
    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        HStack(spacing: AppSpacing.row) {
            Text(ExerciseEmojiMapper.getEmoji(for: routine.exercises.first?.name ?? routine.name))
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(routine.exercises.count) exercises • \(routine.exercises.reduce(0) { $0 + $1.sets.count }) sets")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppSpacing.compact)

            Button {
                routineToPlay = routine
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(AppIconButtonStyle(.brand))
            .accessibilityLabel("Start \(routine.name)")

            Menu {
                Button("Edit") {
                    routineToEdit = routine
                }
                Button("Delete", role: .destructive) {
                    workoutService.deleteRoutine(routine)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appFont(size: 17, weight: .semibold)
                    .foregroundStyle(AppPalette.text)
                    .frame(width: 44, height: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            }
            .accessibilityLabel("Options for \(routine.name)")
        }
        .padding(AppSpacing.row)
        .appSurface(.quiet, padding: 0)
    }
}
