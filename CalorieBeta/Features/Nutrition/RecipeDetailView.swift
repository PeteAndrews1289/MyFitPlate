import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss
    @State private var showingAddToLogSheet = false
    @State private var showingAddToPlanSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {
                    RecipeHeroCard(recipe: recipe)
                    RecipeMacroGrid(nutrition: recipe.nutrition)
                    RecipeIngredientsCard(ingredients: recipe.ingredients)
                    RecipeInstructionsCard(instructions: recipe.instructions)
                    RecipeNutrientDetailsCard(nutrition: recipe.nutrition)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 96)
            }

            RecipeDetailActionBar(
                onPlan: { showingAddToPlanSheet = true },
                onLog: { showingAddToLogSheet = true }
            )
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddToLogSheet) {
            if let _ = recipe.detailedIngredients {
                RecipeLoggingView(
                    recipe: recipe,
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: dailyLogService.activelyViewedDate,
                    onLogUpdated: { showingAddToLogSheet = false }
                )
            } else {
                AddFoodView(
                    initialFoodItem: recipeService.recipeToFoodItem(recipe: recipe),
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: dailyLogService.activelyViewedDate,
                    source: "recipe_detail",
                    onLogUpdated: {
                        showingAddToLogSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddToPlanSheet) {
            AddRecipeToPlanSheet(recipe: recipe)
                .environmentObject(recipeService)
                .environmentObject(mealPlannerService)
        }
    }
}

private struct RecipeHeroCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .appFont(size: 38)
                .frame(width: 68, height: 68)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(recipe.name)
                    .appFont(size: 25, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    RecipeHeroChip(icon: "list.bullet", text: "\(recipe.ingredients.count) ingredients")
                    RecipeHeroChip(icon: "text.badge.checkmark", text: "\(recipe.instructions.count) steps")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RecipeHeroChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .appFont(size: 11, weight: .bold)
            .foregroundColor(.brandPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.brandPrimary.opacity(0.10), in: Capsule())
    }
}

private struct RecipeMacroGrid: View {
    let nutrition: Nutrition

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            RecipeMacroTile(title: "Calories", value: "\(Int(nutrition.calories.rounded()))", unit: "cal", icon: "flame.fill", color: .orange)
            RecipeMacroTile(title: "Protein", value: "\(Int(nutrition.protein.rounded()))", unit: "g", icon: "bolt.fill", color: .accentProtein)
            RecipeMacroTile(title: "Carbs", value: "\(Int(nutrition.carbs.rounded()))", unit: "g", icon: "leaf.fill", color: .accentCarbs)
            RecipeMacroTile(title: "Fat", value: "\(Int(nutrition.fats.rounded()))", unit: "g", icon: "drop.fill", color: .accentFats)
        }
    }
}

private struct RecipeMacroTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(unit)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecipeIngredientsCard: View {
    let ingredients: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecipeSectionHeader(title: "Ingredients", icon: "basket.fill")

            VStack(spacing: 8) {
                ForEach(ingredients, id: \.self) { ingredient in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .padding(.top, 1)

                        Text(ingredient)
                            .appFont(size: 14, weight: .medium)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecipeInstructionsCard: View {
    let instructions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecipeSectionHeader(title: "Instructions", icon: "text.badge.checkmark")

            VStack(spacing: 10) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.brandPrimary, in: Circle())

                        Text(instruction)
                            .appFont(size: 14, weight: .medium)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecipeNutrientDetailsCard: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup {
                VStack(spacing: 8) {
                    nutrientRow(label: "Saturated Fat", value: nutrition.saturatedFat)
                    nutrientRow(label: "Polyunsaturated Fat", value: nutrition.polyunsaturatedFat)
                    nutrientRow(label: "Monounsaturated Fat", value: nutrition.monounsaturatedFat)
                    nutrientRow(label: "Fiber", value: nutrition.fiber)
                    nutrientRow(label: "Calcium", value: nutrition.calcium, unit: "mg")
                    nutrientRow(label: "Iron", value: nutrition.iron, unit: "mg")
                    nutrientRow(label: "Potassium", value: nutrition.potassium, unit: "mg")
                    nutrientRow(label: "Sodium", value: nutrition.sodium, unit: "mg")
                    nutrientRow(label: "Vitamin A", value: nutrition.vitaminA, unit: "mcg")
                    nutrientRow(label: "Vitamin C", value: nutrition.vitaminC, unit: "mg")
                    nutrientRow(label: "Vitamin D", value: nutrition.vitaminD, unit: "mcg")
                    nutrientRow(label: "Vitamin B12", value: nutrition.vitaminB12, unit: "mcg")
                    nutrientRow(label: "Folate", value: nutrition.folate, unit: "mcg")
                }
                .padding(.top, 8)
            } label: {
                RecipeSectionHeader(title: "More Nutrition", icon: "chart.bar.doc.horizontal.fill")
            }
        }
        .tint(.brandPrimary)
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String = "g") -> some View {
        if let value, value > 0 {
            HStack {
                Text(label)
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(.textPrimary)

                Spacer()

                Text("\(String(format: "%.1f", value)) \(unit)")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
    }
}

private struct RecipeSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
        }
    }
}

