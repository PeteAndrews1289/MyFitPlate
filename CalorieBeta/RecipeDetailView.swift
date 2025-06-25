import SwiftUI

struct RecipeDetailView: View {
    let recipe: UserRecipe

    var body: some View {
        Form {
            Section(header: Text("Summary")) {
                HStack {
                    Text("Servings")
                    Spacer()
                    Text("\(recipe.totalServings, specifier: "%g")")
                }
                HStack {
                    Text("Serving Size")
                    Spacer()
                    Text(recipe.servingSizeDescription)
                }
            }

            Section(header: Text("Nutrition Per Serving")) {
                if recipe.nutritionPerServing.calories > 0 {
                    nutrientRow(label: "Calories", value: String(format: "%.0f kcal", recipe.nutritionPerServing.calories))
                    nutrientRow(label: "Protein", value: String(format: "%.1f g", recipe.nutritionPerServing.protein))
                    nutrientRow(label: "Carbs", value: String(format: "%.1f g", recipe.nutritionPerServing.carbs))
                    nutrientRow(label: "Fats", value: String(format: "%.1f g", recipe.nutritionPerServing.fats))
                } else {
                    Text("Nutritional information has not been calculated. Match all ingredients to see full details.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Ingredients")) {
                ForEach(recipe.ingredients) { ingredient in
                    Text(ingredient.foodName)
                }
            }
            
            Section(header: Text("Instructions")) {
                if let instructions = recipe.instructions, !instructions.isEmpty {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .bold()
                            Text(instruction)
                        }
                    }
                } else {
                    Text("No instructions available.")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder private func nutrientRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
