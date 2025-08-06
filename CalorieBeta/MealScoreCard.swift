

import SwiftUI

struct MealScoreCard: View {
    let score: MealScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Yesterday's Meal Score")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Text(score.grade)
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(score.color)
            }

            Text(score.summary)
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .asCard()
    }
}
