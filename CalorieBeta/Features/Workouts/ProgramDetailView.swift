import MyFitPlateCore

import SwiftUI
struct ProgramDetailView: View {
    @State private var program: WorkoutProgram
    let isPreview: Bool
    let isSelectingProgram: Bool
    let onSelectProgram: (() -> Void)?

    @EnvironmentObject var workoutService: WorkoutService

    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore

    @State private var workoutToPlay: WorkoutPlayerLaunch?
    @State private var completedLogs: [Date: WorkoutSessionLog] = [:]
    @State private var sessionLogs: [WorkoutSessionLog] = []
    @State private var reviewLog: WorkoutSessionLog?
    @State private var routineToEdit: WorkoutRoutine?
    @State private var scheduleStart: Date
    @State private var scheduleDays: [Int]
    @State private var isSavingSchedule = false
    @State private var scheduleFeedback: String?
    @State private var showingBlockEditor = false
    @State private var showingMigrationHistory = false
    @State private var showingSuccessor = false
    @State private var showingAgenda = false
    @State private var scheduleEditProposal: WorkoutProgram?
    @State private var pendingProgress: [WorkoutProgramProgressCommand] = []
    @State private var progressMessage: String?
    @State private var progressBusy = false
    @State private var isLoadingBlockHistory = false
    @State private var hasLoadedBlockHistory = false
    @State private var blockHistoryError: String?
    @State private var blockHistoryRequestID: UUID?

    init(program: WorkoutProgram, isPreview: Bool = false, isSelectingProgram: Bool = false, onSelectProgram: (() -> Void)? = nil) {
        self._program = State(initialValue: program)
        self._scheduleStart = State(initialValue: program.startDate ?? Date())
        self._scheduleDays = State(initialValue: program.daysOfWeek ?? [])
        self.isPreview = isPreview
        self.isSelectingProgram = isSelectingProgram
        self.onSelectProgram = onSelectProgram
        self._workspace = State(initialValue: !isPreview && program.startDate == nil ? .schedule : .overview)
    }

    private var totalProgramWorkouts: Int {
        program.totalSlots
    }

    private var completedWorkouts: Int {
        min(program.currentProgressIndex ?? 0, totalProgramWorkouts)
    }

    private var programProgress: Double {
        guard totalProgramWorkouts > 0 else { return 0 }
        return min(Double(completedWorkouts) / Double(totalProgramWorkouts), 1)
    }

    private var isProgramComplete: Bool {
        program.startDate != nil && totalProgramWorkouts > 0 && completedWorkouts >= totalProgramWorkouts
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
            return "Choose this plan, then make its schedule your own."
        }

        if program.startDate == nil {
            return "Set your training days to begin."
        }

        if nextWorkoutInfo == nil {
            return "Block complete. Review your work and plan what comes next."
        }

