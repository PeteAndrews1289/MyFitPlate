import SwiftUI

/// This view is the detailed sheet that appears when a user taps on the `WellnessScoreCardView`.
/// It provides a larger view of the score and more descriptive text for each component.
struct WellnessScoreDetailView: View {
    // The data model passed in from the card.
    let wellnessScore: WellnessScore
    
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
}
