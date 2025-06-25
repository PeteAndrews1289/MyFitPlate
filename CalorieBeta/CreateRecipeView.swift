import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - CreateRecipeView Main View
struct CreateRecipeView: View {
    @ObservedObject var recipeService: RecipeService
    var recipeToEdit: UserRecipe?
    @Environment(\.dismiss) var dismiss

    @State private var recipe: UserRecipe
    @State private var isSaving = false
    @State private var saveError: String? = nil

    // State for managing the ingredient matching flow
    @State private var ingredientToMatch: RecipeIngredient? = nil
    @State private var showingFoodSearchForMatch = false
    @State private var foodItemToAddAsIngredient: FoodItem? = nil
    @State private var showingAddIngredientDetail = false
    
    init(recipeService: RecipeService, recipeToEdit: UserRecipe? = nil) {
        self.recipeService = recipeService
        self.recipeToEdit = recipeToEdit
        if let existingRecipe = recipeToEdit {
            _recipe = State(initialValue: existingRecipe)
        } else {
            _recipe = State(initialValue: UserRecipe(userID: Auth.auth().currentUser?.uid ?? "", name: ""))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                recipeDetailsSection
                ingredientsSection
                instructionsSection
                nutritionSection

                if let error = saveError {
                    Text("Error: \(error)").foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle(recipeToEdit == nil ? "Create Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecipe() }
                    .disabled(recipe.name.isEmpty || recipe.ingredients.isEmpty || isSaving)
                }
            }
            .onAppear {
                print("\n--- CreateRecipeView: Appeared ---")
                print("Recipe being edited: \(recipeToEdit?.name ?? "A New Recipe")")
                print("Initial state of recipe in view:")
                dump(recipe)
            }
            .sheet(isPresented: $showingFoodSearchForMatch) {
                let initialQuery = ingredientToMatch?.originalImportedString ?? ingredientToMatch?.foodName
                ingredientSearchSheet(initialQuery: initialQuery)
            }
            .sheet(isPresented: $showingAddIngredientDetail, onDismiss: { foodItemToAddAsIngredient = nil } ) {
                if let foodItem = foodItemToAddAsIngredient {
                    AddIngredientDetailView(
                        foodItem: foodItem,
                        originalIngredientString: ingredientToMatch?.originalImportedString ?? foodItem.name,
                        onAdd: { newOrMatchedIngredient in
                            if let ingredientToMatchID = ingredientToMatch?.id,
                               let index = recipe.ingredients.firstIndex(where: { $0.id == ingredientToMatchID }) {
                                recipe.ingredients[index] = newOrMatchedIngredient
                            } else {
                                recipe.ingredients.append(newOrMatchedIngredient)
                            }
                            recipe.calculateTotals()
                        }
                    )
                }
            }
        }
    }

    // MARK: - View Sections
    
