import SwiftUI
import FirebaseAuth

struct MealPlannerView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spotlightManager: SpotlightManager
    
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var planForSelectedDate: MealPlanDay?
    @State private var isLoading = false
    @State private var showingGroceryList = false
    @State private var showingMealPlanSurvey = false
    
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
                    .background(Color.backgroundSecondary)
                    .featureSpotlight(isActive: isSpotlightActive(for: "weekView"))
                    .id("weekView")
                    .onChange(of: selectedDate) { _ in fetchPlan() }

                if isLoading {
                    Spacer()
                    ProgressView("Loading Plan...")
                    Spacer()
                } else if let plan = planForSelectedDate, !plan.meals.isEmpty {
                    List {
                        Text("Plan for \(selectedDate, formatter: DateFormatter.longDate)")
                            .appFont(size: 17, weight: .semibold)
                            .listRowBackground(Color.clear)
                            .padding(.bottom, 5)

                        ForEach(plan.meals) { meal in
                            mealSection(for: meal)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
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
            .tint(.brandPrimary)
            .sheet(isPresented: $showingGroceryList) {
                NavigationView {
                    GroceryListView()
                }
            }
            .sheet(isPresented: $showingMealPlanSurvey) {
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
    
    @ViewBuilder
    private func mealSection(for meal: PlannedMeal) -> some View {
        Section(header: Text(meal.mealType)) {
            Text(meal.foodItem?.name ?? "Unnamed Meal").appFont(size: 17, weight: .semibold)
            
            if let ingredients = meal.ingredients, !ingredients.isEmpty {
                ForEach(ingredients, id: \.self) { ingredient in
                    Text("• \(ingredient)").appFont(size: 15)
                }
            }
            
            if let instructions = meal.instructions, !instructions.isEmpty {
                DisclosureGroup("Instructions") {
                    Text(instructions).appFont(size: 15)
                }
            }
            
            Button(action: { log(meal: meal) }) {
                Label("Log with AI Assistant", systemImage: "plus.bubble.fill")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.brandPrimary)
        }
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
}

struct WeekView: View {
    @Binding var selectedDate: Date
    @Namespace private var animationNamespace
    let calendar = Calendar.current
    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        HStack {
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 8) {
                    Text(dayOfWeek(for: date)).appFont(size: 12).foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .brandPrimary : Color(UIColor.secondaryLabel))
                    Text(dayOfMonth(for: date)).appFont(size: 17, weight: .semibold).padding(10)
                        .background( Group { if calendar.isDate(date, inSameDayAs: selectedDate) { Circle().fill(Color.brandPrimary).matchedGeometryEffect(id: "selectedDay", in: animationNamespace) } else { Circle().fill(Color.clear) } } )
                        .foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .white : .textPrimary)
                }
                .frame(maxWidth: .infinity)
                .onTapGesture { withAnimation(.spring()) { selectedDate = date } }
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
