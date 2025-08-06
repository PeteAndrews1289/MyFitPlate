import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var cycleService: CycleTrackingService
    @Environment(\.colorScheme) var colorScheme

    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingProfileSheet = false
    @State private var showingAddExerciseView = false
    
    @State private var exerciseToEdit: LoggedExercise? = nil
    @State private var showingEditExerciseView = false
    @State private var weeklyInsight: UserInsight?

    @State private var mealSuggestion: MealSuggestion? = nil
    @State private var showingSuggestionDetail = false
    @State private var showingSuggestionPreferences = false

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false
    
    @State private var showingWorkoutRoutines = false
    
    private let spotlightOrder = ["nutritionProgress", "waterTracker", "dailyLog"]
    private let spotlightContent: [String: (title: String, text: String)] = [
        "nutritionProgress": ("Daily Progress", "This area shows your real-time progress for calories, macros, and micronutrients. Swipe left or right to see different views!"),
        "waterTracker": ("Water Intake", "Quickly log your water intake here. The bottle will fill up as you get closer to your daily goal."),
        "dailyLog": ("Your Daily Log", "All of your logged food and exercise will appear here. Swipe any item to edit or delete it.")
    ]

    private var selectedDateFormattedString: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(selectedDate) {
            formatter.dateFormat = "MMMM d"
            return "Today, \(formatter.string(from: selectedDate))"
        }
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    private var showCycleCard: Bool {
        return cycleService.cycleSettings.typicalCycleLength > 0 && goalSettings.gender == "Female"
    }

    var body: some View {
         ZStack {
            NavigationLink(destination: WorkoutRoutinesView(), isActive: $showingWorkoutRoutines) { EmptyView() }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        dateNavigationView
                            .padding(.horizontal)
                        
                        if showCycleCard {
                            if cycleService.isLoadingInsight {
                                ProgressView()
                                    .padding()
                            } else if let insight = cycleService.aiInsight {
                                CycleInsightCard(insight: insight)
                                    .padding(.horizontal)
                            }
                        }
                        
                        nutritionProgressSection
                            .padding(.horizontal)
                            .id("nutritionProgress")
                        
                        if isToday {
                            MealSuggestionCardView(
                                suggestion: mealSuggestion,
                                onGenerate: {
                                    Task {
                                        self.mealSuggestion = await insightsService.generateSingleMealSuggestion()
                                    }
                                },
                                onTap: {
                                    if mealSuggestion != nil {
                                        showingSuggestionDetail = true
                                    } else {
                                        showingSuggestionPreferences = true
                                    }
                                },
                                onPrefs: {
                                    showingSuggestionPreferences = true
                                },
                                isLoading: insightsService.isGeneratingSuggestion
                            )
                            .padding(.horizontal)
                        }
                        
                        if let currentDailyLog = dailyLogService.currentDailyLog, Calendar.current.isDate(currentDailyLog.date, inSameDayAs: selectedDate) {
                            
                         
                            let insightToShow = insightsService.isLoadingInsights ? nil : weeklyInsight
                            
                            WaterTrackingCardView(date: currentDailyLog.date, insight: insightToShow)
                                .asCard()
                                .featureSpotlight(isActive: isSpotlightActive(for: "waterTracker"))
                                .id("waterTracker")
                                .padding(.horizontal)
                        }
                        
                        foodDiarySection
                            .padding(.horizontal)
                            .id("dailyLog")
                    }
                    .padding(.top)
                    .padding(.bottom, 120)
                }
                .onChange(of: currentSpotlightIndex) { newIndex in
                    if showingSpotlightTour && newIndex < tourSpotlightIDs.count {
                        let spotlightID = tourSpotlightIDs[newIndex]
                        withAnimation {
                            proxy.scrollTo(spotlightID, anchor: .center)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Text("MyFitPlate")
                            .appFont(size: 17, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        
                        Button(action: { showingWorkoutRoutines = true }) {
                            Image(systemName: "dumbbell.fill")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { self.showingProfileSheet = true }) {
                            Label("Profile", systemImage: "person")
                        }
                        Divider()
                        Button(action: { self.showSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }

            if showingSpotlightTour {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .onTapGesture(perform: advanceTour)
                    .transition(.opacity)

                if currentSpotlightIndex < tourSpotlightIDs.count {
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
         .sheet(isPresented: $showingSuggestionDetail) {
             if let suggestion = mealSuggestion {
                 MealSuggestionDetailView(suggestion: suggestion, onLog: logMealSuggestion)
             }
         }
         .sheet(isPresented: $showingSuggestionPreferences) {
             SuggestionPreferencesView(goalSettings: goalSettings)
         }
         .sheet(isPresented: $showingProfileSheet) {
             NavigationView {
                 UserProfileView()
             }
         }
         .sheet(isPresented: $showingAddExerciseView) {
             AddExerciseView { newExercise in
                 if let userID = Auth.auth().currentUser?.uid {
                     self.dailyLogService.addExerciseToLog(for: userID, exercise: newExercise)
                 }
             }
         }
         .sheet(item: $exerciseToEdit) { exerciseToEdit in
             AddExerciseView(exerciseToEdit: exerciseToEdit) { updatedExercise in
                 if let userID = Auth.auth().currentUser?.uid {
                     self.dailyLogService.deleteExerciseFromLog(for: userID, exerciseID: exerciseToEdit.id)
                     self.dailyLogService.addExerciseToLog(for: userID, exercise: updatedExercise)
                 }
             }
         }
         .onAppear(perform: onHomeViewAppear)
         .onReceive(insightsService.$currentInsights) { insights in
             self.weeklyInsight = insights.first
         }
    }
    
    private func logMealSuggestion(_ suggestion: MealSuggestion) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: suggestion.mealName,
            calories: suggestion.calories,
            protein: suggestion.protein,
            carbs: suggestion.carbs,
            fats: suggestion.fats,
            servingSize: "1 serving (AI Suggestion)",
            servingWeight: 0,
            timestamp: Date()
        )
        
        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: foodItem, source: "ai_suggestion")
        
        withAnimation {
            self.mealSuggestion = nil
        }
    }
    
    private func onHomeViewAppear() {
        dailyLogService.activelyViewedDate = selectedDate
        fetchLogForSelectedDate()
        if isToday {
            healthKitViewModel.checkAuthorizationStatus()
            cycleService.fetchAIInsight()
        }
        
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

    private var dateNavigationView: some View {
        HStack {
            Button(action: {
                self.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: self.selectedDate)!
                self.dailyLogService.activelyViewedDate = self.selectedDate
                self.fetchLogForSelectedDate()
            }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(UIColor.secondaryLabel).opacity(0.5))
            }
            Spacer()
            Text(selectedDateFormattedString)
                .appFont(size: 17, weight: .semibold)
            Spacer()
            Button(action: {
                self.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate)!
                self.dailyLogService.activelyViewedDate = self.selectedDate
                self.fetchLogForSelectedDate()
            }) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(isToday ? Color(UIColor.secondaryLabel).opacity(0.2) : Color(UIColor.secondaryLabel).opacity(0.5))
            }
            .disabled(isToday)
        }
        .padding(.vertical, 4)
    }

    private var nutritionProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutrition Progress")
                .appFont(size: 22, weight: .bold)
                .padding(.horizontal)
            
            if let currentDailyLog = dailyLogService.currentDailyLog, Calendar.current.isDate(currentDailyLog.date, inSameDayAs: selectedDate) {
                NutritionProgressView(dailyLog: currentDailyLog, goal: goalSettings, insight: weeklyInsight)
            } else {
                 ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .asCard()
        .featureSpotlight(isActive: isSpotlightActive(for: "nutritionProgress"))
    }

    private var foodDiarySection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Daily Log")
                .appFont(size: 22, weight: .bold)

            let currentLogForDisplay = (dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: selectedDate)) ? dailyLogService.currentDailyLog : nil

            if (currentLogForDisplay?.meals.flatMap({ $0.foodItems }).isEmpty ?? true) && (currentLogForDisplay?.exercises?.isEmpty ?? true) {
                 Text("No food or exercise logged yet for this day.")
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .appFont(size: 15)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                foodDiaryGroupedContent(meals: currentLogForDisplay?.meals ?? [])
                
                if let exercises = dailyLogService.currentDailyLog?.exercises, !exercises.isEmpty {
                    Divider().padding(.vertical, 8)
                    activityWidget()
                }
            }
        }
        .asCard()
        .featureSpotlight(isActive: isSpotlightActive(for: "dailyLog"))
    }

    @ViewBuilder
    private func activityWidget() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Activity")
                    .appFont(size: 20, weight: .semibold)
                Spacer()
                Button("Add") { showingAddExerciseView = true }
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.brandPrimary)
            }

            let exercises = dailyLogService.currentDailyLog?.exercises ?? []
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(exercises) { exercise in
                    SwipeableExerciseRowView(
                        exercise: exercise,
                        onDelete: { exerciseID in self.deleteExercise(byID: exerciseID) },
                        onEdit: { exerciseToEdit in
                            self.exerciseToEdit = exerciseToEdit
                            self.showingEditExerciseView = true
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func foodDiaryGroupedContent(meals: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(meals) { meal in
                if !meal.foodItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meal.name)
                            .appFont(size: 20, weight: .semibold)
                        
                        VStack(spacing: 0) {
                            ForEach(meal.foodItems) { foodItem in
                                SwipeableFoodItemView(
                                    initialFoodItem: foodItem,
                                    dailyLog: $dailyLogService.currentDailyLog,
                                    onDelete: { itemID in self.deleteFood(byID: itemID) },
                                    onLogUpdated: { },
                                    date: self.selectedDate
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchLogForSelectedDate(completion: @escaping () -> Void = {}) {
            guard let userID = Auth.auth().currentUser?.uid else {
                completion()
                return
            }
            
            dailyLogService.fetchLog(for: userID, date: selectedDate) { [self] _ in
            
                self.goalSettings.recalculateAllGoals()
                
                if self.isToday {
                    self.insightsService.generateDailySmartInsight()
                }
                
                completion()
            }
        }

    private func deleteFood(byID foodItemID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.deleteFoodFromCurrentLog(
            for: userID,
            foodItemID: foodItemID
        )
    }

    private func deleteExercise(byID exerciseID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.deleteExerciseFromLog(
            for: userID,
            exerciseID: exerciseID
        )
    }
}

private struct SwipeableExerciseRowView: View {
    let exercise: LoggedExercise
    let onDelete: (String) -> Void
    let onEdit: (LoggedExercise) -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete(exercise.id)
                            offset = 0
                            isSwiped = false
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 40, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .cornerRadius(8)
                }
                .padding(.vertical, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                    .font(.title3)
                VStack(alignment: .leading) {
                    HStack {
                        Text(exercise.name)
                            .appFont(size: 15, weight: .medium)
                            .foregroundColor(.textPrimary)
                        if exercise.source == "HealthKit" {
                            Image("Apple_Health")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }
                    if let duration = exercise.durationMinutes, duration > 0 {
                        Text("\(duration) min")
                            .appFont(size: 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
                Spacer()
                Text("\(Int(exercise.caloriesBurned)) cal")
                    .appFont(size: 15)
                    .foregroundColor(.accentPositive)
                    .padding(.trailing, 5)
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(UIColor.systemGray6).opacity(0.5))
            .cornerRadius(8)
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    onEdit(exercise)
                } else {
                    withAnimation(.easeInOut) {
                        offset = 0
                        isSwiped = false
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut) {
                            if value.translation.width < -50 {
                                offset = -70
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
        }
        .padding(.bottom, 2)
    }
}

private struct SwipeableFoodItemView: View {
    let initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    let onDelete: (String) -> Void
    let onLogUpdated: () -> Void
    let date: Date
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false
    @State private var showDetailView = false

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationLink(destination: FoodDetailView(initialFoodItem: initialFoodItem, dailyLog: $dailyLog, date: date, source: "log_swipe", onLogUpdated: onLogUpdated ), isActive: $showDetailView) { EmptyView() }.opacity(0)
            if isSwiped { HStack { Spacer(); Button { withAnimation(.easeInOut) { onDelete(initialFoodItem.id); offset = 0; isSwiped = false } } label: { Image(systemName: "trash").foregroundColor(.white).frame(width: 60, height: 50, alignment: .center) }.buttonStyle(PlainButtonStyle()).background(Color.red).contentShape(Rectangle()).cornerRadius(8) }.padding(.vertical, 2).transition(.move(edge: .trailing).combined(with: .opacity)) }
            HStack {
                Text(FoodEmojiMapper.getEmoji(for: initialFoodItem.name) + " " + initialFoodItem.name)
                    .lineLimit(1)
                    .appFont(size: 17)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(initialFoodItem.calories)) cal")
                    .appFont(size: 15)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture { if !isSwiped { showDetailView = true } else { withAnimation(.easeInOut) { offset = 0; isSwiped = false } } }
            .gesture( DragGesture().onChanged { value in if value.translation.width < 0 { offset = max(value.translation.width, -70) } else if isSwiped && value.translation.width > 0 { offset = -70 + value.translation.width } }.onEnded { value in withAnimation(.easeInOut) { if value.translation.width < -50 { offset = -70; isSwiped = true } else { offset = 0; isSwiped = false } } } )
        }
        .padding(.bottom, 1)
    }
}
