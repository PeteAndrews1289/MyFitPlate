import SwiftUI

struct RecipeDetailView: View {
    @State private var recipe: Recipe
    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @State private var showingAddToLogSheet = false
    @State private var showingAddToPlanSheet = false
    @State private var showingEditSheet = false

    init(recipe: Recipe) {
        _recipe = State(initialValue: recipe)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                RecipeIdentityHeader(recipe: recipe)
                RecipeNutritionSummary(nutrition: recipe.nutrition)
                RecipeIngredientsSection(ingredients: recipe.ingredients)
                RecipeInstructionsSection(instructions: recipe.instructions)
                RecipeNutrientDetailsSection(nutrition: recipe.nutrition)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.group)
        }
        .accessibilityIdentifier("recipe_detail")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditSheet = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            RecipeDetailActionBar(
                onPlan: { showingAddToPlanSheet = true },
                onLog: { showingAddToLogSheet = true }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            CreateRecipeView(recipeToEdit: recipe) { updated in
                recipe = updated
            }
        }
        .sheet(isPresented: $showingAddToLogSheet) {
            if recipe.detailedIngredients != nil {
                RecipeLoggingView(
                    recipe: recipe,
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: dailyLogService.activelyViewedDate,
                    onLogUpdated: { showingAddToLogSheet = false }
                )
            } else {
                NavigationStack {
                    AddFoodView(
                        initialFoodItem: recipeService.recipeToFoodItem(recipe: recipe),
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "recipe_detail",
                        onLogUpdated: { showingAddToLogSheet = false }
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddToPlanSheet) {
            AddRecipeToPlanSheet(recipe: recipe)
                .environmentObject(recipeService)
                .environmentObject(mealPlannerService)
        }
    }
}

private struct RecipeIdentityHeader: View {
    let recipe: Recipe

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    recipeArtwork
                    identityText
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    recipeArtwork
                    identityText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recipeArtwork: some View {
        if let imageURLString = recipe.imageURL, let url = URL(string: imageURLString) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
            } placeholder: {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .fill(AppPalette.control)
                    .frame(width: 68, height: 68)
            }
            .accessibilityHidden(true)
        } else if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "fork.knife")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 68, height: 68)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .font(.system(size: 36))
                .frame(width: 68, height: 68)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(recipe.name)
                .appTextRole(dynamicTypeSize.isAccessibilitySize ? .sectionTitle : .screenTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recipe_detail_title")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        ingredientMetadata
                        instructionMetadata
                    }
                } else {
                    HStack(spacing: AppSpacing.row) {
                        ingredientMetadata
                        instructionMetadata
                    }
                }
            }
        }
    }

    private var ingredientMetadata: some View {
        Label("\(recipe.ingredients.count.formatted()) ingredients", systemImage: "basket")
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
            .accessibilityIdentifier("recipe_detail_ingredient_count")
    }

    private var instructionMetadata: some View {
        Label("\(recipe.instructions.count.formatted()) steps", systemImage: "list.number")
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
            .accessibilityIdentifier("recipe_detail_instruction_count")
    }
}

private struct RecipeNutritionSummary: View {
    let nutrition: Nutrition

    var body: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Calories",
                value: "\(Int(nutrition.calories.rounded()).formatted()) cal",
                accent: AppPalette.energy
            ),
            AppMetricItem(
                label: "Protein",
                value: "\(Int(nutrition.protein.rounded()).formatted()) g",
                accent: .accentProtein
            ),
            AppMetricItem(
                label: "Carbs",
                value: "\(Int(nutrition.carbs.rounded()).formatted()) g",
                accent: .accentCarbs
            ),
            AppMetricItem(
                label: "Fat",
                value: "\(Int(nutrition.fats.rounded()).formatted()) g",
                accent: .accentFats
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("recipe_nutrition_summary")
    }
}

private struct RecipeIngredientsSection: View {
    let ingredients: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Ingredients",
                subtitle: "Amounts are shown as saved with this recipe."
            )

            VStack(spacing: 0) {
                if ingredients.isEmpty {
                    Text("No ingredients recorded.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.group)
                } else {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            Circle()
                                .fill(AppPalette.brand)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                                .accessibilityHidden(true)

                            Text(ingredient)
                                .appTextRole(.body)
                                .foregroundStyle(AppPalette.text)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.group)
                        .padding(.vertical, AppSpacing.row)

                        if index < ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_ingredients")
    }
}

