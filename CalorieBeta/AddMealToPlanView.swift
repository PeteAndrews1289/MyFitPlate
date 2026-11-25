import MyFitPlateCore
import SwiftUI

struct AddMealToPlanView: View {
    let date: Date
    @Binding var isPresented: Bool
    var replacing: PlannedMeal?
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMealType = "Dinner"
    @State private var showingCreateRecipeSheet = false
    @State private var candidate: PlannedMeal?
    @State private var owner: String?
    @State private var recipeForReview: Recipe?
    @State private var pendingReviewedRecipe: Recipe?
    @State private var recipeReviewMessage: String?
    @State private var showingCompositions = false
    @State private var showingCompositionEditor = false
    @State private var pendingComposition: PlannedMeal?
    @State private var libraryRefresh = UUID()
    @State private var foodRequestID: UUID?
    @State private var isResolvingFood = false

    var body: some View {
        NavigationStack {
            MealPlanningChooserView(date: date, mealType: $selectedMealType,
                recipes: recipeService.userRecipes, recipesLoading: recipeService.isLoading,
                isResolvingFood: isResolvingFood, message: recipeReviewMessage,
                onFood: chooseFood, onRecipe: { chooseRecipe($0) },
                onComposition: chooseComposition, libraryRefresh: libraryRefresh)
                .navigationTitle(replacing == nil ? "Add meal" : "Swap meal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { foodRequestID = nil; dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) { creationMenu }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("add_meal_plan_screen")
                .task {
                    owner = DIContainer.shared.authService.currentUserID
                    if let replacing { selectedMealType = MealPlanEditingRules.canonicalSlot(replacing.mealType) }
                    await recipeService.fetchUserRecipes()
                }
                .sheet(isPresented: $showingCompositions, onDismiss: {
                    candidate = pendingComposition; pendingComposition = nil
                    libraryRefresh = UUID()
                }) {
                    MealCompositionLibraryView { meal in
                        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
                        var value = meal; value.mealType = selectedMealType; pendingComposition = value
                    }
                }
                .sheet(isPresented: $showingCompositionEditor, onDismiss: { libraryRefresh = UUID() }) {
                    MealCompositionEditorView(original: nil)
                }
                .sheet(item: $candidate) { meal in
                    PlannedMealEditSheet(meal: meal, date: date, title: "Review planned meal") { reviewed in
                        try await add(reviewed)
                    }
                }
                .sheet(isPresented: $showingCreateRecipeSheet, onDismiss: {
                    let reviewed = pendingReviewedRecipe
                    pendingReviewedRecipe = nil; recipeForReview = nil
                    Task { @MainActor in
                        await recipeService.fetchUserRecipes()
                        guard let owner, owner == DIContainer.shared.authService.currentUserID else { return }
                        if let reviewed { chooseRecipe(reviewed, reopenReviewOnFailure: false) }
                    }
                }) {
                    CreateRecipeView(recipeToEdit: recipeForReview) { saved in
                        guard let owner, owner == DIContainer.shared.authService.currentUserID else { return }
                        pendingReviewedRecipe = saved
                    }
                }
        }
        .onDisappear {
            foodRequestID = nil
            isResolvingFood = false
        }
    }

    private var creationMenu: some View {
        Menu {
            Button("Create recipe", systemImage: "book") {
                recipeForReview = nil; pendingReviewedRecipe = nil
                showingCreateRecipeSheet = true
            }.accessibilityIdentifier("planner_create_recipe")
            Button("Build a meal", systemImage: "square.stack") { showingCompositionEditor = true }
                .accessibilityIdentifier("planner_build_composition")
            Button("Manage saved meals", systemImage: "folder") { showingCompositions = true }
                .accessibilityIdentifier("planner_compositions")
        } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
        .accessibilityLabel("Create or manage meals")
        .accessibilityIdentifier("planner_create_menu")
        .disabled(isResolvingFood)
    }

    private func chooseFood(_ food: FoodItem, hydrate: Bool) {
        guard let owner, owner == DIContainer.shared.authService.currentUserID else {
            recipeReviewMessage = MealPlanEditError.accountChanged.localizedDescription
            return
        }
        let mealType = selectedMealType
        recipeReviewMessage = nil
        guard hydrate, FoodSearchRanking.isFatSecretID(food.id) else {
            presentFood(food, mealType: mealType)
            return
        }
        let requestID = UUID()
        foodRequestID = requestID; isResolvingFood = true
        FatSecretFoodAPIService().fetchFoodDetails(foodId: food.id) { result in
            DispatchQueue.main.async {
                guard foodRequestID == requestID, DIContainer.shared.authService.currentUserID == owner else { return }
                foodRequestID = nil; isResolvingFood = false
                switch result {
                case .success(let details):
                    let selectedServing = FoodSearchRanking.hydratedQuickLogItem(
                        preview: food, detailBase: details.foodInfo,
                        availableServings: details.availableServings)
                    presentFood(selectedServing, mealType: mealType)
                case .failure:
                    recipeReviewMessage = "Serving details couldn't load. Try this food again; your plan hasn't changed."
                }
            }
        }
    }

    private func presentFood(_ food: FoodItem, mealType: String) {
        let ingredient = food.servingWeight > 0
            ? "\(food.servingWeight.formatted(.number.precision(.fractionLength(0...2)))) g \(food.name)"
            : "\(food.servingSize) \(food.name)"
        candidate = PlannedMeal(mealType: mealType, foodItem: food, ingredients: [ingredient])
    }

    private func chooseComposition(_ composition: SavedMealComposition) {
        guard let owner, owner == DIContainer.shared.authService.currentUserID else {
            recipeReviewMessage = MealPlanEditError.accountChanged.localizedDescription
            return
        }
        do {
            let food = try MealCompositionRules.food(composition.snapshot)
            candidate = PlannedMeal(mealType: selectedMealType, foodItem: food,
                ingredients: composition.components.map(MealCompositionRules.ingredientText))
            recipeReviewMessage = nil
        } catch { recipeReviewMessage = error.localizedDescription }
    }

    private func chooseRecipe(_ recipe: Recipe, reopenReviewOnFailure: Bool = true) {
        guard let owner, owner == DIContainer.shared.authService.currentUserID else {
            recipeReviewMessage = MealPlanEditError.accountChanged.localizedDescription
            return
        }
        do {
            let selection = RecipePortionRules.defaultSelection(for: recipe)
            var meal = PlannedMeal(mealType: selectedMealType, recipeID: recipe.id,
                foodItem: try RecipePortionRules.foodItem(for: recipe, selection: selection),
                ingredients: try RecipePortionRules.ingredients(for: recipe, selection: selection),
                instructions: recipe.instructions.joined(separator: "\n"))
            if let profile = recipe.planningProfile, profile.isCurrent(for: recipe) {
                meal.planningEvidence = try PlannedMealEvidence(profile: profile, meal: meal)
            }
            recipeReviewMessage = nil
            candidate = meal
        } catch {
            recipeReviewMessage = "Review this recipe before planning it. " + error.localizedDescription
            guard reopenReviewOnFailure else { return }
            recipeForReview = recipe; pendingReviewedRecipe = nil
            showingCreateRecipeSheet = true
        }
    }

    private func add(_ candidate: PlannedMeal) async throws {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
        mealPlannerService.invalidateCache(for: owner)
        let fetched = try await mealPlannerService.fetchBasePlanResult(for: date, userID: owner).get()
        let original = fetched ?? MealPlanEditingRules.emptyDay(date)
        var updated = original, meal = candidate
        if let replacing {
            guard let index = updated.meals.firstIndex(where: { $0.id == replacing.id }),
                  (try? PlanFingerprint.make(updated.meals[index])) == (try? PlanFingerprint.make(replacing)) else {
                throw MealPlanEditError.changed
            }
            meal.id = replacing.id
            updated.meals[index] = meal
        } else {
            var inserted = MealPlanEditingRules.duplicate(meal)
            if let evidence = meal.planningEvidence, evidence.isCurrent(for: meal) {
                inserted.planningEvidence = try PlannedMealEvidence(profile: evidence.profile, meal: inserted)
            }
            updated.meals.append(inserted)
        }
        let change = MealPlanChange(title: replacing == nil ? "Meal added" : "Meal swapped", before: [original], after: [updated])
        try await mealPlannerService.applyPlanChange(change, for: owner)
        guard DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
        HapticManager.instance.feedback(.medium)
        isPresented = false
        dismiss()
    }
}
