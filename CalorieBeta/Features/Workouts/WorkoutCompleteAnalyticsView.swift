import MyFitPlateCore

import SwiftUI
import Charts
import StoreKit

struct WorkoutCompleteAnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var mealExperimentStore: MealExperimentStore

    // The raw data source. Kept in state so past-session edits can refresh this screen in place.
    @State private var log: WorkoutSessionLog
    @State private var ownerUserID: String?

    @StateObject var analyticsService = WorkoutAnalyticsService()
    @State private var analytics: WorkoutAnalytics?
    @State private var comparison: WorkoutComparison?
    @State private var trendData: [String: [ExerciseTrendPoint]] = [:]
    @State private var muscleSplit: [MuscleSplitPoint] = [] // New State

    @State private var isAnimated = false
    @State private var isLoading = true
    @State private var showingPRCelebration = false
    @State private var showingRecoveryFoodSearch = false
    @State private var showingRecoveryMealDetail = false
    @State private var showingNutritionAudit = false
    @State private var showingWorkoutEditor = false
    @State private var futureTemplate: WorkoutRoutine?
    @State private var isSavingWorkoutEdit = false
    @State private var workoutEditMessage: String?
    @State private var pendingCorrection: WorkoutCorrectionReceipt?
    @State private var correctionConflict = false
    @State private var recoveryMealReview: MealReviewSaveSession?
    @State private var recoveryMealSuggestion: MealSuggestion?
    @State private var recoverySuggestionUserID: String?
    @State private var didLogRecoveryHandoffViewed = false
    @State private var analyticsLoadGeneration: UUID?
    private let isFreshCompletion: Bool

    init(log: WorkoutSessionLog, isFreshCompletion: Bool = false) {
        self._log = State(initialValue: log)
        self._ownerUserID = State(initialValue: DIContainer.shared.authService.currentUserID)
        self.isFreshCompletion = isFreshCompletion
    }

    private var freshProgramStatus: String? {
        guard let ownerUserID, ownerUserID == DIContainer.shared.authService.currentUserID else { return nil }
        if log.programLinkDecision == .standalone {
            guard isFreshCompletion, let program = workoutService.activeProgram, program.userID == ownerUserID,
                  program.archivedAt == nil, let slot = program.currentProgressIndex, (0..<program.totalSlots).contains(slot),
                  let next = program.routine(forSlot: slot) else { return "Standalone workout" }
            return "Standalone workout · \(program.name) is still on \(next.name)"
        }
        guard isFreshCompletion, let context = log.programContext,
              let program = workoutService.userPrograms.first(where: { $0.id == context.programID && $0.userID == ownerUserID }),
              program.archivedAt == nil, let next = program.currentProgressIndex else { return nil }
        if next == program.totalSlots { return "End of program reached" }
        guard (0..<program.totalSlots).contains(next), next != context.slotIndex,
              let routine = program.routine(forSlot: next) else { return nil }
        let position = program.weekAndDay(forSlot: next)
        return "Up next · \(routine.name) · Week \(position.week), day \(position.day)"
    }

    private var displayedAnalytics: WorkoutAnalytics {
        analytics ?? localAnalytics
    }

    private var localAnalytics: WorkoutAnalytics {
        analyticsService.generateImmediateSessionAnalytics(for: log)
    }

    private var totalVolume: Double {
        WorkoutSetMath.volume(log)
    }

    private var completedSetCount: Int { WorkoutSetMath.workingSetCount(log) }

    private var totalRepCount: Int {
        log.completedExercises.reduce(0) { $0 + WorkoutSetMath.workingSets(in: $1).reduce(0) { $0 + $1.reps } }
    }

    private var cardioMinutes: Int {
        let seconds = log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + ($1.durationInSeconds ?? 0) }
        }
        return seconds / 60
    }

    private var sessionTime: (label: String, value: String) {
        if let seconds = log.recordedDurationSeconds {
            return ("Duration", Duration.seconds(seconds).formattedWorkoutTime)
        }
        let estimate = max(cardioMinutes, completedSetCount * 2)
        return estimate > 0 ? ("Estimated time", "\(estimate.formatted()) min") : ("Duration", "Unavailable")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let coverage = analyticsService.historyCoverageMessage {
                    Text(coverage).appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("workout_analytics_history_coverage")
                }
                WorkoutSyncNotice(service: workoutService)
                if let workoutEditMessage {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(workoutEditMessage).appTextRole(.secondary)
                        if pendingCorrection != nil {
                            Button("Retry workout correction") { Task { await saveEditedWorkout(log) } }
                                .disabled(isSavingWorkoutEdit)
                                .accessibilityIdentifier("workout_correction_retry")
                            if correctionConflict {
                                Button("Keep newer saved session") { Task { await keepNewerSession() } }
                                    .accessibilityIdentifier("workout_correction_keep_newer")
                            }
                        }
                    }.appSurface(.quiet)
                }
                WorkoutSummaryHeroCard(
                    date: log.date,
                    routineName: log.displayName(routines: workoutService.userRoutines, programs: workoutService.userPrograms),
                    programStatus: freshProgramStatus ?? log.programPosition(in: workoutService.userPrograms),
                    totalVolume: displayedAnalytics.totalVolume,
                    exerciseCount: log.completedExercises.count,
                    setCount: completedSetCount,
                    repCount: totalRepCount,
                    sessionTime: sessionTime,
                    isAnimated: isAnimated,
                    canEdit: log.id != nil,
                    isEditingDisabled: isSavingWorkoutEdit,
                    onEdit: {
                        HapticManager.instance.feedback(.light)
                        showingWorkoutEditor = true
                    }
                )

                SessionExerciseBreakdownCard(exercises: log.completedExercises)

                WorkoutNextTimeCard(log: log, ownerID: ownerUserID,
                    hasPendingCorrection: pendingCorrection != nil || isSavingWorkoutEdit, workoutService: workoutService)

                if let comp = comparison {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Compared with last time",
                            subtitle: comp.previousDate?.formatted(date: .abbreviated, time: .omitted)
                        )

                        AppMetricStrip(items: [AppMetricItem(label: "Recorded working volume", value: formatPercent(comp.volumeDiffPercent), accent: comp.volumeDiffPercent >= 0 ? AppPalette.positive : AppPalette.caution)])
                        if comp.durationIsMeasured {
                            Text("Actual duration change: \(formatPercent(comp.durationDiffPercent)). Duration is context, not a speed or quality score.")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        } else {
                            Text("Comparing duration needs two timed workouts and a previous time above zero.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }.appSurface(.quiet)
                }

                if shouldShowRecoveryHandoff {
                    workoutRecoveryHandoffCard(plan: workoutCompletionFuelPlan)
                }

                if let comparison = mealExperimentStore.active, MealExperimentEvidenceRules.matches(log, experiment: comparison, allowLegacy: true) {
                    NavigationLink { MealExperimentsView(openCheckIn: true, preferredSessionID: log.id) } label: {
                        Label("Check in on your pre-workout meal", systemImage: "fork.knife.circle")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("workout_meal_checkin")
                }

                if !displayedAnalytics.personalRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(
                            title: "New records",
                            subtitle: "Personal bests detected in this session."
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(displayedAnalytics.personalRecords), id: \.key) { exerciseName, prValue in
                                    PRCard(exerciseName: exerciseName, detail: prValue)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                    // DESIGN.md §7: celebrate records once, at the moment of reveal — a
                    // spring entrance and a success haptic, no repeat fanfare.
                    .scaleEffect(isAnimated ? 1 : 0.92)
                    .opacity(isAnimated ? 1 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(0.15), value: isAnimated)
                    .onAppear {
                        if isFreshCompletion { HapticManager.instance.notification(.success) }
                    }
                }

                Button("Review a reusable future routine") {
                    guard let owner = DIContainer.shared.authService.currentUserID, owner == ownerUserID else { return }
                    futureTemplate = WorkoutExerciseCopyRules.routine(from: log, userID: owner)
                }.buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("workout_review_future_template")
                Text("This creates a separate reviewed routine. It does not rewrite the completed receipt or your active block.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                NavigationLink("Explore exercise trends & evidence", destination: WorkoutEvidenceReportView(initialProgramID: log.programContext?.programID))
                    .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("workout_open_evidence_report")
                if !muscleSplit.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(
                            title: "Muscle focus",
                            subtitle: "Working-set distribution across this session."
                        )

                        Chart(muscleSplit) { point in
                            BarMark(
                                x: .value("Sets", point.setCount),
                                y: .value("Muscle", point.muscleName)
                            )
                            .foregroundStyle(AppPalette.effort.gradient)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .appSurface(.quiet)
                    }
                }

                if !displayedAnalytics.aiInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeader(
                            title: "Maia analysis",
                            subtitle: "Coaching notes grounded in this workout."
                        )

                        ForEach(displayedAnalytics.aiInsights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                } else if isLoading {
                    InlineAnalysisLoadingCard()
                }

                ShareLink(item: generateShareText(analytics: displayedAnalytics), preview: SharePreview("Workout Summary", image: Image(systemName: "trophy.fill"))) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .accessibilityIdentifier("workout_summary_share")
                .simultaneousGesture(TapGesture().onEnded {
                    DIContainer.shared.analyticsManager?.logEvent("workout_summary_share_opened", parameters: nil)
                })
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("workout_summary")
        .background(AppPalette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: finishSummary)
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("workout_summary_done")
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(.bar)
        }
        .sheet(isPresented: $showingRecoveryFoodSearch) {
            FoodSearchView(
                dailyLog: $dailyLogService.currentDailyLog,
                onFoodItemLogged: {
                    showingRecoveryFoodSearch = false
                },
                searchContext: "workout_recovery"
            )
        }
        .sheet(isPresented: $showingRecoveryMealDetail) {
            if let review = recoveryMealReview {
                SavedMealSuggestionDetailView(
                    review: review, pantryItemNames: pantryService.pantryItems.map(\.name),
                    remainingCalories: remainingCaloriesToday, remainingProtein: remainingProteinToday,
                    remainingCarbs: remainingCarbsToday, remainingFats: remainingFatsToday,
                    onAccepted: { recoveryMealReview = nil; showingRecoveryMealDetail = false },
                    onDiscarded: { recoveryMealReview = nil; showingRecoveryMealDetail = false }
                )
            }
        }
        .sheet(isPresented: $showingNutritionAudit) {
            if let log = currentTodayLog {
                NavigationStack {
                    NutritionAuditView(
                        dailyLog: log,
                        dailyLogBinding: $dailyLogService.currentDailyLog,
                        date: Date()
                    )
                }
            }
        }
        .sheet(item: $futureTemplate) { routine in
            RoutineEditorView(workoutService: workoutService, routine: routine, draftScope: "future-template-\(log.id ?? routine.id)") { edited in
                guard DIContainer.shared.authService.currentUserID == ownerUserID else { throw WorkoutBlockError.accountChanged }
                try await workoutService.saveRoutine(edited)
            }
        }
        .sheet(isPresented: $showingWorkoutEditor) {
            WorkoutSessionLogEditorSheet(
                log: pendingCorrection?.updated ?? log,
                isSaving: isSavingWorkoutEdit,
                saveMessage: workoutEditMessage,
                hasPendingCorrection: pendingCorrection != nil,
                onSave: { updatedLog in
                    Task { await saveEditedWorkout(updatedLog) }
                }
            )
        }
        .onAppear {
            isAnimated = true
            if let ownerUserID, let sessionID = log.id {
                do {
                    pendingCorrection = try WorkoutCorrectionStore().pending(sessionID: sessionID, userID: ownerUserID)
                    if pendingCorrection != nil { workoutEditMessage = "A saved correction still needs to finish. Retry it before making another edit." }
                } catch { workoutEditMessage = "A saved correction could not be read. It has been kept on this device." }
            }
            loadData()
            logRecoveryHandoffViewedIfNeeded()
            if let ownerUserID, ownerUserID == DIContainer.shared.authService.currentUserID {
                NotificationCenter.default.post(name: .reminderEvidenceChanged, object: ownerUserID)
            }
            if isFreshCompletion && !localAnalytics.personalRecords.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showingPRCelebration = true
                }
            }
        }
        .onChange(of: comparison) { _, newComp in
            if isFreshCompletion && newComp?.isPR == true {
                showingPRCelebration = true
            }
        }
        .celebrationOverlay(type: .workoutPR, isPresented: $showingPRCelebration)
    }

    private func loadData() {
        isLoading = true
        self.muscleSplit = analyticsService.calculateMuscleSplit(log: log)
        let requestID = UUID()
        analyticsLoadGeneration = requestID

        if ScreenshotDemoMode.isEnabled {
            analytics = localAnalytics
            comparison = nil
            trendData = [:]
            isLoading = false
            return
        }

        guard let userID = ownerUserID,
              DIContainer.shared.authService.currentUserID == userID else {
            analytics = localAnalytics
            comparison = nil
            trendData = [:]
            isLoading = false
            return
        }

        // If insights were already generated and saved, use them immediately.
        if let saved = log.aiInsights, !saved.isEmpty {
            self.analytics = WorkoutAnalytics(
                totalVolume: localAnalytics.totalVolume,
                personalRecords: localAnalytics.personalRecords,
                aiInsights: saved
            )
            Task {
                let comparison = await analyticsService.compareAgainstPrevious(currentLog: log, userID: userID)
                guard analyticsLoadGeneration == requestID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                self.comparison = comparison

                self.isLoading = false
            }
            return
        }

        // Fresh session: show local insights immediately, then replace with AI insights.
        analytics = localAnalytics

        Task {
            let generated = await analyticsService.generateAnalytics(for: log, userID: userID)
            guard analyticsLoadGeneration == requestID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            self.analytics = generated

            // Persist so the History view can show them without re-generating.
            if let sessionID = log.id, !generated.aiInsights.isEmpty {
                await analyticsService.saveInsights(generated.aiInsights, forSessionID: sessionID, userID: userID)
                guard analyticsLoadGeneration == requestID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
            }

            let comparison = await analyticsService.compareAgainstPrevious(currentLog: log, userID: userID)
            guard analyticsLoadGeneration == requestID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            self.comparison = comparison

            self.isLoading = false
        }
    }

    private func finishSummary() {
        let shouldRequestReview = shouldRequestAppReview()
        dismiss()

        guard shouldRequestReview else { return }
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.appReviewPromptRequested.rawValue, parameters: [
            "moment": AppReviewPromptCoordinator.Moment.completedSession.rawValue
        ])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            requestReview()
        }
    }

    private func shouldRequestAppReview() -> Bool {
        guard isFreshCompletion,
              !ScreenshotDemoMode.isEnabled,
              !AppRuntime.isUITesting(),
              let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return false
        }

        let sessionID = log.id ?? "\(log.routineID):\(log.date.timeIntervalSinceReferenceDate)"
        return AppReviewPromptCoordinator.registerCompletedSession(
            id: sessionID,
            appVersion: appVersion
        )
    }

    @MainActor
    private func saveEditedWorkout(_ updatedLog: WorkoutSessionLog) async {
        guard let userID = ownerUserID,
              DIContainer.shared.authService.currentUserID == userID else {
            ToastManager.shared.showToast(message: "Sign in to edit workout history.")
            return
        }

        isSavingWorkoutEdit = true
        let coordinator = WorkoutCorrectionCoordinator(repository: DIContainer.shared.workoutRepository,
            diary: dailyLogService, auth: DIContainer.shared.authService)
        do {
            let command = try pendingCorrection ?? coordinator.prepare(original: log, updated: updatedLog, userID: userID)
            pendingCorrection = command
            let receipt = try await coordinator.resume(command)
            pendingCorrection = receipt.isComplete ? nil : receipt
            guard DIContainer.shared.authService.currentUserID == userID else {
                isSavingWorkoutEdit = false
                return
            }
            log = receipt.updated
            analytics = nil
            comparison = nil
            trendData = [:]
            muscleSplit = []
            showingWorkoutEditor = !receipt.isComplete
            switch receipt.diaryResult {
            case .updated, .alreadyCurrent: workoutEditMessage = "Workout and linked diary estimate updated."
            case .missing: workoutEditMessage = "Workout updated. Its diary entry was missing and was not recreated."
            case .preservedOverride: workoutEditMessage = "Workout updated. Existing diary totals were kept because they were edited or the original estimate was not recorded."
            default: workoutEditMessage = "History is saved. Retry to finish its linked diary correction."
            }
            loadData()
        } catch {
            if let correctionError = error as? WorkoutCorrectionError, case .conflict = correctionError {
                correctionConflict = true
                showingWorkoutEditor = false
            }
            workoutEditMessage = error is WorkoutCorrectionError
                ? "This session changed or contains unsupported values. Your correction is kept; reopen the latest session before changing it again."
                : "Your correction is kept on this device. Retry when connected."
        }

        isSavingWorkoutEdit = false
    }

    @MainActor
    private func keepNewerSession() async {
        guard let receipt = pendingCorrection, let userID = ownerUserID,
              DIContainer.shared.authService.currentUserID == userID, let id = log.id else { return }
        do {
            let latest = try await DIContainer.shared.workoutRepository.fetchWorkoutSessionLog(userID: userID, sessionID: id)
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            let coordinator = WorkoutCorrectionCoordinator(repository: DIContainer.shared.workoutRepository,
                diary: dailyLogService, auth: DIContainer.shared.authService)
            _ = try coordinator.abandon(receipt)
            log = latest; pendingCorrection = nil; correctionConflict = false
            workoutEditMessage = "Kept the newer saved session. Your proposed correction was not applied."
            loadData()
        } catch { workoutEditMessage = "Could not load the newer session. Both versions are kept; try again." }
    }

    private var currentTodayLog: DailyLog? {
        dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDateInToday(log.date) ? log : nil
        }
    }

    private var remainingCaloriesToday: Double {
        max(0, (goalSettings.calories ?? 0) - (currentTodayLog?.totalCalories() ?? 0))
    }

    private var remainingProteinToday: Double {
        max(0, goalSettings.protein - (currentTodayLog?.totalMacros().protein ?? 0))
    }

    private var remainingCarbsToday: Double {
        max(0, goalSettings.carbs - (currentTodayLog?.totalMacros().carbs ?? 0))
    }

    private var remainingFatsToday: Double {
        max(0, goalSettings.fats - (currentTodayLog?.totalMacros().fats ?? 0))
    }

    private var shouldShowRecoveryHandoff: Bool {
        Calendar.current.isDateInToday(log.date) && (goalSettings.calories ?? 0) > 0
    }

    private var workoutCompletionFuelPlan: TodayFuelPlan {
        TodayFuelPlanRules.makeWorkoutCompletionPlan(
            today: currentTodayLog,
            goals: TodayFuelPlanGoals(
                calories: goalSettings.calories ?? 0,
                protein: goalSettings.protein,
                carbs: goalSettings.carbs,
                fats: goalSettings.fats
            ),
            sessionLog: log,
            now: Date()
        )
    }

    private func workoutRecoveryHandoffCard(plan: TodayFuelPlan) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(plan.title).appTextRole(.sectionTitle)

            Text(plan.detail)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AppMetricStrip(items: recoveryMetricItems(for: plan))

            recoveryHandoffActions(for: plan)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("workout_summary_recovery")
    }

    @ViewBuilder
    private func recoveryHandoffActions(for plan: TodayFuelPlan) -> some View {
        switch plan.action {
        case .fillMacros:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.compact) {
                    recoveryFoodSearchButton
                    recoveryFillMacrosButton
                }

                VStack(spacing: AppSpacing.compact) {
                    recoveryFoodSearchButton
                    recoveryFillMacrosButton
                }
            }

        case .reviewDay:
            Button(action: reviewTodayFromRecoveryHandoff) {
                Label("Review today", systemImage: "checklist")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))

        case .openRecoverySearch:
            Button(action: openRecoveryFoodSearch) {
                Label("Find recovery food", systemImage: "magnifyingglass")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))

        case .none:
            EmptyView()
        }
    }

    private func recoveryMetricItems(for plan: TodayFuelPlan) -> [AppMetricItem] {
        var items = [
            AppMetricItem(
                label: plan.remainingCalories >= 0 ? "Budget" : "Over",
                value: "\(Int(abs(plan.remainingCalories).rounded()).formatted()) cal",
                accent: plan.remainingCalories >= 0 ? AppPalette.energy : AppPalette.caution
            )
        ]
        if let protein = plan.targetProteinGrams {
            items.append(AppMetricItem(label: "Protein", value: "\(protein) g", accent: AppPalette.protein))
        }
        if let carbs = plan.targetCarbGrams {
            items.append(AppMetricItem(label: "Carbs", value: "\(carbs) g", accent: AppPalette.carbohydrate))
        }
        return items
    }

    private var recoveryFoodSearchButton: some View {
        Button(action: openRecoveryFoodSearch) {
            Label("Find Food", systemImage: "magnifyingglass")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
    }

    private var recoveryFillMacrosButton: some View {
        Button(action: generateRecoveryMealSuggestion) {
            HStack(spacing: AppSpacing.compact) {
                if insightsService.isGeneratingSuggestion {
                    ProgressView()
                        .tint(AppPalette.text)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("Fill Macros")
            }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .disabled(insightsService.isGeneratingSuggestion)
    }

    private func openRecoveryFoodSearch() {
        guard ownerUserID == DIContainer.shared.authService.currentUserID else { return }
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("search")
        showingRecoveryFoodSearch = true
    }

    private func generateRecoveryMealSuggestion() {
        guard let userID = ownerUserID,
              DIContainer.shared.authService.currentUserID == userID else { return }
        guard let day = DiaryDayContext(userID: userID, date: Date()) else { return }
        if let saved = MealReviewSaveSession.resumeMealSuggestion(source: "workout_recovery_suggestion", userID: userID) {
            recoveryMealReview = saved
            showingRecoveryMealDetail = true
            return
        }
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("fill_macros")

        Task {
            let pantryNames = pantryService.pantryItems.map(\.name)
            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames) {
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                recoveryMealReview = suggestion.makeReview(userID: userID, day: day, source: "workout_recovery_suggestion")
                self.showingRecoveryMealDetail = true
            } else {
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                ToastManager.shared.showToast(message: "Maia couldn't build a meal right now. Check your connection and try again.")
            }
        }
    }

    private func reviewTodayFromRecoveryHandoff() {
        guard ownerUserID == DIContainer.shared.authService.currentUserID else { return }
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("review_day")
        if currentTodayLog != nil {
            showingNutritionAudit = true
        } else {
            ToastManager.shared.showToast(message: "Nothing to review yet.")
        }
    }

    private func logRecoveryHandoffViewedIfNeeded() {
        guard shouldShowRecoveryHandoff, !didLogRecoveryHandoffViewed else { return }
        didLogRecoveryHandoffViewed = true
        let plan = workoutCompletionFuelPlan
        DIContainer.shared.analyticsManager?.logEvent("workout_recovery_handoff_viewed", parameters: [
            "kind": plan.kind.rawValue,
            "remaining_calories": Int(plan.remainingCalories.rounded()),
            "target_protein": plan.targetProteinGrams ?? 0,
            "target_carbs": plan.targetCarbGrams ?? 0,
            "exercise_count": log.completedExercises.count,
            "set_count": completedSetCount
        ])
    }

    private func logRecoveryHandoffAction(_ action: String) {
        let plan = workoutCompletionFuelPlan
        DIContainer.shared.analyticsManager?.logEvent("workout_recovery_handoff_tapped", parameters: [
            "kind": plan.kind.rawValue,
            "action": action,
            "remaining_calories": Int(plan.remainingCalories.rounded()),
            "target_protein": plan.targetProteinGrams ?? 0,
            "target_carbs": plan.targetCarbGrams ?? 0
        ])
    }

    private func generateShareText(analytics: WorkoutAnalytics) -> String {
        let prCount = analytics.personalRecords.count
        let prText = prCount > 0 ? "Hit \(prCount) new PRs!" : "Great session!"
        let summary = "Just finished a workout with MyFitPlate: \(Int(analytics.totalVolume)) lbs total volume. \(prText)"
        return MyFitPlateLinks.shareMessage(summary)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%+.0f%%", value * 100)
    }
}

// MARK: - Subviews

private struct WorkoutSessionLogEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingElapsedSeconds: Bool
    @State private var draft: WorkoutSessionLog
    let isSaving: Bool
    let saveMessage: String?
    let hasPendingCorrection: Bool
    let onSave: (WorkoutSessionLog) -> Void

    init(log: WorkoutSessionLog, isSaving: Bool, saveMessage: String?, hasPendingCorrection: Bool, onSave: @escaping (WorkoutSessionLog) -> Void) {
        self._draft = State(initialValue: log)
        self.isSaving = isSaving
        self.saveMessage = saveMessage
        self.hasPendingCorrection = hasPendingCorrection
        self.onSave = onSave
    }

    var body: some View {
        AppEditorScaffold(
            title: "Edit workout",
            subtitle: "Correct the saved session without changing the original Apple Health workout.",
            dismiss: {
                guard !isSaving else { return }
                dismiss()
            }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let saveMessage { Text(saveMessage).appTextRole(.secondary).accessibilityIdentifier("workout_correction_message") }
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Session",
                        subtitle: "Changes update this MyFitPlate history record."
                    )

                    Text("\(draft.date.formatted(date: .abbreviated, time: .shortened)) · Original diary day")
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )

                    if draft.elapsedSeconds != nil {
                        HStack {
                            Text("Elapsed seconds")
                            Spacer()
                            TextField("Seconds", value: Binding(get: { draft.elapsedSeconds ?? 0 },
                                set: { draft.elapsedSeconds = $0 }), format: .number)
                                .keyboardType(.numberPad)
                                .focused($editingElapsedSeconds)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(minWidth: 72, maxWidth: 120)
                                .accessibilityLabel("Elapsed seconds")
                                .accessibilityIdentifier("workout_editor_elapsed_seconds")
                        }
                        .appTextRole(.body)
                        .padding(AppSpacing.row)
                        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .contentShape(Rectangle())
                        .onTapGesture { editingElapsedSeconds = true }
                        Text("Session seconds update the linked diary duration when its original estimate is unchanged.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Actual elapsed time was not recorded for this older session.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }

                    AppMetricStrip(items: [
                        AppMetricItem(
                            label: "Exercises",
                            value: draft.completedExercises.count.formatted(),
                            accent: AppPalette.effort
                        ),
                        AppMetricItem(
                            label: "Sets",
                            value: draft.completedExercises.reduce(0) { $0 + $1.sets.count }.formatted(),
                            accent: AppPalette.brand
                        )
                    ])
                }
                .appSurface(.emphasized)

                if draft.completedExercises.isEmpty {
                    AppListRow(
                        icon: AppDataAvailabilityReason.notProvided.icon,
                        iconColor: AppPalette.caution,
                        title: "No exercises in this session",
                        subtitle: "Close this editor and add a new workout instead."
                    )
                    .appSurface(.quiet, padding: 0)
                } else {
                    ForEach(draft.completedExercises.indices, id: \.self) { exerciseIndex in
                        let exercise = draft.completedExercises[exerciseIndex]

                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            AppSectionHeader(
                                title: exercise.exerciseName,
                                subtitle: "\(exercise.sets.count) \(exercise.sets.count == 1 ? "set" : "sets") · \(exerciseTypeLabel(exercise.exercise.type))"
                            )

                            VStack(spacing: 0) {
                                ForEach(draft.completedExercises[exerciseIndex].sets.indices, id: \.self) { setIndex in
                                    CompletedSetEditorRow(
                                        set: $draft.completedExercises[exerciseIndex].sets[setIndex],
                                        setIndex: setIndex + 1,
                                        exerciseType: exercise.exercise.type,
                                        equipment: exercise.exercise.loadEquipment
                                    )
                                    .padding(AppSpacing.group)

                                    if setIndex < draft.completedExercises[exerciseIndex].sets.count - 1 {
                                        Divider().padding(.leading, AppSpacing.group)
                                    }
                                }
                            }
                            .appSurface(.quiet, padding: 0)
                        }
                    }
                }
            }.disabled(hasPendingCorrection)
        } actions: {
            Button {
                editingElapsedSeconds = false
                onSave(sanitizedDraft())
            } label: {
                if isSaving {
                    HStack {
                        ProgressView()
                        Text("Saving workout…")
                    }
                } else {
                    Label(hasPendingCorrection ? "Retry correction" : "Save workout", systemImage: "checkmark")
                }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(isSaving || draft.completedExercises.isEmpty)
            .accessibilityIdentifier("workout_editor_save")
        }
        .interactiveDismissDisabled(isSaving)
        .tint(AppPalette.brand)
    }

    private func exerciseTypeLabel(_ type: ExerciseType) -> String {
        switch type {
        case .strength: "Strength"
        case .cardio: "Cardio"
        case .flexibility: "Mobility"
        }
    }

    private func sanitizedDraft() -> WorkoutSessionLog {
        var clean = draft
        for exerciseIndex in clean.completedExercises.indices {
            for setIndex in clean.completedExercises[exerciseIndex].sets.indices {
                clean.completedExercises[exerciseIndex].sets[setIndex].weight = max(0, clean.completedExercises[exerciseIndex].sets[setIndex].weight)
                clean.completedExercises[exerciseIndex].sets[setIndex].reps = max(0, clean.completedExercises[exerciseIndex].sets[setIndex].reps)
                if let distance = clean.completedExercises[exerciseIndex].sets[setIndex].distance {
                    clean.completedExercises[exerciseIndex].sets[setIndex].distance = max(0, distance)
                }
                if let duration = clean.completedExercises[exerciseIndex].sets[setIndex].durationInSeconds {
                    clean.completedExercises[exerciseIndex].sets[setIndex].durationInSeconds = max(0, duration)
                }
            }
        }
        return clean
    }
}

