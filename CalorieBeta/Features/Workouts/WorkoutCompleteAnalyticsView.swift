import MyFitPlateCore

import SwiftUI
import Charts

struct WorkoutCompleteAnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var pantryService: PantryService
    
    // The raw data source
    let log: WorkoutSessionLog
    
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
    @State private var recoveryMealSuggestion: MealSuggestion?
    @State private var didLogRecoveryHandoffViewed = false

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
            VStack(spacing: 18) {
                WorkoutSummaryHeroCard(
                    date: log.date,
                    totalVolume: totalVolume,
                    exerciseCount: log.completedExercises.count,
                    setCount: completedSetCount,
                    isAnimated: isAnimated
                )
                .padding(.horizontal)
                .padding(.top, 14)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "Total Volume", value: "\(Int(displayedAnalytics.totalVolume))", unit: "lbs", icon: "dumbbell.fill", color: .brandPrimary)
                    StatCard(title: "Work Sets", value: "\(completedSetCount)", unit: "logged", icon: "checkmark.seal.fill", color: .accentPositive)
                    StatCard(title: "Total Reps", value: "\(totalRepCount)", unit: totalRepCount == 1 ? "rep" : "reps", icon: "repeat", color: .orange)
                    StatCard(title: "Est. Time", value: "\(estimatedDurationMinutes)", unit: "min", icon: "clock.fill", color: .blue)
                }
                .padding(.horizontal)

                if shouldShowRecoveryHandoff {
                    workoutRecoveryHandoffCard(plan: workoutCompletionFuelPlan)
                        .padding(.horizontal)
                }

                if let comp = comparison {
                    HStack(spacing: 12) {
                        StatCard(title: "Volume vs Last", value: formatPercent(comp.volumeDiffPercent), unit: comp.previousDate?.formatted(date: .abbreviated, time: .omitted) ?? "last time", icon: "chart.bar.fill", color: comp.volumeDiffPercent >= 0 ? .accentPositive : .orange)
                        StatCard(title: "Pace vs Last", value: formatPercent(-comp.durationDiffPercent), unit: "estimated", icon: "speedometer", color: comp.durationDiffPercent <= 0 ? .accentPositive : .blue)
                    }
                    .padding(.horizontal)
                }

                SessionExerciseBreakdownCard(exercises: log.completedExercises)
                    .padding(.horizontal)

                if !displayedAnalytics.personalRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "crown.fill").foregroundColor(.yellow)
                            Text("New records").appFont(size: 20, weight: .bold)
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(displayedAnalytics.personalRecords), id: \.key) { exerciseName, prValue in
                                    PRCard(exerciseName: exerciseName, detail: prValue)
                                }
                            }
                            .padding(.horizontal)
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
                        Text("Key gains")
                            .appFont(size: 20, weight: .bold)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(Array(log.completedExercises.prefix(3))) { exercise in
                                    if let points = trendData[exercise.exerciseName], points.count > 1 {
                                        ExerciseTrendChartView(exerciseName: exercise.exerciseName, dataPoints: points, metric: "Max Weight")
                                            .frame(width: 300)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if !muscleSplit.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Muscle Focus")
                            .appFont(size: 20, weight: .bold)
                            .padding(.horizontal)

                        Chart(muscleSplit) { point in
                            BarMark(
                                x: .value("Sets", point.setCount),
                                y: .value("Muscle", point.muscleName)
                            )
                            .foregroundStyle(Color.brandPrimary.gradient)
                        }
                        .frame(height: 200)
                        .padding()
                        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal)
                    }
                }

                if !displayedAnalytics.aiInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles").foregroundColor(.brandPrimary)
                            Text("Maia's Analysis").appFont(size: 20, weight: .bold)
                        }
                        .padding(.horizontal)

                        ForEach(displayedAnalytics.aiInsights) { insight in
                            InsightCard(insight: insight)
                        }
                        .padding(.horizontal)
                    }
                } else if isLoading {
                    InlineAnalysisLoadingCard()
                        .padding(.horizontal)
                }

                ShareLink(item: generateShareText(analytics: displayedAnalytics), preview: SharePreview("Workout Summary", image: Image(systemName: "trophy.fill"))) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
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
        self.muscleSplit = analyticsService.calculateMuscleSplit(log: log)

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: recoveryHandoffIcon(for: plan.kind))
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(recoveryHandoffColor(for: plan.kind))
                    .frame(width: 42, height: 42)
                    .background(recoveryHandoffColor(for: plan.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.kind == .overTargetReview ? "Today fuel check" : "Recovery meal")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(recoveryHandoffColor(for: plan.kind))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(recoveryHandoffColor(for: plan.kind).opacity(0.12), in: Capsule())

                    Text(plan.title)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(plan.summary)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(plan.detail)
                .appFont(size: 12, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                recoveryMetricPill(
                    title: plan.remainingCalories >= 0 ? "Budget" : "Over",
                    value: "\(Int(abs(plan.remainingCalories).rounded()).formatted()) cal",
                    color: plan.remainingCalories >= 0 ? .brandPrimary : .orange
                )

                if let protein = plan.targetProteinGrams {
                    recoveryMetricPill(title: "Protein", value: "\(protein)g", color: .accentProtein)
                }

                if let carbs = plan.targetCarbGrams {
                    recoveryMetricPill(title: "Carbs", value: "\(carbs)g", color: .accentCarbs)
                }
            }

            recoveryHandoffActions(for: plan)
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(recoveryHandoffColor(for: plan.kind).opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func recoveryHandoffActions(for plan: TodayFuelPlan) -> some View {
        switch plan.action {
        case .fillMacros:
            HStack(spacing: 10) {
                Button(action: openRecoveryFoodSearch) {
                    Label("Find food", systemImage: "magnifyingglass")
                        .appFont(size: 13, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.backgroundPrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: generateRecoveryMealSuggestion) {
                    HStack(spacing: 6) {
                        if insightsService.isGeneratingSuggestion {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                                .appFont(size: 12, weight: .bold)
                        }
                        Text("Fill macros")
                            .appFont(size: 13, weight: .bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(insightsService.isGeneratingSuggestion)
            }

        case .reviewDay:
            Button(action: reviewTodayFromRecoveryHandoff) {
                Label("Review today", systemImage: "checklist")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.backgroundPrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

        case .openRecoverySearch:
            Button(action: openRecoveryFoodSearch) {
                Label("Find recovery food", systemImage: "magnifyingglass")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.backgroundPrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

        case .none:
            EmptyView()
        }
    }

    private func recoveryMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recoveryHandoffIcon(for kind: TodayFuelPlan.Kind) -> String {
        kind == .overTargetReview ? "exclamationmark.triangle.fill" : "fork.knife.circle.fill"
    }

    private func recoveryHandoffColor(for kind: TodayFuelPlan.Kind) -> Color {
        kind == .overTargetReview ? .orange : .brandPrimary
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
        return "Just finished a workout with MyFitPlate: \(Int(analytics.totalVolume)) lbs total volume. \(prText)"
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%+.0f%%", value * 100)
    }
}

// MARK: - Subviews

struct WorkoutSummaryHeroCard: View {
    let date: Date
    let totalVolume: Double
    let exerciseCount: Int
    let setCount: Int
    let isAnimated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Complete")
                        .appFont(size: 30, weight: .black)
                        .foregroundColor(.textPrimary)

                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "trophy.fill")
                    .appFont(size: 36, weight: .bold)
                    .foregroundColor(.yellow)
                    .scaleEffect(isAnimated ? 1.0 : 0.65)
                    .animation(.spring(response: 0.45, dampingFraction: 0.62), value: isAnimated)
            }

            HStack(spacing: 12) {
                SummaryHeroPill(title: "Volume", value: "\(Int(totalVolume)) lbs", icon: "dumbbell.fill")
                SummaryHeroPill(title: "Logged", value: "\(exerciseCount) ex / \(setCount) sets", icon: "list.bullet.clipboard.fill")
            }
        }
        .asCard()
    }
}

private struct SummaryHeroPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SessionExerciseBreakdownCard: View {
    let exercises: [CompletedExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Session Breakdown")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("\(exercises.count) exercises completed")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "list.bullet.rectangle.fill")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }

            VStack(spacing: 10) {
                ForEach(Array(exercises.prefix(8))) { exercise in
                    SessionExerciseRow(exercise: exercise)
                }

                if exercises.count > 8 {
                    Text("+\(exercises.count - 8) more")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
        }
        .asCard()
    }
}

private struct SessionExerciseRow: View {
    let exercise: CompletedExercise

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
        HStack(spacing: 12) {
            Text(ExerciseEmojiMapper.getEmoji(for: exercise.exerciseName))
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exerciseName)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("\(exercise.sets.count) sets - \(bestSetText)")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer()

            if volume > 0 {
                Text("\(Int(volume))")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            }
        }
        .padding(10)
        .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding()
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatCard: View {
    let title: String, value: String, unit: String, icon: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon).foregroundColor(color); Spacer() }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).appFont(size: 24, weight: .bold)
                Text(unit).appFont(size: 12).foregroundColor(.secondary)
            }
            Text(title).appFont(size: 14, weight: .medium).foregroundColor(.secondary).opacity(0.8)
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }
}

struct PRCard: View {
    let exerciseName: String, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: "crown.fill").foregroundColor(.yellow); Spacer() }
            Text(exerciseName)
                .appFont(size: 14, weight: .bold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .appFont(size: 12)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 140, height: 110)
        .background(Color.backgroundSecondary)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.3), lineWidth: 2))
        .cornerRadius(16)
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
    var categoryColor: Color {
        switch insight.category {
        case "Performance": return .blue
        case "Recovery": return .indigo
        case "Nutrition": return .green
        default: return .orange
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(categoryColor.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: categoryIcon).foregroundColor(categoryColor)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title).appFont(size: 16, weight: .bold)
                Text(insight.message).appFont(size: 14).foregroundColor(.secondary).lineSpacing(2)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }
}
