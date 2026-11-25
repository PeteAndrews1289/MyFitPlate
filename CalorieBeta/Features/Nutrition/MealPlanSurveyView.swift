import MyFitPlateCore
import SwiftUI

struct MealPlanSurveyView: View {
    let startingDate: Date
    @EnvironmentObject private var goals: GoalSettings
    @EnvironmentObject private var planner: MealPlannerService
    @EnvironmentObject private var recipes: RecipeService
    @Environment(\.dismiss) private var dismiss
    @State private var source = 0
    @State private var practicalEnabled = true
    @State private var weekBrief = MealPlanningWeekBrief()
    @State private var diet: PlanningDiet = .unrestricted
    @State private var exclusions = ""
    @State private var equipment = ""
    @State private var minutes = ""
    @State private var budget = ""
    @State private var household = 1
    @State private var tolerance = 0.20
    @State private var proteinMinimum = true
    @State private var keepExisting = true
    @State private var preferences = "Chicken, rice, broccoli, yogurt, fruit"
    @State private var isLoading = false
    @State private var generationError: String?
    @State private var draft: MealPlanWeekDraft?
    @State private var generationTask: Task<Void, Never>?
    @State private var briefReady = false
    @State private var briefUnreadable = false
    @State private var briefOwner: String?
    @State private var editingRecipe: Recipe?
    init(initialStep: Int = 0, startingDate: Date = Date()) {
        self.startingDate = Calendar.current.startOfDay(for: startingDate)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Picker("Build from", selection: $source) {
                            Text("Saved recipes").tag(0)
                            Text("Maia ideas").tag(1)
                        }.pickerStyle(.segmented).accessibilityIdentifier("planner_generation_source")
                        Text(source == 0 ? "Plan with your recipes and prepared portions." : "Explore new meals with estimated nutrition.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        DisclosureGroup("About this plan") {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text("Review one brief, then approve the week. Existing meals stay locked unless you choose otherwise.")
                                Text(source == 0 ? "Uses your saved recipe quantities and nutrition. Restrictions need current personal ingredient reviews. Prepared portions use recorded amounts and best-before dates."
                                     : "Maia drafts new ideas with estimated nutrition. Cooking-day schedules, repeated batches and prepared-stock choices apply to Saved recipes. Unknown ingredients, costs or prep times cannot pass strict limits.")
                            }
                            .appTextRole(.caption).foregroundStyle(.secondary)
                            .padding(.top, AppSpacing.compact)
                        }
                        .appTextRole(.secondary)
                    }
                }
                if source == 0 {
                    practicalWeekSection
                    recipeReadinessSection
                }
                Section("Daily nutrition") {
                    Text("\(Int(goals.calories ?? 2_000)) cal · \(Int(goals.protein)) g protein · \(Int(goals.carbs)) g carbs · \(Int(goals.fats)) g fat")
                        .appTextRole(.control)
                    Picker("Calorie flexibility", selection: $tolerance) {
                        Text("±10%").tag(0.10); Text("±20%").tag(0.20); Text("±30%").tag(0.30)
                    }
                    Toggle("At least 85% of protein target each day", isOn: $proteinMinimum)
                    Text("Carbs and fats are reviewed alongside calories. Your saved goals stay unchanged.").appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Cooking brief") {
                    Stepper("Cook for \(household) original portion\(household == 1 ? "" : "s")", value: $household, in: 1...12)
                        .accessibilityIdentifier("planner_household_portions")
                    Text(practicalEnabled && source == 0
                        ? "New batches cook at least this many original recipe portions, expanding to cover planned repeats. Personal portions stay separate; extra portions remain unallocated. Planning never marks food cooked or eaten."
                        : "Your personal meal stays one selected recipe portion. Extra cooking portions remain unallocated for your household or future leftover plans; they are not marked cooked or eaten.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    TextField("Maximum prep minutes · optional", text: $minutes).keyboardType(.numberPad)
                    TextField("Equipment · stove, oven, or no cooking", text: $equipment)
                    TextField("Weekly cooking budget in USD · optional", text: $budget).keyboardType(.decimalPad)
                    Text("Budget includes the full cooking quantity using your recipe price estimates. Unknown prices block a requested budget.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Ingredients") {
                    if let saved = goals.effectiveMealConstraintProfile, saved.hasRestrictions {
                        Text("Saved constraints: " + saved.diet.title + (saved.hardExclusions.isEmpty ? "" : " · " + saved.hardExclusions.joined(separator: ", ")))
                            .appTextRole(.secondary)
                        Text("The choices below can add limits. Change your account-wide exclusions in Food preferences.").appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Ingredient pattern", selection: $diet) { ForEach(PlanningDiet.allCases) { Text($0.title).tag($0) } }
                    TextField("Exclude ingredients · comma separated", text: $exclusions).accessibilityIdentifier("planner_generation_exclusions")
                    Text("Exclusions require a personal review of every selected recipe. This does not establish allergen or cross-contact safety.").appTextRole(.caption).foregroundStyle(.secondary)
                    if source == 1 { TextField("Foods and cuisines you prefer", text: $preferences) }
                }
                Section("Current plan") {
                    Toggle("Keep existing meal slots locked", isOn: $keepExisting)
                    Text("Stock is reconciled in Shop after review. Planning never deducts pantry or cooked food.").appTextRole(.caption).foregroundStyle(.secondary)
                }
            }.appFormStyle()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Plan your week").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { generationTask?.cancel(); dismiss() }.disabled(isLoading) } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let generationError {
                        Text(generationError).appTextRole(.secondary)
                            .foregroundStyle(AppPalette.caution)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("meal_plan_generation_error")
                    }
                    Button(isLoading ? "Building and checking…" : "Build review draft") { generate() }
                        .buttonStyle(AppActionButtonStyle(.primary)).disabled(isLoading)
                        .accessibilityIdentifier("meal_plan_generate_plan")
                }.padding().background(AppPalette.canvas)
            }
            .sheet(item: $draft) { draft in MealPlanDraftReviewView(draft: draft) { dismiss() } }
            .sheet(item: $editingRecipe, onDismiss: { Task { await recipes.fetchUserRecipes() } }) { recipe in
                CreateRecipeView(recipeToEdit: recipe, planningDetailsInitiallyExpanded: true)
            }
            .task { restoreBrief(); await recipes.fetchUserRecipes() }
            .onChange(of: briefData) { _, _ in keepBrief() }
            .onDisappear { generationTask?.cancel() }
        }
        .interactiveDismissDisabled(isLoading)
        .accessibilityIdentifier("meal_plan_survey_screen")
    }
    private var preflightConstraints: MealPlanConstraints {
        var c = MealPlanConstraints(calories: goals.calories ?? 2_000, protein: goals.protein, carbs: goals.carbs, fats: goals.fats)
        c.ingredientProfile = goals.effectiveMealConstraintProfile; c.diet = diet; c.exclusions = list(exclusions)
        c.availableEquipment = list(equipment); c.maxPrepMinutes = Int(minutes); c.weeklyBudget = Double(budget)
        c.practicalWeek = practicalEnabled ? weekBrief : nil
        return c
    }
    private var recipeReadinessSection: some View {
        let readiness = MealPlanningPreflight.recipes(recipes.userRecipes, constraints: preflightConstraints)
        return Section("Recipe readiness") {
            Text("\(readiness.filter(\.usable).count) of \(readiness.count) saved recipes ready for this brief")
                .appTextRole(.control).accessibilityIdentifier("planner_recipe_readiness")
            Text("Ready recipes still need to fit each slot's portion, protein and cooking allowance. Missing slots remain explicit in the review; no restrictions are changed automatically.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            ForEach(readiness.filter { !$0.usable }) { item in
                DisclosureGroup(item.name) {
                    ForEach(item.issues, id: \.self) { Text($0).appTextRole(.secondary) }
                    Button("Review recipe details") {
                        editingRecipe = recipes.userRecipes.first { ($0.id ?? $0.name) == item.id }
                    }.accessibilityIdentifier("planner_repair_recipe_\(item.id)")
                }
            }
            if readiness.isEmpty { Text("Save a recipe with confirmed portions and nutrition to use it here.").appTextRole(.secondary) }
        }
    }
    private var practicalWeekSection: some View {
        Section("Your actual week") {
            Toggle("Plan around cooking days", isOn: $practicalEnabled)
                .accessibilityIdentifier("planner_practical_week")
            if practicalEnabled {
                DisclosureGroup("Meals to plan · \(weekBrief.mealTypes.count) selected") {
                    ForEach(MealPlanEditingRules.mealTypes, id: \.self) { slot in
                        Toggle(slot, isOn: Binding(get: { weekBrief.mealTypes.contains(slot) }, set: { enabled in
                            weekBrief.mealTypes.removeAll { $0 == slot }
                            if enabled { weekBrief.mealTypes.append(slot) }
                        })).accessibilityIdentifier("planner_slot_\(slot.lowercased())")
                    }
                }
                Toggle("Repeat meals from one batch", isOn: $weekBrief.repeatMeals)
                    .accessibilityIdentifier("planner_repeat_meals")
                Toggle("Use verified prepared portions", isOn: $weekBrief.usePreparedStock)
                    .accessibilityIdentifier("planner_use_prepared_stock")
                DisclosureGroup("Cooking days and open meals") {
                    Button("Use two cooking days") {
                        weekBrief.days = (0..<7).map { offset in
                            var day = weekBrief.days.first { $0.offset == offset } ?? .init(offset: offset)
                            day.cookingMinutes = [0, 3].contains(offset) ? 90 : 0
                            return day
                        }
                    }.accessibilityIdentifier("planner_two_cooking_days")
                    ForEach($weekBrief.days) { $day in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            let date = Calendar.current.date(byAdding: .day, value: day.offset, to: startingDate) ?? startingDate
                            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).appTextRole(.control)
                            Stepper(day.cookingMinutes == 0 ? "No cooking" : "Up to \(day.cookingMinutes) min", value: $day.cookingMinutes, in: 0...480, step: 15)
                                .accessibilityIdentifier("planner_cooking_day_\(day.offset)")
                            Menu {
                                ForEach(MealPlanEditingRules.mealTypes, id: \.self) { slot in
                                    Button {
                                        if day.openMealTypes.contains(slot) { day.openMealTypes.removeAll { $0 == slot } } else { day.openMealTypes.append(slot) }
                                    } label: {
                                        Label(slot, systemImage: day.openMealTypes.contains(slot) ? "checkmark" : "plus")
                                    }
                                    .accessibilityLabel(slot)
                                }
                            } label: {
                                Text(day.openMealTypes.isEmpty ? "Leave a meal open" : "Open: " + day.openMealTypes.joined(separator: ", "))
                                    .appTextRole(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.borderless).accessibilityIdentifier("planner_open_meals_\(day.offset)")
                        }.padding(.vertical, AppSpacing.compact)
                    }
                }
                Text("Leave restaurant meals or flexible slots open. Nutrition checks cover selected slots; existing meals remain locked. Repeats stay within three days of their planned cooking date. Actual storage and freshness still need your review.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var brief: MealPlanningBrief {
        .init(source: source, diet: diet, exclusions: exclusions, equipment: equipment, minutes: minutes, budget: budget,
            household: household, tolerance: tolerance, proteinMinimum: proteinMinimum, keepExisting: keepExisting, preferences: preferences,
            practicalWeek: practicalEnabled ? weekBrief : nil)
    }
    private var briefData: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(brief)
    }
    private func restoreBrief() {
        guard !briefReady else { return }
        briefOwner = DIContainer.shared.authService.currentUserID
        defer { briefReady = true }
        guard let owner = briefOwner else { return }
        do {
            guard let value = try EditorDraftStore().load(MealPlanningBrief.self, userID: owner, scope: "meal-planning-brief")?.value else { return }
            source = value.source; diet = value.diet; exclusions = value.exclusions; equipment = value.equipment
            minutes = value.minutes; budget = value.budget; household = value.household; tolerance = value.tolerance
            proteinMinimum = value.proteinMinimum; keepExisting = value.keepExisting; preferences = value.preferences
            practicalEnabled = value.practicalWeek != nil; weekBrief = value.practicalWeek ?? .init()
        } catch { briefUnreadable = true; generationError = "Your earlier planning brief couldn't be opened and has been kept. No plan has changed." }
    }
    private func keepBrief() {
        guard briefReady, !briefUnreadable, let owner = briefOwner, DIContainer.shared.authService.currentUserID == owner else { return }
        do { try EditorDraftStore().save(brief, userID: owner, scope: "meal-planning-brief") } catch { generationError = "Couldn't keep this brief on the device. Your plan is unchanged." }
    }
    private func generate() {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == briefOwner, !briefUnreadable else { return }
        let pending = MealPlanWeekSaveSession(userID: owner)
        if let saved = pending.checkpoint?.draft { draft = saved; return }
        generationError = nil
        var constraints = MealPlanConstraints(calories: goals.calories ?? 2_000, protein: goals.protein, carbs: goals.carbs, fats: goals.fats)
        constraints.ingredientProfile = goals.effectiveMealConstraintProfile
        constraints.diet = diet; constraints.exclusions = list(exclusions); constraints.availableEquipment = list(equipment)
        constraints.householdPortions = Double(household); constraints.calorieTolerance = tolerance; constraints.enforceProtein = proteinMinimum
        let rawMinutes = minutes.trimmingCharacters(in: .whitespaces), rawBudget = budget.trimmingCharacters(in: .whitespaces)
        guard rawMinutes.isEmpty || Int(rawMinutes) != nil, rawBudget.isEmpty || Double(rawBudget) != nil else {
            generationError = "Enter valid prep minutes and a budget, or leave them empty."; return
        }
        constraints.maxPrepMinutes = Int(rawMinutes); constraints.weeklyBudget = Double(rawBudget)
        if practicalEnabled && source == 0 {
            var schedule = weekBrief; schedule.notBefore = Calendar.current.startOfDay(for: Date())
            constraints.practicalWeek = schedule
        }
        do { try constraints.validate() } catch { generationError = error.localizedDescription; return }
        do { try EditorDraftStore().save(constraints, userID: owner, scope: "meal-planning-constraints") } catch { generationError = "Your planning constraints could not be kept. Try again before generating."; return }
        let request = constraints, useSavedRecipes = source == 0, shouldLock = keepExisting
        isLoading = true
        generationTask = Task { @MainActor in
            defer { isLoading = false }
            do {
                var locked: [MealPlanDay] = []
                if shouldLock || request.practicalWeek != nil {
                    planner.invalidateCache(for: owner)
                    for offset in 0..<7 {
                        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: startingDate) else { throw MealPlanEditError.invalid }
                        let old = try await planner.fetchBasePlanResult(for: date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(date)
                        locked.append(shouldLock || date < Calendar.current.startOfDay(for: Date()) ? old : MealPlanEditingRules.emptyDay(date))
                    }
                }
                try Task.checkCancellation()
                let days: [MealPlanDay]
                if useSavedRecipes {
                    var stock: [PantryItem] = [], savedPlans: [MealPlanDay] = []
                    if request.practicalWeek?.usePreparedStock == true {
                        let repository = DIContainer.shared.nutritionRepository!
                        stock = try await repository.fetchInventory(userID: owner)
                        savedPlans = try await repository.fetchMealPlansForStockReservations(userID: owner)
                    }
                    days = try await SavedRecipeWeekPlanner.makeAsync(recipes: recipes.userRecipes.filter { RecipeLibraryRules.isVisible($0) },
                        constraints: request, starting: startingDate, locked: locked, stock: stock, savedPlans: savedPlans, allowPartialReview: true)
                } else {
                    let ideas = try await planner.draftWeekPlan(goals: goals, preferredFoods: list(preferences), preferredCuisines: [], preferredSnacks: [], starting: startingDate, userID: owner)
                    days = try ideas.map { day in
                        var result = day
                        let old = locked.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) }?.meals ?? []
                        let occupied = Set(old.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
                        let additions = try day.meals.filter { !occupied.contains(MealPlanEditingRules.canonicalSlot($0.mealType)) }.map { meal in
                            request.householdPortions > 1 ? try MealPlanCookingRules.configuring(meal, date: day.date, cookingPortions: request.householdPortions) : meal
                        }
                        result.meals = old + additions
                        return result
                    }
                }
                try Task.checkCancellation()
                guard DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
                guard goals.effectiveMealConstraintProfile == request.ingredientProfile else { throw MealConstraintError.reviewRequired }
                var value = MealPlanWeekDraft(days: days, title: "Review your week", constraints: request, preserveCookingBatches: true)
                value.lockedMealIDs = Set(locked.flatMap(\.meals).map(\.id))
                value.existingLockedMealIDs = value.lockedMealIDs
                let review = MealPlanWeekSaveSession(userID: owner, draft: value)
                guard let stored = review.checkpoint else { throw MealPlanEditError.invalid }
                draft = stored.draft
            } catch is CancellationError { generationError = "Planning stopped. Your brief is still here." } catch { generationError = error.localizedDescription }
        }
    }
}

private struct MealPlanningBrief: Codable {
    var source: Int
    var diet: PlanningDiet
    var exclusions: String
    var equipment: String
    var minutes: String
    var budget: String
    var household: Int
    var tolerance: Double
    var proteinMinimum: Bool
    var keepExisting: Bool
    var preferences: String
    var practicalWeek: MealPlanningWeekBrief?
}
