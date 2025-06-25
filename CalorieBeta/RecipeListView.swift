import SwiftUI
import FirebaseAuth

struct RecipeListView: View {
    @StateObject private var recipeService = RecipeService()
    @State private var showingCreateRecipeSheet = false
    @State private var recipeToEdit: UserRecipe? = nil
    @State private var showingEditRecipeSheet = false
    @State private var showingImporterSheet = false

    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        // The NavigationView is crucial for NavigationLinks to work.
        NavigationView {
            List {
                if recipeService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if recipeService.userRecipes.isEmpty {
                     Text("No saved recipes yet.\nTap '+' to create one or the import icon to add from a URL.")
                         .multilineTextAlignment(.center)
                         .foregroundColor(.gray)
                         .frame(maxWidth: .infinity, alignment: .center)
                         .padding(.vertical, 40)
                } else {
                    ForEach(recipeService.userRecipes) { recipe in
                        // Each row is now a NavigationLink to the detail view
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            RecipeRow(
                                recipe: recipe,
                                recipeService: recipeService,
                                onEdit: {
                                    self.recipeToEdit = recipe
                                    self.showingEditRecipeSheet = true
                                }
                            )
                            .environmentObject(dailyLogService)
                        }
                    }
                    .onDelete(perform: deleteRecipe)
                }
            }
            .navigationTitle("My Recipes & Meals")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingImporterSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.down") // Import Icon
                            .imageScale(.large)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        self.recipeToEdit = nil
                        showingCreateRecipeSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill") // Add New Icon
                            .imageScale(.large)
                    }
                }
            }
            .onAppear {
                recipeService.fetchUserRecipes()
            }
            .sheet(isPresented: $showingCreateRecipeSheet) {
                 CreateRecipeView(recipeService: recipeService)
            }
            .sheet(isPresented: $showingImporterSheet) {
                // Present the importer view
                RecipeImporterView()
                    .environmentObject(recipeService)
            }
            .sheet(isPresented: $showingEditRecipeSheet) {
                if let recipeToEdit = recipeToEdit {
                    CreateRecipeView(recipeService: recipeService, recipeToEdit: recipeToEdit)
                }
            }
        }
    }

     private func deleteRecipe(at offsets: IndexSet) {
         offsets.forEach { index in
             guard index < recipeService.userRecipes.count else { return }
             let recipe = recipeService.userRecipes[index]
             recipeService.deleteRecipe(recipe) { error in
                 if let error = error {
                    print("Error deleting recipe: \(error.localizedDescription)")
                 }
             }
         }
     }
}

// MARK: - Sub-views for RecipeListView

fileprivate struct RecipeRow: View {
    let recipe: UserRecipe
    @ObservedObject var recipeService: RecipeService
    var onEdit: () -> Void
    @EnvironmentObject var dailyLogService: DailyLogService
    @State private var showingLogSheet = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recipe.name).font(.headline)
                Text("\(recipe.servingSizeDescription) - \(recipe.nutritionPerServing.calories, specifier: "%.0f") cal")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            // Edit button stops the navigation link from triggering
            Button(action: {
                onEdit()
            }) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.gray)
                    .imageScale(.large)
            }
            .buttonStyle(BorderlessButtonStyle())
            .padding(.trailing, 8)

            // Log button also stops navigation
            Button(action: {
                showingLogSheet = true
            }) {
                 Image(systemName: "plus.circle.fill")
                     .foregroundColor(.accentColor)
                     .imageScale(.large)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $showingLogSheet) {
            LogRecipeSheetView(recipe: recipe) { quantity in
                 logRecipe(quantity: quantity)
                 showingLogSheet = false
            }
        }
    }

    private func logRecipe(quantity: Double) {
        guard let userID = Auth.auth().currentUser?.uid, quantity > 0 else { return }
        
        let nutrition = recipe.nutritionPerServing
        let loggedItem = FoodItem(
            id: UUID().uuidString,
            name: recipe.name,
            calories: nutrition.calories * quantity,
            protein: nutrition.protein * quantity,
            carbs: nutrition.carbs * quantity,
            fats: nutrition.fats * quantity,
            servingSize: "\(String(format: "%g", quantity)) x \(recipe.servingSizeDescription)",
            servingWeight: 0,
            timestamp: Date()
        )
        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: loggedItem, source: "recipe")
    }
}

fileprivate struct LogRecipeSheetView: View {
    let recipe: UserRecipe
    let onLog: (Double) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var quantityString: String = "1"
    
    var body: some View {
         NavigationView {
             Form {
                 Section {
                     VStack(alignment: .center, spacing: 8) {
                         Text(recipe.name)
                             .font(.title2.bold())
                             .multilineTextAlignment(.center)
                         Text("Logging for \(recipe.servingSizeDescription)")
                             .font(.callout)
                             .foregroundColor(.gray)
                     }
                     .frame(maxWidth: .infinity)
                     .padding(.vertical, 10)
                 }
                 .listRowBackground(Color.clear)

                 Section(header: Text("Nutrition per Serving")) {
                     HStack { Text("Calories"); Spacer(); Text("\(recipe.nutritionPerServing.calories, specifier: "%.0f") kcal").foregroundColor(.secondary) }
                     HStack { Text("Protein"); Spacer(); Text("\(recipe.nutritionPerServing.protein, specifier: "%.1f") g").foregroundColor(.secondary) }
                     HStack { Text("Carbs"); Spacer(); Text("\(recipe.nutritionPerServing.carbs, specifier: "%.1f") g").foregroundColor(.secondary) }
                     HStack { Text("Fats"); Spacer(); Text("\(recipe.nutritionPerServing.fats, specifier: "%.1f") g").foregroundColor(.secondary) }
                 }

                 Section(header: Text("Log Recipe")) {
                     HStack {
                         Text("Number of Servings:")
                         Spacer()
                         TextField("Quantity", text: $quantityString)
                             .keyboardType(.decimalPad)
                             .frame(width: 80)
                             .textFieldStyle(RoundedBorderTextFieldStyle())
                             .multilineTextAlignment(.trailing)
                     }
                     Button("Log Recipe") {
                         if let quantity = Double(quantityString), quantity > 0 {
                             onLog(quantity)
                         }
                     }
                     .buttonStyle(.borderedProminent)
                     .disabled(Double(quantityString) == nil || (Double(quantityString) ?? 0) <= 0)
                     .frame(maxWidth: .infinity, alignment: .center)
                 }
             }
             .navigationTitle("Log Recipe").navigationBarTitleDisplayMode(.inline)
             .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
         }
    }
}
