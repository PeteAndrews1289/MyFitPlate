import SwiftUI
import MyFitPlateCore

struct RecipeLoggingView: View {
    let recipe: Recipe
    @Binding var dailyLog: DailyLog?
    let onLogUpdated: () -> Void

    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var saveSession: MealReviewSaveSession
    @State private var ingredientSnapshot: RecipeIngredientEditorSnapshot
    private var ingredients: [FoodItem] {
        get { ingredientSnapshot.ingredients }
        nonmutating set { ingredientSnapshot = RecipeIngredientEditorSnapshot(newValue) }
    }
    @State private var ingredientsChanged = false
    @State private var invalidIngredientIDs: Set<String> = []
    @State private var portionAmountText = "1"
    @State private var portionUnit: RecipePortionUnit
    @State private var selectedMeal: String
    @State private var variationDraft: Recipe?
    @State private var variationError: String?
    private let meals = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    init(recipe: Recipe, dailyLog: Binding<DailyLog?>, date: Date, mealName: String = "Breakfast",
         initialSelection: RecipePortionSelection? = nil, onLogUpdated: @escaping () -> Void) {
        self.recipe = recipe
        _dailyLog = dailyLog
        self.onLogUpdated = onLogUpdated
        _ingredientSnapshot = State(initialValue: RecipeIngredientEditorSnapshot(recipe.resolvedIngredientFoods))
        let selection = initialSelection ?? RecipePortionRules.defaultSelection(for: recipe)
        _portionUnit = State(initialValue: selection.unit)
        _portionAmountText = State(initialValue: Self.amountText(for: selection))
        let initialFood = (try? RecipePortionRules.foodItem(for: recipe, selection: selection)) ?? recipe.foodItemForLogging()
        let review = MealReviewSaveSession(
            items: [initialFood], userID: DIContainer.shared.authService.currentUserID,
            date: date, mealName: mealName, source: "recipe",
            draftScope: "recipe-review-\(recipe.id ?? recipe.name)"
        )
        _saveSession = StateObject(wrappedValue: review)
        _selectedMeal = State(initialValue: review.mealName)
    }