private struct CompletedSetEditorRow: View {
    @Binding var set: CompletedSet
    let setIndex: Int
    let exerciseType: ExerciseType
    let equipment: StrengthEquipment?

    private var distanceBinding: Binding<Double> {
        Binding(
            get: { set.distance ?? 0 },
            set: { set.distance = max(0, $0) }
        )
    }

    private var durationSecondsBinding: Binding<Int> {
        Binding(
            get: { max(0, set.durationInSeconds ?? 0) },
            set: { set.durationInSeconds = max(0, $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Set \(setIndex)")
                    .appFont(size: 13, weight: .bold)
                Spacer()
                if let effort = set.effort {
                    Text("\(effort.scale == .rir ? "RIR" : "RPE") \(formatEffort(effort.value))")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            Picker("Set role", selection: Binding(get: { set.resolvedSetType }, set: { set.setType = $0 })) {
                ForEach(SetType.allCases, id: \.rawValue) { role in Text(role.rawValue.capitalized).tag(role) }
            }
            .accessibilityIdentifier("workout_editor_role_\(set.id)")

            switch exerciseType {
            case .strength:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.row) {
                        strengthWeightField
                        strengthRepsField
                    }

                    VStack(spacing: AppSpacing.row) {
                        strengthWeightField
                        strengthRepsField
                    }
                }

            case .cardio:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.row) {
                        cardioDistanceField
                        durationField
                    }

                    VStack(spacing: AppSpacing.row) {
                        cardioDistanceField
                        durationField
                    }
                }

            case .flexibility:
                durationField
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editableNumberField<Field: View>(
        title: String,
        unit: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 6) {
                field()
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .appFont(size: 17, weight: .bold)

                Text(unit)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var strengthWeightField: some View {
        editableNumberField(title: equipment?.loadingMeaning.title ?? "Load as logged", unit: equipment?.unit.rawValue ?? "lb") {
            TextField("0", value: Binding(get: { (equipment?.unit ?? .lb).displayWeight(set.weight) },
                                          set: { set.weight = (equipment?.unit ?? .lb).storedWeight($0) }), format: .number.precision(.fractionLength(0...2)))
                .accessibilityIdentifier("workout_editor_weight_\(set.id)")
        }
    }

    private var strengthRepsField: some View {
        editableNumberField(title: "Reps", unit: "reps") {
            TextField("0", value: $set.reps, format: .number)
                .accessibilityIdentifier("workout_editor_reps_\(set.id)")
        }
    }

    private var cardioDistanceField: some View {
        editableNumberField(title: "Distance", unit: "mi") {
            TextField("0", value: distanceBinding, format: .number.precision(.fractionLength(0...2)))
        }
    }

    private var durationField: some View {
        editableNumberField(title: "Duration", unit: "sec") {
            TextField("0", value: durationSecondsBinding, format: .number)
        }
    }

    private func formatEffort(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct WorkoutSummaryHeroCard: View {
    let date: Date
    let routineName: String
    let programStatus: String?
    let totalVolume: Double
    let exerciseCount: Int
    let setCount: Int
    let repCount: Int
    let sessionTime: (label: String, value: String)
    let isAnimated: Bool
    let canEdit: Bool
    let isEditingDisabled: Bool
    let onEdit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            summaryIdentity
            if let programStatus {
                Text(programStatus)
                    .appTextRole(.secondary).foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workout_summary_program_status")
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                metricLayout {
                    summaryMetric(
                        "Working volume", value: "\(Int(totalVolume).formatted()) lb",
                        identifier: "workout_summary_volume"
                    )
                    summaryMetric(
                        sessionTime.label, value: sessionTime.value,
                        identifier: "workout_summary_duration"
                    )
                }

                Divider()

                metricLayout {
                    summaryMetric("Exercises", value: exerciseCount.formatted(), identifier: "workout_summary_exercises", prominent: false)
                    summaryMetric("Working sets", value: setCount.formatted(), identifier: "workout_summary_sets", prominent: false)
                    summaryMetric("Reps", value: repCount.formatted(), identifier: "workout_summary_reps", prominent: false)
                }
            }
            .appSurface(.quiet)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout_summary_metrics")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_summary_header")
    }

    private var summaryIdentity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.compact) {
                Text("Workout complete")
                    .appTextRole(.screenTitle)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("workout_summary_title")
                Image(systemName: "checkmark.circle.fill")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.positive)
                    .frame(width: 32, height: 32)
                    .scaleEffect(isAnimated || reduceMotion ? 1 : 0.85)
                    .animation(reduceMotion ? nil : AppMotion.standard, value: isAnimated)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: AppSpacing.compact) {
                Text(routineName + " · " + date.formatted(date: .abbreviated, time: .shortened))
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if canEdit {
                    Button(action: onEdit) {
                        Text("Edit")
                            .appTextRole(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditingDisabled)
                    .accessibilityLabel("Edit workout")
                    .accessibilityIdentifier("workout_summary_edit")
                }
            }
        }
    }