        let position = program.weekAndDay(forSlot: program.currentProgressIndex ?? 0)
        return "Week \(position.week) · Day \(position.day)"
    }

    private var calendarWorkoutMap: [Date: WorkoutRoutine] {
        var map: [Date: WorkoutRoutine] = [:]
        for slot in 0..<program.totalSlots {
            if let date = program.date(forSlot: slot), let routine = program.routine(forSlot: slot) { map[date] = routine }
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
        WorkoutRules.sessionLogsBySlot(in: program, sessionLogs: sessionLogs)
    }

    private var nextWorkoutInfo: (routine: WorkoutRoutine, title: String)? {
        guard let progressIndex = program.currentProgressIndex,
              !program.routines.isEmpty,
              let daysPerWeek = program.daysOfWeek?.count, daysPerWeek > 0 else {
            return nil
        }

        let totalWorkoutsInProgram = program.totalSlots
        guard progressIndex < totalWorkoutsInProgram else {
            return nil
        }

        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }
        guard let routine = program.routine(forSlot: progressIndex) else { return nil }

        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Begin Week \(weekNumber), Day \(dayNumber)"

        return (routine, title)
    }

    private var startDateBinding: Binding<Date> {
        Binding<Date>(
            get: { scheduleStart },
            set: { scheduleStart = $0; scheduleFeedback = nil }
        )
    }

    private var daysOfWeekBinding: Binding<[Int]> {
        Binding<[Int]>(
            get: { scheduleDays },
            set: { scheduleDays = $0.sorted(); scheduleFeedback = nil }
        )
    }

    private enum Workspace: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case schedule = "Schedule"
        case progress = "Progress"
        var id: Self { self }
    }

    @State private var workspace: Workspace = .overview

    var body: AnyView {
        VStack(spacing: 0) {
            if !isPreview {
                Picker("Program workspace", selection: $workspace) {
                    ForEach(Workspace.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .accessibilityIdentifier("program_workspace")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if !isPreview {
                        WorkoutSyncNotice(service: workoutService)
                        progressReview
                    }
                    if isPreview {
                        previewContent
                    } else {
                        switch workspace {
                        case .overview: overviewContent
                        case .schedule: scheduleContent
                        case .progress: progressContent
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .id(workspace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_detail")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle(isPreview ? "Program Preview" : "Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isPreview {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Original rotations and restore history") { showingMigrationHistory = true }
                            .accessibilityIdentifier("program_migration_history")
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Program options")
                    .accessibilityIdentifier("program_options")
                }
            }
        }
        .programDetailBoundary()
        .sheet(isPresented: $showingSuccessor) {
            let latest = workoutService.userPrograms.first { $0.id == program.id } ?? program
            ProgramSuccessorView(source: latest, workoutService: workoutService) { saved in
                program = saved
                scheduleStart = saved.startDate ?? Date(); scheduleDays = saved.daysOfWeek ?? []
                Task { await refreshSessionLogs(for: saved) }
            }
        }
        .sheet(isPresented: $showingMigrationHistory) {
            WorkoutMigrationHistoryView(program: program, workoutService: workoutService) { saved in
                program = saved; scheduleStart = saved.startDate ?? Date(); scheduleDays = saved.daysOfWeek ?? []
                Task { await refreshSessionLogs(for: saved) }
            }
        }
        .sheet(item: $scheduleEditProposal, onDismiss: {
            if let latest = workoutService.userPrograms.first(where: { $0.id == program.id }) {
                program = latest; scheduleStart = latest.startDate ?? Date(); scheduleDays = latest.daysOfWeek ?? []
            }
        }) { proposal in
            NavigationStack { ProgramCreatorView(workoutService: workoutService, programToEdit: program, isPresentedModally: true, proposedEdits: proposal) }
        }
        .programDetailBoundary()
        .sheet(isPresented: $showingAgenda) {
                TrainingCalendarAgendaView(program: program, logs: sessionLogs, workoutService: workoutService,
                    onUpdate: { program = $0 }, onStart: { routine, slot in
                        startProgramWorkout(routine, slot: slot)
                    }, onReview: { reviewLog = $0 })
            }
            .sheet(isPresented: $showingBlockEditor) {
            NavigationStack {
                WorkoutBlockEditorView(program: program, workoutService: workoutService) { saved in
                    program = saved
                }
            }
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                draftScope: "saved-program-\(program.id ?? "unknown")-routine-\(routine.id)",
                onSave: { updatedRoutine in
                    guard let index = program.routines.firstIndex(where: { $0.id == updatedRoutine.id }) else { throw CancellationError() }
                    var draft = program
                    draft.routines[index] = updatedRoutine
                    guard let saved = await workoutService.saveProgram(draft) else { throw CocoaError(.fileWriteUnknown) }
                    program = saved
                }
            )
        }
        .programDetailBoundary()
        .fullScreenCover(item: $workoutToPlay) { launch in
            WorkoutPlayerView(routine: launch.routine, programContext: launch.programContext) {
                refreshAfterCompletion()
            }
            .environmentObject(goalSettings)
            .environmentObject(dailyLogService)
            .environmentObject(workoutService)
            .environmentObject(achievementService)
            .environmentObject(trainingFuelPlanStore)
        }
        .sheet(item: $reviewLog) { log in
            NavigationStack {
                WorkoutCompleteAnalyticsView(log: log)
                    .navigationTitle("Session Review")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .programDetailBoundary()
        .onReceive(workoutService.$userPrograms) { programs in
            guard !isPreview, let latest = programs.first(where: { $0.id == program.id }) else { return }
            program = latest; reloadPendingProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutSyncStateChanged)) { _ in reloadPendingProgress() }
        .onAppear {
            guard !isPreview else { return }
            reloadPendingProgress()
            Task { await refreshSessionLogs(for: program) }
        }
        .programDetailBoundary()
    }

    private var overviewContent: AnyView {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            programHero
            if isProgramComplete {
                successorAction
            } else if program.startDate != nil {
                nextSession
            }
            blockAction
            routineBreakdown
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_overview")
        .programDetailBoundary()
    }

    private var scheduleContent: AnyView {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            if program.trainingBlock != nil, program.startDate != nil {
                Button("Open full training agenda") { showingAgenda = true }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("program_open_agenda")
            }
            if program.startDate != nil { programCalendar }
            ProgramScheduleSetupCard(
                startDate: startDateBinding,
                selectedDays: daysOfWeekBinding,
                isScheduled: program.startDate != nil,
                isSaving: isSavingSchedule,
                feedback: scheduleFeedback,
                onSave: saveSchedule
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_schedule")
        .programDetailBoundary()
    }

    private var progressContent: AnyView {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            programHero
            ProgramBlockReviewCard(
                review: WorkoutBlockReview.make(program: program, logs: sessionLogs),
                isLoading: isLoadingBlockHistory, hasLoaded: hasLoadedBlockHistory,
                errorMessage: blockHistoryError,
                onRetry: { Task { await refreshSessionLogs(for: program) } }
            )
            if hasLoadedBlockHistory {
                ProgramBlockPerformanceCard(evidence: WorkoutBlockPerformance.make(program: program, logs: sessionLogs))
            }
            if !isProgramComplete { successorAction }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("program_progress")
        .programDetailBoundary()
    }

    private var previewContent: AnyView {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            programHero
            ProgramPlanningReviewCard(program: program)
            ProgramPreviewActionCard(
                daysPerWeek: program.daysOfWeek?.count ?? 0,
                routineCount: program.routines.count,
                isSelecting: isSelectingProgram,
                onSelect: onSelectProgram
            )
            if program.startDate != nil {
                nextSession
                programCalendar
            }
            routineBreakdown
        }
        .programDetailBoundary()
    }

    private var programHero: AnyView {
        ProgramDetailHeroCard(
            programName: program.name,
            statusText: statusText,
            progress: programProgress,
            completedWorkouts: completedWorkouts,
            totalWorkouts: totalProgramWorkouts,
            routineCount: program.routines.count,
            trainingDays: program.daysOfWeek?.count ?? 0,
            exerciseCount: totalExerciseCount,
            setCount: totalSetCount,
            skippedCount: Set(program.skippedIndices ?? []).filter { $0 >= 0 && $0 < completedWorkouts }.count
        )
        .programDetailBoundary()
    }

    private var nextSession: AnyView {
        TodaysNextStepSlider(
            program: program,
            completedLogsByIndex: completedLogsByIndex,
            onStart: { routine, slot in
                startProgramWorkout(routine, slot: slot)
            },
            onSkipTo: { target in
                Task {
                    if let updated = await workoutService.skipToIndex(target, in: program) {
                        if let receipt = updated.lastSkipReceipt {
                            for slot in receipt.addedSkips { recordTrainingFuelSkip(for: program, slot: slot) }
                        }
                        program = updated
                    }
                }
            },
            onReview: { log in self.reviewLog = log },
            skipFuelReview: trainingFuelPlanStore.confirmedPlan.flatMap { plan in
                guard plan.draft.sourceID == program.id else { return nil }
                return "Confirmed fuel plan: \(plan.draft.sessionTitle), \(plan.draft.scheduledAt.formatted(date: .abbreviated, time: .shortened)). A matching plan may be marked skipped. Meals and food logs stay intact; review fueling separately if you Undo training."
            },
            showsExercisePreview: isPreview
        )
        .programDetailBoundary()
    }

    private var programCalendar: AnyView {
        ProgramCalendarCard {
            CalendarView(
                workoutMap: calendarWorkoutMap,
                completedLogs: completedLogs,
                skippedDates: skippedDates,
                onStart: { routine, date in
                    let slots = (0..<program.totalSlots).filter {
                        program.routine(forSlot: $0)?.id == routine.id && program.date(forSlot: $0).map {
                            Calendar.current.isDate($0, inSameDayAs: date)
                        } == true
                    }
                    guard slots.count == 1, let slot = slots.first else {
                        ToastManager.shared.showToast(message: "Choose the specific session in your training agenda.")
                        return
                    }
                    startProgramWorkout(routine, slot: slot)
                },
                onReview: { log in self.reviewLog = log }
            )
        }
        .programDetailBoundary()
    }

    private var routineBreakdown: AnyView {
        ProgramRoutineBreakdownCard(
            routines: program.routines,
            allowsEditing: !isPreview && program.trainingBlock == nil,
            allowsStarting: !isPreview,
            onEdit: { self.routineToEdit = $0 },
            onStart: { routine in
                if let context = WorkoutRules.sessionContext(for: program, routineID: routine.id),
                   let scheduled = program.routine(forSlot: context.slotIndex) {
                    startProgramWorkout(scheduled, slot: context.slotIndex)
                } else {
                    workoutToPlay = WorkoutPlayerLaunch(standalone: routine)
                }
            }
        )
        .programDetailBoundary()
    }

    private func startProgramWorkout(_ routine: WorkoutRoutine, slot: Int) {
        guard let launch = WorkoutPlayerLaunch(routine: routine, program: program, slot: slot) else {
            ToastManager.shared.showToast(message: "Reopen your program to choose its current session.")
            return
        }
        workoutToPlay = launch
    }

    private func refreshAfterCompletion() {
        let latest = workoutService.userPrograms.first { $0.id == program.id }
            ?? (workoutService.activeProgram?.id == program.id ? workoutService.activeProgram : nil)
            ?? program
        program = latest
        Task {
            await refreshSessionLogs(for: latest)
        }
    }

    private var successorAction: some View {
        Button { showingSuccessor = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label("Plan your next block", systemImage: "arrow.triangle.branch").appTextRole(.control)
                Text("Repeat or adjust a separate block. Your current progress stays intact.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(AppPalette.text).appSurface(.quiet)
        .accessibilityIdentifier("program_next_block")
    }

    private var blockAction: some View {
        Button { showingBlockEditor = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "calendar.badge.clock").appFont(size: 20, weight: .medium).accessibilityHidden(true)
                    Text(program.trainingBlock == nil ? "Build training block" : "Edit training block")
                        .appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                }
                Text(program.trainingBlock.map { "\($0.weeks.count) weeks · \($0.sessionsPerWeek) sessions each week" }
                     ?? "Plan week-specific targets while keeping your current progress.")
                    .appFont(size: 13).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .appSurface(.quiet)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.text)
        .accessibilityIdentifier("program_edit_block")
    }

    @ViewBuilder private var progressReview: some View {
        if program.lastSkipReceipt != nil || !pendingProgress.isEmpty || progressMessage != nil {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if let receipt = program.lastSkipReceipt, receipt.postEpoch == program.progressEpoch {
                Text("Latest skip: \(receipt.addedSkips.count) uncompleted \(receipt.addedSkips.count == 1 ? "session" : "sessions")").appTextRole(.control)
                Button("Undo last skip") {
                    progressBusy = true
                    Task { @MainActor in
                        do { program = try await workoutService.undoLastProgramSkip(in: program); progressMessage = "Training skip restored without removing completed work. Review its fuel plan separately." } catch { progressMessage = "Undo could not apply because the plan or work changed. All current progress and logs are kept. \(error.localizedDescription)" }
                        progressBusy = false; reloadPendingProgress()
                    }
                }.frame(minHeight: 44).disabled(progressBusy).accessibilityIdentifier("program_undo_skip")
            }
            ForEach(pendingProgress, id: \.id) { command in
                Text(command.kind == .completion ? "Workout progress queued for verification" : "Reviewed \(command.kind.rawValue) is pending")
                    .appTextRole(.secondary)
                Button("Check progress receipt") { resolveProgress(command, cancel: false) }.frame(minHeight: 44).disabled(progressBusy)
                if command.kind != .completion {
                    Button("Cancel pending progress change") { resolveProgress(command, cancel: true) }.frame(minHeight: 44).disabled(progressBusy)
                }
            }
            if !pendingProgress.isEmpty { Button("Retry queued workout saves") { workoutService.retryPendingSaves() }.frame(minHeight: 44) }
            if let progressMessage { Text(progressMessage).appTextRole(.secondary).foregroundStyle(.secondary) }
        }.buttonStyle(AppListButtonStyle()).appSurface(.quiet).accessibilityElement(children: .contain).accessibilityIdentifier("program_progress_recovery")
        }
    }
    private func reloadPendingProgress() {
        guard !isPreview else { return }
        do { pendingProgress = try workoutService.pendingProgramProgress(in: program) } catch { progressMessage = "Progress checkpoints could not be read; their files are kept." }
    }
    private func resolveProgress(_ command: WorkoutProgramProgressCommand, cancel: Bool) {
        guard !progressBusy else { return }; progressBusy = true
        Task { @MainActor in
            do {
                let result = try await workoutService.resolveProgramProgress(command, cancelPending: cancel)
                switch result {
                case .accepted(let saved): if let saved { program = saved }; progressMessage = "This progress event was accepted; later work is kept."
                case .cancelled(let saved): if let saved { program = saved }; progressMessage = "Pending progress change cancelled. Late delivery cannot apply it."
                case .pending: progressMessage = "Not accepted yet. Your queued event is retained for retry."
                }
            } catch { progressMessage = "The receipt could not refresh. Your checkpoint and logs are kept. \(error.localizedDescription)" }
            progressBusy = false; reloadPendingProgress()
        }
    }

    private func saveSchedule() {
        guard !scheduleDays.isEmpty, !isSavingSchedule else { return }
        if let block = program.trainingBlock, scheduleDays.count != block.sessionsPerWeek {
            scheduleFeedback = "This block has \(block.sessionsPerWeek) sessions each week. Keep that number of training days."
            return
        }
        scheduleFeedback = "Review every affected future date before submitting."
        var draft = program; draft.startDate = scheduleStart; draft.daysOfWeek = scheduleDays
        scheduleEditProposal = draft
    }

    private func recordTrainingFuelSkip(for program: WorkoutProgram, slot index: Int) {
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

    private func refreshSessionLogs(for program: WorkoutProgram, expectingAtLeast expectedCount: Int? = nil) async {
        let ownerID = DIContainer.shared.authService.currentUserID
        guard ownerID == program.userID else { return }
        let requestID = UUID()
        blockHistoryRequestID = requestID
        isLoadingBlockHistory = true
        blockHistoryError = nil
        defer { if blockHistoryRequestID == requestID { isLoadingBlockHistory = false } }
        guard case .success(var logs) = await workoutService.fetchSessionLogsResult(for: program) else {
            if blockHistoryRequestID == requestID, DIContainer.shared.authService.currentUserID == ownerID {
                blockHistoryError = "Workout evidence could not refresh. Your saved program position is kept."
            }
            return
        }
        guard !Task.isCancelled, blockHistoryRequestID == requestID, program.id == self.program.id,
              DIContainer.shared.authService.currentUserID == ownerID else { return }
        if let expectedCount, logs.count < expectedCount {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let retryLogs = await workoutService.fetchSessionLogs(for: program)
            if retryLogs.count > logs.count {
                logs = retryLogs
            }
        }

        guard !Task.isCancelled, blockHistoryRequestID == requestID, program.id == self.program.id,
              DIContainer.shared.authService.currentUserID == ownerID else { return }
        self.sessionLogs = logs
        hasLoadedBlockHistory = true
        if let reconciled = await workoutService.reconcileProgramProgress(in: self.program, knownLogs: logs) { self.program = reconciled }

        var completedMap: [Date: WorkoutSessionLog] = [:]
        let calendar = Calendar.current
        for (slot, log) in completedLogsByIndex {
            if let date = self.program.date(forSlot: slot) {
                completedMap[calendar.startOfDay(for: date)] = log
            }
        }
        self.completedLogs = completedMap
    }
}

private extension View {
    /// Bound each destination's generic metadata before composing presentation modifiers.
    func programDetailBoundary() -> AnyView { AnyView(self) }
}
