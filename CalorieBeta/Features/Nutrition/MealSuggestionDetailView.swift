import SwiftUI

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
                        Text("Estimate: \(formatted(suggestion.calories)) cal, P \(formatted(suggestion.protein)) g, C \(formatted(suggestion.carbs)) g, F \(formatted(suggestion.fats)) g")
                            .appFont(size: 15)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .appFont(size: 20, weight: .semibold)
                        ForEach(suggestion.ingredients, id: \.self) { ingredient in
                            Text("- \(ingredient)")
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
                        Label("Log this meal", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top)

                }
                .padding()
            }
            .navigationTitle("Meal suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }
}
