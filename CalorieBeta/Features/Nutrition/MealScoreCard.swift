import SwiftUI

struct MealScoreCard: View {
    let score: MealScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Yesterday's Report Card")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Text(score.grade)
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(score.color)
            }

            Text(score.summary)
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
            
            Divider()
            
            VStack(spacing: 8) {
                ScoreRow(title: "Calorie Control", score: score.calorieScore)
                ScoreRow(title: "Macro Balance", score: score.macroScore)
                ScoreRow(title: "Food Quality", score: score.qualityScore)
            }
        }
        .asCard()
    }
}

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
