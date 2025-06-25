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
    @Environment(\.colorScheme) var colorScheme
    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingProfileSheet = false
    @State private var showingAddExerciseView = false
    @State private var showingMealPlanSurvey = false
    @State private var showingMealPlanner = false
    @State private var showingGroceryList = false
    
    @State private var exerciseToEdit: LoggedExercise? = nil
    @State private var showingEditExerciseView = false
    @State private var weeklyInsight: UserInsight?

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
    
    private var containerBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : .white
    }

    var body: some View {
         ZStack {
            Color(colorScheme == .dark ? .systemBackground : .systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

             ScrollView {
                 VStack(spacing: 16) {
                     dateNavigationView
                     
                     nutritionProgressSection
                     
                     foodDiarySection
                     
                     if let exercises = dailyLogService.currentDailyLog?.exercises, !exercises.isEmpty {
                         activityWidget()
                     }
                     
                     milestoneWidget()
                 }
                 .padding(.horizontal)
                 .padding(.bottom, 100)
             }
             .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) {
                     Text("MyFitPlate")
                         .font(.headline)
                         .foregroundColor(.primary.opacity(0.5))
                         .padding(.leading, 5)
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     Menu {
                         Button(action: { self.showingProfileSheet = true }) {
                             Label("Profile", systemImage: "person")
                         }
                         
                         Divider()
                         
                         Button(action: { self.showingMealPlanSurvey = true }) {
                             Label("Weekly Plan Generator", systemImage: "wand.and.stars")
                         }
                         Button(action: { self.showingMealPlanner = true }) {
                             Label("View Meal Plan", systemImage: "calendar")
                         }
                         Button(action: { self.showingGroceryList = true }) {
                             Label("Grocery List", systemImage: "list.bullet.clipboard")
                         }
                         
                         Divider()
                         
                         Button(action: { self.showSettings = true }) {
                             Label("Settings", systemImage: "gearshape")
                         }
                     } label: {
                         Image(systemName: "line.3.horizontal")
                             .font(.title2)
                             .foregroundColor(.gray)
                     }
                 }
             }
         }
         .sheet(isPresented: $showingProfileSheet, content: {
             NavigationView {
                 UserProfileView()
             }
         })
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
         .sheet(isPresented: $showingMealPlanSurvey, content: {
             MealPlanSurveyView()
         })
         .sheet(isPresented: $showingMealPlanner, content: {
             MealPlannerView()
         })
         .sheet(isPresented: $showingGroceryList, content: {
             NavigationView {
                 GroceryListView()
             }
         })
         .onAppear {
            dailyLogService.activelyViewedDate = selectedDate
            fetchLogForSelectedDate()
            if isToday {
                healthKitViewModel.checkAuthorizationStatus()
            }
         }
         .onReceive(insightsService.$currentInsights) { insights in
             self.weeklyInsight = insights.first
         }
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
                    .foregroundColor(.secondary.opacity(0.5))
            }
            Spacer()
            Text(selectedDateFormattedString)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: {
                self.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate)!
                self.dailyLogService.activelyViewedDate = self.selectedDate
                self.fetchLogForSelectedDate()
            }) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(isToday ? .secondary.opacity(0.2) : .secondary.opacity(0.5))
            }
            .disabled(isToday)
        }
        .padding(.vertical, 4)
    }

    private var nutritionProgressSection: some View {
        Group {
            if let currentDailyLog = dailyLogService.currentDailyLog, Calendar.current.isDate(currentDailyLog.date, inSameDayAs: selectedDate) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nutrition Progress")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.leading)
                    NutritionProgressView(dailyLog: currentDailyLog, goal: goalSettings, insight: weeklyInsight)
                }
                .padding([.top, .bottom, .trailing])
                .background(containerBackground)
                .cornerRadius(15)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            } else {
                 VStack {
                     ProgressView()
                 }
                 .frame(maxWidth: .infinity, minHeight: 220)
                 .background(containerBackground)
                 .cornerRadius(15)
                 .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
        }
    }

    @ViewBuilder
    private func activityWidget() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Today's Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add") { showingAddExerciseView = true }
                    .font(.callout)
            }

            let exercises = dailyLogService.currentDailyLog?.exercises ?? []
            
            if !exercises.isEmpty {
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
                .padding(.top, 4)
            } else {
                Text("No workouts logged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(containerBackground)
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func milestoneWidget() -> some View {
        if let initialWt = goalSettings.weightHistory.first?.weight,
           let targetWt = goalSettings.targetWeight,
           abs(initialWt - targetWt) > 0.01 {
            MilestoneView(
                initialWeight: initialWt,
                currentWeight: goalSettings.weight,
                targetWeight: targetWt
            )
        }
    }

    private var foodDiarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Food Log")
                .font(.title3)
                .fontWeight(.semibold)
                .padding([.top, .leading, .trailing])

            let currentLogForDisplay = (dailyLogService.currentDailyLog != nil && Calendar.current.isDate(dailyLogService.currentDailyLog!.date, inSameDayAs: selectedDate)) ? dailyLogService.currentDailyLog : nil

            if (currentLogForDisplay?.meals.flatMap({ $0.foodItems }).isEmpty ?? true) {
                 Text("No food logged yet for this day.")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                foodDiaryGroupedContent(meals: currentLogForDisplay?.meals ?? [])
            }
        }
        .padding(.vertical)
        .background(containerBackground)
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func foodDiaryGroupedContent(meals: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(meals) { meal in
                if !meal.foodItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meal.name)
                            .font(.headline)
                            .padding(.horizontal)
                        Divider().padding(.horizontal)
                        VStack(spacing: 0) {
                            ForEach(meal.foodItems) { foodItem in
                                SwipeableFoodItemView(
                                    initialFoodItem: foodItem,
                                    dailyLog: $dailyLogService.currentDailyLog,
                                    onDelete: { itemID in self.deleteFood(byID: itemID) },
                                    onLogUpdated: { },
                                    date: self.selectedDate
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchLogForSelectedDate(completion: @escaping () -> Void = {}) {
        guard let userID = Auth.auth().currentUser?.uid else { completion(); return }
        dailyLogService.fetchLog(for: userID, date: selectedDate) { _ in
            goalSettings.recalculateAllGoals()
            completion()
        }
    }
    
    private func fetchLogForSelectedDate() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchLog(for: userID, date: selectedDate) { _ in
            goalSettings.recalculateAllGoals()
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
    @Environment(\.colorScheme) var colorSchemeS
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
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(colorSchemeS == .dark ? .white : .black)
                        if exercise.source == "HealthKit" {
                            Image("Apple_Health")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }
                    if let duration = exercise.durationMinutes, duration > 0 {
                        Text("\(duration) min")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Text("\(Int(exercise.caloriesBurned)) cal")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.trailing, 5)
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(.systemGray6).opacity(0.5))
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
    @Environment(\.colorScheme) var colorSchemeS
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false
    @State private var showDetailView = false

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationLink(destination: FoodDetailView(initialFoodItem: initialFoodItem, dailyLog: $dailyLog, date: date, source: "log_swipe", onLogUpdated: onLogUpdated ), isActive: $showDetailView) { EmptyView() }.opacity(0)
            if isSwiped { HStack { Spacer(); Button { withAnimation(.easeInOut) { onDelete(initialFoodItem.id); offset = 0; isSwiped = false } } label: { Image(systemName: "trash").foregroundColor(.white).frame(width: 60, height: 50, alignment: .center) }.buttonStyle(PlainButtonStyle()).background(Color.red).contentShape(Rectangle()).cornerRadius(8) }.padding(.vertical, 4).transition(.move(edge: .trailing).combined(with: .opacity)) }
            HStack { Text(FoodEmojiMapper.getEmoji(for: initialFoodItem.name) + " " + initialFoodItem.name).lineLimit(1).font(.body).foregroundColor(colorSchemeS == .dark ? .white : .black); Spacer(); Text("\(Int(initialFoodItem.calories)) cal").font(.subheadline).foregroundColor(.gray) }.padding(.vertical, 12).padding(.horizontal).background(Color.clear).cornerRadius(8).contentShape(Rectangle()).offset(x: offset)
            .onTapGesture { if !isSwiped { showDetailView = true } else { withAnimation(.easeInOut) { offset = 0; isSwiped = false } } }
            .gesture( DragGesture().onChanged { value in if value.translation.width < 0 { offset = max(value.translation.width, -70) } else if isSwiped && value.translation.width > 0 { offset = -70 + value.translation.width } }.onEnded { value in withAnimation(.easeInOut) { if value.translation.width < -50 { offset = -70; isSwiped = true } else { offset = 0; isSwiped = false } } } )
        }.padding(.bottom, 4)
    }
}