    private var metricLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.row))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.row))
    }

    private func summaryMetric(_ label: String, value: String, identifier: String, prominent: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .appTextRole(prominent ? .sectionTitle : .control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityIdentifier(identifier)
    }
}

private struct SessionExerciseBreakdownCard: View {
    @AppStorage(BodyUnits.preferenceKey) private var useMetric = BodyUnits.prefersMetric()
    let exercises: [CompletedExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Recorded sets").appTextRole(.sectionTitle)
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.exerciseName).appTextRole(.control).foregroundStyle(AppPalette.text)
                    if exercise.exercise.type == .strength, let meaning = exercise.exercise.loadEquipment?.loadingMeaning, meaning != .asLogged {
                        Text(meaning.title).appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    if exercise.sets.isEmpty { Text("No recorded sets").appTextRole(.secondary).foregroundStyle(.secondary) }
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(alignment: .firstTextBaseline) {
                            Text(set.resolvedSetType == .normal ? "Set \(index + 1)" : "Set \(index + 1) · \(set.resolvedSetType.rawValue.capitalized)")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: AppSpacing.compact)
                            Text(measurement(set, exercise: exercise)).monospacedDigit()
                        }
                        .appTextRole(.body)
                        .accessibilityElement(children: .combine)
                    }
                }
                Divider()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_summary_breakdown")
    }

    private func measurement(_ set: CompletedSet, exercise: CompletedExercise) -> String {
        if exercise.exercise.type == .strength {
            let unit = exercise.exercise.loadEquipment?.unit ?? .lb
            if exercise.exercise.loadEquipment?.loadingMeaning == .bodyweightOnly { return "\(set.reps) reps" }
            let weight = unit.displayWeight(set.weight).formatted(.number.precision(.fractionLength(0...2)))
            return "\(weight) \(unit.rawValue) × \(set.reps)"
        }
        let distance = set.distance.map { RunFormat.distanceText(meters: $0 * RunFormat.metersPerMile, metric: useMetric) }
        let time = set.durationInSeconds.map { Duration.seconds($0).formattedWorkoutTime }
        let parts = [distance, time].compactMap { $0 }
        return parts.isEmpty ? "Completed" : parts.joined(separator: " · ")
    }
}

