import SwiftUI
import FirebaseAuth

struct MealSuggestionDetailView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    
    let suggestion: MealSuggestion
    var onLog: (MealSuggestion) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.mealName)
                            .appFont(size: 28, weight: .bold)
                        Text("Est: \(String(format: "%.0f", suggestion.calories)) cal, P:\(String(format: "%.0f", suggestion.protein))g, C:\(String(format: "%.0f", suggestion.carbs))g, F:\(String(format: "%.0f", suggestion.fats))g")
                            .appFont(size: 15)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .appFont(size: 20, weight: .semibold)
                        ForEach(suggestion.ingredients, id: \.self) { ingredient in
                            Text("• \(ingredient)")
                                .appFont(size: 16)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions")
                            .appFont(size: 20, weight: .semibold)
                        Text(suggestion.instructions)
                            .appFont(size: 16)
                    }
                    
                    Spacer()
                    
                    Button {
                        onLog(suggestion)
                        dismiss()
                    } label: {
                        Label("Log This Meal", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top)

                }
                .padding()
            }
            .navigationTitle("Meal Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}