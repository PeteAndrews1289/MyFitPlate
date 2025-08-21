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
                let nutrition = recipe.nutritionPerServing
                if nutrition.calories > 0 {
                    nutrientRow(label: "Calories", value: String(format: "%.0f kcal", nutrition.calories))
                    nutrientRow(label: "Protein", value: String(format: "%.1f g", nutrition.protein))
                    nutrientRow(label: "Carbs", value: String(format: "%.1f g", nutrition.carbs))
                    nutrientRow(label: "Fats", value: String(format: "%.1f g", nutrition.fats))
                    
                    DisclosureGroup("Full Breakdown") {
                        nutrientRow(label: "Saturated Fat", value: nutrition.saturatedFat, unit: "g")
                        nutrientRow(label: "Polyunsaturated Fat", value: nutrition.polyunsaturatedFat, unit: "g")
                        nutrientRow(label: "Monounsaturated Fat", value: nutrition.monounsaturatedFat, unit: "g")
                        nutrientRow(label: "Fiber", value: nutrition.fiber, unit: "g")
                        nutrientRow(label: "Calcium", value: nutrition.calcium, unit: "mg", specifier: "%.0f")
                        nutrientRow(label: "Iron", value: nutrition.iron, unit: "mg")
                        nutrientRow(label: "Potassium", value: nutrition.potassium, unit: "mg", specifier: "%.0f")
                        nutrientRow(label: "Sodium", value: nutrition.sodium, unit: "mg", specifier: "%.0f")
                        nutrientRow(label: "Vitamin A", value: nutrition.vitaminA, unit: "mcg", specifier: "%.0f")
                        nutrientRow(label: "Vitamin C", value: nutrition.vitaminC, unit: "mg", specifier: "%.0f")
                        nutrientRow(label: "Vitamin D", value: nutrition.vitaminD, unit: "mcg", specifier: "%.0f")
                        nutrientRow(label: "Vitamin B12", value: nutrition.vitaminB12, unit: "mcg")
                        nutrientRow(label: "Folate", value: nutrition.folate, unit: "mcg", specifier: "%.0f")
                    }
                } else {
                    Text("Nutritional information has not been calculated. Match all ingredients to see full details.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            
            Section(header: Text("Ingredients")) {
                ForEach(recipe.ingredients) { ingredient in
                    Text(ingredient.foodName)
                        .appFont(size: 15)
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
                        .appFont(size: 15)
                    }
                } else {
                    Text("No instructions available.")
                        .foregroundColor(Color(UIColor.secondaryLabel))
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
            Text(value).foregroundColor(Color(UIColor.secondaryLabel))
        }
        .appFont(size: 15)
    }
    
    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String, specifier: String = "%.1f") -> some View {
         if let unwrappedValue = value, unwrappedValue > 0.001 || (specifier == "%.0f" && unwrappedValue >= 0.5) {
              HStack { Text(label); Spacer(); Text("\(unwrappedValue, specifier: specifier) \(unit)").foregroundColor(Color(UIColor.secondaryLabel)) }
              .appFont(size: 15)
         } else {
              EmptyView()
         }
    }
}
