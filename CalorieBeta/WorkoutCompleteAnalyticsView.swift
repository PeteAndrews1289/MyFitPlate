import SwiftUI
import FirebaseAuth
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // 1. Header
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)
                        .scaleEffect(isAnimated ? 1.0 : 0.5)
                        .animation(.spring(), value: isAnimated)
                    
                    Text("Workout Summary")
                        .appFont(size: 32, weight: .black)
                    
                    Text(log.date.dateValue().formatted(date: .abbreviated, time: .shortened))
                        .appFont(size: 16)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                if let analytics = analytics {
                    // 2. Comparison (Versus Last Time)
                    if let comp = comparison {
                        HStack {
                            StatCard(title: "Volume vs Last", value: String(format: "%+.0f%%", comp.volumeDiffPercent * 100), unit: "", icon: "chart.bar.fill", color: comp.volumeDiffPercent >= 0 ? .green : .orange)
                            StatCard(title: "Duration vs Last", value: String(format: "%+.0f%%", comp.durationDiffPercent * 100), unit: "", icon: "clock.fill", color: .blue)
                        }
                        .padding(.horizontal)
                    } else {
                        // Standard stats if no comparison available
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            StatCard(title: "Total Volume", value: "\(Int(analytics.totalVolume))", unit: "lbs", icon: "dumbbell.fill", color: .blue)
                            StatCard(title: "Exercises", value: "\(log.completedExercises.count)", unit: "total", icon: "figure.run", color: .orange)
                        }
                        .padding(.horizontal)
                    }
                    
                    // 3. PR Celebration List (NEW)
                    if !analytics.personalRecords.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "crown.fill").foregroundColor(.yellow)
                                Text("New Records!").font(.headline)
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(analytics.personalRecords), id: \.key) { exerciseName, prValue in
                                        PRCard(exerciseName: exerciseName, detail: prValue)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // 4. Trends Charts
                    if !trendData.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Key Gains")
                                .appFont(size: 20, weight: .bold)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(log.completedExercises.prefix(3)) { exercise in
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
                    
                    // 5. Muscle Split / Heatmap (NEW)
                    if !muscleSplit.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Muscle Focus")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            Chart(muscleSplit) { point in
                                BarMark(
                                    x: .value("Volume", point.volume),
                                    y: .value("Muscle", point.muscleName)
                                )
                                .foregroundStyle(by: .value("Muscle", point.muscleName))
                            }
                            .frame(height: 200)
                            .padding()
                            .background(Color.backgroundSecondary)
                            .cornerRadius(16)
                            .padding(.horizontal)
                        }
                    }

                    // 6. AI Insights
                    if !analytics.aiInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles").foregroundColor(.brandPrimary)
                                Text("Maia's Analysis").appFont(size: 20, weight: .bold)
                            }
                            .padding(.horizontal)
                            ForEach(analytics.aiInsights) { insight in
                                InsightCard(insight: insight)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Share Button
                    ShareLink(item: generateShareText(analytics: analytics), preview: SharePreview("Workout Summary", image: Image(systemName: "trophy.fill"))) {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                } else {
                    ProgressView("Analyzing...")
                        .padding()
                }
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Calculate Muscle Split locally immediately
        self.muscleSplit = analyticsService.calculateMuscleSplit(log: log)
        
        Task {
            // 1. Calculate Standard Analytics (includes PRs and Insights)
            let result = await analyticsService.generateAnalyticsForPastSession(sessionID: log.id ?? "", workoutName: "Workout", date: log.date.dateValue())
            self.analytics = result
            
            // 2. Fetch Comparison
            self.comparison = await analyticsService.compareAgainstPrevious(currentLog: log, userID: uid)
            
            // 3. Fetch Trends
            for exercise in log.completedExercises.prefix(3) {
                let points = await analyticsService.fetchTrends(for: exercise.exerciseName, userID: uid)
                self.trendData[exercise.exerciseName] = points
            }
            self.isLoading = false
        }
    }
    
    private func generateShareText(analytics: WorkoutAnalytics) -> String {
        let prCount = analytics.personalRecords.count
        let prText = prCount > 0 ? "Hit \(prCount) new PRs!" : "Great session!"
        return "Just crushed a workout with MyFitPlate! 💪 \(Int(analytics.totalVolume))lbs total volume. \(prText)"
    }
}

// MARK: - Subviews

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
        case "Performance": return "chart.bar.fill"; case "Recovery": return "bed.double.fill"; case "Nutrition": return "fork.knife"; default: return "lightbulb.fill"
        }
    }
    var categoryColor: Color {
        switch insight.category {
        case "Performance": return .blue; case "Recovery": return .indigo; case "Nutrition": return .green; default: return .orange
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
