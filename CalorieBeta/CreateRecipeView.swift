import SwiftUI
import FirebaseAuth

struct CreateRecipeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @State private var recipeName = ""
    @State private var ingredients: [FoodItem] = []
    @State private var instructions = ""
    @State private var showingFoodSearch = false
    @State private var creationMode: CreationMode = .ai
    @State private var aiDescription = ""
    @State private var isLoading = false

    enum CreationMode: String, CaseIterable, Identifiable {
        case ai = "AI"
        case manual = "Manual"
        var id: Self { self }
    }
    
    private var totalNutrition: Nutrition {
        ingredients.reduce(Nutrition.zero) { partialResult, item in
            return Nutrition(
                calories: partialResult.calories + item.calories,
                protein: partialResult.protein + item.protein,
                carbs: partialResult.carbs + item.carbs,
                fats: partialResult.fats + item.fats,
                saturatedFat: (partialResult.saturatedFat ?? 0) + (item.saturatedFat ?? 0),
                polyunsaturatedFat: (partialResult.polyunsaturatedFat ?? 0) + (item.polyunsaturatedFat ?? 0),
                monounsaturatedFat: (partialResult.monounsaturatedFat ?? 0) + (item.monounsaturatedFat ?? 0),
                fiber: (partialResult.fiber ?? 0) + (item.fiber ?? 0),
                calcium: (partialResult.calcium ?? 0) + (item.calcium ?? 0),
                iron: (partialResult.iron ?? 0) + (item.iron ?? 0),
                potassium: (partialResult.potassium ?? 0) + (item.potassium ?? 0),
                sodium: (partialResult.sodium ?? 0) + (item.sodium ?? 0),
                vitaminA: (partialResult.vitaminA ?? 0) + (item.vitaminA ?? 0),
                vitaminC: (partialResult.vitaminC ?? 0) + (item.vitaminC ?? 0),
                vitaminD: (partialResult.vitaminD ?? 0) + (item.vitaminD ?? 0),
                vitaminB12: (partialResult.vitaminB12 ?? 0) + (item.vitaminB12 ?? 0),
                folate: (partialResult.folate ?? 0) + (item.folate ?? 0)
            )
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Picker("Creation Mode", selection: $creationMode) {
                        ForEach(CreationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if creationMode == .ai {
                        aiSection
                    } else {
                        manualSection
                    }
                }
                .navigationTitle("Create Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Save", action: saveRecipe).disabled(isSaveDisabled) }
                }
                .sheet(isPresented: $showingFoodSearch) {
                    FoodSearchView(
                        dailyLog: $dailyLogService.currentDailyLog,
                        onFoodItemLogged: nil,
                        onFoodItemSelected: addIngredient,
                        searchContext: "recipe_ingredient"
                    )
                }
                
                if isLoading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView("Creating Recipe...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding().background(Color.black.opacity(0.8)).cornerRadius(10)
                }
            }
        }
    }

    private var aiSection: some View {
        Section(header: Text("Describe Your Recipe"), footer: Text("Describe the meal and the AI will generate the ingredients, instructions, and nutritional information for you.")) {
            TextEditor(text: $aiDescription)
                .frame(height: 200).padding(4).background(Color(.systemGray6)).cornerRadius(8)
        }
    }

    private var manualSection: some View {
        Group {
            Section(header: Text("Recipe Details")) {
                TextField("Recipe Name", text: $recipeName)
            }
            
            if !ingredients.isEmpty {
                Section(header: Text("Total Nutrition")) {
                    HStack {
                        Text("Calories").appFont(size: 14, weight: .semibold)
                        Spacer()
                        Text("\(totalNutrition.calories, specifier: "%.0f") kcal").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Macros (P/C/F)").appFont(size: 14, weight: .semibold)
                        Spacer()
                        Text("\(totalNutrition.protein, specifier: "%.0f")g / \(totalNutrition.carbs, specifier: "%.0f")g / \(totalNutrition.fats, specifier: "%.0f")g").foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Ingredients")) {
                ForEach(ingredients) { ingredient in
                    VStack(alignment: .leading) {
                        Text(ingredient.name).appFont(size: 16, weight: .medium)
                        Text("Cals: \(ingredient.calories, specifier: "%.0f"), P: \(ingredient.protein, specifier: "%.0f")g, C: \(ingredient.carbs, specifier: "%.0f")g, F: \(ingredient.fats, specifier: "%.0f")g")
                            .appFont(size: 12).foregroundColor(.secondary)
                    }
                }
                .onDelete(perform: removeIngredient)
                
                Button(action: { showingFoodSearch = true }) {
                    Label("Add Ingredient", systemImage: "plus")
                }
            }

            Section(header: Text("Instructions")) {
                TextEditor(text: $instructions)
                    .frame(height: 200)
            }
        }
    }

    private func addIngredient(foodItem: FoodItem) {
        ingredients.append(foodItem)
        showingFoodSearch = false
    }

    private func removeIngredient(at offsets: IndexSet) {
        ingredients.remove(atOffsets: offsets)
    }

    private var isSaveDisabled: Bool {
        if creationMode == .ai {
            return aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return recipeName.isEmpty || ingredients.isEmpty || instructions.isEmpty
        }
    }

    private func saveRecipe() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        Task {
            if creationMode == .ai {
                _ = await recipeService.createRecipeFromAI(description: aiDescription, userID: userID)
            } else {
                let ingredientNames = ingredients.map { $0.name }
                let instructionSteps = instructions.split(separator: "\n").map(String.init)
                let recipe = Recipe(name: recipeName, ingredients: ingredientNames, instructions: instructionSteps, nutrition: totalNutrition)
                try? await recipeService.saveRecipe(recipe, for: userID)
            }
            
            isLoading = false
            dismiss()
        }
    }
}
