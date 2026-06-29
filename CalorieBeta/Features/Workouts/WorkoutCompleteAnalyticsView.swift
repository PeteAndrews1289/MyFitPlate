import MyFitPlateCore

import SwiftUI
import Charts

struct WorkoutCompleteAnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    
    // The raw data source
    let log: WorkoutSessionLog
    
    @StateObject var analyticsService = WorkoutAnalyticsService()
    @State private var analytics: WorkoutAnalytics?
    @State private var comparison: WorkoutComparison?
    @State private var trendData: [String: [ExerciseTrendPoint]] = [:]
    @State private var muscleSplit: [MuscleSplitPoint] = [] // New State
    
    @State private var isAnimated = false
    @State private var isLoading = true

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
                            Text("New Records").appFont(size: 20, weight: .bold)
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
                }

                if !trendData.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Key Gains")
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
        .onAppear {
            isAnimated = true
            loadData()
        }
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
