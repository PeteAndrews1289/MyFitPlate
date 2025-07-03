import SwiftUI

struct AddMealToPlanView: View {
    @EnvironmentObject var recipeService: RecipeService
    @Environment(\.dismiss) var dismiss
    
    let mealType: String
    let onAdd: (PlannedMeal) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                NavigationLink(destination: CreateRecipeView(recipeService: recipeService)) {
                    Text("Create New Recipe")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.brandSecondary)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()

                if recipeService.userRecipes.isEmpty {
                    Text("No recipes found. Create one to add it to your plan.")
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding()
                }
                
                List(recipeService.userRecipes) { recipe in
                    Button(action: {
                        let plannedMeal = PlannedMeal(
                            id: UUID().uuidString,
                            mealType: mealType,
                            recipeID: recipe.id,
                            foodItem: FoodItem(id: recipe.id ?? UUID().uuidString, name: recipe.name, calories: recipe.nutritionPerServing.calories, protein: recipe.nutritionPerServing.protein, carbs: recipe.nutritionPerServing.carbs, fats: recipe.nutritionPerServing.fats, servingSize: recipe.servingSizeDescription, servingWeight: 0)
                        )
                        onAdd(plannedMeal)
                    }) {
                        VStack(alignment: .leading) {
                            Text(recipe.name)
                                .appFont(size: 17, weight: .semibold)
                            Text("\(recipe.nutritionPerServing.calories, specifier: "%.0f") cal per serving")
                                .appFont(size: 15)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                    }
                }
            }
            .navigationTitle("Add to \(mealType)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if recipeService.userRecipes.isEmpty {
                    recipeService.fetchUserRecipes()
                }
            }
        }
    }
}