    private var hasFrozenReview: Bool { saveSession.isLocked || saveSession.restoredReview }
    private var frozenFood: FoodItem? { hasFrozenReview ? saveSession.items.first : nil }
    private static func amountText(for selection: RecipePortionSelection) -> String {
        selection.amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...3)))
    }
    private var portionSelection: RecipePortionSelection {
        RecipePortionSelection(unit: portionUnit, amount: Double(portionAmountText.replacingOccurrences(of: ",", with: ".")) ?? .nan)
    }
    private var portionSnapshot: RecipePortionSnapshot? { try? RecipePortionRules.snapshot(for: recipe, selection: portionSelection) }
    private var totalNutrition: Nutrition {
        if hasFrozenReview { return Nutrition.total(for: saveSession.items) }
        guard let snapshot = portionSnapshot else { return .zero }
        if ingredientsChanged {
            let multiplier = (recipe.ingredientBasis ?? recipe.nutritionBasis) == .wholeRecipe ? snapshot.batchFraction
                : snapshot.servingsEquivalent
            return Nutrition.total(for: ingredients).scaled(by: multiplier ?? portionSelection.amount)
        }
        return snapshot.selectedNutrition
    }

    private var canLogRecipe: Bool {
        hasFrozenReview ? !saveSession.items.isEmpty
            : portionSnapshot != nil && invalidIngredientIDs.isEmpty && (!ingredientsChanged || !ingredients.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    RecipeLoggingIdentity(name: frozenFood?.name ?? recipe.name, isSavedReview: frozenFood != nil)
                    if saveSession.restoredReview && saveSession.items.isEmpty {
                        Text("This unfinished review has no portion to log.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        restoreSavedPortion
                    } else if hasFrozenReview {
                        Text("Saved nutrition for the reviewed amount")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    } else {
                        Text(recipe.nutritionBasisLabel).appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    RecipeLoggingNutrition(nutrition: totalNutrition)
                    Text("For \(saveSession.date.formatted(date: .abbreviated, time: .omitted)) · \(saveSession.mealName)")
                        .appTextRole(.secondary)
                        .accessibilityIdentifier("recipe_log_destination")
                    if (saveSession.restoredReview || saveSession.isSubmitted) && !saveSession.items.isEmpty {
                        Text("Your reviewed portion and destination are kept on this device. Finish logging to save this meal once.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if let error = saveSession.errorMessage {
                        Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .accessibilityIdentifier("recipe_log_error")
                    }
                    if ingredientsChanged || frozenFood?.recipePortionSnapshot?.adjustedIngredientFoods != nil {
                        Button("Save these adjustments as a recipe variation") { prepareVariation() }
                            .frame(minHeight: 44).accessibilityIdentifier("recipe_log_save_variation")
                        Text("The variation keeps the edited original recipe amounts. Your eaten portion is reviewed separately, and the finished batch weight needs measuring again.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if let variationError { Text(variationError).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
                    mealSection.disabled(hasFrozenReview)
                    if hasFrozenReview {
                        if frozenFood != nil { frozenPortionSection }
                    } else {
                        RecipePortionPicker(recipe: recipe, unit: $portionUnit, amountText: $portionAmountText,
                                            identifier: "recipe_log_portion")
                        if recipe.hasCompleteIngredientNutrition {
                            ingredientSection
                        } else {
                            Text("Ingredient nutrition is not fully linked. This logs the saved nutrition; ingredient edits belong in the recipe editor.")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .accessibilityIdentifier("recipe_logging")
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Log recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(saveSession.isSaving)
                }
                if saveSession.restoredReview && !saveSession.isSubmitted {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Discard", role: .destructive) { if saveSession.discard() { dismiss() } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: logRecipe) {
                    Label(saveSession.isSaving ? "Saving…" : saveSession.isSubmitted ? "Retry logging" : "Log recipe", systemImage: "plus.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!canLogRecipe || saveSession.isSaving || saveSession.isAccepted)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.row)
                .background(.bar)
                .accessibilityIdentifier("recipe_log_action")
            }
            .interactiveDismissDisabled(saveSession.isSaving)
            .sheet(item: $variationDraft) { draft in CreateRecipeView(initialDraft: draft) }
            .onChange(of: selectedMeal) { _, meal in
                if !saveSession.updateDestination(date: saveSession.date, mealName: meal) { selectedMeal = saveSession.mealName }
            }
            .onChange(of: portionAmountText) { _, _ in refreshReviewFood() }
            .onChange(of: portionUnit) { _, _ in refreshReviewFood() }
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Meal", subtitle: "Choose where this portion belongs on the date above.")
            RecipeLoggingMealPicker(meals: meals, selectedMeal: $selectedMeal)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("recipe_log_meal")
    }

    private var frozenPortionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Amount: \(frozenFood?.servingSize ?? "Saved amount")")
                .appTextRole(.body).monospacedDigit()
                .accessibilityIdentifier("recipe_log_portions")
            if let notes = frozenFood?.sourceMetadata?.notes, !notes.isEmpty {
                Text(notes).appTextRole(.secondary).foregroundStyle(.secondary)
            }
            Text("This review keeps the food and nutrition shown above. Changes to the recipe do not change this saved portion.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("recipe_log_saved_portion")
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Ingredients", subtitle: (recipe.ingredientBasis ?? recipe.nutritionBasis) == .wholeRecipe
                ? "These are whole-recipe amounts. Logged nutrition divides them by the recipe yield, then uses your selected servings."
                : "Adjust the original saved ingredient amounts for this log only. The amount above applies afterward.")
            if ingredients.isEmpty {
                Text("All ingredients were removed.")
                    .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("recipe_log_empty_ingredients")
                restoreSavedPortion
            } else {
                ForEach(ingredients) { ingredient in
                    RecipeLoggingIngredientRow(ingredient: ingredient, onQuantityChange: { quantity in
                        guard let index = ingredients.firstIndex(where: { $0.id == ingredient.id }),
                              let adjusted = RecipeIngredientQuantityRules.adjustedIngredient(ingredients[index], newQuantity: quantity) else { return }
                        ingredients[index] = adjusted
                        ingredientsChanged = true
                        refreshReviewFood()
                    }, onValidityChanged: { valid in
                        if valid { invalidIngredientIDs.remove(ingredient.id) } else {
                            invalidIngredientIDs.insert(ingredient.id)
                        }
                    }, onDelete: {
                        ingredients.removeAll { $0.id == ingredient.id }
                        invalidIngredientIDs.remove(ingredient.id)
                        ingredientsChanged = true
                        refreshReviewFood()
                    })
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_log_ingredients")
    }

    @ViewBuilder
    private var restoreSavedPortion: some View {
        let selection = RecipePortionRules.defaultSelection(for: recipe)
        if let portion = try? RecipePortionRules.foodItem(for: recipe, selection: selection) {
            Button("Restore saved recipe portion") {
                guard saveSession.restartEmptyRecipeReview(with: portion) else { return }
                ingredients = recipe.resolvedIngredientFoods
                ingredientsChanged = false
                invalidIngredientIDs.removeAll()
                portionUnit = selection.unit
                portionAmountText = Self.amountText(for: selection)
                variationError = nil
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .disabled(saveSession.isLocked)
            .accessibilityIdentifier("recipe_log_restore_portion")
        } else {
            Text("Open the recipe editor to review its yield and nutrition.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }
    }

    @discardableResult
    private func refreshReviewFood() -> Bool {
        guard !hasFrozenReview else { return false }
        guard canLogRecipe else { return saveSession.replaceItems([]) }
        let id = saveSession.items.first?.id ?? recipe.id ?? UUID().uuidString
        guard var food = try? RecipePortionRules.foodItem(for: recipe, selection: portionSelection, entryID: id,
            finalNutritionOverride: totalNutrition, ingredientsAdjusted: ingredientsChanged,
            adjustedIngredientFoods: ingredientsChanged ? ingredients : nil) else { return false }
        if ingredientsChanged {
            food.sourceMetadata?.notes = "Ingredient amounts adjusted for this log. " + recipe.nutritionBasisLabel
            food.sourceMetadata?.reviewStatus = .userEdited
        }
        return saveSession.replaceItems([food])
    }

    private func prepareVariation() {
        do {
            if !hasFrozenReview { guard refreshReviewFood() else { throw RecipeIntegrityError.incompleteIngredients } }
            guard let food = saveSession.items.first else { throw RecipeIntegrityError.incompleteIngredients }
            variationDraft = try RecipeVariationRules.variation(from: food)
        } catch { variationError = "The variation needs complete reviewed ingredient amounts. " + error.localizedDescription }
    }

    private func logRecipe() {
        guard canLogRecipe, !saveSession.isSaving, !saveSession.isAccepted else { return }
        if !saveSession.isSubmitted && !saveSession.restoredReview {
            guard refreshReviewFood() else { return }
            guard saveSession.updateDestination(date: saveSession.date, mealName: selectedMeal) else { return }
        }
        saveSession.save(using: dailyLogService) { accepted in
            guard accepted else { return }
            HapticManager.instance.feedback(.medium)
            onLogUpdated()
            dismiss()
        }
    }
}

private struct RecipeLoggingIdentity: View {
    let name: String
    let isSavedReview: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    artwork
                    textBlock
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    artwork
                    textBlock
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "fork.knife")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(FoodEmojiMapper.getEmoji(for: name))
                .font(.system(size: 34))
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .appTextRole(dynamicTypeSize.isAccessibilitySize ? .sectionTitle : .screenTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recipe_log_title")
            Text(isSavedReview ? "Review the saved portion and destination before logging." : "Review the meal destination and ingredient amounts before logging.")
                .appTextRole(dynamicTypeSize.isAccessibilitySize ? .caption : .secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
                .accessibilityIdentifier("recipe_log_subtitle")
        }
    }
}

private struct RecipeLoggingNutrition: View {
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
        .accessibilityIdentifier("recipe_log_nutrition")
    }
}

private struct RecipeLoggingMealPicker: View {
    let meals: [String]
    @Binding var selectedMeal: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(meals, id: \.self) { meal in
                        Button {
                            selectedMeal = meal
                        } label: {
                            Label(
                                meal,
                                systemImage: selectedMeal == meal ? "checkmark" : "fork.knife"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        Text(selectedMeal)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Spacer(minLength: AppSpacing.compact)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(AppPalette.brandText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Meal")
                .accessibilityValue(selectedMeal)
            } else {
                Picker("Meal", selection: $selectedMeal) {
                    ForEach(meals, id: \.self) { meal in
                        Text(meal).tag(meal)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

/// FoodItem equality intentionally means identity throughout the app. Recipe editing
/// needs content equality as well so changing a stable ingredient redraws totals and
/// the existing focused row rather than replacing its identity.
struct RecipeIngredientEditorSnapshot: Equatable {
    let ingredients: [FoodItem]
    private let content: Data?
    init(_ ingredients: [FoodItem]) {
        self.ingredients = ingredients
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        content = try? encoder.encode(ingredients)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let first = lhs.content, let second = rhs.content else { return false }
        return first == second
    }
}

struct RecipeLoggingIngredientRow: View {
    private let ingredientSnapshot: RecipeIngredientEditorSnapshot
    private var ingredient: FoodItem { ingredientSnapshot.ingredients[0] }
    let onQuantityChange: (Double) -> Void
    var onValidityChanged: (Bool) -> Void = { _ in }
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var quantityString: String

    init(
        ingredient: FoodItem,
        onQuantityChange: @escaping (Double) -> Void,
        onValidityChanged: @escaping (Bool) -> Void = { _ in },
        onDelete: @escaping () -> Void
    ) {
        self.ingredientSnapshot = RecipeIngredientEditorSnapshot([ingredient])
        self.onQuantityChange = onQuantityChange
        self.onValidityChanged = onValidityChanged
        self.onDelete = onDelete
        let initialQuantity = ingredient.quantityValue ?? ingredient.servingWeight
        _quantityString = State(
            initialValue: Self.formattedQuantity(initialQuantity > 0 ? initialQuantity : 1)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        ingredientDetails
                        quantityControls
                    }
                } else {
                    HStack(alignment: .center, spacing: AppSpacing.row) {
                        ingredientDetails
                        Spacer(minLength: AppSpacing.row)
                        quantityControls
                    }
                }
            }
            if !isValidQuantity {
                Text("Enter an amount greater than zero.")
                    .appTextRole(.caption).foregroundStyle(AppPalette.caution)
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_log_ingredient_\(ingredient.id)")
        .onChange(of: incomingQuantity, initial: true) { _, amount in
            // A restored parent snapshot can arrive after this stable row creates
            // its local text state. Do not rewrite text being typed for the same
            // numeric amount (including a trailing decimal or extra zeroes).
            guard amount.isFinite, amount > 0,
                  Double(quantityString.replacingOccurrences(of: ",", with: ".")) != amount else { return }
            quantityString = Self.formattedQuantity(amount)
        }
    }

    private var ingredientDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(nutritionSummary)
                .accessibilityIdentifier("recipe_ingredient_nutrition_\(ingredient.id)")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quantityControls: some View {
        HStack(spacing: AppSpacing.compact) {
            TextField("Quantity", text: $quantityString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .appTextRole(.body)
                .frame(minWidth: 64, idealWidth: 72, maxWidth: 92)
                .padding(.horizontal, AppSpacing.compact)
                .frame(minHeight: 44)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .onChange(of: quantityString) { _, newValue in
                    let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                    let valid = Double(normalized).map { $0.isFinite && $0 > 0 } ?? false
                    onValidityChanged(valid)
                    if valid, let newDouble = Double(normalized) {
                        onQuantityChange(newDouble)
                    }
                }
                .accessibilityIdentifier("recipe_ingredient_quantity_\(ingredient.id)")
                .accessibilityLabel("Quantity for \(ingredient.name)")
                .accessibilityValue("\(quantityString) \(unit)")

            Text(unit)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Remove \(ingredient.name)")
        }
    }

    private var incomingQuantity: Double {
        let amount = ingredient.quantityValue ?? ingredient.servingWeight
        return amount > 0 ? amount : 1
    }

    private var unit: String {
        ingredient.servingUnit ?? (ingredient.quantityValue != nil ? "serving" : ingredient.servingWeight > 0 ? "g" : "serving")
    }

    private var isValidQuantity: Bool {
        Double(quantityString.replacingOccurrences(of: ",", with: ".")).map { $0.isFinite && $0 > 0 } ?? false
    }

    private var nutritionSummary: String {
        let calories = Int(ingredient.calories.rounded()).formatted()
        let protein = Int(ingredient.protein.rounded()).formatted()
        let carbs = Int(ingredient.carbs.rounded()).formatted()
        let fats = Int(ingredient.fats.rounded()).formatted()
        return "\(calories) cal · P \(protein) g · C \(carbs) g · F \(fats) g"
    }

    static func formattedQuantity(_ quantity: Double) -> String {
        // Editable text must round-trip the stored value. Group separators or a
        // display-only precision cap can turn recovery into an unintended edit.
        let text = String(quantity)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
