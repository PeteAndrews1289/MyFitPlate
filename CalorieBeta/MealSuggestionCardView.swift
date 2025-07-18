import SwiftUI

struct MealSuggestion: Codable, Equatable, Identifiable {
    var id = UUID()
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let ingredients: [String]
    let instructions: String
    
    enum CodingKeys: String, CodingKey {
        case mealName, calories, protein, carbs, fats, ingredients, instructions
    }
}

struct MealSuggestionCardView: View {
    let suggestion: MealSuggestion?
    var onGenerate: () -> Void
    var onTap: () -> Void
    var onPrefs: () -> Void
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Maia's Suggestions")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Button(action: onPrefs) {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(isLoading)
                
                Button(action: onGenerate) {
                    Image(systemName: "sparkles")
                }
                .disabled(isLoading)
            }
            .tint(.brandPrimary)

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
                        
                        Text("Est: \(String(format: "%.0f", suggestion.calories)) cal, P:\(String(format: "%.0f", suggestion.protein))g, C:\(String(format: "%.0f", suggestion.carbs))g, F:\(String(format: "%.0f", suggestion.fats))g")
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        
                        Text("Tap to see recipe...")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Tap the sparkles ✨ to get a meal idea that fits your remaining goals for today.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(minHeight: 60)
                }
            }
            .buttonStyle(.plain)
        }
        .asCard()
    }
}
