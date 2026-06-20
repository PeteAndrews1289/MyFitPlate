import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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
                        VStack(spacing: 16) {
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

                            AddMealRecipeSearchField(searchText: $searchText)

                            if filteredRecipes.isEmpty {
                                AddMealNoMatchesState(searchText: searchText)
                            } else {
                                VStack(spacing: 12) {
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
                        .padding(16)
                        .padding(.bottom, 18)
                    }
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Add Meal")
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
            .alert("Could not add meal", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func loadContext() async {
        await recipeService.fetchUserRecipes()
        await loadExistingPlan()
    }

    private func loadExistingPlan() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        existingPlan = await mealPlannerService.fetchPlan(for: date, userID: userID)
    }

    private func addRecipeToPlan(_ recipe: Recipe) {
        guard savingRecipeKey == nil else { return }
        guard let userID = Auth.auth().currentUser?.uid else {
            alertMessage = "You need to be signed in to update a meal plan."
            return
        }

        let key = recipeKey(for: recipe)
        savingRecipeKey = key

        Task { @MainActor in
            var plan = await mealPlannerService.fetchPlan(for: date, userID: userID) ?? emptyPlan(for: date)
            if replaceExistingMealType {
                plan.meals.removeAll { mealTypeMatches($0.mealType, selectedMealType) }
            }
            plan.meals.append(plannedMeal(from: recipe))
            plan.meals.sort(by: sortMeals)
            existingPlan = plan

            await mealPlannerService.savePlan(plan, for: userID)
            await mealPlannerService.refreshGroceryList(for: userID)
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
            date: Timestamp(date: startOfDay),
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

private struct AddMealToPlanHero: View {
    let date: Date
    let onCreate: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a Saved Recipe")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text(dateText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.brandPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create recipe")
            }

            Text("Choose a slot, then add a recipe to this day's plan. You can still regenerate meals around it later.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct AddMealTypePicker: View {
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
                        .font(.system(size: 13, weight: .bold))
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
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mealType) already has \(mealCount) \(mealLabel)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("Add another recipe to this slot, or replace the current \(mealType.lowercased()) plan.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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

private struct AddMealRecipeSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandPrimary)

            TextField("Search recipes or ingredients...", text: $searchText)
                .textInputAutocapitalization(.words)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear recipe search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
                .font(.system(size: 27))
                .frame(width: 50, height: 50)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text("\(recipe.ingredients.count) ingredients")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Text("Cal \(Int(recipe.nutrition.calories.rounded()))  P \(Int(recipe.nutrition.protein.rounded()))g  C \(Int(recipe.nutrition.carbs.rounded()))g  F \(Int(recipe.nutrition.fats.rounded()))g")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)

            Button(action: onAdd) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 42, height: 42)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                }
            }
            .background(Color.brandPrimary, in: Circle())
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel("Add \(recipe.name) to \(mealType)")
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AddMealToPlanLoadingState: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Loading recipes")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("Getting your saved meals ready to add.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
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
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.brandPrimary)
                .frame(width: 76, height: 76)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 5) {
                Text("No saved recipes yet")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text("Create recipes first, then come back here to place them into a meal plan.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Create Recipe", action: onCreate)
                .buttonStyle(PrimaryButtonStyle())
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No matching recipes")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
