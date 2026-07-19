import SwiftUI
struct AddMealToPlanView: View {
    let date: Date
    @Binding var isPresented: Bool

    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMealType = "Dinner"
    @State private var searchText = ""
    @State private var savingRecipeKey: String?
    @State private var alertMessage: String?
    @State private var failedRecipe: Recipe?
    @State private var existingPlan: MealPlanDay?
    @State private var replaceExistingMealType = false
    @State private var showingCreateRecipeSheet = false

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    private var filteredRecipes: [Recipe] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recipeService.userRecipes }
        return recipeService.userRecipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(trimmed) ||
            recipe.ingredients.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var selectedMealCount: Int {
        existingPlan?.meals.filter { mealTypeMatches($0.mealType, selectedMealType) }.count ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if recipeService.isLoading && recipeService.userRecipes.isEmpty {
                    AddMealToPlanLoadingState()
                } else if recipeService.userRecipes.isEmpty {
                    AddMealToPlanEmptyState {
                        showingCreateRecipeSheet = true
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.section) {
                            AddMealToPlanHero(date: date) {
                                showingCreateRecipeSheet = true
                            }

                            AddMealTypePicker(
                                mealTypes: mealTypes,
                                selectedMealType: $selectedMealType
                            )

                            if selectedMealCount > 0 {
                                AddMealSlotModeCard(
                                    mealType: selectedMealType,
                                    mealCount: selectedMealCount,
                                    replaceExistingMealType: $replaceExistingMealType
                                )
                            }

                            if let alertMessage, let failedRecipe {
                                AddMealSaveFailureCard(
                                    message: alertMessage,
                                    retry: { addRecipeToPlan(failedRecipe) },
                                    dismiss: {
                                        self.alertMessage = nil
                                        self.failedRecipe = nil
                                    }
                                )
                            }

                            AddMealRecipeSearchField(searchText: $searchText)

                            if filteredRecipes.isEmpty {
                                AddMealNoMatchesState(searchText: searchText)
                            } else {
                                VStack(spacing: AppSpacing.row) {
                                    ForEach(filteredRecipes) { recipe in
                                        AddMealRecipeCard(
                                            recipe: recipe,
                                            mealType: selectedMealType,
                                            isSaving: savingRecipeKey == recipeKey(for: recipe),
                                            onAdd: { addRecipeToPlan(recipe) }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.top, AppSpacing.group)
                        .padding(.bottom, AppSpacing.section)
                    }
                }
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .accessibilityIdentifier("add_meal_plan_screen")
            .navigationTitle("Add meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissSheet()
                    }
                }
            }
            .task {
                await loadContext()
            }
            .onChange(of: selectedMealType) { _, _ in
                if selectedMealCount == 0 {
                    replaceExistingMealType = false
                }
            }
            .sheet(isPresented: $showingCreateRecipeSheet, onDismiss: {
                Task {
                    await loadContext()
                }
            }) {
                CreateRecipeView()
                    .environmentObject(recipeService)
                    .environmentObject(dailyLogService)
            }
        }
    }

    private func loadContext() async {
        await recipeService.fetchUserRecipes()
        await loadExistingPlan()
    }

    private func loadExistingPlan() async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let plan = await mealPlannerService.fetchPlan(for: date, userID: userID)
        guard DIContainer.shared.authService.currentUserID == userID else { return }
        existingPlan = plan
    }

    private func addRecipeToPlan(_ recipe: Recipe) {
        guard savingRecipeKey == nil else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else {
            alertMessage = "You need to be signed in to update a meal plan."
            failedRecipe = recipe
            return
        }

        let key = recipeKey(for: recipe)
        savingRecipeKey = key
        alertMessage = nil
        failedRecipe = nil

        Task { @MainActor in
            var plan = await mealPlannerService.fetchPlan(for: date, userID: userID) ?? emptyPlan(for: date)
            guard DIContainer.shared.authService.currentUserID == userID else {
                savingRecipeKey = nil
                return
            }
            if replaceExistingMealType {
                plan.meals.removeAll { mealTypeMatches($0.mealType, selectedMealType) }
            }
            plan.meals.append(plannedMeal(from: recipe))
            plan.meals.sort(by: sortMeals)

            let didSave = await mealPlannerService.savePlan(plan, for: userID)
            guard DIContainer.shared.authService.currentUserID == userID else {
                savingRecipeKey = nil
                return
            }
            guard didSave else {
                savingRecipeKey = nil
                alertMessage = "Your recipe and meal-slot choices are still here. Check your connection, then try again."
                failedRecipe = recipe
                HapticManager.instance.notification(.warning)
                return
            }

            existingPlan = plan
            await mealPlannerService.refreshGroceryList(for: userID)
            guard DIContainer.shared.authService.currentUserID == userID else {
                savingRecipeKey = nil
                return
            }
            savingRecipeKey = nil
            HapticManager.instance.feedback(.medium)
            dismissSheet()
        }
    }

    private func plannedMeal(from recipe: Recipe) -> PlannedMeal {
        PlannedMeal(
            id: UUID().uuidString,
            mealType: selectedMealType,
            recipeID: recipe.id,
            foodItem: recipeService.recipeToFoodItem(recipe: recipe),
            ingredients: recipe.ingredients,
            instructions: recipe.instructions.joined(separator: "\n")
        )
    }

    private func emptyPlan(for date: Date) -> MealPlanDay {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return MealPlanDay(
            id: mealPlanID(for: startOfDay),
            date: startOfDay,
            meals: []
        )
    }

    private func recipeKey(for recipe: Recipe) -> String {
        recipe.id ?? recipe.name
    }

    private func sortMeals(_ first: PlannedMeal, _ second: PlannedMeal) -> Bool {
        let firstOrder = mealOrder(for: first.mealType)
        let secondOrder = mealOrder(for: second.mealType)
        if firstOrder != secondOrder {
            return firstOrder < secondOrder
        }
        return (first.foodItem?.name ?? "").localizedCaseInsensitiveCompare(second.foodItem?.name ?? "") == .orderedAscending
    }

    private func mealOrder(for mealType: String) -> Int {
        mealTypes.firstIndex { mealType.localizedCaseInsensitiveContains($0) } ?? mealTypes.count
    }

    private func mealTypeMatches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveContains(rhs) || rhs.localizedCaseInsensitiveContains(lhs)
    }

    private func mealPlanID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dismissSheet() {
        isPresented = false
        dismiss()
    }
}

