import SwiftUI
import MyFitPlateCore

struct RecipeDetailView: View {
    @State private var recipe: Recipe
    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @State private var showingAddToLogSheet = false
    @State private var showingAddToPlanSheet = false
    @State private var showingEditSheet = false
    @State private var showingVersions = false

    init(recipe: Recipe) {
        _recipe = State(initialValue: recipe)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                RecipeIdentityHeader(recipe: recipe)
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    RecipeNutritionSummary(nutrition: recipe.nutritionPerPortion)
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                        Text(recipe.nutritionBasisLabel)
                        if let weight = recipe.cookedWeightGrams, weight.isFinite, weight > 0 {
                            Spacer(minLength: 0)
                            Text("\(weight.formatted(.number.precision(.fractionLength(0...1)))) g cooked")
                                .accessibilityLabel("Finished batch, \(weight.formatted()) grams cooked")
                                .accessibilityIdentifier("recipe_detail_cooked_weight")
                        }
                    }.appTextRole(.caption).foregroundStyle(.secondary)
                }
                if recipe.nutritionNeedsReview == true || !recipe.unresolvedIngredientTexts.isEmpty {
                    Text("Saved nutrition may be estimated or unchanged after ingredient edits. Review the recipe before logging.")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                }
                RecipeIngredientsSection(
                    ingredients: RecipePortionRules.originalIngredientLines(for: recipe),
                    basis: (recipe.ingredientBasis ?? recipe.nutritionBasis) == .wholeRecipe ? "Amounts for the whole recipe" : recipe.ingredientBasis == .perServing ? "Amounts for one serving" : "Amounts as saved")
                RecipeInstructionsSection(instructions: recipe.instructions)
                RecipeNutrientDetailsSection(nutrition: recipe.nutritionPerPortion)
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
                HStack {
                    if recipe.id != nil { Button("Versions", systemImage: "clock.arrow.circlepath") { showingVersions = true }.accessibilityIdentifier("recipe_version_history") }
                    Button("Edit") { showingEditSheet = true }
                }.buttonStyle(AppListButtonStyle())
            }
        }
        .safeAreaInset(edge: .bottom) {
            RecipeDetailActionBar(
                onPlan: { showingAddToPlanSheet = true },
                onLog: { showingAddToLogSheet = true }
            )
        }
        .sheet(isPresented: $showingVersions) {
            if let id = recipe.id { RecipeVersionHistoryView(recipeID: id) { updated in
                if let updated, updated.id == recipe.id { recipe = updated }
            } }
        }
        .sheet(isPresented: $showingEditSheet) {
            CreateRecipeView(recipeToEdit: recipe) { updated in
                recipe = updated
            }
        }
        .sheet(isPresented: $showingAddToLogSheet) {
            RecipeLoggingView(
                recipe: recipe,
                dailyLog: $dailyLogService.currentDailyLog,
                date: dailyLogService.activelyViewedDate,
                onLogUpdated: { showingAddToLogSheet = false }
            )
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
                    .scaledToFill()
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
            FoodGlyph(recipe.name, pointSize: 36)
                .frame(width: 68, height: 68)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
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
        Label("\(recipe.ingredients.count.formatted()) ingredient\(recipe.ingredients.count == 1 ? "" : "s")", systemImage: "basket")
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
    let basis: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Ingredients",
                subtitle: basis
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
                                .fill(AppPalette.separator)
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
                title: "Method",
                subtitle: instructions.isEmpty ? nil : "\(instructions.count) steps"
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
                                .foregroundStyle(AppPalette.brandText)
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
    @State private var isLoadingPlan = true
    @State private var planRequestID = UUID()
    @State private var owner: String?
    @State private var portionAmountText = "1"
    @State private var portionUnit: RecipePortionUnit

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    init(recipe: Recipe) {
        self.recipe = recipe
        _portionUnit = State(initialValue: RecipePortionRules.defaultSelection(for: recipe).unit)
    }

    private var portionSelection: RecipePortionSelection {
        RecipePortionSelection(unit: portionUnit, amount: Double(portionAmountText.replacingOccurrences(of: ",", with: ".")) ?? .nan)
    }
    private var portionSnapshot: RecipePortionSnapshot? { try? RecipePortionRules.snapshot(for: recipe, selection: portionSelection) }

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

                    Text(recipe.nutritionBasisLabel).appTextRole(.secondary).foregroundStyle(.secondary)
                    RecipePortionPicker(recipe: recipe, unit: $portionUnit, amountText: $portionAmountText,
                                        identifier: "recipe_plan_portion")
                    RecipeNutritionSummary(nutrition: portionSnapshot?.selectedNutrition ?? .zero)
                }
                .disabled(isSaving)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .accessibilityIdentifier("recipe_plan_scroll")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
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
                .disabled(isSaving || isLoadingPlan || owner == nil || portionSnapshot == nil)
                .accessibilityIdentifier("recipe_plan_save")
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
            .interactiveDismissDisabled(isSaving)
            .task {
                owner = DIContainer.shared.authService.currentUserID
                await loadExistingPlan()
            }
            .onChange(of: selectedDate) { _, _ in
                existingPlan = nil
                replaceExistingMealType = false
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
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        let date = selectedDate, requestID = UUID()
        planRequestID = requestID
        isLoadingPlan = true
        mealPlannerService.invalidateCache(for: owner)
        let result = await mealPlannerService.fetchBasePlanResult(for: date, userID: owner)
        guard planRequestID == requestID, date == selectedDate,
              DIContainer.shared.authService.currentUserID == owner else { return }
        isLoadingPlan = false
        switch result {
        case .success(let plan): existingPlan = plan
        case .failure: alertMessage = "Couldn't load this day's plan. Your choices are still here. Saving will check the plan again."
        }
    }

    private func saveToPlan() {
        guard !isSaving, portionSnapshot != nil else { return }
        guard let owner, DIContainer.shared.authService.currentUserID == owner else {
            alertMessage = "You need to be signed in to update a meal plan."
            return
        }
        isSaving = true
        let date = selectedDate, mealType = selectedMealType
        let replacing = replaceExistingMealType, reviewedPlan = existingPlan
        let meal: PlannedMeal
        do {
            meal = PlannedMeal(mealType: mealType, recipeID: recipe.id,
                foodItem: try RecipePortionRules.foodItem(for: recipe, selection: portionSelection),
                ingredients: try RecipePortionRules.ingredients(for: recipe, selection: portionSelection),
                instructions: recipe.instructions.joined(separator: "\n"))
        } catch {
            isSaving = false
            alertMessage = error.localizedDescription
            return
        }
        Task { @MainActor in
            defer { isSaving = false }
            do {
                mealPlannerService.invalidateCache(for: owner)
                let fetched = try await mealPlannerService.fetchBasePlanResult(for: date, userID: owner).get()
                let original = fetched ?? MealPlanEditingRules.emptyDay(date)
                if replacing, !MealPlanEditingRules.matches(fetched, expected: reviewedPlan ?? MealPlanEditingRules.emptyDay(date)) {
                    // Refresh slots before asking the user to confirm replacement again.
                    existingPlan = fetched
                    replaceExistingMealType = false
                    throw MealPlanEditError.changed
                }
                var updated = original
                if replacing { updated.meals.removeAll { mealTypeMatches($0.mealType, mealType) } }
                updated.meals.append(MealPlanEditingRules.duplicate(meal))
                try await mealPlannerService.applyPlanChange(
                    MealPlanChange(title: "Recipe added", before: [original], after: [updated]), for: owner
                )
                guard DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
                HapticManager.instance.feedback(.medium)
                dismiss()
            } catch {
                alertMessage = MealPlannerErrorText.message(for: error)
                HapticManager.instance.notification(.warning)
            }
        }
    }

    private func mealTypeMatches(_ lhs: String, _ rhs: String) -> Bool {
        MealPlanEditingRules.canonicalSlot(lhs) == MealPlanEditingRules.canonicalSlot(rhs)
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
                            .foregroundStyle(AppPalette.brandText)
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

#if DEBUG
/// Direct, mock-account-only presentations for the whole-app design contact sheet.
struct NutritionDesignGallery: View {
    let screen: String
    @EnvironmentObject private var goals: GoalSettings
    @State private var waterAmount = "96"
    private var recipe: Recipe { ScreenshotDemoData.recipeDemoRecipes[0] }
    @ViewBuilder var body: some View {
        switch screen {
        case "ai-summary": AISummaryView(estimatedItems: ScreenshotDemoData.aiTextDemoFoods, mealName: "Dinner", date: Date())
        case "ai-menu": AIMenuSelectionView(estimatedItems: .constant(ScreenshotDemoData.aiTextDemoFoods), date: Date(), mealName: "Dinner")
        case "ai-text-review": AITextResultsView(foodItems: ScreenshotDemoData.aiTextDemoFoods, date: Date(), mealName: "Dinner", onLogComplete: {})
        case "preferences": SuggestionPreferencesView(goalSettings: goals)
        case "water": SetWaterGoalView(waterGoalInput: $waterAmount, onAccepted: {})
        case let name where name.hasPrefix("buffet-"): BuffetDesignGallery(screen: name)
        case "recipe-create": CreateRecipeView()
        case "recipe-edit": CreateRecipeView(recipeToEdit: recipe)
        case "recipe-detail": NavigationStack { RecipeDetailView(recipe: recipe) }
        case "recipe-log": RecipeLoggingView(recipe: recipe, dailyLog: .constant(nil), date: Date(), mealName: "Lunch", onLogUpdated: {})
        case "recipe-plan": AddRecipeToPlanSheet(recipe: recipe)
        case "recipe-history": RecipeVersionHistoryView(recipeID: recipe.id ?? "design-recipe", onChanged: { _ in })
        case "week-review": MealPlanDraftReviewView(draft: MealPlanWeekDraft(days: ScreenshotDemoData.mealPrepDemoDays, title: "Your week"), didSave: {})
        case "week-partial": MealPlanDraftReviewView(draft: partialWeek, didSave: {})
        case "day-review":
            if let batch = try? NutritionDayBatchReview(ownerID: DIContainer.shared.authService.currentUserID ?? "mock_user", status: .complete, logs: [ScreenshotDemoData.trustHubDemoLog]) {
                NutritionBatchReviewView(initial: batch)
            }
        default: NavigationStack { RecipeListView() }
        }
    }
    private var partialWeek: MealPlanWeekDraft {
        // Use an unseeded future week so existing demo plans cannot fill the intended gap.
        let start = Calendar.current.date(byAdding: .day, value: 35, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        var constraints = MealPlanConstraints(calories: 1800, protein: 150, carbs: 200, fats: 35)
        constraints.practicalWeek = MealPlanningWeekBrief(mealTypes: ["Dinner"],
            days: (0..<7).map { MealPlanningDayBrief(offset: $0, cookingMinutes: $0 == 2 ? 15 : 60) })
        let days = (0..<7).map { offset -> MealPlanDay in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            var day = MealPlanEditingRules.emptyDay(date)
            if offset != 2 {
                var food = recipe.foodItemForLogging()
                food.id = "design-dinner-food-\(offset)"
                var meal = PlannedMeal(id: "design-dinner-\(offset)", mealType: "Dinner", foodItem: food,
                    ingredients: RecipePortionRules.originalIngredientLines(for: recipe), instructions: recipe.instructions.joined(separator: "\n"))
                meal.planningEvidence = try? PlannedMealEvidence(profile: RecipePlanningProfile(prepMinutes: 25,
                    equipment: ["Stove"], costPerServing: 5, reviewedAt: Date()), meal: meal)
                day.meals = [meal]
            }
            return day
        }
        return MealPlanWeekDraft(days: days, title: "A week that fits", constraints: constraints)
    }

}
#endif
