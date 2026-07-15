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
    
    // The raw data source. Kept in state so past-session edits can refresh this screen in place.
    @State private var log: WorkoutSessionLog
    
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
    @State private var isSavingWorkoutEdit = false
    @State private var recoveryMealSuggestion: MealSuggestion?
    @State private var didLogRecoveryHandoffViewed = false
    private let isFreshCompletion: Bool

    init(log: WorkoutSessionLog, isFreshCompletion: Bool = false) {
        self._log = State(initialValue: log)
        self.isFreshCompletion = isFreshCompletion
    }

    private var displayedAnalytics: WorkoutAnalytics {
        analytics ?? localAnalytics
    }

    private var localAnalytics: WorkoutAnalytics {
        analyticsService.generateImmediateSessionAnalytics(for: log)
    }

    private var totalVolume: Double {
        log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { setSum, set in
                setSum + (set.weight * Double(set.reps))
            }
        }
    }

    private var completedSetCount: Int {
        log.completedExercises.reduce(0) { $0 + $1.sets.count }
    }

    private var totalRepCount: Int {
        log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + $1.reps }
        }
    }

    private var cardioMinutes: Int {
        let seconds = log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + ($1.durationInSeconds ?? 0) }
        }
        return seconds / 60
    }

    private var estimatedDurationMinutes: Int {
        max(cardioMinutes, completedSetCount * 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                WorkoutSummaryHeroCard(
                    date: log.date,
                    totalVolume: displayedAnalytics.totalVolume,
                    exerciseCount: log.completedExercises.count,
                    setCount: completedSetCount,
                    repCount: totalRepCount,
                    estimatedMinutes: estimatedDurationMinutes,
                    isAnimated: isAnimated
                )

                if shouldShowRecoveryHandoff {
                    workoutRecoveryHandoffCard(plan: workoutCompletionFuelPlan)
                }

                if let comp = comparison {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Compared With Last Time",
                            subtitle: comp.previousDate?.formatted(date: .abbreviated, time: .omitted)
                        )

                        AppMetricStrip(items: [
                            AppMetricItem(
                                label: "Volume",
                                value: formatPercent(comp.volumeDiffPercent),
                                accent: comp.volumeDiffPercent >= 0 ? AppPalette.positive : AppPalette.caution
                            ),
                            AppMetricItem(
                                label: "Estimated pace",
                                value: formatPercent(-comp.durationDiffPercent),
                                accent: comp.durationDiffPercent <= 0 ? AppPalette.positive : AppPalette.effort
                            )
                        ])
                        .appSurface(.quiet)
                    }
                }

                SessionExerciseBreakdownCard(exercises: log.completedExercises)

                if log.id != nil {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingWorkoutEditor = true
                    } label: {
                        Label("Edit Workout", systemImage: "pencil")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .disabled(isSavingWorkoutEdit)
                    .accessibilityIdentifier("workout_summary_edit")
                }

                if !displayedAnalytics.personalRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(
                            title: "New Records",
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
                        HapticManager.instance.notification(.success)
                    }
                }

                if !trendData.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(
                            title: "Key Gains",
                            subtitle: "Recent movement trends from your saved sessions."
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(Array(log.completedExercises.prefix(3))) { exercise in
                                    if let points = trendData[exercise.exerciseName], points.count > 1 {
                                        ExerciseTrendChartView(exerciseName: exercise.exerciseName, dataPoints: points, metric: "Max Weight")
                                            .frame(width: 300)
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                if !muscleSplit.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(
                            title: "Muscle Focus",
                            subtitle: "Working-set distribution across this session."
                        )

                        Chart(muscleSplit) { point in
                            BarMark(
                                x: .value("Sets", point.setCount),
                                y: .value("Muscle", point.muscleName)
                            )
                            .foregroundStyle(Color.brandPrimary.gradient)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .appSurface(.quiet)
                    }
                }

                if !displayedAnalytics.aiInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        AppSectionHeader(
                            title: "Maia Analysis",
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
            if let suggestion = recoveryMealSuggestion {
                MealSuggestionDetailView(
                    suggestion: suggestion,
                    pantryItemNames: pantryService.pantryItems.map(\.name),
                    remainingCalories: remainingCaloriesToday,
                    remainingProtein: remainingProteinToday,
                    remainingCarbs: remainingCarbsToday,
                    remainingFats: remainingFatsToday,
                    onLog: logRecoveryMealSuggestion
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
        .sheet(isPresented: $showingWorkoutEditor) {
            WorkoutSessionLogEditorSheet(
                log: log,
                isSaving: isSavingWorkoutEdit,
                onSave: { updatedLog in
                    Task { await saveEditedWorkout(updatedLog) }
                }
            )
        }
        .toolbar {
            if log.id != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showingWorkoutEditor = true
                    }
                    .disabled(isSavingWorkoutEdit)
                }
            }
        }
        .onAppear {
            isAnimated = true
            loadData()
            logRecoveryHandoffViewedIfNeeded()
            if !localAnalytics.personalRecords.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showingPRCelebration = true
                }
            }
        }
        .onChange(of: comparison) { _, newComp in
            if newComp?.isPR == true {
                showingPRCelebration = true
            }
        }
        .celebrationOverlay(type: .workoutPR, isPresented: $showingPRCelebration)
    }
    
    private func loadData() {
        isLoading = true
        self.muscleSplit = analyticsService.calculateMuscleSplit(log: log)

        if ScreenshotDemoMode.isEnabled {
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
                let uid = DIContainer.shared.authService.currentUserID
                if let uid {
                    self.comparison = await analyticsService.compareAgainstPrevious(currentLog: log, userID: uid)
                    for exercise in log.completedExercises.prefix(3) {
                        let points = await analyticsService.fetchTrends(for: exercise.exerciseName, userID: uid)
                        self.trendData[exercise.exerciseName] = points
                    }
                }
                self.isLoading = false
            }
            return
        }

        // Fresh session: show local insights immediately, then replace with AI insights.
        analytics = localAnalytics

        Task {
            let uid = DIContainer.shared.authService.currentUserID
            let generated = await analyticsService.generateAnalytics(for: log, userID: uid)
            self.analytics = generated

            // Persist so the History view can show them without re-generating.
            if let uid, let sessionID = log.id, !generated.aiInsights.isEmpty {
                await analyticsService.saveInsights(generated.aiInsights, forSessionID: sessionID, userID: uid)
            }

            if let uid {
                self.comparison = await analyticsService.compareAgainstPrevious(currentLog: log, userID: uid)
                for exercise in log.completedExercises.prefix(3) {
                    let points = await analyticsService.fetchTrends(for: exercise.exerciseName, userID: uid)
                    self.trendData[exercise.exerciseName] = points
                }
            }

            self.isLoading = false
        }
    }

    private func finishSummary() {
        let shouldRequestReview = shouldRequestAppReview()
        dismiss()

        guard shouldRequestReview else { return }
        DIContainer.shared.analyticsManager?.logEvent("app_review_prompt_requested", parameters: [
            "moment": "completed_session"
        ])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            requestReview()
        }
    }

    private func shouldRequestAppReview() -> Bool {
        guard isFreshCompletion,
              !ScreenshotDemoMode.isEnabled,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing"),
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
        guard let userID = DIContainer.shared.authService.currentUserID else {
            ToastManager.shared.showToast(message: "Sign in to edit workout history.")
            return
        }

        var logToSave = updatedLog
        logToSave.aiInsights = nil
        isSavingWorkoutEdit = true

        do {
            try await DIContainer.shared.workoutRepository.saveWorkoutSessionLog(userID: userID, log: logToSave)
            log = logToSave
            analytics = nil
            comparison = nil
            trendData = [:]
            muscleSplit = []
            showingWorkoutEditor = false
            ToastManager.shared.showToast(message: "Workout updated.")
            loadData()
        } catch {
            ToastManager.shared.showToast(message: "Couldn't update workout. Check your connection and try again.")
        }

        isSavingWorkoutEdit = false
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
            AppSectionHeader(title: plan.title, subtitle: plan.summary) {
                Label(
                    plan.kind == .overTargetReview ? "Fuel Check" : "Recovery Meal",
                    systemImage: recoveryHandoffIcon(for: plan.kind)
                )
                .appTextRole(.caption)
                .foregroundStyle(recoveryHandoffColor(for: plan.kind))
            }

            Text(plan.detail)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AppMetricStrip(items: recoveryMetricItems(for: plan))

            recoveryHandoffActions(for: plan)
        }
        .appSurface(.emphasized)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(recoveryHandoffColor(for: plan.kind).opacity(0.16), lineWidth: 1)
        )
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
                accent: plan.remainingCalories >= 0 ? AppPalette.brand : AppPalette.caution
            )
        ]
        if let protein = plan.targetProteinGrams {
            items.append(AppMetricItem(label: "Protein", value: "\(protein) g", accent: AppPalette.effort))
        }
        if let carbs = plan.targetCarbGrams {
            items.append(AppMetricItem(label: "Carbs", value: "\(carbs) g", accent: AppPalette.achievement))
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
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("Fill Macros")
            }
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(insightsService.isGeneratingSuggestion)
    }

    private func recoveryHandoffIcon(for kind: TodayFuelPlan.Kind) -> String {
        kind == .overTargetReview ? "exclamationmark.triangle.fill" : "fork.knife.circle.fill"
    }

    private func recoveryHandoffColor(for kind: TodayFuelPlan.Kind) -> Color {
        kind == .overTargetReview ? AppPalette.caution : AppPalette.brand
    }

    private func openRecoveryFoodSearch() {
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("search")
        showingRecoveryFoodSearch = true
    }

    private func generateRecoveryMealSuggestion() {
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("fill_macros")

        Task {
            let pantryNames = pantryService.pantryItems.map(\.name)
            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames) {
                self.recoveryMealSuggestion = suggestion
                self.showingRecoveryMealDetail = true
            } else {
                ToastManager.shared.showToast(message: "Maia couldn't build a meal right now. Check your connection and try again.")
            }
        }
    }

    private func reviewTodayFromRecoveryHandoff() {
        HapticManager.instance.feedback(.light)
        logRecoveryHandoffAction("review_day")
        if currentTodayLog != nil {
            showingNutritionAudit = true
        } else {
            ToastManager.shared.showToast(message: "Nothing to review yet.")
        }
    }

    private func logRecoveryMealSuggestion(_ suggestion: MealSuggestion) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: suggestion.mealName,
            calories: Double(suggestion.calories),
            protein: suggestion.protein,
            carbs: suggestion.carbs,
            fats: suggestion.fats,
            servingSize: "1 serving (AI Suggestion)",
            servingWeight: 0,
            timestamp: Date()
        )

        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: foodItem, source: "workout_recovery_suggestion")
        DIContainer.shared.analyticsManager?.logEvent("workout_recovery_handoff_logged", parameters: [
            "calories": Int(suggestion.calories.rounded()),
            "protein": Int(suggestion.protein.rounded()),
            "carbs": Int(suggestion.carbs.rounded())
        ])

        withAnimation {
            self.recoveryMealSuggestion = nil
            self.showingRecoveryMealDetail = false
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
    @State private var draft: WorkoutSessionLog
    let isSaving: Bool
    let onSave: (WorkoutSessionLog) -> Void

    init(log: WorkoutSessionLog, isSaving: Bool, onSave: @escaping (WorkoutSessionLog) -> Void) {
        self._draft = State(initialValue: log)
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Date", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                }

                ForEach(draft.completedExercises.indices, id: \.self) { exerciseIndex in
                    let exercise = draft.completedExercises[exerciseIndex]
                    Section(exercise.exerciseName) {
                        ForEach(draft.completedExercises[exerciseIndex].sets.indices, id: \.self) { setIndex in
                            CompletedSetEditorRow(
                                set: $draft.completedExercises[exerciseIndex].sets[setIndex],
                                setIndex: setIndex + 1,
                                exerciseType: exercise.exercise.type
                            )
                        }
                    }
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(sanitizedDraft())
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
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

    private var distanceBinding: Binding<Double> {
        Binding(
            get: { set.distance ?? 0 },
            set: { set.distance = max(0, $0) }
        )
    }

    private var durationMinutesBinding: Binding<Int> {
        Binding(
            get: { max(0, (set.durationInSeconds ?? 0) / 60) },
            set: { set.durationInSeconds = max(0, $0) * 60 }
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
        .padding(.vertical, 4)
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
        editableNumberField(title: "Weight", unit: "lb") {
            TextField("0", value: $set.weight, format: .number.precision(.fractionLength(0...1)))
        }
    }

    private var strengthRepsField: some View {
        editableNumberField(title: "Reps", unit: "reps") {
            TextField("0", value: $set.reps, format: .number)
        }
    }

    private var cardioDistanceField: some View {
        editableNumberField(title: "Distance", unit: "mi") {
            TextField("0", value: distanceBinding, format: .number.precision(.fractionLength(0...2)))
        }
    }

    private var durationField: some View {
        editableNumberField(title: "Duration", unit: "min") {
            TextField("0", value: durationMinutesBinding, format: .number)
        }
    }

    private func formatEffort(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct WorkoutSummaryHeroCard: View {
    let date: Date
    let totalVolume: Double
    let exerciseCount: Int
    let setCount: Int
    let repCount: Int
    let estimatedMinutes: Int
    let isAnimated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Session Review",
                title: "Workout Complete",
                subtitle: date.formatted(date: .abbreviated, time: .shortened)
            ) {
                Image(systemName: "trophy.fill")
                    .appFont(size: 24, weight: .bold)
                    .foregroundStyle(AppPalette.achievement)
                    .frame(width: 52, height: 52)
                    .background(
                        AppPalette.achievement.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                    .scaleEffect(isAnimated ? 1.0 : 0.65)
                    .animation(AppMotion.standard, value: isAnimated)
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Volume", value: "\(Int(totalVolume).formatted()) lb", accent: AppPalette.effort),
                AppMetricItem(label: "Exercises", value: exerciseCount.formatted(), accent: Color.secondary),
                AppMetricItem(label: "Working sets", value: setCount.formatted(), accent: AppPalette.positive),
                AppMetricItem(label: "Reps", value: repCount.formatted(), accent: AppPalette.effort),
                AppMetricItem(label: "Estimated time", value: "\(estimatedMinutes) min", accent: AppPalette.recovery)
            ])
            .appSurface(.emphasized)
        }
        .accessibilityIdentifier("workout_summary_header")
    }
}

private struct SessionExerciseBreakdownCard: View {
    let exercises: [CompletedExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Session Breakdown",
                subtitle: "\(exercises.count) exercises completed"
            )

            VStack(spacing: 0) {
                ForEach(Array(exercises.prefix(8).enumerated()), id: \.element.id) { index, exercise in
                    SessionExerciseRow(exercise: exercise)

                    if index < min(exercises.count, 8) - 1 {
                        Divider()
                            .padding(.leading, 64)
                    }
                }

                if exercises.count > 8 {
                    Text("+\(exercises.count - 8) more")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(AppSpacing.row)
                }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityIdentifier("workout_summary_breakdown")
    }
}

private struct SessionExerciseRow: View {
    let exercise: CompletedExercise
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var volume: Double {
        exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    private var bestSetText: String {
        switch exercise.exercise.type {
        case .strength:
            guard let bestSet = exercise.sets.max(by: { lhs, rhs in
                (lhs.weight * Double(lhs.reps)) < (rhs.weight * Double(rhs.reps))
            }) else { return "No sets" }
            return "\(String(format: "%g", bestSet.weight)) lb x \(bestSet.reps)"

        case .cardio:
            let totalDistance = exercise.sets.reduce(0) { $0 + ($1.distance ?? 0) }
            let totalMinutes = exercise.sets.reduce(0) { $0 + (($1.durationInSeconds ?? 0) / 60) }
            if totalDistance > 0 && totalMinutes > 0 {
                return "\(String(format: "%.1f", totalDistance)) mi in \(totalMinutes) min"
            }
            if totalMinutes > 0 {
                return "\(totalMinutes) min"
            }
            return "\(exercise.sets.count) sets"

        case .flexibility:
            let totalSeconds = exercise.sets.reduce(0) { $0 + ($1.durationInSeconds ?? 0) }
            return totalSeconds > 0 ? "\(totalSeconds) sec" : "\(exercise.sets.count) sets"
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    exerciseIdentity
                    if volume > 0 {
                        Text("\(Int(volume).formatted()) lb volume")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.brand)
                    }
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    exerciseIdentity
                    Spacer(minLength: AppSpacing.compact)

                    if volume > 0 {
                        Text("\(Int(volume).formatted()) lb")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.brand)
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }

    private var exerciseIdentity: some View {
        HStack(spacing: AppSpacing.row) {
            Text(ExerciseEmojiMapper.getEmoji(for: exercise.exerciseName))
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.brand.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exerciseName)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

                Text("\(exercise.sets.count) sets · \(bestSetText)")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
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
