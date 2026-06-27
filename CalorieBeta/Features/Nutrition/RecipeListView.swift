import SwiftUI
import FirebaseAuth

struct RecipeListView: View {
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss
    
    @State private var showingCreateRecipeSheet = false
    @State private var searchText = ""

    private var filteredRecipes: [Recipe] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recipeService.userRecipes }
        return recipeService.userRecipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(trimmed) ||
            recipe.ingredients.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                if recipeService.isLoading && recipeService.userRecipes.isEmpty {
                    RecipeListLoadingState()
                } else if recipeService.userRecipes.isEmpty {
                    RecipeListEmptyState {
                        showingCreateRecipeSheet = true
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            RecipeLibrarySummaryCard(
                                recipes: recipeService.userRecipes,
                                onCreate: { showingCreateRecipeSheet = true }
                            )

                            RecipeSearchField(searchText: $searchText)

                            if filteredRecipes.isEmpty {
                                RecipeListNoMatchesState(searchText: searchText)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(filteredRecipes) { recipe in
                                        RecipeCardRow(
                                            recipe: recipe,
                                            onDelete: { deleteRecipe(recipe) }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
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
    
    private func deleteRecipe(_ recipe: Recipe) {
        Task {
            await recipeService.deleteRecipe(recipe: recipe)
        }
        HapticManager.instance.feedback(.light)
    }
}

private struct RecipeLibrarySummaryCard: View {
    let recipes: [Recipe]
    let onCreate: () -> Void

    private var averageCalories: Double {
        guard !recipes.isEmpty else { return 0 }
        return recipes.reduce(0) { $0 + $1.nutrition.calories } / Double(recipes.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recipe Library")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Saved meals ready to log or reuse.")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.brandPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create recipe")
            }

            HStack(spacing: 10) {
                RecipeLibraryMetric(title: "Recipes", value: "\(recipes.count)", color: .brandPrimary)
                RecipeLibraryMetric(title: "Avg Calories", value: "\(Int(averageCalories.rounded()))", color: .orange)
            }
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RecipeLibraryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 22, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct RecipeSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.brandPrimary)

            TextField("Search recipes or ingredients...", text: $searchText)
                .textInputAutocapitalization(.words)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(size: 18, weight: .semibold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear recipe search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct RecipeCardRow: View {
    let recipe: Recipe
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                HStack(spacing: 12) {
                    Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                        .appFont(size: 28)
                        .frame(width: 50, height: 50)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.name)
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        Text("\(recipe.ingredients.count) ingredients")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))

                        Text("Cal \(Int(recipe.nutrition.calories.rounded()))  P \(Int(recipe.nutrition.protein.rounded()))g  C \(Int(recipe.nutrition.carbs.rounded()))g  F \(Int(recipe.nutrition.fats.rounded()))g")
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(recipe.name)")
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecipeListLoadingState: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Loading recipes")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }
}

private struct RecipeListEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .appFont(size: 40, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 76, height: 76)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 5) {
                Text("No saved recipes yet")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Create one with Maia or build it manually from foods you already log.")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Create Recipe", action: onCreate)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }
}

private struct RecipeListNoMatchesState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 22, weight: .semibold)
                .foregroundColor(.brandPrimary)
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No matching recipes")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