    private var recipeDetailsSection: some View {
        Section("Recipe Details") {
            TextField("Recipe Name", text: $recipe.name)
            HStack {
                Text("Makes")
                TextField("Number", value: $recipe.totalServings, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: recipe.totalServings) { _ in recipe.calculateTotals() }
                Spacer()
                TextField("Serving Size Desc (e.g., 'bowl')", text: $recipe.servingSizeDescription)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
    
    private var ingredientsSection: some View {
        Section(header: Text("Ingredients (\(recipe.ingredients.count))")) {
            ForEach($recipe.ingredients) { $ingredient in
                IngredientRowView(ingredient: $ingredient) {
                    self.ingredientToMatch = ingredient
                    self.showingFoodSearchForMatch = true
                }
            }
            .onDelete(perform: deleteIngredient)
            
            Button {
                self.ingredientToMatch = nil
                self.showingFoodSearchForMatch = true
            } label: {
                Label("Add Ingredient", systemImage: "plus")
            }
        }
    }
    
    private var instructionsSection: some View {
        Section("Instructions") {
            if let instructions = recipe.instructions, !instructions.isEmpty {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top) {
                        Text("\(index + 1).")
                            .bold()
                        Text(instruction)
                    }
                }
            } else {
                Text("No instructions were imported.")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var nutritionSection: some View {
        Section("Nutrition Per Serving") {
            let allMatched = !recipe.ingredients.contains { $0.foodId == nil }
            
            if !allMatched && !recipe.ingredients.isEmpty {
                Text("Tap on orange ingredients to match them with a food item and calculate nutrition.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            nutrientRow(label: "Calories", value: String(format: "%.0f kcal", recipe.nutritionPerServing.calories))
            nutrientRow(label: "Protein", value: String(format: "%.1f g", recipe.nutritionPerServing.protein))
            nutrientRow(label: "Carbs", value: String(format: "%.1f g", recipe.nutritionPerServing.carbs))
            nutrientRow(label: "Fats", value: String(format: "%.1f g", recipe.nutritionPerServing.fats))
        }
    }
    
    private func ingredientSearchSheet(initialQuery: String?) -> some View {
        NavigationView {
            FoodSearchViewForIngredients(initialQuery: initialQuery) { selectedFoodItem in
                self.foodItemToAddAsIngredient = selectedFoodItem
                self.showingFoodSearchForMatch = false
                
                if self.ingredientToMatch == nil {
                    self.ingredientToMatch = RecipeIngredient(foodName: selectedFoodItem.name, quantity: 1, selectedServingDescription: "", calories: 0, protein: 0, carbs: 0, fats: 0)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showingAddIngredientDetail = true
                }
            }
            .navigationTitle("Search Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingFoodSearchForMatch = false }
                }
            }
        }
    }
    
    // MARK: - Helper Methods & Actions
    
    private func deleteIngredient(at offsets: IndexSet) {
        recipe.ingredients.remove(atOffsets: offsets)
        recipe.calculateTotals()
    }
    
    private func saveRecipe() {
        isSaving = true
        saveError = nil
        if let userID = Auth.auth().currentUser?.uid {
            recipe.userID = userID
            if recipeToEdit == nil { recipe.id = nil }
            recipeService.saveRecipe(recipe) { result in
                isSaving = false
                switch result {
                case .success: dismiss()
                case .failure(let error): saveError = error.localizedDescription
                }
            }
        } else {
            saveError = "User not logged in."
            isSaving = false
        }
    }
    
    @ViewBuilder private func nutrientRow(label: String, value: String, hideIfZero: Bool = false) -> some View {
        let numericPart = value.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
        if !hideIfZero || (Double(numericPart) ?? 0) > 0.01 {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value).font(.callout).foregroundColor(.secondary)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - IngredientRowView Sub-view
fileprivate struct IngredientRowView: View {
    @Binding var ingredient: RecipeIngredient
    var onTap: () -> Void

    private var isPlaceholder: Bool {
        ingredient.foodId == nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading) {
                    Text(ingredient.foodName)
                        .font(.headline)
                        .foregroundColor(isPlaceholder ? .orange : .primary)
                    
                    if isPlaceholder {
                        Text("Tap to match with a food item")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("\(ingredient.quantity, specifier: "%g") x \(ingredient.selectedServingDescription ?? "") (\(ingredient.calories, specifier: "%.0f") kcal)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - FoodSearchViewForIngredients Sub-view
fileprivate struct FoodSearchViewForIngredients: View {
    var initialQuery: String?
    var onSelect: (FoodItem) -> Void
    @State private var searchQuery = ""
    @State private var searchResults: [FoodItem] = []
    @State private var isLoading = false
    @State private var debounceTimer: Timer?
    @State private var error: ErrorAlert? = nil
    private let foodAPIService = FatSecretFoodAPIService()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search food items...", text: $searchQuery)
                    .padding(10).background(Color(.systemGray6)).cornerRadius(8)
                    .onChange(of: searchQuery) { newValue in handleSearchQueryChange(newValue) }
                    .submitLabel(.search).onSubmit { performSearch() }
                Button(action: performSearch) { Image(systemName: "magnifyingglass").foregroundColor(.white).padding(10).background(Color.accentColor).cornerRadius(8) }
            }.padding()

            List {
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(searchResults) { foodItem in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(foodItem.name).font(.subheadline)
                            Text(foodItem.servingSize)
                                .font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(foodItem)
                    }
                }
            }
            .listStyle(.plain)
            .alert(item: $error) { errorAlert in Alert(title: Text("Error"), message: Text(errorAlert.message), dismissButton: .default(Text("OK"))) }
        }
        .onAppear {
            if let query = initialQuery {
                let parsed = IngredientParser.parse(query)
                searchQuery = parsed.name
                performSearch()
            }
        }
        .onDisappear { debounceTimer?.invalidate() }
    }

    private func handleSearchQueryChange(_ newValue: String) { debounceTimer?.invalidate(); let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { searchResults = []; isLoading = false; return }; debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in self.performSearch() } }
    private func performSearch() {
        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchResults = []; isLoading = false; return }
        isLoading = true
        foodAPIService.fetchFoodByQuery(query: query) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.handleSearchResults(result)
            }
        }
    }
    private func handleSearchResults(_ result: Result<[FoodItem], Error>) { switch result { case .success(let i): searchResults = i; case .failure(let e): searchResults = []; self.error = ErrorAlert(message: "Search failed: \(e.localizedDescription)") } }
}

// MARK: - AddIngredientDetailView Sub-view
fileprivate struct AddIngredientDetailView: View {
    let foodItem: FoodItem
    let originalIngredientString: String
    let onAdd: (RecipeIngredient) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var availableServings: [ServingSizeOption] = []
    @State private var selectedServingID: UUID? = nil
    @State private var quantity: String = "1"
    @State private var isLoadingDetails: Bool = false
    @State private var errorLoading: String? = nil

    private let foodAPIService = FatSecretFoodAPIService()

     private var selectedServingOption: ServingSizeOption? {
         guard let selectedID = selectedServingID else { return nil }
         return availableServings.first { $0.id == selectedID }
     }

     private var addButtonEnabled: Bool {
          selectedServingOption != nil && (Double(quantity) ?? 0) > 0
      }

    var body: some View {
         NavigationView {
             VStack {
                 if isLoadingDetails {
                     ProgressView("Loading serving sizes...")
                 } else if let error = errorLoading {
                     Text("Error: \(error)").foregroundColor(.red).padding()
                 } else if availableServings.isEmpty {
                     Text("No specific serving sizes found for this item. Cannot add.").padding()
                 } else {
                     Form {
                         Section("Ingredient") {
                             Text(foodItem.name).font(.headline)
                         }
                         Section("Serving Used in Recipe") {
                             HStack {
                                 Text("Quantity")
                                 TextField("e.g., 1.5", text: $quantity)
                                     .keyboardType(.decimalPad)
                                     .multilineTextAlignment(.trailing)
                             }
                             Picker("Serving Size", selection: $selectedServingID) {
                                 ForEach(availableServings) { option in
                                     Text(option.description).tag(option.id as UUID?)
                                 }
                             }
                             .pickerStyle(.menu)
                         }
                     }
                 }
                 Spacer()
             }
             .navigationTitle("Add Ingredient")
             .navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") { dismiss() }
                 }
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Add") { addIngredientAction() }
                     .disabled(!addButtonEnabled || availableServings.isEmpty)
                 }
             }
             .onAppear(perform: setupView)
         }
    }

