import SwiftUI
import FirebaseAuth

struct MealPlannerView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var recipeService: RecipeService
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var planForSelectedDate: MealPlanDay?
    @State private var isLoading = false
    @State private var loadingMessage = "Checking saved plan..."
    @State private var showingGroceryList = false
    @State private var showingMealPlanSurvey = false
    @State private var showingAddMealToPlan = false
    @State private var showingLogDayConfirmation = false

    @State private var regeneratingMealID: String?
    @State private var loggedMealID: String?
    @State private var mealPendingDelete: PlannedMeal?
    @State private var weekPlans: [String: MealPlanDay] = [:]
    @State private var didPrefetchVisibleWeek = false

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false

    private let spotlightOrder = ["weekView", "planContent", "toolbarActions"]
    private let spotlightContent: [String: (title: String, text: String)] = [
        "weekView": ("Select a Day", "Tap any day of the week to view or manage your meal plan for that specific date."),
        "planContent": ("Your Daily Plan", "Once a meal plan is generated, your meals for the selected day will appear here."),
        "toolbarActions": ("Meal Plan Tools", "Use the toolbar buttons to manage your plan, add saved recipes, generate a new week, or open your grocery list.")
    ]

    private var visibleWeekDates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var visibleWeekPlans: [MealPlanDay] {
        visibleWeekDates.compactMap { weekPlans[dateKey(for: $0)] }
    }

    private var weekMealCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: visibleWeekDates.map { date in
            (dateKey(for: date), weekPlans[dateKey(for: date)]?.meals.count ?? 0)
        })
    }

    private var selectedPlanTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today's Plan"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: selectedDate))'s Plan"
    }

    var body: some View {
        ZStack {
            mainScrollView
                .background(Color.backgroundPrimary)
                .navigationTitle("Meal Plan")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingGroceryList) {
                    NavigationStack {
                        GroceryListView()
                    }
                }
                .sheet(isPresented: $showingAddMealToPlan, onDismiss: handlePlanEditDismiss) {
                    AddMealToPlanView(date: selectedDate, isPresented: $showingAddMealToPlan)
                        .environmentObject(mealPlannerService)
                        .environmentObject(dailyLogService)
                        .environmentObject(recipeService)
                }
                .sheet(isPresented: $showingMealPlanSurvey, onDismiss: handlePlanEditDismiss) {
                    MealPlanSurveyView()
                }
                .confirmationDialog(
                    "Remove this meal?",
                    isPresented: Binding(
                        get: { mealPendingDelete != nil },
                        set: { if !$0 { mealPendingDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Remove Meal", role: .destructive) {
                        if let meal = mealPendingDelete {
                            delete(meal: meal)
                        }
                        mealPendingDelete = nil
                    }

                    Button("Cancel", role: .cancel) {
                        mealPendingDelete = nil
                    }
                } message: {
                    Text(mealPendingDelete?.foodItem?.name ?? "This meal will be removed from the selected day.")
                }
                .confirmationDialog(
                    "Log this planned day?",
                    isPresented: $showingLogDayConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Log Planned Meals") {
                        if let plan = planForSelectedDate {
                            logDay(plan: plan)
                        }
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This adds the planned meals to the food log for \(selectedDate, formatter: DateFormatter.longDate).")
                }
                .onAppear(perform: onMealPlanAppear)

            if showingSpotlightTour {
                spotlightOverlay
            }
        }
        .toolbar {
            toolbarContent
        }
    }

    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                WeekView(
                    selectedDate: $selectedDate,
                    mealCountsByDay: weekMealCounts
                )
                .featureSpotlight(isActive: isSpotlightActive(for: "weekView"))
                .id("weekView")
                .onChange(of: selectedDate) { _, _ in fetchPlan() }

                WeeklyPlanOverviewCard(
                    plans: visibleWeekPlans,
                    onOpenGrocery: { showingGroceryList = true },
                    onGenerate: { showingMealPlanSurvey = true }
                )

                if isLoading {
                    MealPlanLoadingState(message: loadingMessage)
                        .padding(.top, 24)
                } else if let plan = planForSelectedDate, !plan.meals.isEmpty {
                    planContentView(for: plan)
                } else {
                    MealPlannerEmptyState(
                        onGenerate: { showingMealPlanSurvey = true },
                        onAddRecipe: { showingAddMealToPlan = true }
                    )
                    .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
                    .id("planContent")
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func planContentView(for plan: MealPlanDay) -> some View {
        MealPlanSummaryCard(date: selectedDate, meals: plan.meals, goals: goalSettings)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedPlanTitle)
                        .appFont(size: 22, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Regenerate individual meals or send them to Maia to log.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                if plan.meals.contains(where: { $0.foodItem != nil }) {
                    Button(action: { showingLogDayConfirmation = true }) {
                        Label("Log Day", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentPositive.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentPositive)
                }

                Button(action: { showingAddMealToPlan = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.brandPrimary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundColor(.brandPrimary)
            }

            ForEach(plan.meals) { meal in
                MealCardView(
                    meal: meal,
                    isRegenerating: regeneratingMealID == meal.id,
                    isLogged: loggedMealID == meal.id,
                    onLog: log,
                    onRegenerate: { regenerate(meal: meal) },
                    onDelete: { mealPendingDelete = meal }
                )
            }
        }
        .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
        .id("planContent")
    }

    @ViewBuilder
    private var spotlightOverlay: some View {
        Color.black.opacity(0.5).ignoresSafeArea()
            .onTapGesture(perform: advanceTour)
            .transition(.opacity)

        if !tourSpotlightIDs.isEmpty && currentSpotlightIndex < tourSpotlightIDs.count {
            let currentID = tourSpotlightIDs[currentSpotlightIndex]
            if let content = spotlightContent[currentID] {
                SpotlightTextView(
                    content: content,
                    currentIndex: currentSpotlightIndex,
                    total: tourSpotlightIDs.count,
                    position: .bottom,
                    onNext: advanceTour
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { showingGroceryList = true }) {
                Image(systemName: "list.bullet.clipboard")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button(action: { showingAddMealToPlan = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add meal to plan")

                Button(action: { showingMealPlanSurvey = true }) {
                    Image(systemName: "wand.and.stars")
                }
                .accessibilityLabel("Generate meal plan")
            }
        }
    }

    private func onMealPlanAppear() {
        fetchPlan()
        prefetchVisibleWeekIfNeeded()
        refreshWeekOverview()

        let needed = spotlightOrder.filter { !spotlightManager.isShown(id: $0) }
        if !needed.isEmpty {
            self.tourSpotlightIDs = needed
            self.currentSpotlightIndex = 0
            withAnimation {
                self.showingSpotlightTour = true
            }
        }
    }

    private func isSpotlightActive(for id: String) -> Bool {
        guard showingSpotlightTour, !tourSpotlightIDs.isEmpty, currentSpotlightIndex < tourSpotlightIDs.count else {
             return false
        }
        return tourSpotlightIDs[currentSpotlightIndex] == id
    }

    private func advanceTour() {
        if currentSpotlightIndex < tourSpotlightIDs.count - 1 {
            withAnimation {
                currentSpotlightIndex += 1
            }
        } else {
            finishTour()
        }
    }

    private func finishTour() {
        withAnimation {
            showingSpotlightTour = false
        }
        tourSpotlightIDs.forEach { spotlightManager.markAsShown(id: $0) }
    }

    private func fetchPlan() {
        guard let userID = Auth.auth().currentUser?.uid else { isLoading = false; return }
        let requestedDate = selectedDate

        if let cachedPlan = mealPlannerService.cachedPlan(for: requestedDate, userID: userID) {
            planForSelectedDate = cachedPlan
            isLoading = false
        } else {
            planForSelectedDate = nil
            loadingMessage = "Checking saved plan..."
            isLoading = true
        }

        Task {
            let plan = await mealPlannerService.fetchPlan(for: requestedDate, userID: userID)
            await MainActor.run {
                guard Calendar.current.isDate(requestedDate, inSameDayAs: selectedDate) else { return }
                self.planForSelectedDate = plan
                self.isLoading = false
                self.updateWeekCache(with: plan, for: requestedDate)
            }
        }
    }

    private func prefetchVisibleWeekIfNeeded() {
        guard !didPrefetchVisibleWeek, let userID = Auth.auth().currentUser?.uid else { return }
        didPrefetchVisibleWeek = true

        Task {
            await mealPlannerService.prefetchPlans(starting: Date(), userID: userID)
        }
    }

    private func refreshWeekOverview() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let dates = visibleWeekDates

        Task {
            var plans: [String: MealPlanDay] = [:]
            await withTaskGroup(of: (String, MealPlanDay?).self) { group in
                for date in dates {
                    group.addTask {
                        let plan = await mealPlannerService.fetchPlan(for: date, userID: userID)
                        return (dateKey(for: date), plan)
                    }
                }

                for await (key, plan) in group {
                    if let plan, !plan.meals.isEmpty {
                        plans[key] = plan
                    }
                }
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    weekPlans = plans
                }
            }
        }
    }

    private func updateWeekCache(with plan: MealPlanDay?, for date: Date) {
        let key = dateKey(for: date)
        if let plan, !plan.meals.isEmpty {
            weekPlans[key] = plan
        } else {
            weekPlans.removeValue(forKey: key)
        }
    }

    private func handlePlanEditDismiss() {
        fetchPlan()
        refreshWeekOverview()
    }

    private func log(meal: PlannedMeal) {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        if var foodItem = meal.foodItem {
            foodItem.timestamp = Date()
            dailyLogService.addMealToLog(
                for: userID,
                date: selectedDate,
                mealName: meal.mealType,
                foodItems: [foodItem],
                source: "meal_plan"
            )
            loggedMealID = meal.id
            HapticManager.instance.feedback(.medium)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if loggedMealID == meal.id {
                    loggedMealID = nil
                }
            }
            return
        }

        guard let ingredients = meal.ingredients, !ingredients.isEmpty else { return }

        let ingredientListString = ingredients.joined(separator: "\n- ")
        let prompt = """
        Calculate the nutritional breakdown for a recipe with these ingredients. Do not ask for confirmation; provide the breakdown directly in the specified format.

        Ingredients:
        - \(ingredientListString)

        Your response MUST be in the following format:
        ---Nutritional Breakdown---
        Calories: [Number]
        Protein: [Number]g
        Carbs: [Number]g
        Fats: [Number]g
        """

        appState.pendingChatPrompt = prompt
        appState.selectedTab = 1
    }

    private func logDay(plan: MealPlanDay) {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        let mealGroups: [(mealName: String, foodItems: [FoodItem])] = plan.meals.compactMap { meal in
            guard var foodItem = meal.foodItem else { return nil }
            foodItem.timestamp = Date()
            return (mealName: meal.mealType, foodItems: [foodItem])
        }

        guard !mealGroups.isEmpty else { return }

        dailyLogService.addMealGroupsToLog(
            for: userID,
            date: selectedDate,
            mealGroups: mealGroups,
            source: "meal_plan"
        )
        HapticManager.instance.feedback(.medium)
    }

    private func delete(meal: PlannedMeal) {
        guard let userID = Auth.auth().currentUser?.uid, var updatedPlan = planForSelectedDate else { return }
        updatedPlan.meals.removeAll { $0.id == meal.id }
        planForSelectedDate = updatedPlan
        updateWeekCache(with: updatedPlan, for: selectedDate)
        HapticManager.instance.feedback(.light)

        Task {
            await mealPlannerService.savePlan(updatedPlan, for: userID)
            await mealPlannerService.refreshGroceryList(for: userID)
        }
    }

    private func regenerate(meal: PlannedMeal) {
        guard let userID = Auth.auth().currentUser?.uid, let currentPlan = planForSelectedDate else { return }

        regeneratingMealID = meal.id

        Task {
            let foodList = goalSettings.suggestionProteins + goalSettings.suggestionCarbs + goalSettings.suggestionVeggies

            if let newMeal = await mealPlannerService.regenerateSingleMeal(
                for: currentPlan,
                mealToReplace: meal,
                goals: goalSettings,
                preferredFoods: foodList,
                preferredCuisines: goalSettings.suggestionCuisines,
                preferredSnacks: [],
                userID: userID) {

                if var updatedPlan = self.planForSelectedDate, let index = updatedPlan.meals.firstIndex(where: { $0.id == meal.id }) {
                    updatedPlan.meals[index] = newMeal
                    self.planForSelectedDate = updatedPlan
                    self.updateWeekCache(with: updatedPlan, for: selectedDate)
                    await mealPlannerService.savePlan(updatedPlan, for: userID)
                    await mealPlannerService.refreshGroceryList(for: userID)
                }
            }
            regeneratingMealID = nil
        }
    }
}
