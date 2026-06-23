import SwiftUI

/// A custom glassmorphism card background
struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

/// A macro progress bar
struct MacroBar: View {
    let title: String
    let actual: Double
    let goal: Double
    let color: Color
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).bold()
                Spacer()
                Text("\(Int(actual)) / \(Int(goal)) \(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: min(geo.size.width, geo.size.width * (actual / max(goal, 1))))
                }
            }
            .frame(height: 8)
        }
    }
}

/// The new modern Wellness Score Detail View
struct WellnessScoreDetailView: View {
    let wellnessScore: WellnessScore
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?
    
    @Environment(\.dismiss) var dismiss
    
    // Background animation
    @State private var animateGradient = false

    var body: some View {
        NavigationView {
            ZStack {
                // Animated Glassmorphism Backdrop
                LinearGradient(colors: [wellnessScore.color.opacity(0.3), Color.backgroundPrimary], startPoint: animateGradient ? .topLeading : .bottomLeading, endPoint: animateGradient ? .bottomTrailing : .topTrailing)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true), value: animateGradient)
                    .onAppear { animateGradient.toggle() }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                        
                        // Summary Cards
                        VStack(spacing: 20) {
                            GlassCard {
                                detailRow(
                                    title: "Nutrition Score",
                                    score: wellnessScore.nutritionScore,
                                    description: "Based on how well you met your calorie, macro, and food quality goals yesterday.",
                                    color: .accentColor,
                                    icon: "fork.knife"
                                )
                            }
                            
                            GlassCard {
                                detailRow(
                                    title: "Sleep Score",
                                    score: wellnessScore.sleepScore,
                                    description: wellnessScore.sleepScore == nil ? "Sleep data is not available yet. Review Apple Health access." : "Calculated from your total sleep duration.",
                                    color: .blue,
                                    icon: "moon.fill"
                                )
                            }
                            
                            GlassCard {
                                detailRow(
                                    title: "Recovery Score",
                                    score: wellnessScore.recoveryScore,
                                    description: "Reflects your body's readiness based on Resting Heart Rate and HRV.",
                                    color: .purple,
                                    icon: "heart.fill"
                                )
                            }
                        }
                        
                        if let score = mealScore, score.overallScore > 0 {
                            MealScoreExpandedSection(score: score)
                        }
                        
                        if let report = sleepReport {
                            SleepExpandedSection(report: report)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Wellness Debrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(wellnessScore.color.opacity(0.16), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(Double(wellnessScore.overallScore) / 100.0, 1.0)))
                    .stroke(wellnessScore.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.9), value: wellnessScore.overallScore)
                VStack(spacing: 0) {
                    Text("\(wellnessScore.overallScore)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("/ 100")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .frame(width: 132, height: 132)

            Text(wellnessScore.summary)
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 14)
    }

    private func detailRow(title: String, score: Int?, description: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(score.map { "\($0)" } ?? "--")
                        .appFont(size: 22, weight: .heavy)
                        .foregroundColor(color)
                    Text(score != nil ? "/100" : "")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule().fill(color)
                        .frame(width: max(9, geo.size.width * CGFloat(min(Double(score ?? 0) / 100.0, 1.0))))
                }
            }
            .frame(height: 9)

            Text(description)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Meal Score Section
private struct MealScoreExpandedSection: View {
    let score: MealScore
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Yesterday's Report")
                        .font(.title2).bold()
                    Spacer()
                    Text(score.grade)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(score.color)
                }
                
                if !score.personalizedAISummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("AI Insights")
                                .font(.headline)
                                .foregroundColor(.purple)
                        }
                        Text(score.personalizedAISummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(16)
                }

                VStack(spacing: 16) {
                    MacroBar(title: "Calories", actual: score.actualCalories, goal: score.goalCalories, color: .orange, unit: "kcal")
                    MacroBar(title: "Protein", actual: score.actualProtein, goal: score.goalProtein, color: .accentProtein, unit: "g")
                    MacroBar(title: "Carbs", actual: score.actualCarbs, goal: score.goalCarbs, color: .accentCarbs, unit: "g")
                    MacroBar(title: "Fats", actual: score.actualFats, goal: score.goalFats, color: .accentFats, unit: "g")
                }
                
                if !score.improvementTips.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Actionable Tips")
                        .font(.headline)
                    ForEach(score.improvementTips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.icon)
                                .foregroundColor(tip.color)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.category).font(.subheadline).bold().foregroundColor(tip.color)
                                Text(tip.advice).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sleep Section
