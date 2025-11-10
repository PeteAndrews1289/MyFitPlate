import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss
    @State private var showingAddToLogSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(recipe.name)
                    .font(.largeTitle.bold())
                    .padding(.bottom, 5)

                nutritionSection

                ingredientsSection

                instructionsSection
            }
            .padding()
        }
        .navigationTitle("Recipe Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add to Log") {
                    showingAddToLogSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddToLogSheet) {
            AddFoodView(
                isPresented: $showingAddToLogSheet,
                foodItem: recipeService.recipeToFoodItem(recipe: recipe),
                onFoodLogged: logRecipe
            )
        }
    }
    
    private func logRecipe(foodItem: FoodItem, mealType: String) {
        Task {
            await dailyLogService.logFoodItem(foodItem, mealType: mealType)
            dismiss()
        }
    }
    
    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition per Serving")
                .font(.title2.bold())
            
            let nutrition = recipe.nutrition
            HStack {
                NutritionPill(name: "Calories", value: nutrition.calories, unit: "", color: .red)
                NutritionPill(name: "Protein", value: nutrition.protein, unit: "g", color: .accentProtein)
                NutritionPill(name: "Carbs", value: nutrition.carbs, unit: "g", color: .accentCarbs)
                NutritionPill(name: "Fats", value: nutrition.fats, unit: "g", color: .accentFats)
            }
            
            DisclosureGroup("Full Nutritional Details") {
                VStack(alignment: .leading, spacing: 8) {
                    nutrientRow(label: "Saturated Fat", value: nutrition.saturatedFat)
                    nutrientRow(label: "Polyunsaturated Fat", value: nutrition.polyunsaturatedFat)
                    nutrientRow(label: "Monounsaturated Fat", value: nutrition.monounsaturatedFat)
                    nutrientRow(label: "Fiber", value: nutrition.fiber)
                    nutrientRow(label: "Calcium", value: nutrition.calcium, unit: "mg")
                    nutrientRow(label: "Iron", value: nutrition.iron, unit: "mg")
                    nutrientRow(label: "Potassium", value: nutrition.potassium, unit: "mg")
                    nutrientRow(label: "Sodium", value: nutrition.sodium, unit: "mg")
                    nutrientRow(label: "Vitamin A", value: nutrition.vitaminA, unit: "mcg")
                    nutrientRow(label: "Vitamin C", value: nutrition.vitaminC, unit: "mg")
                    nutrientRow(label: "Vitamin D", value: nutrition.vitaminD, unit: "mcg")
                    nutrientRow(label: "Vitamin B12", value: nutrition.vitaminB12, unit: "mcg")
                    nutrientRow(label: "Folate", value: nutrition.folate, unit: "mcg")
                }
                .padding(.top)
            }
        }
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(.title2.bold())
            ForEach(recipe.ingredients, id: \.self) { ingredient in
                Text("• \(ingredient)")
            }
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instructions")
                .font(.title2.bold())
            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top) {
                    Text("\(index + 1).")
                        .bold()
                    Text(instruction)
                }
            }
        }
    }
    
    @ViewBuilder
    private func nutrientRow(label: String, value: Double?, unit: String = "g") -> some View {
        if let value = value, value > 0 {
            HStack {
                Text(label)
                Spacer()
                Text("\(String(format: "%.1f", value)) \(unit)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct NutritionPill: View {
    let name: String
    let value: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(name)
                .font(.caption)
            Text("\(String(format: "%.0f", value))\(unit)")
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .foregroundColor(color)
    }
}