private struct InlineAnalysisLoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.brandPrimary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Building deeper analysis")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("Your workout is already saved. Trends and coaching notes will appear when ready.")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .appSurface(.quiet)
    }
}

struct PRCard: View {
    let exerciseName: String, detail: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label("Personal Record", systemImage: "crown.fill")
                .appTextRole(.caption)
                .foregroundStyle(AppPalette.achievement)
            Text(exerciseName)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 260 : 180, alignment: .leading)
        .frame(minHeight: 120, alignment: .topLeading)
        .appSurface(.quiet)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.achievement.opacity(0.24), lineWidth: 1)
        }
    }
}

struct InsightCard: View {
    let insight: WorkoutAnalysisInsight
    var categoryIcon: String {
        switch insight.category {
        case "Performance": return "chart.bar.fill"
        case "Recovery": return "bed.double.fill"
        case "Nutrition": return "fork.knife"
        default: return "lightbulb.fill"
        }
    }
    var categoryRole: AppSignalRole {
        switch insight.category {
        case "Performance": return .effort
        case "Recovery": return .recovery
        case "Nutrition": return .current
        default: return .caution
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(insight.category, systemImage: categoryIcon)
                .appTextRole(.caption)
                .foregroundStyle(categoryRole.color)

            Text(insight.title)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text(insight.message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appSurface(.quiet)
    }
}
