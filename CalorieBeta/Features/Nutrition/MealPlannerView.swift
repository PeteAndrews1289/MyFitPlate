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
    @State private var showingMealPrepMode = false
    @State private var showingPantrySheet = false
    
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var isAnalyzingImage = false
    @State private var visionRecipes: [VisionRecipe] = []
    @State private var showingVisionResults = false
    @State private var errorMessage: String?

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
                .sheet(isPresented: $showingPantrySheet) {
                    PantryView()
                }
                .fullScreenCover(isPresented: $showingMealPrepMode) {
                    MealPrepCookingView(days: visibleWeekPlans)
                }

            if showingSpotlightTour {
                spotlightOverlay
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker { image in
                self.inputImage = image
            }
            .onDisappear {
                if let image = inputImage {
                    analyzePantryImage(image)
                    inputImage = nil
                }
            }
        }
        .sheet(isPresented: $showingVisionResults) {
            VisionRecipeResultsView(recipes: visionRecipes)
                .environmentObject(dailyLogService)
        }
        .alert("Analysis Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
                    onGenerate: { showingMealPlanSurvey = true },
                    onStartMealPrep: { showingMealPrepMode = true }
                )
                
                scanPantryButton

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
    
    @ViewBuilder
    private var scanPantryButton: some View {
        Button(action: { showingImagePicker = true }) {
            HStack(spacing: 12) {
                if isAnalyzingImage {
                    ProgressView()
                        .tint(.white)
                    Text("Chef Maia is analyzing...")
                } else {
                    Image(systemName: "camera.macro")
                        .font(.system(size: 20, weight: .bold))
                    VStack(alignment: .leading) {
                        Text("Scan Pantry")
                            .appFont(size: 16, weight: .bold)
                        Text("AI Recipe Generator")
                            .appFont(size: 12)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Spacer()
                if !isAnalyzingImage {
                    Image(systemName: "chevron.right")
                }
            }
            .foregroundColor(.white)
            .padding(18)
            .background(
                LinearGradient(colors: [.brandPrimary, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .cornerRadius(20)
            .shadow(color: .brandPrimary.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(isAnalyzingImage)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                Button(action: { showingGroceryList = true }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .accessibilityLabel("Grocery List")

                Button(action: { showingPantrySheet = true }) {
                    Image(systemName: "refrigerator.fill")
                }
                .accessibilityLabel("Pantry")
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
    
    private func analyzePantryImage(_ image: UIImage) {
        isAnalyzingImage = true
        PantryVisionService.shared.generateRecipesFromImage(image: image) { result in
            DispatchQueue.main.async {
                self.isAnalyzingImage = false
                switch result {
                case .success(let recipes):
                    self.visionRecipes = recipes
                    self.showingVisionResults = true
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
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
        mealPlannerService.invalidateCache()
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

// MARK: - Pantry Vision Service & Views

struct VisionRecipe: Codable, Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
}

struct VisionRecipeResponse: Codable {
    let recipes: [VisionRecipe]
}

class PantryVisionService {
    static let shared = PantryVisionService()
    private init() {}
    
    func generateRecipesFromImage(image: UIImage, retryCount: Int = 1, completion: @escaping (Result<[VisionRecipe], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        
        let prompt = """
        You are a master chef and a nutritional expert. Analyze the provided image of a pantry, fridge, or ingredients.
        Identify all the edible ingredients you can see.
        Generate exactly 3 healthy, unique recipes that primarily use these ingredients.
        Your response MUST be a valid JSON object.
        Root key MUST be "recipes" (an array of objects).
        Each object MUST have the following keys:
        - "title" (String): The name of the recipe.
        - "description" (String): A short 1-2 sentence description of how to make it with the ingredients seen.
        - "calories" (Double): Estimated total calories for one serving.
        - "protein" (Double): Estimated total protein (g).
        - "carbs" (Double): Estimated total carbs (g).
        - "fats" (Double): Estimated total fats (g).
        """
        
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image]]
                ]
            ]
        ]
        
        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o",
                maxTokens: 1500,
                retryCount: 0
            )
            
            switch result {
            case .success(let jsonString):
                let cleanedContent = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let contentData = cleanedContent.data(using: .utf8) else {
                    if retryCount > 0 {
                        self.generateRecipesFromImage(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    }
                    return
                }
                
                do {
                    let decodedResponse = try JSONDecoder().decode(VisionRecipeResponse.self, from: contentData)
                    DispatchQueue.main.async { completion(.success(decodedResponse.recipes)) }
                } catch {
                    if retryCount > 0 {
                        self.generateRecipesFromImage(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.decodingError(error)))
                    }
                }
                
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }
}

struct VisionRecipeResultsView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss
    
    let recipes: [VisionRecipe]
    @State private var currentIndex = 0
    @State private var showSuccessMessage = false
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            VStack(spacing: 20) {
                Text("Chef Maia's Ideas")
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .padding(.top, 30)
                
                Text("Based on what I saw, here's what you can make!")
                    .appFont(size: 15)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                        visionRecipeCard(recipe: recipe)
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .frame(height: 400)
                
                Button(action: {
                    logCurrentRecipe()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log Meal")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            
            if showSuccessMessage {
                VStack {
                    Spacer()
                    Text("Meal Logged!")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.accentPositive)
                        .cornerRadius(12)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    @ViewBuilder
    private func visionRecipeCard(recipe: VisionRecipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recipe.title)
                .appFont(size: 24, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text(recipe.description)
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            VStack(spacing: 12) {
                HStack {
                    macroBadge(title: "Calories", value: "\(Int(recipe.calories))", color: .orange)
                    macroBadge(title: "Protein", value: "\(Int(recipe.protein))g", color: .red)
                }
                HStack {
                    macroBadge(title: "Carbs", value: "\(Int(recipe.carbs))g", color: .blue)
                    macroBadge(title: "Fats", value: "\(Int(recipe.fats))g", color: .purple)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func macroBadge(title: String, value: String, color: Color) -> some View {
        VStack {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func logCurrentRecipe() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let recipe = recipes[currentIndex]
        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: recipe.title,
            calories: recipe.calories,
            protein: recipe.protein,
            carbs: recipe.carbs,
            fats: recipe.fats,
            servingSize: "1 Meal",
            servingWeight: 0,
            quantityValue: 1.0,
            servingUnit: "Meal"
        )
        
        dailyLogService.addFoodToLog(for: userID, date: Date(), mealName: "Lunch", foodItem: foodItem, source: "pantry_vision")
        
        withAnimation {
            showSuccessMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSuccessMessage = false
            }
            dismiss()
        }
    }
}
