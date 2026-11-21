import MyFitPlateCore

import SwiftUI

struct WorkoutRoutinesView: View {
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var workoutToPlay: WorkoutPlayerLaunch?
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
    @State private var resumableDraft: WorkoutSessionDraft?
    @State private var routineToDelete: WorkoutRoutine?
    @State private var showingPlanLibrary = false
    @State private var showingOneOffWorkouts = false

    @StateObject private var viewModel = WorkoutDashboardViewModel()

    #if DEBUG
    init() {
        let screen = ScreenshotDemoData.requestedScreen
        _showingAIGenerator = State(initialValue: ScreenshotDemoMode.isEnabled &&
            (ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-outline") || ProcessInfo.processInfo.arguments.contains("-ui-testing-open-ai-generator")))
        _workoutToPlay = State(
            initialValue: screen == "workout-player" ? WorkoutPlayerLaunch(standalone: ScreenshotDemoData.routineBuilderRoutine) : nil
        )
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
        SpotlightTourStep(id: "train-library", title: "Your training",
                          text: "Open your program and schedule, check recovery and fuel, or explore running and training tools.")
    ]

    var body: AnyView {
        SpotlightTourScaffold(steps: WorkoutRoutinesView.trainTourSteps) { isActive in
        let isNextStepSpotlightActive = isActive("train-next-step")
        let isLibrarySpotlightActive = isActive("train-library")
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    let nextWorkout = viewModel.nextWorkoutInfo(for: workoutService.activeProgram)

                    AppScreenHeader(
                        title: "Train",
                        subtitle: nil
                    ) {
                        HStack(spacing: AppSpacing.compact) {
                            Button { showingSavedPrograms = true } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(AppIconButtonStyle(.neutral))
                            .accessibilityLabel("Saved plans")
                            .accessibilityIdentifier("train_saved_plans")
                            NavigationLink(destination: AnyView(WorkoutHistoryView())) {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .buttonStyle(AppIconButtonStyle(.neutral))
                            .accessibilityLabel("Workout history")
                        }
                    }
                    .accessibilityIdentifier("train_screen_header")

                    WorkoutSyncNotice(service: workoutService)
                    WorkoutMigrationRecoveryLink(workoutService: workoutService)
                    if let resumableDraft {
                        let savedSets = resumableDraft.routine.exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count }
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("Continue your workout").appTextRole(.sectionTitle)
                            Text(resumableDraft.routine.name).appTextRole(.body)
                            Text("\(savedSets.formatted()) \(savedSets == 1 ? "set" : "sets") saved · \(resumableDraft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            Button {
                                workoutToPlay = WorkoutPlayerLaunch(resuming: resumableDraft)
                            } label: {
                                Label(resumableDraft.completion == nil ? "Resume Workout" : "Finish Saving", systemImage: "play.fill")
                            }
                            .buttonStyle(AppActionButtonStyle(.primary))
                            .accessibilityIdentifier("workout_resume")
                        }
                        .appSurface(.emphasized)
                    }
                    // DESIGN.md rule 1: the Train screen answers "what do I do right now?"
                    // Resume or the next session is the single hero. Secondary planning
                    // and recovery details live on focused destination pages.
                    if resumableDraft == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        if let program = workoutService.activeProgram {
                            TodaysNextStepSlider(
                                program: program,
                                completedLogsByIndex: viewModel.completedLogsByIndex(for: program),
                                onStart: { routine, slot in
                                    startProgramWorkout(routine, program: program, slot: slot)
                                },
                                onSkipTo: { target in
                                    Task {
                                        if let updated = await workoutService.skipToIndex(target, in: program),
                                           updated.currentProgressIndex != program.currentProgressIndex {
                                            recordTrainingFuelSkip(for: program)
                                        }
                                    }
                                },
                                onReview: { log in self.reviewLog = log },
                                showsExercisePreview: false
                            )

                            if program.weekRescue != nil, let date = program.date(forSlot: program.currentProgressIndex ?? 0) {
                                Text("Adjusted plan · Next session \(date.formatted(date: .abbreviated, time: .omitted))")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                        } else if !workoutService.hasLoadedPrograms || workoutService.preferredProgramUnavailable {
                            VStack(alignment: .leading, spacing: AppSpacing.row) {
                                if workoutService.isLoadingPrograms {
                                    ProgressView("Loading your saved programs")
                                } else {
                                    Label("Your saved programs couldn’t load", systemImage: "icloud.slash")
                                        .appTextRole(.sectionTitle)
                                }
                                Text("Reconnect and retry to load your existing plan and progress.")
                                    .appTextRole(.secondary)
                                    .foregroundStyle(.secondary)
                                if workoutService.isLoadingPrograms {
                                    Button("Retry", action: workoutService.retryPendingSaves)
                                        .buttonStyle(AppActionButtonStyle(.secondary))
                                }
                            }
                            .appSurface(.emphasized)
                            .accessibilityIdentifier("workout_library_loading")
                        } else {
                            TrainingDecisionCard(
                                nextWorkout: nextWorkout,
                                activeProgramName: nil,
                                routineCount: workoutService.userRoutines.count,
                                onStartWorkout: {
                                    if let nextWorkout, let slot = nextWorkout.program.currentProgressIndex {
                                        startProgramWorkout(nextWorkout.routine, program: nextWorkout.program, slot: slot)
                                    }
                                },
                                onChoosePlan: {
                                    showingPlanLibrary = true
                                },
                                onChooseOneOff: {
                                    showingOneOffWorkouts = true
                                }
                            )
                        }
                    }
                    .featureSpotlight(isActive: isNextStepSpotlightActive)
                    }

                    trainingDestinations
                        .featureSpotlight(isActive: isLibrarySpotlightActive)

                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
                .workoutPresentationBoundary()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingPlanLibrary) { planLibrary }
            .navigationDestination(isPresented: $showingOneOffWorkouts) { oneOffWorkouts }
            .workoutPresentationBoundary()
            .navigationDestination(isPresented: $showingScreenshotProgramDetail) {
                if let screenshotProgramDetail {
                    ProgramDetailView(program: screenshotProgramDetail)
                }
            }
            .navigationDestination(isPresented: $showingScreenshotWorkoutHistory) {
                WorkoutHistoryView(fixtureLogs: screenshotHistoryLogs)
            }
            .onAppear {
                workoutService.fetchRoutinesAndPrograms()
                refreshDraft()
            }
            .task(id: workoutService.activeProgram?.id) {
                await viewModel.refreshSessionLogs(for: workoutService.activeProgram, workoutService: workoutService)
            }
            .workoutPresentationBoundary()
        }
            .workoutPresentationBoundary()
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
            .confirmationDialog("Delete this routine?", isPresented: Binding(
                get: { routineToDelete != nil }, set: { if !$0 { routineToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Routine", role: .destructive) {
                    if let routineToDelete { workoutService.deleteRoutine(routineToDelete) }
                    routineToDelete = nil
                }
            } message: { Text("Completed workout history will be kept.") }
            .fullScreenCover(item: $workoutToPlay, onDismiss: refreshDraft) { launch in
                WorkoutPlayerView(routine: launch.routine, programContext: launch.programContext, onWorkoutComplete: {
                    refreshDraft()
                    if let program = workoutService.activeProgram {
                        Task {
                            await viewModel.refreshSessionLogs(for: program, workoutService: workoutService)
                        }
                    }
                })
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
                .environmentObject(trainingFuelPlanStore)
            }
            .workoutPresentationBoundary()
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
            .workoutPresentationBoundary()
            .sheet(item: $routineToEdit) { routine in
                RoutineEditorView(
                    workoutService: workoutService,
                    routine: routine,
                    onSave: { updatedRoutine in
                        try await workoutService.saveRoutine(updatedRoutine)
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
            .workoutPresentationBoundary()
        }
        .workoutPresentationBoundary()
    }

    private var trainingDestinations: AnyView {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Your training").appTextRole(.sectionTitle)
            VStack(spacing: 0) {
                if let program = workoutService.activeProgram {
                    NavigationLink { programOverview } label: {
                        TrainingNavigationRow(icon: "calendar", title: "Program & schedule", subtitle: program.name)
                    }
                    .accessibilityIdentifier("train_program_overview")
                    trainingDivider
                }
                NavigationLink { preparationOverview } label: {
                    TrainingNavigationRow(icon: "heart.text.square", title: "Recovery & fuel", subtitle: "Recent training, check-ins and today's fuel")
                }
                .accessibilityIdentifier("train_preparation")
                trainingDivider
                NavigationLink(destination: AnyView(RunHistoryView())) {
                    TrainingNavigationRow(icon: "figure.run", title: "Running", subtitle: "Record a run, review splits and routes")
                }
                .accessibilityIdentifier("running_history_button")
                trainingDivider
                NavigationLink(destination: AnyView(ToolDirectoryView())) {
                    TrainingNavigationRow(icon: "square.grid.2x2", title: "Training tools", subtitle: "Planning, calculators and more")
                }
                .accessibilityIdentifier("train_all_tools")
            }
            .buttonStyle(.plain)
            .background { Color.clear.appSurface(.quiet, padding: 0).allowsHitTesting(false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("train_destinations")
        .workoutPresentationBoundary()
    }

    private var trainingDivider: some View { Divider().padding(.leading, 64) }

    private var programOverview: AnyView {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                WorkoutSyncNotice(service: workoutService)
                if let program = workoutService.activeProgram {
                    TrainingWeekPreviewCard(program: program, history: viewModel.sessionLogs)
                    ActiveProgramManagementCard(program: program, onDelete: {
                        showingDeleteCurrentProgramAlert = true
                    }) {
                        ProgramListView(workoutService: workoutService)
                            .environmentObject(goalSettings)
                            .environmentObject(dailyLogService)
                            .environmentObject(achievementService)
                            .workoutPresentationBoundary()
                    }
                    NavigationLink { oneOffWorkouts } label: {
                        TrainingNavigationRow(icon: "dumbbell", title: "Saved routines", subtitle: "Start a separate workout or edit a routine")
                            .appSurface(.quiet, padding: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("train_saved_routines")
                    NavigationLink { planLibrary } label: {
                        TrainingNavigationRow(icon: "rectangle.stack", title: "Explore plans", subtitle: "Pre-built, generated and custom programs")
                            .appSurface(.quiet, padding: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("train_explore_plans")
                } else {
                    Text("Your active program is available from Train. Choose a plan there to review its schedule.")
                        .appTextRole(.body).foregroundStyle(.secondary)
                }
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Program & schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("train_program_overview_screen")
        .workoutPresentationBoundary()
    }

    private var preparationOverview: AnyView {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                let todayLog = dailyLogService.currentDailyLog.flatMap { log in
                    Calendar.current.isDateInToday(log.date) ? log : nil
                }
                TrainingReadinessCard(brief: viewModel.trainingBrief(todayLog: todayLog, goalSettings: goalSettings))
                if workoutService.activeProgram != nil {
                    MuscleRecoveryMapView()
                    AdaptiveToolsLinks()
                }
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Recovery & fuel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("train_preparation_screen")
        .workoutPresentationBoundary()
    }

    private var planLibrary: AnyView {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Text("Choose a ready-made plan, generate a tailored program, or build your own.")
                    .appTextRole(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    Button { showingSavedPrograms = true } label: {
                        TrainingNavigationRow(icon: "folder", title: "Saved plans", subtitle: "Open your existing program library")
                    }
                    trainingDivider
                    NavigationLink(destination: PreBuiltProgramsView()
                        .environmentObject(workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)) {
                        TrainingNavigationRow(icon: "rectangle.stack", title: "Pre-built programs", subtitle: "Preview proven training plans")
                    }
                    .accessibilityIdentifier("prebuilt_programs_button")
                    trainingDivider
                    Button { showingAIGenerator = true } label: {
                        TrainingNavigationRow(icon: "sparkles", title: "Generate a program", subtitle: "Review a plan built around your goals")
                    }
                    .accessibilityIdentifier("ai_workout_generator_button")
                    trainingDivider
                    NavigationLink(destination: ProgramCreatorView(workoutService: workoutService)) {
                        TrainingNavigationRow(icon: "square.and.pencil", title: "Build a program", subtitle: "Design your own training split")
                    }
                }
                .buttonStyle(.plain)
                .background { Color.clear.appSurface(.quiet, padding: 0).allowsHitTesting(false) }
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Choose a plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("train_plan_library")
        .workoutPresentationBoundary()
    }

    private var oneOffWorkouts: AnyView {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text("Start a saved routine separately from your program.")
                    .appTextRole(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if workoutService.userRoutines.isEmpty {
                    Text("Build a routine for the sessions you like to repeat.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                } else {
                    ForEach(workoutService.userRoutines) { routine in routineRow(routine) }
                }
                Button {
                    routineToEdit = WorkoutRoutine(userID: DIContainer.shared.authService.currentUserID ?? "", name: "", dateCreated: Date())
                } label: {
                    Label("Create a routine", systemImage: "plus")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Saved routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("train_one_off_workouts")
        .workoutPresentationBoundary()
    }

    private func recordTrainingFuelSkip(for program: WorkoutProgram) {
        let index = program.currentProgressIndex ?? 0
        guard !program.routines.isEmpty else { return }
        guard let routine = program.routine(forSlot: index) else { return }
        let today = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDateInToday(log.date) ? log : nil
        }
        guard trainingFuelPlanStore.recordProgramSkip(
            programID: program.id,
            routineID: routine.id,
            today: today,
            for: DIContainer.shared.authService.currentUserID,
            slotIndex: index
        ) else { return }
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
            parameters: ["outcome": "skipped", "source": "program_skip"]
        )
    }

    private func startProgramWorkout(_ routine: WorkoutRoutine, program: WorkoutProgram, slot: Int) {
        guard let launch = WorkoutPlayerLaunch(routine: routine, program: program, slot: slot) else {
            ToastManager.shared.showToast(message: "Reopen your program to choose its current session.")
            return
        }
        workoutToPlay = launch
    }

    private func refreshDraft() {
        guard let userID = DIContainer.shared.authService.currentUserID else { resumableDraft = nil; return }
        resumableDraft = try? WorkoutDraftStore().load(userID: userID)
    }

    @ViewBuilder
    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        let primaryType = routine.exercises.first?.type
            ?? RoutineEditorDefaults.inferredType(name: routine.name, category: nil)
        HStack(spacing: AppSpacing.row) {
            Image(systemName: primaryType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(primaryType.color)
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
                workoutToPlay = WorkoutPlayerLaunch(standalone: routine)
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
                    routineToDelete = routine
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

private extension View {
    /// Keep screen and destination metadata shallow enough for the device's
    /// type-decoder stack. These fixed boundaries retain the existing state owners.
    func workoutPresentationBoundary() -> AnyView { AnyView(self) }
}