private struct RecipeInstructionsSection: View {
    let instructions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Instructions",
                subtitle: instructions.isEmpty ? nil : "Follow the saved order."
            )

            VStack(spacing: 0) {
                if instructions.isEmpty {
                    Text("No instructions recorded.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.group)
                } else {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            Text((index + 1).formatted())
                                .appTextRole(.caption)
                                .foregroundStyle(AppPalette.brand)
                                .frame(width: 28, height: 28)
                                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                                .accessibilityHidden(true)

                            Text(instruction)
                                .appTextRole(.body)
                                .foregroundStyle(AppPalette.text)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.group)
                        .padding(.vertical, AppSpacing.row)

                        if index < instructions.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_instructions")
    }
}

private struct RecipeNutrientValue: Identifiable {
    let label: String
    let value: Double
    let unit: String

    var id: String { label }
}

private struct RecipeNutrientDetailsSection: View {
    let nutrition: Nutrition

    private var nutrientValues: [RecipeNutrientValue] {
        let values: [(String, Double?, String)] = [
            ("Saturated Fat", nutrition.saturatedFat, "g"),
            ("Polyunsaturated Fat", nutrition.polyunsaturatedFat, "g"),
            ("Monounsaturated Fat", nutrition.monounsaturatedFat, "g"),
            ("Fiber", nutrition.fiber, "g"),
            ("Calcium", nutrition.calcium, "mg"),
            ("Iron", nutrition.iron, "mg"),
            ("Potassium", nutrition.potassium, "mg"),
            ("Sodium", nutrition.sodium, "mg"),
            ("Vitamin A", nutrition.vitaminA, "mcg"),
            ("Vitamin C", nutrition.vitaminC, "mg"),
            ("Vitamin D", nutrition.vitaminD, "mcg"),
            ("Vitamin B12", nutrition.vitaminB12, "mcg"),
            ("Folate", nutrition.folate, "mcg"),
            ("Magnesium", nutrition.magnesium, "mg"),
            ("Phosphorus", nutrition.phosphorus, "mg"),
            ("Zinc", nutrition.zinc, "mg"),
            ("Copper", nutrition.copper, "mcg"),
            ("Manganese", nutrition.manganese, "mg"),
            ("Selenium", nutrition.selenium, "mcg"),
            ("Vitamin B1", nutrition.vitaminB1, "mg"),
            ("Vitamin B2", nutrition.vitaminB2, "mg"),
            ("Vitamin B3", nutrition.vitaminB3, "mg"),
            ("Vitamin B5", nutrition.vitaminB5, "mg"),
            ("Vitamin B6", nutrition.vitaminB6, "mg"),
            ("Vitamin E", nutrition.vitaminE, "mg"),
            ("Vitamin K", nutrition.vitaminK, "mcg")
        ]

        return values.compactMap { label, value, unit in
            guard let value, value.isFinite, value >= 0 else { return nil }
            return RecipeNutrientValue(label: label, value: value, unit: unit)
        }
    }

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                Text("\(nutrition.reportedVitaminMineralCount) of \(MicronutrientKey.vitaminAndMineralKeys.count) vitamins and minerals reported. Missing values are unknown, not zero.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, AppSpacing.row)

                ForEach(Array(nutrientValues.enumerated()), id: \.element.id) { index, nutrient in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                        Text(nutrient.label)
                            .appTextRole(.body)
                            .foregroundStyle(AppPalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: AppSpacing.group)
                        Text("\(formatted(nutrient.value)) \(nutrient.unit)")
                            .appTextRole(.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, AppSpacing.compact)

                    if index < nutrientValues.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.top, AppSpacing.row)
        } label: {
            AppSectionHeader(
                title: "More Nutrition",
                subtitle: "Reported fats, fiber, vitamins, and minerals"
            )
        }
        .tint(AppPalette.brand)
        .appSurface(.quiet)
        .accessibilityIdentifier("recipe_more_nutrition")
    }

    private func formatted(_ value: Double) -> String {
        let fractionLength = value < 10 ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(fractionLength)))
    }
}

