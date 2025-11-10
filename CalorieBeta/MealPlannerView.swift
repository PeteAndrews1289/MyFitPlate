import SwiftUI
import FirebaseAuth

struct MealPlannerView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spotlightManager: SpotlightManager
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var planForSelectedDate: MealPlanDay?
    @State private var isLoading = false
    @State private var showingGroceryList = false
    @State private var showingMealPlanSurvey = false

    @State private var regeneratingMealID: String?

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false

    private let spotlightOrder = ["weekView", "planContent", "toolbarActions"]
    private let spotlightContent: [String: (title: String, text: String)] = [
        "weekView": ("Select a Day", "Tap any day of the week to view or manage your meal plan for that specific date."),
        "planContent": ("Your Daily Plan", "Once a meal plan is generated, your meals for the selected day will appear here."),
        "toolbarActions": ("Meal Plan Tools", "Use the toolbar buttons to manage your plan. Tap ✨ to generate a new 7-day plan, or tap 📋 to see your grocery list.")
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                WeekView(selectedDate: $selectedDate)
                    .padding(.vertical, 10)
                    .background(colorScheme == .dark ? Color(UIColor.systemGray).opacity(0.2) : Color(UIColor.systemGray6))
                    .cornerRadius(20)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 15)
                    .featureSpotlight(isActive: isSpotlightActive(for: "weekView"))
                    .id("weekView")
                    .onChange(of: selectedDate) { _ in fetchPlan() }

                if isLoading {
                    Spacer()
                    ProgressView("Loading Plan...")
                    Spacer()
                } else if let plan = planForSelectedDate, !plan.meals.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Plan for \(selectedDate, formatter: DateFormatter.longDate)")
                                .appFont(size: 17, weight: .semibold)
                                .padding(.horizontal)

                            ForEach(plan.meals) { meal in
                                MealCardView(
                                    meal: meal,
                                    isRegenerating: regeneratingMealID == meal.id,
                                    onLog: log,
                                    onRegenerate: { regenerate(meal: meal) }
                                )
                            }
                        }
                        .padding()
                    }
                    .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
                    .id("planContent")
                } else {
                    Spacer()
                    Text("No plan found for this day.").appFont(size: 17)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Button("Generate New Meal Plan") {
                        showingMealPlanSurvey = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                    Spacer()
                    .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
                    .id("planContent")
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingGroceryList) {
                NavigationView {
                    GroceryListView()
                }
            }
            .sheet(isPresented: $showingMealPlanSurvey, onDismiss: fetchPlan) {
                MealPlanSurveyView()
            }
            .onAppear(perform: onMealPlanAppear)

            if showingSpotlightTour {
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
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingGroceryList = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingMealPlanSurvey = true }) {
                    Image(systemName: "wand.and.stars")
                }
            }
        }
    }

    private func onMealPlanAppear() {
        fetchPlan()

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
        isLoading = true
        guard let userID = Auth.auth().currentUser?.uid else { isLoading = false; return }
        Task {
            self.planForSelectedDate = await mealPlannerService.fetchPlan(for: selectedDate, userID: userID)
            self.isLoading = false
        }
    }

    private func log(meal: PlannedMeal) {
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
                    await mealPlannerService.savePlan(updatedPlan, for: userID)
                }
            }
            regeneratingMealID = nil
        }
    }
}

private struct MealCardView: View {
    let meal: PlannedMeal
    var isRegenerating: Bool
    var onLog: (PlannedMeal) -> Void
    var onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(meal.mealType)
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(.secondary)

            Text(meal.foodItem?.name ?? "Unnamed Meal")
                .appFont(size: 20, weight: .bold)

            if let foodItem = meal.foodItem {
                HStack {
                    nutrientPill(label: "Cal", value: foodItem.calories, color: .red)
                    nutrientPill(label: "P", value: foodItem.protein, color: .accentProtein)
                    nutrientPill(label: "C", value: foodItem.carbs, color: .accentCarbs)
                    nutrientPill(label: "F", value: foodItem.fats, color: .accentFats)
                }
            }

            if let ingredients = meal.ingredients, let instructions = meal.instructions, !ingredients.isEmpty, !instructions.isEmpty {
                DisclosureGroup("View Recipe") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .appFont(size: 15, weight: .semibold)
                        ForEach(ingredients, id: \.self) { ingredient in
                            Text("• \(ingredient)").appFont(size: 14)
                        }

                        Text("Instructions")
                            .appFont(size: 15, weight: .semibold)
                            .padding(.top, 5)
                        Text(instructions).appFont(size: 14)
                    }
                    .padding(.top, 8)
                }
            }

            HStack {
                Button(action: { onLog(meal) }) {
                    Label("Log with AI", systemImage: "plus.bubble.fill")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: onRegenerate) {
                    if isRegenerating {
                        ProgressView()
                    } else {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRegenerating)
            }
            .padding(.top, 5)

        }
        .asCard()
    }

    @ViewBuilder
    private func nutrientPill(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .appFont(size: 10, weight: .bold)
            Text(String(format: "%.0f", value))
                .appFont(size: 12, weight: .semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(20)
    }
}


struct WeekView: View {
    @Binding var selectedDate: Date
    @Namespace private var animationNamespace
    let calendar = Calendar.current
    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        let now = Date()
        let day = String(Calendar.current.component(.day, from: now))

        HStack {
            ForEach(dates, id: \.self) { date in
                VStack {
                    VStack(spacing: 8) {
                        if (dayOfMonth(for: date) == day) {
                            Text(dayOfWeek(for: date)).appFont(size: 12).foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .brandPrimary : Color(UIColor.secondaryLabel))
                        } else {
                            Text(dayOfWeek(for: date)).appFont(size: 12).foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .brandPrimary : Color(UIColor.secondaryLabel))
                        }

                        if (dayOfMonth(for: date) == day) {
                            Text(dayOfMonth(for: date))
                                .appFont(size: 17, weight: .semibold)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(10)
                                .background( Group { if calendar.isDate(date, inSameDayAs: selectedDate) { Circle().fill(Color.brandPrimary).matchedGeometryEffect(id: "selectedDay", in: animationNamespace) } else { Circle().fill(Color.clear) } } )
                                .foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .white : .textPrimary)
                                .padding(.top, -1)
                                .padding(.bottom, -5)
                        } else {
                            Text(dayOfMonth(for: date))
                                .appFont(size: 17, weight: .semibold)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(10)
                                .background( Group { if calendar.isDate(date, inSameDayAs: selectedDate) { Circle().fill(Color.brandPrimary).matchedGeometryEffect(id: "selectedDay", in: animationNamespace) } else { Circle().fill(Color.clear) } } )
                                .foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .white : .textPrimary)
                                .padding(.bottom, 3)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70)
                    .onTapGesture {
                        withAnimation(.spring()) { selectedDate = date }
                        HapticManager.instance.feedback(.light)
                    }

                    if (dayOfMonth(for: date) == day) {
                        Circle()
                            .frame(width: 5, height: 5)
                            .foregroundColor(.green)
                            .padding(.bottom, -5)
                            .padding(.top, -5)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func dayOfWeek(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "EEE"; return formatter.string(from: date) }
    private func dayOfMonth(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "d"; return formatter.string(from: date) }
}

fileprivate extension DateFormatter {
    static var longDate: DateFormatter { let formatter = DateFormatter(); formatter.dateStyle = .long; return formatter }
}