private struct AddMealSaveFailureCard: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("Meal was not saved", systemImage: "wifi.exclamationmark")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.compact) {
                Button("Try Again", action: retry)
                    .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))

                Button("Dismiss", action: dismiss)
                    .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
            }
        }
        .appSurface(.quiet)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.caution.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AddMealToPlanHero: View {
    let date: Date
    let onCreate: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppScreenHeader(
                eyebrow: "Meal Plan",
                title: "Add a Saved Recipe",
                subtitle: dateText
            ) {
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Create recipe")
            }

            Text("Choose a slot, then add a recipe to this day's plan. You can still regenerate meals around it later.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AddMealTypePicker: View {
    let mealTypes: [String]
    @Binding var selectedMealType: String

    var body: some View {
        Picker("Meal slot", selection: $selectedMealType) {
            ForEach(mealTypes, id: \.self) { mealType in
                Text(mealType).tag(mealType)
            }
        }
        .pickerStyle(.segmented)
        .appSurface(.quiet, padding: AppSpacing.compact)
        .onChange(of: selectedMealType) { _, _ in
            HapticManager.instance.feedback(.light)
        }
    }
}

private struct AddMealSlotModeCard: View {
    let mealType: String
    let mealCount: Int
    @Binding var replaceExistingMealType: Bool

    private var mealLabel: String {
        mealCount == 1 ? "meal" : "meals"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.caution)
                    .frame(width: 36, height: 36)
                    .background(AppPalette.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mealType) already has \(mealCount) \(mealLabel)")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)

                    Text("Add another recipe to this slot, or replace the current \(mealType.lowercased()) plan.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Add mode", selection: $replaceExistingMealType) {
                Text("Add alongside").tag(false)
                Text("Replace slot").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .appSurface(.quiet)
    }
}

private struct AddMealRecipeSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appTextRole(.control)
                .foregroundStyle(.secondary)

            TextField("Search recipes or ingredients", text: $searchText)
                .textInputAutocapitalization(.words)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appTextRole(.control)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear recipe search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        )
    }
}

private struct AddMealRecipeCard: View {
    let recipe: Recipe
    let mealType: String
    let isSaving: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .appFont(size: 27)
                .frame(width: 50, height: 50)
                .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(2)

                Text("\(recipe.ingredients.count) ingredients")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)

                Text("Cal \(Int(recipe.nutrition.calories.rounded()).formatted())  P \(Int(recipe.nutrition.protein.rounded()).formatted())g  C \(Int(recipe.nutrition.carbs.rounded()).formatted())g  F \(Int(recipe.nutrition.fats.rounded()).formatted())g")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)

            Button(action: onAdd) {
                if isSaving {
                    ProgressView()
                        .tint(AppPalette.brand)
                } else {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(AppIconButtonStyle(.brand))
            .disabled(isSaving)
            .accessibilityLabel("Add \(recipe.name) to \(mealType)")
        }
        .appSurface(.quiet, padding: AppSpacing.row)
    }
}

private struct AddMealToPlanLoadingState: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(AppPalette.brand)

            Text("Loading recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text("Getting your saved meals ready to add.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct AddMealToPlanEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .appFont(size: 40, weight: .bold)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 76, height: 76)
                .background(AppPalette.brand.opacity(0.10), in: Circle())

            VStack(spacing: 5) {
                Text("No saved recipes yet")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text("Create recipes first, then come back here to place them into a meal plan.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Create recipe", action: onCreate)
                .buttonStyle(AppActionButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}

private struct AddMealNoMatchesState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(AppPalette.control, in: Circle())

            Text("No matching recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }
}
