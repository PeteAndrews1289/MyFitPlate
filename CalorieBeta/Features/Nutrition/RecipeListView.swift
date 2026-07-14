import SwiftUI

struct RecipeListView: View {
    @EnvironmentObject private var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreateRecipeSheet = false
    @State private var pendingDeletion: Recipe?
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
        NavigationStack {
            Group {
                if recipeService.isLoading && recipeService.userRecipes.isEmpty {
                    loadingState
                } else if recipeService.userRecipes.isEmpty {
                    emptyState
                } else {
                    recipeLibrary
                }
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("My Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes or ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateRecipeSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create recipe")
                }
            }
            .refreshable {
                await recipeService.fetchUserRecipes()
            }
            .task {
                await recipeService.fetchUserRecipes()
            }
        }
        .sheet(isPresented: $showingCreateRecipeSheet, onDismiss: refreshRecipes) {
            CreateRecipeView()
        }
        .alert("Delete recipe?", isPresented: deletionAlertIsPresented) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let recipe = pendingDeletion else { return }
                pendingDeletion = nil
                deleteRecipe(recipe)
            }
        } message: {
            Text("This removes \(pendingDeletion?.name ?? "the recipe") from your library. Foods already logged from it will not change.")
        }
    }

    private var recipeLibrary: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                RecipeLibrarySummary(recipes: recipeService.userRecipes)

                if filteredRecipes.isEmpty {
                    noMatchesState
                } else {
                    savedRecipesSection
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("recipe_library")
    }

    private var savedRecipesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Saved Recipes",
                subtitle: searchText.isEmpty
                    ? "Open a recipe to review, plan, or log it."
                    : "\(filteredRecipes.count) result\(filteredRecipes.count == 1 ? "" : "s")"
            )

            LazyVStack(spacing: 0) {
                ForEach(Array(filteredRecipes.enumerated()), id: \.element.id) { index, recipe in
                    RecipeLibraryRow(
                        recipe: recipe,
                        onDelete: { pendingDeletion = recipe }
                    )

                    if index < filteredRecipes.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
            .accessibilityIdentifier("recipe_library_list")
        }
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)
            Text("Loading Recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "book.closed")
                .appTextRole(.screenTitle)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))

            VStack(spacing: 4) {
                Text("No Saved Recipes")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                Text("Generate one with Maia, import a recipe, or build one from foods you already log.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingCreateRecipeSheet = true
            } label: {
                Label("Create Recipe", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    private var noMatchesState: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "magnifyingglass")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
            Text("No Matching Recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
            Text("Try another recipe name or ingredient.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func refreshRecipes() {
        Task { await recipeService.fetchUserRecipes() }
    }

    private func deleteRecipe(_ recipe: Recipe) {
        Task { await recipeService.deleteRecipe(recipe: recipe) }
        HapticManager.instance.feedback(.light)
    }
}

private struct RecipeLibrarySummary: View {
    let recipes: [Recipe]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var averageCalories: Double {
        guard !recipes.isEmpty else { return 0 }
        return recipes.reduce(0) { $0 + $1.nutrition.calories } / Double(recipes.count)
    }

    private var averageIngredientCount: Double {
        guard !recipes.isEmpty else { return 0 }
        return Double(recipes.reduce(0) { $0 + $1.ingredients.count }) / Double(recipes.count)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    RecipeLibraryAccessibilityMetric(
                        identifier: "recipe_summary_saved",
                        label: "Saved",
                        spokenLabel: "Saved recipes",
                        value: recipes.count.formatted(),
                        accent: AppPalette.brand
                    )
                    Divider()
                    RecipeLibraryAccessibilityMetric(
                        identifier: "recipe_summary_ingredients",
                        label: "Avg Ingredients",
                        spokenLabel: "Average ingredients",
                        value: Int(averageIngredientCount.rounded()).formatted(),
                        accent: .blue
                    )
                    Divider()
                    RecipeLibraryAccessibilityMetric(
                        identifier: "recipe_summary_calories",
                        label: "Avg Calories",
                        spokenLabel: "Average calories",
                        value: "\(Int(averageCalories.rounded()).formatted()) cal",
                        accent: .orange
                    )
                }
            } else {
                AppMetricStrip(items: [
                    AppMetricItem(label: "Saved", value: recipes.count.formatted()),
                    AppMetricItem(
                        label: "Avg Ingredients",
                        value: Int(averageIngredientCount.rounded()).formatted(),
                        accent: .blue
                    ),
                    AppMetricItem(
                        label: "Avg Calories",
                        value: "\(Int(averageCalories.rounded()).formatted()) cal",
                        accent: .orange
                    )
                ])
            }
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_library_summary")
    }
}

private struct RecipeLibraryAccessibilityMetric: View {
    let identifier: String
    let label: String
    let spokenLabel: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(label)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }

            Text(value)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenLabel), \(value)")
        .accessibilityIdentifier(identifier)
    }
}

private struct RecipeLibraryRow: View {
    let recipe: Recipe
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            recipeGlyph

            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metadata

                    Text(nutritionSummary)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens recipe details")

            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Recipe", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Actions for \(recipe.name)")
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityIdentifier("recipe_row_\(recipe.id ?? recipe.name)")
    }

    @ViewBuilder
    private var recipeGlyph: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "fork.knife")
                .appTextRole(.control)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(recipe.ingredients.count.formatted()) ingredients")
                Text("\(recipe.instructions.count.formatted()) steps")
            }
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
        } else {
            Text("\(recipe.ingredients.count.formatted()) ingredients · \(recipe.instructions.count.formatted()) steps")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private var nutritionSummary: String {
        let calories = Int(recipe.nutrition.calories.rounded()).formatted()
        let protein = Int(recipe.nutrition.protein.rounded()).formatted()
        return "\(calories) cal · \(protein) g protein"
    }
}