private struct RecipeDetailActionBar: View {
    let onPlan: () -> Void
    let onLog: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    logButton
                    planButton
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    planButton
                    logButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.row)
        .padding(.bottom, AppSpacing.compact)
        .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.separator)
                .frame(height: 1)
        }
    }

    private var planButton: some View {
        Button(action: onPlan) {
            Label("Add to Plan", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("recipe_add_to_plan")
    }

    private var logButton: some View {
        Button(action: onLog) {
            Label("Add to Log", systemImage: "plus.circle.fill")
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .accessibilityIdentifier("recipe_add_to_log")
    }
}

private struct AddRecipeToPlanSheet: View {
    let recipe: Recipe

    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedMealType = "Dinner"
    @State private var existingPlan: MealPlanDay?
    @State private var replaceExistingMealType = false
    @State private var isSaving = false
    @State private var alertMessage: String?

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    private var selectedMealCount: Int {
        existingPlan?.meals.filter { mealTypeMatches($0.mealType, selectedMealType) }.count ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    RecipePlanIdentity(recipe: recipe)
                    scheduleSection

                    if selectedMealCount > 0 {
                        AddRecipePlanModeControl(
                            mealType: selectedMealType,
                            mealCount: selectedMealCount,
                            replaceExistingMealType: $replaceExistingMealType
                        )
                    }

                    RecipeNutritionSummary(nutrition: recipe.nutrition)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Add to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveToPlan) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isSaving)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
            }
            .task { await loadExistingPlan() }
            .onChange(of: selectedDate) { _, _ in
                Task { await loadExistingPlan() }
            }
            .onChange(of: selectedMealType) { _, _ in
                if selectedMealCount == 0 {
                    replaceExistingMealType = false
                }
            }
            .alert("Could Not Add Recipe", isPresented: alertIsPresented) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Schedule",
                subtitle: "Choose the day and meal slot."
            )

            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(AppPalette.brand)

            Divider()

            AddRecipeMealTypePicker(
                mealTypes: mealTypes,
                selectedMealType: $selectedMealType
            )
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("recipe_plan_schedule")
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }

    private func loadExistingPlan() async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        existingPlan = await mealPlannerService.fetchPlan(for: selectedDate, userID: userID)
    }

    private func saveToPlan() {
        guard !isSaving else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else {
            alertMessage = "You need to be signed in to update a meal plan."
            return
        }

        isSaving = true

        Task { @MainActor in
            var plan = await mealPlannerService.fetchPlan(for: selectedDate, userID: userID)
                ?? emptyPlan(for: selectedDate)
            if replaceExistingMealType {
                plan.meals.removeAll { mealTypeMatches($0.mealType, selectedMealType) }
            }
            plan.meals.append(plannedMeal)
            plan.meals.sort(by: sortMeals)

            await mealPlannerService.savePlan(plan, for: userID)
            await mealPlannerService.refreshGroceryList(for: userID)
            isSaving = false
            HapticManager.instance.feedback(.medium)
            dismiss()
        }
    }

    private var plannedMeal: PlannedMeal {
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
        return MealPlanDay(id: mealPlanID(for: startOfDay), date: startOfDay, meals: [])
    }

    private func sortMeals(_ first: PlannedMeal, _ second: PlannedMeal) -> Bool {
        let firstOrder = mealOrder(for: first.mealType)
        let secondOrder = mealOrder(for: second.mealType)
        if firstOrder != secondOrder {
            return firstOrder < secondOrder
        }
        return (first.foodItem?.name ?? "")
            .localizedCaseInsensitiveCompare(second.foodItem?.name ?? "") == .orderedAscending
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
}

private struct RecipePlanIdentity: View {
    let recipe: Recipe

    var body: some View {
        AppScreenHeader(
            eyebrow: "Saved Recipe",
            title: recipe.name,
            subtitle: "Choose where this recipe should appear in your plan."
        )
    }
}

private struct AddRecipeMealTypePicker: View {
    let mealTypes: [String]
    @Binding var selectedMealType: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(mealTypes, id: \.self) { mealType in
                        Button {
                            select(mealType)
                        } label: {
                            Label(
                                mealType,
                                systemImage: selectedMealType == mealType ? "checkmark" : "fork.knife"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Meal")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                            Text(selectedMealType)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                        }
                        Spacer(minLength: AppSpacing.compact)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(AppPalette.brand)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Picker("Meal", selection: $selectedMealType) {
                    ForEach(mealTypes, id: \.self) { mealType in
                        Text(mealType).tag(mealType)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func select(_ mealType: String) {
        selectedMealType = mealType
        HapticManager.instance.feedback(.light)
    }
}

private struct AddRecipePlanModeControl: View {
    let mealType: String
    let mealCount: Int
    @Binding var replaceExistingMealType: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var mealLabel: String {
        mealCount == 1 ? "meal" : "meals"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Existing \(mealType)",
                subtitle: "\(mealCount.formatted()) \(mealLabel) already planned"
            )

            if dynamicTypeSize.isAccessibilitySize {
                Picker("How to add", selection: $replaceExistingMealType) {
                    Text("Add Alongside").tag(false)
                    Text("Replace Slot").tag(true)
                }
                .pickerStyle(.menu)
                .tint(AppPalette.brand)
            } else {
                Picker("How to add", selection: $replaceExistingMealType) {
                    Text("Add Alongside").tag(false)
                    Text("Replace Slot").tag(true)
                }
                .pickerStyle(.segmented)
            }
        }
        .appSurface(.quiet)
    }
}
