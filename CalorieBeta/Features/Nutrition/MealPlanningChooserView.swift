import MyFitPlateCore
import SwiftUI

/// A selection surface only. Every choice still passes through the planner's
/// portion/date review; this view never logs food or changes a saved plan.
struct MealPlanningChooserView: View {
    let date: Date
    @Binding var mealType: String
    let recipes: [Recipe]
    let recipesLoading: Bool
    let isResolvingFood: Bool
    let message: String?
    let onFood: (FoodItem, Bool) -> Void
    let onRecipe: (Recipe) -> Void
    let onComposition: (SavedMealComposition) -> Void
    let libraryRefresh: UUID
    @EnvironmentObject private var dailyLogService: DailyLogService
    @StateObject private var foodSearch = FoodSearchViewModel()
    @State private var scope: Scope = .all
    @State private var compositions: [SavedMealComposition] = []
    @State private var compositionsLoading = true
    @State private var libraryError: String?
    private let owner = DIContainer.shared.authService.currentUserID

    private enum Scope: String, CaseIterable {
        case all = "All", foods = "Foods", recipes = "Recipes", meals = "Meals"
    }

    private var query: String { foodSearch.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingRecipes: [Recipe] {
        RecipeLibraryRules.filtered(recipes, query: query, filter: .all).filter(RecipeLibraryRules.isVisible)
    }
    private var matchingMeals: [SavedMealComposition] {
        compositions.filter { !$0.isArchived && (query.isEmpty || $0.name.localizedStandardContains(query)
            || $0.components.contains { $0.name.localizedStandardContains(query) }) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.group) {
                if let message {
                    Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("planner_recipe_review_required")
                }
                if isResolvingFood {
                    ProgressView("Getting serving details…").accessibilityIdentifier("planner_food_resolving")
                }
                if scope == .all || scope == .foods { foodChoices }
                if scope == .all || scope == .recipes { recipeChoices }
                if scope == .all || scope == .meals { mealChoices }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            .disabled(isResolvingFood)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
        .background(AppPalette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner_choice_list")
        .task {
            foodSearch.setup(dailyLogService: dailyLogService)
            foodSearch.selectedMeal = mealType
            foodSearch.fetchData()
        }
        .task(id: libraryRefresh) { await loadCompositions() }
        .onChange(of: mealType) { _, value in foodSearch.selectedMeal = value }
    }

    private var searchHeader: some View {
        VStack(spacing: AppSpacing.compact) {
            HStack(spacing: AppSpacing.compact) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("planner_choice_date")
                Spacer(minLength: 0)
                Picker("Meal", selection: $mealType) {
                    ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) }
                    if !MealPlanEditingRules.mealTypes.contains(mealType) { Text(mealType).tag(mealType) }
                }
                .pickerStyle(.menu).frame(minHeight: 44)
                .accessibilityIdentifier("planner_add_slot")
            }
            FoodSearchHeader(searchText: $foodSearch.searchText,
                placeholder: "Search foods, recipes or meals",
                onClear: { foodSearch.searchText = "" }, onSubmit: foodSearch.submitSearch)
            Picker("Search in", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("planner_choice_scope")
        }
        .disabled(isResolvingFood)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.bottom, AppSpacing.row)
        .background(AppPalette.canvas)
    }