enum SleepRangePicker: String, CaseIterable {
    case lastNight = "Last Night"
    case average = "7-Day Average"
}

private struct SleepExpandedSection: View {
    let report: EnhancedSleepReport
    @State private var selectedRange: SleepRangePicker = .average

    private var lastNightData: EnhancedSleepReport.DailySleepStageData? {
        report.dailySleepData.max(by: { $0.date < $1.date })
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60.0)); let hours = totalMinutes / 60; let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" } else { return "\(minutes)m" }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Sleep Analysis")
                        .font(.title2).bold()
                    Spacer()
                }
                
                Picker("Range", selection: $selectedRange) {
                    ForEach(SleepRangePicker.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                
                if selectedRange == .average {
                    weeklyAverageContent
                } else {
                    if let lastNight = lastNightData {
                        lastNightContent(lastNight)
                    } else {
                        Text("No data available for last night.")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var weeklyAverageContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("\(report.averageSleepScore)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(sleepScoreColor(report.averageSleepScore))
                Text("Weekly Average Score (\(report.dateRange))")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                statRow(title: "Time Asleep", value: formatDuration(report.averageTimeAsleep))
                statRow(title: "Time in Bed", value: formatDuration(report.averageTimeInBed))
                statRow(title: "Consistency", value: "\(report.sleepConsistencyScore)/100", description: report.sleepConsistencyMessage)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Average Stages").font(.headline)
                SleepStagesBar(awake: report.averageTimeAwake, rem: report.averageTimeInREM, core: report.averageTimeInCore, deep: report.averageTimeInDeep)
                
                VStack(spacing: 8) {
                    stageLegend(label: "Awake", value: report.averageTimeAwake, color: .gray)
                    stageLegend(label: "REM", value: report.averageTimeInREM, color: .purple)
                    stageLegend(label: "Core", value: report.averageTimeInCore, color: .blue)
                    stageLegend(label: "Deep", value: report.averageTimeInDeep, color: .indigo)
                }
            }
        }
    }
    
    @ViewBuilder
    private func lastNightContent(_ data: EnhancedSleepReport.DailySleepStageData) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(formatDuration(data.timeAsleep))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                Text("Total Sleep Last Night")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                statRow(title: "Time in Bed", value: formatDuration(data.timeInBed))
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Stages").font(.headline)
                SleepStagesBar(awake: data.timeAwake, rem: data.timeREM, core: data.timeCore, deep: data.timeDeep)
                
                VStack(spacing: 8) {
                    stageLegend(label: "Awake", value: data.timeAwake, color: .gray)
                    stageLegend(label: "REM", value: data.timeREM, color: .purple)
                    stageLegend(label: "Core", value: data.timeCore, color: .blue)
                    stageLegend(label: "Deep", value: data.timeDeep, color: .indigo)
                }
            }
        }
    }

    private func statRow(title: String, value: String, description: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { 
                Text(title).font(.subheadline).bold()
                Spacer()
                Text(value).font(.subheadline).bold().foregroundColor(.secondary) 
            }
            if let desc = description { 
                Text(desc).font(.caption).foregroundColor(.secondary) 
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func stageLegend(label: String, value: TimeInterval, color: Color) -> some View {
        HStack { 
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.subheadline)
            Spacer()
            Text(formatDuration(value)).font(.subheadline).foregroundColor(.secondary) 
        }
    }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score { case 85...: return .green; case 70..<85: return .yellow; case 50..<70: return .orange; default: return .red }
    }
}

private struct SleepStagesBar: View {
    let awake: TimeInterval
    let rem: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    
    private var total: TimeInterval { awake + rem + core + deep }
    
    var body: some View {
        GeometryReader { geo in
            if total > 0 {
                HStack(spacing: 0) {
                    Color.gray.frame(width: max(0, geo.size.width * (awake / total)))
                    Color.purple.frame(width: max(0, geo.size.width * (rem / total)))
                    Color.blue.frame(width: max(0, geo.size.width * (core / total)))
                    Color.indigo.frame(width: max(0, geo.size.width * (deep / total)))
                }
                .cornerRadius(8)
            } else {
                Color.gray.opacity(0.3).cornerRadius(8)
            }
        }
        .frame(height: 16)
    }
}
