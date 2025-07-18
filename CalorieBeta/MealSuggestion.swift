import SwiftUI

struct MealSuggestion: Codable, Equatable {
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
}

struct MealSuggestionCardView: View {
    @Binding var suggestion: MealSuggestion?
    var onGenerate: () -> Void
    var onLog: (MealSuggestion) -> Void
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Maia's Suggestions")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Button(action: onGenerate) {
                    Image(systemName: "sparkles")
                }
                .disabled(isLoading)
            }
            .tint(.brandPrimary)

            Divider()
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 80)
            } else if let suggestion = suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text(suggestion.mealName)
                        .appFont(size: 16, weight: .bold)
                    
                    Text("Est: \(String(format: "%.0f", suggestion.calories)) cal, P:\(String(format: "%.0f", suggestion.protein))g, C:\(String(format: "%.0f", suggestion.carbs))g, F:\(String(format: "%.0f", suggestion.fats))g")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    
                    Button(action: { onLog(suggestion) }) {
                        Text("Log This Meal")
                            .appFont(size: 14, weight: .semibold)
                    }
                    .tint(.brandPrimary)
                    
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap the sparkles ✨ to get a meal idea that fits your remaining goals for today.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(minHeight: 80)
            }
        }
        .asCard()
    }
}
