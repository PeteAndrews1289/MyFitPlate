import SwiftUI

struct RecipeLoggingView: View {
    let recipe: Recipe
    @Binding var dailyLog: DailyLog?
    let date: Date
    let onLogUpdated: () -> Void

    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss

    @State private var ingredients: [FoodItem]
    @State private var selectedMeal = "Breakfast"

    private let meals = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    init(
        recipe: Recipe,
        dailyLog: Binding<DailyLog?>,
        date: Date,
        onLogUpdated: @escaping () -> Void
    ) {
        self.recipe = recipe
        _dailyLog = dailyLog
        self.date = date
        self.onLogUpdated = onLogUpdated
        _ingredients = State(initialValue: recipe.detailedIngredients ?? [])
    }

    private var totalNutrition: Nutrition {
        guard recipe.detailedIngredients != nil else { return recipe.nutrition }
        return Nutrition.total(for: ingredients)
    }

    private var canLogRecipe: Bool {
        recipe.detailedIngredients == nil || !ingredients.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    RecipeLoggingIdentity(recipe: recipe)
                    RecipeLoggingNutrition(nutrition: totalNutrition)
                    mealSection
                    ingredientSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .accessibilityIdentifier("recipe_logging")
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Log Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: logRecipe) {
                    Label("Log Recipe", systemImage: "plus.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!canLogRecipe)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("recipe_log_action")
            }
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Meal",
                subtitle: "Choose where this recipe belongs in today's log."
            )
            RecipeLoggingMealPicker(
                meals: meals,
                selectedMeal: $selectedMeal
            )
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_log_meal")
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Ingredients",
                subtitle: ingredients.isEmpty
                    ? "At least one ingredient is required to log this editable recipe."
                    : "Adjust amounts before logging. Nutrition updates immediately."
            )

            if ingredients.isEmpty {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("All ingredients were removed. Cancel or reopen the recipe to restore its saved ingredients.")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appSurface(.quiet)
                .accessibilityIdentifier("recipe_log_empty_ingredients")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        RecipeLoggingIngredientRow(
                            ingredient: ingredient,
                            onQuantityChange: { newQuantity in
                                updateQuantity(for: ingredient, newQuantity: newQuantity)
                            },
                            onDelete: { deleteIngredient(ingredient) }
                        )

                        if index < ingredients.count - 1 {
                            Divider()
                                .padding(.leading, AppSpacing.group)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_log_ingredients")
    }

    private func updateQuantity(for item: FoodItem, newQuantity: Double) {
        guard let index = ingredients.firstIndex(where: { $0.id == item.id }),
              let adjusted = RecipeIngredientQuantityRules.adjustedIngredient(
                  ingredients[index],
                  newQuantity: newQuantity
              ) else {
            return
        }
        ingredients[index] = adjusted
    }

    private func deleteIngredient(_ item: FoodItem) {
        ingredients.removeAll { $0.id == item.id }
        HapticManager.instance.feedback(.light)
    }

    private func logRecipe() {
        guard canLogRecipe else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        let loggedItem = FoodItem(
            id: UUID().uuidString,
            name: recipe.name,
            calories: totalNutrition.calories,
            protein: totalNutrition.protein,
            carbs: totalNutrition.carbs,
            fats: totalNutrition.fats,
            saturatedFat: totalNutrition.saturatedFat,
            polyunsaturatedFat: totalNutrition.polyunsaturatedFat,
            monounsaturatedFat: totalNutrition.monounsaturatedFat,
            fiber: totalNutrition.fiber,
            servingSize: "1 recipe",
            servingWeight: 0,
            timestamp: Date(),
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recipe,
                confidence: .userVerified,
                reviewStatus: .notRequired,
                sourceName: "Recipe",
                sourceID: recipe.id
            ),
            calcium: totalNutrition.calcium,
            iron: totalNutrition.iron,
            potassium: totalNutrition.potassium,
            sodium: totalNutrition.sodium,
            vitaminA: totalNutrition.vitaminA,
            vitaminC: totalNutrition.vitaminC,
            vitaminD: totalNutrition.vitaminD,
            vitaminB12: totalNutrition.vitaminB12,
            folate: totalNutrition.folate,
            magnesium: totalNutrition.magnesium,
            phosphorus: totalNutrition.phosphorus,
            zinc: totalNutrition.zinc,
            copper: totalNutrition.copper,
            manganese: totalNutrition.manganese,
            selenium: totalNutrition.selenium,
            vitaminB1: totalNutrition.vitaminB1,
            vitaminB2: totalNutrition.vitaminB2,
            vitaminB3: totalNutrition.vitaminB3,
            vitaminB5: totalNutrition.vitaminB5,
            vitaminB6: totalNutrition.vitaminB6,
            vitaminE: totalNutrition.vitaminE,
            vitaminK: totalNutrition.vitaminK
        )

        dailyLogService.addFoodToLog(
            for: userID,
            date: date,
            mealName: selectedMeal,
            foodItem: loggedItem,
            source: "recipe"
        )
        HapticManager.instance.feedback(.medium)
        onLogUpdated()
        dismiss()
    }
}

private struct RecipeLoggingIdentity: View {
    let recipe: Recipe

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
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .font(.system(size: 34))
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .appTextRole(dynamicTypeSize.isAccessibilitySize ? .sectionTitle : .screenTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recipe_log_title")
            Text("Review the meal destination and ingredient amounts before logging.")
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
                accent: .orange
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
                            .foregroundStyle(AppPalette.brand)
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

private struct RecipeLoggingIngredientRow: View {
    let ingredient: FoodItem
    let onQuantityChange: (Double) -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var quantityString: String

    init(
        ingredient: FoodItem,
        onQuantityChange: @escaping (Double) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.ingredient = ingredient
        self.onQuantityChange = onQuantityChange
        self.onDelete = onDelete
        let initialQuantity = ingredient.quantityValue ?? ingredient.servingWeight
        _quantityString = State(
            initialValue: Self.formattedQuantity(initialQuantity > 0 ? initialQuantity : 1)
        )
    }

    var body: some View {
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
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityIdentifier("recipe_log_ingredient_\(ingredient.id)")
    }

    private var ingredientDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(nutritionSummary)
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
                    if let newDouble = Double(normalized) {
                        onQuantityChange(newDouble)
                    }
                }
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

    private var unit: String {
        ingredient.servingUnit ?? "g"
    }

    private var nutritionSummary: String {
        let calories = Int(ingredient.calories.rounded()).formatted()
        let protein = Int(ingredient.protein.rounded()).formatted()
        let carbs = Int(ingredient.carbs.rounded()).formatted()
        let fats = Int(ingredient.fats.rounded()).formatted()
        return "\(calories) cal · P \(protein) g · C \(carbs) g · F \(fats) g"
    }

    private static func formattedQuantity(_ quantity: Double) -> String {
        quantity.formatted(.number.precision(.fractionLength(quantity.rounded() == quantity ? 0 : 1)))
    }
}
