import SwiftUI

import MyFitPlateCore

struct MealSuggestionCardView: View {
    let suggestion: MealSuggestion?
    var onGenerate: () -> Void
    var onTap: () -> Void
    var onPrefs: () -> Void
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Maia suggestions")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Button(action: onPrefs) {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(isLoading)
                .accessibilityLabel("Meal suggestion preferences")
                
                Button(action: onGenerate) {
                    Image(systemName: "sparkles")
                }
                .disabled(isLoading)
                .accessibilityLabel("Generate meal suggestion")
            }
            .tint(.blue)

            Divider()
            
            Button(action: onTap) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(minHeight: 60)
                } else if let suggestion = suggestion {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.mealName)
                            .appFont(size: 16, weight: .bold)
                        
                        Text("Estimate: \(formatted(suggestion.calories)) cal, P \(formatted(suggestion.protein)) g, C \(formatted(suggestion.carbs)) g, F \(formatted(suggestion.fats)) g")
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        
                        Text("Tap to see recipe")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.blue)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Use sparkles to get a meal idea that fits your remaining goals for today.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(minHeight: 60)
                }
            }
            .buttonStyle(.plain)
        }
        .asCard()
    }

    private func formatted(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