private struct RecipeDetailActionBar: View {
    let onPlan: () -> Void
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onPlan()
            } label: {
                Label("Plan", systemImage: "calendar.badge.plus")
                    .appFont(size: 16, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .foregroundColor(.brandPrimary)
            .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.brandPrimary.opacity(0.22), lineWidth: 1)
            )
            .buttonStyle(.plain)

            Button {
                onLog()
            } label: {
                Label("Add to Log", systemImage: "plus.circle.fill")
                    .appFont(size: 16, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .foregroundColor(.white)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.backgroundPrimary.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }
}

private struct AddRecipeToPlanSheet: View {
    let recipe: Recipe

    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var mealPlannerService: MealPlannerService
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
                VStack(spacing: 16) {
                    AddRecipeToPlanHero(recipe: recipe)

                    VStack(alignment: .leading, spacing: 14) {
                        RecipeSectionHeader(title: "Schedule", icon: "calendar")

                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(.brandPrimary)

                        AddRecipeMealTypePicker(
                            mealTypes: mealTypes,
                            selectedMealType: $selectedMealType
                        )
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if selectedMealCount > 0 {
                        AddRecipePlanModeCard(
                            mealType: selectedMealType,
                            mealCount: selectedMealCount,
                            replaceExistingMealType: $replaceExistingMealType
                        )
                    }

                    RecipeMacroGrid(nutrition: recipe.nutrition)
                }
                .padding(16)
                .padding(.bottom, 86)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Add to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    saveToPlan()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color.backgroundPrimary.opacity(0.98).ignoresSafeArea(edges: .bottom))
            }
            .task {
                await loadExistingPlan()
            }
            .onChange(of: selectedDate) { _, _ in
                Task { await loadExistingPlan() }
            }
            .onChange(of: selectedMealType) { _, _ in
                if selectedMealCount == 0 {
                    replaceExistingMealType = false
                }
            }
            .alert("Could not add recipe", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func loadExistingPlan() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        existingPlan = await mealPlannerService.fetchPlan(for: selectedDate, userID: userID)
    }

    private func saveToPlan() {
        guard !isSaving else { return }
        guard let userID = Auth.auth().currentUser?.uid else {
            alertMessage = "You need to be signed in to update a meal plan."
            return
        }

        isSaving = true

        Task { @MainActor in
            var plan = await mealPlannerService.fetchPlan(for: selectedDate, userID: userID) ?? emptyPlan(for: selectedDate)
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
        return MealPlanDay(id: mealPlanID(for: startOfDay), date: Timestamp(date: startOfDay), meals: [])
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
}

private struct AddRecipeToPlanHero: View {
    let recipe: Recipe

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(FoodEmojiMapper.getEmoji(for: recipe.name))
                .appFont(size: 34)
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.name)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Choose where this recipe should appear in your plan.")
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AddRecipeMealTypePicker: View {
    let mealTypes: [String]
    @Binding var selectedMealType: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(mealTypes, id: \.self) { mealType in
                Button {
                    selectedMealType = mealType
                    HapticManager.instance.feedback(.light)
                } label: {
                    Text(mealType)
                        .appFont(size: 13, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundColor(selectedMealType == mealType ? .brandPrimary : Color(UIColor.secondaryLabel))
                        .background(
                            selectedMealType == mealType ? Color.brandPrimary.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AddRecipePlanModeCard: View {
    let mealType: String
    let mealCount: Int
    @Binding var replaceExistingMealType: Bool

    private var mealLabel: String {
        mealCount == 1 ? "meal" : "meals"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(mealType) already has \(mealCount) \(mealLabel)")
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.textPrimary)

            Picker("Add mode", selection: $replaceExistingMealType) {
                Text("Add Alongside").tag(false)
                Text("Replace Slot").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
