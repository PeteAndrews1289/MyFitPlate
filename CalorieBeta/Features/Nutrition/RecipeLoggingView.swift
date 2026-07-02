import SwiftUI

struct RecipeLoggingView: View {
    let recipe: Recipe
    @Binding var dailyLog: DailyLog?
    let date: Date
    let onLogUpdated: () -> Void

    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss

    @State private var ingredients: [FoodItem] = []
    @State private var selectedMeal: String = "Breakfast"
    let meals = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    init(recipe: Recipe, dailyLog: Binding<DailyLog?>, date: Date, onLogUpdated: @escaping () -> Void) {
        self.recipe = recipe
        self._dailyLog = dailyLog
        self.date = date
        self.onLogUpdated = onLogUpdated
        self._ingredients = State(initialValue: recipe.detailedIngredients ?? [])
    }

    private var totalNutrition: Nutrition {
        ingredients.reduce(Nutrition.zero) { partialResult, item in
            return Nutrition(
                calories: partialResult.calories + item.calories,
                protein: partialResult.protein + item.protein,
                carbs: partialResult.carbs + item.carbs,
                fats: partialResult.fats + item.fats
            )
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        RecipeLoggingHero(recipe: recipe, nutrition: totalNutrition)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Meal").appFont(size: 16, weight: .bold).foregroundColor(.textPrimary)
                            Picker("Meal", selection: $selectedMeal) {
                                ForEach(meals, id: \.self) { meal in
                                    Text(meal).tag(meal)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Ingredients")
                                    .appFont(size: 18, weight: .bold)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text("\(ingredients.count.formatted()) ingredients")
                                    .appFont(size: 12)
                                    .foregroundColor(.secondary)
                            }
                            
                            ForEach(ingredients) { item in
                                RecipeLoggingIngredientRow(
                                    ingredient: item,
                                    onQuantityChange: { newQuantity in
                                        updateQuantity(for: item, newQuantity: newQuantity)
                                    },
                                    onDelete: {
                                        deleteIngredient(item)
                                    }
                                )
                                .padding(.vertical, 8)
                                .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 16)
                }

                Button("Log recipe") {
                    logRecipe()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Log recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func updateQuantity(for item: FoodItem, newQuantity: Double) {
        guard let index = ingredients.firstIndex(where: { $0.id == item.id }) else { return }
        
        let oldQuantity = ingredients[index].quantityValue ?? 1.0
        let ratio = newQuantity / oldQuantity
        
        ingredients[index].quantityValue = newQuantity
        ingredients[index].calories *= ratio
        ingredients[index].protein *= ratio
        ingredients[index].carbs *= ratio
        ingredients[index].fats *= ratio
    }

    private func deleteIngredient(_ item: FoodItem) {
        ingredients.removeAll { $0.id == item.id }
        HapticManager.instance.feedback(.light)
    }

    private func logRecipe() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        // We log the recipe as a single FoodItem, but its macros reflect the edited ingredients
        let loggedItem = FoodItem(
            id: UUID().uuidString,
            name: recipe.name,
            calories: totalNutrition.calories,
            protein: totalNutrition.protein,
            carbs: totalNutrition.carbs,
            fats: totalNutrition.fats,
            servingSize: "1 recipe",
            servingWeight: 0,
            timestamp: Date(),
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recipe,
                confidence: .userVerified,
                reviewStatus: .notRequired,
                sourceName: "Recipe",
                sourceID: recipe.id
            )
        )

        dailyLogService.addFoodToLog(for: userID, date: self.date, mealName: selectedMeal, foodItem: loggedItem, source: "recipe")
        HapticManager.instance.feedback(.medium)
        onLogUpdated()
        dismiss()
    }
}

private struct RecipeLoggingHero: View {
    let recipe: Recipe
    let nutrition: Nutrition

    var body: some View {
        VStack(spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .appFont(size: 48)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())

            Text(recipe.name)
                .appFont(size: 24, weight: .bold)
                .foregroundColor(.textPrimary)

            HStack(spacing: 16) {
                MacroPill(title: "Calories", value: Int(nutrition.calories.rounded()), color: .orange)
                MacroPill(title: "Protein", value: Int(nutrition.protein.rounded()), color: .accentProtein)
                MacroPill(title: "Carbs", value: Int(nutrition.carbs.rounded()), color: .accentCarbs)
                MacroPill(title: "Fat", value: Int(nutrition.fats.rounded()), color: .accentFats)
            }
        }
    }
}

private struct MacroPill: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .appFont(size: 10, weight: .medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecipeLoggingIngredientRow: View {
    let ingredient: FoodItem
    let onQuantityChange: (Double) -> Void
    let onDelete: () -> Void
    
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
        _quantityString = State(initialValue: initialQuantity > 0 ? String(format: "%.1f", initialQuantity) : "1")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)
                
                Text("\(Int(ingredient.calories.rounded()).formatted()) cal | P \(Int(ingredient.protein.rounded()).formatted()) g  C \(Int(ingredient.carbs.rounded()).formatted()) g  F \(Int(ingredient.fats.rounded()).formatted()) g")
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            TextField("Qty", text: $quantityString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .padding(6)
                .background(Color.backgroundPrimary)
                .cornerRadius(6)
                .onChange(of: quantityString) { _, newValue in
                    if let newDouble = Double(newValue) {
                        onQuantityChange(newDouble)
                    }
                }
            
            Text(ingredient.servingUnit ?? "g")
                .appFont(size: 14, weight: .medium)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(ingredient.name)")
        }
        .padding(12)
    }
}
