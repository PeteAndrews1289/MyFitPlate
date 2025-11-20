import SwiftUI

/// This view is the detailed sheet that appears when a user taps on the `WellnessScoreCardView`.
/// It provides a larger view of the score and more descriptive text for each component.
struct WellnessScoreDetailView: View {
    // The data model passed in from the card.
    let wellnessScore: WellnessScore
    
    // *** ADDED: Optional data for the new sections ***
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?
    
    // Environment variable to allow dismissing the sheet.
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Header
                    // The large score and summary text at the top.
                    header
                    
                    // MARK: - Score Details
                    // A vertical stack of the three component scores with explanations.
                    VStack(spacing: 16) {
                        detailRow(
                            title: "Nutrition Score",
                            score: wellnessScore.nutritionScore,
                            description: "Based on how well you met your calorie, macro, and food quality goals yesterday.",
                            color: .accentColor
                        )
                        
                        detailRow(
                            title: "Sleep Score",
                            score: wellnessScore.sleepScore,
                            description: "Calculated from your total sleep duration. Aim for 7-9 hours for optimal recovery.",
                            color: .blue
                        )
                        
                        detailRow(
                            title: "Recovery Score",
                            score: wellnessScore.recoveryScore,
                            description: "Reflects your body's readiness, measured by Resting Heart Rate (lower is better) and Heart Rate Variability (HRV) (higher is better).",
                            color: .purple
                        )
                    }
                    
                    // *** NEW: Conditionally show Meal Score Details ***
                    if let score = mealScore, score.overallScore > 0 {
                        mealScoreSection(score: score)
                    }
                    
                    // *** NEW: Conditionally show Sleep Analysis Details ***
                    if let report = sleepReport {
                        SleepDetailContent(report: report) // Using the helper view
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea()) // Sets the background for the ScrollView.
            .navigationTitle("Wellness Debrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Adds a "Close" button to the top-left corner to dismiss the sheet.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// A private computed property for the header view.
    private var header: some View {
        VStack {
            // The large score (e.g., "85").
            Text("\(wellnessScore.overallScore)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(wellnessScore.color)
            
            // The summary text (e.g., "Feeling strong and ready.").
            Text(wellnessScore.summary)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    /// A private function to create a reusable row for each score component.
    private func detailRow(title: String, score: Int, description: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and score (e.g., "Nutrition Score" ... "80/100").
            HStack {
                Text(title)
                    .font(.title2).bold()
                Spacer()
                Text("\(score)/100")
                    .font(.title2).bold()
                    .foregroundColor(color)
            }
            
            // A progress bar representing the score.
            ProgressView(value: Double(score) / 100.0)
                .tint(color)
            
            // The detailed explanation text.
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding() // Add padding inside the row.
        .background(Color.backgroundSecondary) // Set the row's background.
        .cornerRadius(12) // Round the corners of the row.
    }
    
    // *** NEW: View builder for the Meal Score Section ***
    // (This UI is based on your MealScoreCard.swift file)
    @ViewBuilder
    private func mealScoreSection(score: MealScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yesterday's Report Card")
                .font(.title2).bold()
            
            HStack {
                VStack(alignment: .leading) {
                    Text(score.grade)
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(score.color)
                    Text(score.summary)
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
            }

            Divider()
            
            VStack(spacing: 8) {
                ScoreRow(title: "Calorie Control", score: score.calorieScore)
                ScoreRow(title: "Macro Balance", score: score.macroScore)
                ScoreRow(title: "Food Quality", score: score.qualityScore)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

// *** NEW: Helper view for the Meal Score section ***
private struct ScoreRow: View {
    let title: String
    let score: Int
    
    private var scoreColor: Color {
        switch score {
        case 90...: return .accentPositive
        case 70..<90: return .yellow
        case 50..<70: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        HStack {
            Text(title)
                .appFont(size: 14)
            Spacer()
            Text("\(score)%")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(scoreColor)
        }
    }
}


// *** NEW: Helper view copied from SleepReportCard.swift ***
// This is the detailed content for the sleep analysis
private struct SleepDetailContent: View {
    let report: EnhancedSleepReport

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60.0)); let hours = totalMinutes / 60; let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" } else { return "\(minutes)m" }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack {
                Text("\(report.averageSleepScore)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(sleepScoreColor(report.averageSleepScore))
                Text("Weekly Average Score (\(report.dateRange))")
                    .font(.headline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }

             detailRow(title: "Time Asleep", value: formatDuration(report.averageTimeAsleep))
             detailRow(title: "Time in Bed", value: formatDuration(report.averageTimeInBed))
             detailRow(title: "Consistency Score", value: "\(report.sleepConsistencyScore)", description: report.sleepConsistencyMessage)

            VStack(alignment: .leading, spacing: 8) {
                 Text("Average Time in Stages").font(.title2).bold()
                 stageDetailRow(label: "Awake", value: report.averageTimeAwake, color: .gray)
                 stageDetailRow(label: "REM", value: report.averageTimeInREM, color: .purple)
                 stageDetailRow(label: "Core", value: report.averageTimeInCore, color: .blue)
                 stageDetailRow(label: "Deep", value: report.averageTimeInDeep, color: .indigo)
            }
            .padding().background(Color.backgroundSecondary).cornerRadius(12)
        }
    }

     private func detailRow(title: String, value: String, description: String? = nil) -> some View {
         VStack(alignment: .leading, spacing: 8) {
             HStack { Text(title).font(.title3).bold(); Spacer(); Text(value).font(.title3).bold().foregroundColor(.secondary) }
             if let description = description { Text(description).font(.subheadline).foregroundColor(.secondary) }
         }
         .padding().background(Color.backgroundSecondary).cornerRadius(12)
     }

      @ViewBuilder
      private func stageDetailRow(label: String, value: TimeInterval, color: Color) -> some View {
          HStack { Circle().fill(color).frame(width: 10, height: 10); Text(label).font(.headline); Spacer(); Text(formatDuration(value)).foregroundColor(.secondary) }
      }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score { case 85...: return .green; case 70..<85: return .yellow; case 50..<70: return .orange; default: return .red }
    }
}