    private func setupView() {
        let parsed = IngredientParser.parse(originalIngredientString)
        self.quantity = String(format: "%g", parsed.quantity)
        fetchServingDetails(preferredUnit: parsed.unit)
    }

    private func fetchServingDetails(preferredUnit: String) {
         isLoadingDetails = true
         errorLoading = nil
         foodAPIService.fetchFoodDetails(foodId: foodItem.id) { result in
             DispatchQueue.main.async {
                 isLoadingDetails = false
                 switch result {
                 case .success(let (_, servings)):
                     self.availableServings = servings
                     if let bestMatch = servings.first(where: { $0.description.lowercased().contains(preferredUnit) }) {
                         self.selectedServingID = bestMatch.id
                     } else if let firstServing = servings.first {
                         self.selectedServingID = firstServing.id
                     } else {
                         errorLoading = "No serving sizes found."
                     }
                 case .failure(let error):
                     errorLoading = error.localizedDescription
                 }
             }
         }
     }

     private func addIngredientAction() {
         guard let selectedOption = selectedServingOption,
               let quantityValue = Double(quantity), quantityValue > 0 else {
             return
         }

         let factor = quantityValue
         let finalIngredient = RecipeIngredient(
             foodId: foodItem.id,
             foodName: foodItem.name,
             quantity: quantityValue,
             selectedServingDescription: selectedOption.description,
             selectedServingWeightGrams: selectedOption.servingWeightGrams,
             calories: selectedOption.calories * factor,
             protein: selectedOption.protein * factor,
             carbs: selectedOption.carbs * factor,
             fats: selectedOption.fats * factor,
             saturatedFat: selectedOption.saturatedFat.map { $0 * factor },
             polyunsaturatedFat: selectedOption.polyunsaturatedFat.map { $0 * factor },
             monounsaturatedFat: selectedOption.monounsaturatedFat.map { $0 * factor },
             fiber: selectedOption.fiber.map { $0 * factor },
             calcium: selectedOption.calcium.map { $0 * factor },
             iron: selectedOption.iron.map { $0 * factor },
             potassium: selectedOption.potassium.map { $0 * factor },
             sodium: selectedOption.sodium.map { $0 * factor },
             vitaminA: selectedOption.vitaminA.map { $0 * factor },
             vitaminC: selectedOption.vitaminC.map { $0 * factor },
             vitaminD: selectedOption.vitaminD.map { $0 * factor },
             originalImportedString: originalIngredientString
         )
         onAdd(finalIngredient)
         dismiss()
     }
}
