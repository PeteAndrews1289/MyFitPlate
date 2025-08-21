import SwiftUI

struct CreateRecipeView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var recipeService: RecipeService
    @State private var recipe: UserRecipe
    
    @State private var ingredientText: String = ""
    @State private var newInstruction: String = ""
    @State private var showingIngredientSheet = false
    @State private var ingredientToEdit: Binding<RecipeIngredient>?
    
    private var isEditMode: Bool
    
    init(recipeService: RecipeService, recipeToEdit: UserRecipe? = nil) {
        self.recipeService = recipeService
        if let existingRecipe = recipeToEdit {
            _recipe = State(initialValue: existingRecipe)
            self.isEditMode = true
        } else {
            _recipe = State(initialValue: UserRecipe(userID: "", name: ""))
            self.isEditMode = false
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Recipe Details")) {
                    TextField("Recipe Name", text: $recipe.name)
                    
                    Stepper(value: $recipe.totalServings, in: 1...100, step: 1.0) {
                        Text("Servings: \(recipe.totalServings, specifier: "%.1f")")
                    }
                }

                Section(header: Text("Ingredients"), footer: Text("Add ingredients one per line. You can use natural language, e.g., '1 cup of flour' or '2 large eggs'.").appFont(size: 12)) {
                    TextEditor(text: $ingredientText)
                        .frame(height: 150)
                        .onChange(of: ingredientText) { _ in
                            parseIngredientsFromText()
                        }
                    
                    if !recipe.ingredients.isEmpty {
                        ForEach($recipe.ingredients) { $ingredient in
                            IngredientRowView(ingredient: $ingredient)
                                .onTapGesture {
                                    self.ingredientToEdit = $ingredient
                                    self.showingIngredientSheet = true
                                }
                        }
                        .onDelete(perform: deleteIngredient)
                    }
                }
                
                Section(header: Text("Instructions")) {
                    ForEach(Array(recipe.instructions?.enumerated() ?? [].enumerated()), id: \.offset) { index, instruction in
                        HStack {
                            Text("\(index + 1).")
                                .bold()
                            Text(instruction)
                        }
                    }
                    .onDelete(perform: deleteInstruction)
                    
                    HStack {
                        TextField("Add new step", text: $newInstruction, onCommit: addInstruction)
                        Button(action: addInstruction) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newInstruction.isEmpty)
                    }
                }
                
                Section(header: Text("Nutrition Per Serving")) {
                    if recipe.ingredients.contains(where: { $0.foodId == nil }) {
                        Text("Enter all ingredients to calculate nutrition.")
                            .appFont(size: 14)
                            .foregroundColor(.orange)
                    } else if recipe.ingredients.isEmpty {
                        Text("Add ingredients to see nutrition info.")
                            .appFont(size: 14)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Calories: \(recipe.nutritionPerServing.calories, specifier: "%.0f") kcal")
                            Text("Protein: \(recipe.nutritionPerServing.protein, specifier: "%.1f") g")
                            Text("Carbs: \(recipe.nutritionPerServing.carbs, specifier: "%.1f") g")
                            Text("Fats: \(recipe.nutritionPerServing.fats, specifier: "%.1f") g")
                        }
                        .appFont(size: 15)
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Recipe" : "Create Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        recipeService.saveRecipe(recipe) { result in
                            if case .success = result {
                                dismiss()
                            }
                        }
                    }
                    .disabled(recipe.name.isEmpty || recipe.ingredients.isEmpty)
                }
            }
            .sheet(isPresented: $showingIngredientSheet) {
                if let binding = ingredientToEdit {
                    FoodDetailView(
                        initialFoodItem: foodItem(from: binding.wrappedValue),
                        dailyLog: .constant(nil),
                        source: "recipe_ingredient_edit",
                        onLogUpdated: {},
                        onUpdate: { updatedFoodItem in
                            updateIngredient(from: updatedFoodItem, for: binding)
                            ingredientToEdit = nil
                        }
                    )
                }
            }
            .onAppear(perform: setupInitialIngredientText)
        }
    }

    private func setupInitialIngredientText() {
        ingredientText = recipe.ingredients.map { $0.originalImportedString ?? $0.foodName }.joined(separator: "\n")
    }

    private func parseIngredientsFromText() {
        let lines = ingredientText.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        let parsedIngredients = IngredientParser.parseMultiple(lines)
        
        recipe.ingredients = parsedIngredients.map { parsed in
            RecipeIngredient(
                foodName: parsed.name,
                quantity: parsed.quantity,
                selectedServingDescription: parsed.unit,
                calories: 0,
                protein: 0,
                carbs: 0,
                fats: 0,
                originalImportedString: parsed.originalString
            )
        }
    }

    private func deleteIngredient(at offsets: IndexSet) {
        recipe.ingredients.remove(atOffsets: offsets)
        setupInitialIngredientText()
    }
    
    private func addInstruction() {
        guard !newInstruction.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if recipe.instructions == nil {
            recipe.instructions = []
        }
        recipe.instructions?.append(newInstruction)
        newInstruction = ""
    }

    private func deleteInstruction(at offsets: IndexSet) {
        recipe.instructions?.remove(atOffsets: offsets)
    }

    private func foodItem(from ingredient: RecipeIngredient) -> FoodItem {
        return FoodItem(id: ingredient.foodId ?? UUID().uuidString, name: ingredient.foodName, calories: ingredient.calories, protein: ingredient.protein, carbs: ingredient.carbs, fats: ingredient.fats, saturatedFat: ingredient.saturatedFat, polyunsaturatedFat: ingredient.polyunsaturatedFat, monounsaturatedFat: ingredient.monounsaturatedFat, fiber: ingredient.fiber, servingSize: ingredient.selectedServingDescription ?? "1 serving", servingWeight: ingredient.selectedServingWeightGrams ?? 0, calcium: ingredient.calcium, iron: ingredient.iron, potassium: ingredient.potassium, sodium: ingredient.sodium, vitaminA: ingredient.vitaminA, vitaminC: ingredient.vitaminC, vitaminD: ingredient.vitaminD, vitaminB12: ingredient.vitaminB12, folate: ingredient.folate)
    }
    
    private func updateIngredient(from foodItem: FoodItem, for binding: Binding<RecipeIngredient>) {
        var updatedIngredient = binding.wrappedValue
        updatedIngredient.foodId = foodItem.id
        updatedIngredient.foodName = foodItem.name
        updatedIngredient.calories = foodItem.calories
        updatedIngredient.protein = foodItem.protein
        updatedIngredient.carbs = foodItem.carbs
        updatedIngredient.fats = foodItem.fats
        updatedIngredient.selectedServingDescription = foodItem.servingSize
        updatedIngredient.selectedServingWeightGrams = foodItem.servingWeight
        
        binding.wrappedValue = updatedIngredient
        recipe.calculateTotals()
    }
}
