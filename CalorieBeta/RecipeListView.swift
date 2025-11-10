import SwiftUI
import FirebaseAuth

struct RecipeListView: View {
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss
    
    @State private var showingCreateRecipeSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                if recipeService.isLoading && recipeService.userRecipes.isEmpty {
                    ProgressView("Loading Recipes...")
                } else if recipeService.userRecipes.isEmpty {
                    VStack {
                        Text("No saved recipes yet.")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Tap the '+' button to create your first recipe.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                } else {
                    List {
                        ForEach(recipeService.userRecipes) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                RecipeRow(recipe: recipe)
                            }
                        }
                        .onDelete(perform: deleteRecipe)
                    }
                }
            }
            .navigationTitle("My Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateRecipeSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                Task {
                    await recipeService.fetchUserRecipes()
                }
            }
            .sheet(isPresented: $showingCreateRecipeSheet, onDismiss: {
                Task { await recipeService.fetchUserRecipes() }
            }) {
                 CreateRecipeView()
            }
        }
    }
    
    private func deleteRecipe(at offsets: IndexSet) {
        let recipesToDelete = offsets.map { recipeService.userRecipes[$0] }
        Task {
            for recipe in recipesToDelete {
                await recipeService.deleteRecipe(recipe: recipe)
            }
        }
    }
}

fileprivate struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(recipe.name).appFont(size: 17, weight: .semibold)
            Text("Cals: \(recipe.nutrition.calories, specifier: "%.0f") • P: \(recipe.nutrition.protein, specifier: "%.0f")g • C: \(recipe.nutrition.carbs, specifier: "%.0f")g • F: \(recipe.nutrition.fats, specifier: "%.0f")g")
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .padding(.vertical, 5)
    }
}
