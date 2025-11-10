import SwiftUI

/// This view is the small summary card shown on the Reports tab.
/// It displays the overall wellness score and its three components.
struct WellnessScoreCardView: View {
    // The data model containing all the score information.
    let wellnessScore: WellnessScore
    
    // State variable to control showing the detailed pop-up sheet.
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Section
            HStack {
                // Title and summary text.
                VStack(alignment: .leading) {
                    Text("Daily Wellness Score")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(wellnessScore.summary)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(wellnessScore.color) // Uses the color from the data model.
                }
                Spacer()
                
                // MARK: - Overall Score Gauge
                // A circular gauge showing the main score (e.g., "85").
                Gauge(value: Double(wellnessScore.overallScore), in: 0...100) {
                    // Accessibility label for the gauge.
                    Image(systemName: "heart.fill")
                } currentValueLabel: {
                    // The text displayed inside the gauge.
                    Text("\(wellnessScore.overallScore)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .gaugeStyle(.accessoryCircularCapacity) // Apple's standard circular gauge style.
                .tint(wellnessScore.color) // Tints the gauge with the score-appropriate color.
            }
            
            Divider()
            
            // MARK: - Sub-Score Section
            // A horizontal layout showing the three component scores.
            HStack(spacing: 16) {
                ScoreComponentView(
                    icon: "fork.knife",
                    color: .accentColor,
                    title: "Nutrition",
                    score: wellnessScore.nutritionScore
                )
                ScoreComponentView(
                    icon: "bed.double.fill",
                    color: .blue,
                    title: "Sleep",
                    score: wellnessScore.sleepScore
                )
                ScoreComponentView(
                    icon: "waveform.path.ecg",
                    color: .purple,
                    title: "Recovery",
                    score: wellnessScore.recoveryScore
                )
            }
        }
        .padding() // Adds padding inside the card.
        .background(Color.backgroundSecondary) // Sets the card's background color.
        .cornerRadius(16) // Rounds the corners of the card.
        .contentShape(Rectangle()) // Makes the whole card tappable.
        .onTapGesture {
            showDetail = true // Tapping the card sets this to true...
        }
        .sheet(isPresented: $showDetail) {
            // ...which presents the WellnessScoreDetailView as a pop-up sheet.
            WellnessScoreDetailView(wellnessScore: wellnessScore)
        }
    }
}

/// A small, reusable view to display one of the sub-scores (Nutrition, Sleep, Recovery).
struct ScoreComponentView: View {
    let icon: String
    let color: Color
    let title: String
    let score: Int

    var body: some View {
        HStack {
            // Icon with a circular background.
            Image(systemName: icon)
                .font(.callout)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            // Title and score text.
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(score)")
                    .fontWeight(.semibold)
            }
        }
    }
}