    @ViewBuilder private var foodChoices: some View {
        if query.isEmpty {
            let foods = scope == .all ? Array(foodSearch.usualFoods.prefix(2)) : foodSearch.usualFoods
            foodSection(foods, title: "Saved and recent foods", hydrate: false)
            if scope == .all, foodSearch.usualFoods.count > 2 { scopeButton("See all foods", scope: .foods) }
            if foods.isEmpty && scope == .foods {
                chooserMessage("Find a food", detail: "Search by name or brand. Your saved and recent foods appear here.")
            }
        } else {
            let results = foodSearch.searchPresentation
            if scope == .all {
                let ranked = results.exactPersonalMatches.map { ($0, false) }
                    + results.brandedMatches.map { ($0, true) }
                    + results.otherPersonalMatches.map { ($0, false) }
                    + results.otherRemoteMatches.map { ($0, true) }
                    + foodSearch.supplementResults.map { ($0, true) }
                if !ranked.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Foods").appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(Array(ranked.prefix(2).enumerated()), id: \.offset) { _, choice in
                            FoodPickerRow(food: choice.0, isQuickLogged: false, onSelect: { onFood($0, choice.1) },
                                onQuickLog: nil, onDelete: nil, source: choice.1 ? "search_result" : "recent_tap")
                            Divider()
                        }
                        if ranked.count > 2 { scopeButton("See all foods", scope: .foods) }
                    }
                }
            } else {
                foodSection(results.exactPersonalMatches, title: "Your exact matches", hydrate: false)
                foodSection(results.brandedMatches, title: "Branded foods", hydrate: true)
                foodSection(results.otherPersonalMatches, title: "Saved and recent foods", hydrate: false)
                foodSection(results.otherRemoteMatches, title: "More foods", hydrate: true)
                foodSection(foodSearch.supplementResults, title: "Supplements", hydrate: true)
            }
            if foodSearch.isLoading { ProgressView("Searching foods…").appTextRole(.secondary) }
            if let error = foodSearch.searchErrorMessage {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    Button("Retry food search", action: foodSearch.submitSearch).frame(minHeight: 44)
                }.accessibilityIdentifier("planner_food_search_error")
            } else if let coverage = foodSearch.searchCoverageMessage {
                Text(coverage).appTextRole(.caption).foregroundStyle(.secondary)
            } else if !foodSearch.isLoading && foodSearch.searchResults.isEmpty
                        && foodSearch.trustedSearchResults.isEmpty && foodSearch.supplementResults.isEmpty {
                Text(query.count < 2 ? "Type two or more letters to search foods." : "No foods match this search.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func foodSection(_ foods: [FoodItem], title: String, hydrate: Bool) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title).appTextRole(.secondary).foregroundStyle(.secondary)
                ForEach(foods) { food in
                    FoodPickerRow(food: food, isQuickLogged: false, onSelect: { onFood($0, hydrate) },
                        onQuickLog: nil, onDelete: nil, source: hydrate ? "search_result" : "recent_tap")
                    Divider()
                }
            }
        }
    }

    @ViewBuilder private var recipeChoices: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Saved recipes").appTextRole(.secondary).foregroundStyle(.secondary)
            if recipesLoading && recipes.isEmpty {
                ProgressView("Loading recipes")
            } else if matchingRecipes.isEmpty {
                Text(query.isEmpty ? "Create a recipe from the add menu." : "No recipes match this search.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                ForEach(scope == .all ? Array(matchingRecipes.prefix(2)) : matchingRecipes) { recipe in
                    MealPlanningLibraryRow(name: recipe.name,
                        detail: "\(recipe.ingredients.count.formatted()) ingredient\(recipe.ingredients.count == 1 ? "" : "s") · \(recipe.nutritionBasisLabel)",
                        nutrition: recipe.nutritionPerPortion, action: { onRecipe(recipe) })
                        .accessibilityLabel("Add \(recipe.name) to \(mealType)")
                        .accessibilityIdentifier("planner_choose_recipe_\(recipe.id ?? recipe.name)")
                    Divider()
                }
                if scope == .all && matchingRecipes.count > 2 { scopeButton("See all recipes", scope: .recipes) }
            }
        }
    }

    @ViewBuilder private var mealChoices: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Reusable meals").appTextRole(.secondary).foregroundStyle(.secondary)
            if let libraryError {
                Text(libraryError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                Button("Retry meals") { Task { await loadCompositions() } }.frame(minHeight: 44)
            } else if compositionsLoading && compositions.isEmpty {
                ProgressView("Loading saved meals")
            } else if matchingMeals.isEmpty {
                Text(query.isEmpty ? "Build a reusable meal from foods you eat together." : "No saved meals match this search.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                ForEach(scope == .all ? Array(matchingMeals.prefix(2)) : matchingMeals) { meal in
                    MealPlanningLibraryRow(name: meal.name,
                        detail: "\(meal.components.count.formatted()) foods · saved amounts",
                        nutrition: Nutrition.total(for: meal.components), action: { onComposition(meal) })
                        .accessibilityIdentifier("planner_choose_composition_\(meal.id)")
                    Divider()
                }
                if scope == .all && matchingMeals.count > 2 { scopeButton("See all meals", scope: .meals) }
            }
        }
    }

    private func chooserMessage(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title).appTextRole(.control)
            Text(detail).appTextRole(.secondary).foregroundStyle(.secondary)
        }
    }

    private func scopeButton(_ title: String, scope: Scope) -> some View {
        Button(title) { self.scope = scope }
            .appTextRole(.secondary).frame(minHeight: 44)
    }

    private func loadCompositions() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        compositionsLoading = true
        defer { compositionsLoading = false }
        do {
            let loaded = try await DIContainer.shared.nutritionRepository.fetchSavedMealCompositions(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            compositions = loaded; libraryError = nil
        } catch { libraryError = "Saved meals couldn't refresh. Your recipes and food search are still available." }
    }
}

private struct MealPlanningLibraryRow: View {
    let name: String
    let detail: String
    let nutrition: Nutrition
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).appTextRole(.control).foregroundStyle(AppPalette.text)
                    Text(detail).appTextRole(.caption).foregroundStyle(.secondary)
                    Text("\(nutrition.calories.formatted(.number.precision(.fractionLength(0)))) cal · \(nutrition.protein.formatted(.number.precision(.fractionLength(0)))) g protein")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").appTextRole(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, AppSpacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
