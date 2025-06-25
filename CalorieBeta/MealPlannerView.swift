import SwiftUI
import FirebaseAuth

struct MealPlannerView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var appState: AppState
    
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var planForSelectedDate: MealPlanDay?
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                WeekView(selectedDate: $selectedDate)
                    .padding(.vertical, 10)
                    .onChange(of: selectedDate) { _ in fetchPlan() }

                if isLoading {
                    Spacer()
                    ProgressView("Loading Plan...")
                    Spacer()
                } else if let plan = planForSelectedDate, !plan.meals.isEmpty {
                    List {
                        Text("Plan for \(selectedDate, formatter: DateFormatter.longDate)")
                            .font(.headline).listRowBackground(Color.clear).padding(.bottom, 5)

                        ForEach(plan.meals) { meal in
                            mealSection(for: meal)
                        }
                    }
                } else {
                    Spacer()
                    Text("No plan found for this day.").font(.headline).foregroundColor(.secondary)
                    Text("Use the Meal Plan Generator in Settings to create a new plan.").font(.caption).foregroundColor(.gray)
                    Spacer()
                }
            }
            .navigationTitle("Meal Plan")
            .onAppear(perform: fetchPlan)
        }
    }
    
    @ViewBuilder
    private func mealSection(for meal: PlannedMeal) -> some View {
        Section(header: Text(meal.mealType)) {
            Text(meal.foodItem?.name ?? "Unnamed Meal").font(.headline)
            
            if let ingredients = meal.ingredients, !ingredients.isEmpty {
                ForEach(ingredients, id: \.self) { ingredient in
                    Text("• \(ingredient)").font(.subheadline)
                }
            }
            
            if let instructions = meal.instructions, !instructions.isEmpty {
                DisclosureGroup("Instructions") {
                    Text(instructions).font(.callout)
                }
            }
            
            Button(action: { log(meal: meal) }) {
                Label("Log with AI Assistant", systemImage: "plus.bubble.fill")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(dates, id: \.self) { date in
                    VStack(spacing: 8) {
                        Text(dayOfWeek(for: date)).font(.caption).foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .accentColor : .secondary)
                        Text(dayOfMonth(for: date)).font(.headline).fontWeight(calendar.isDate(date, inSameDayAs: selectedDate) ? .bold : .regular).padding(10)
                            .background( Group { if calendar.isDate(date, inSameDayAs: selectedDate) { Circle().fill(Color.accentColor).matchedGeometryEffect(id: "selectedDay", in: animationNamespace) } else { Circle().fill(Color.clear) } } )
                            .foregroundColor(calendar.isDate(date, inSameDayAs: selectedDate) ? .white : .primary)
                    }
                    .onTapGesture { withAnimation(.spring()) { selectedDate = date } }
                }
            }
            .padding(.horizontal)
        }
    }
    private func dayOfWeek(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "EEE"; return formatter.string(from: date) }
    private func dayOfMonth(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "d"; return formatter.string(from: date) }
}

fileprivate extension DateFormatter {
    static var longDate: DateFormatter { let formatter = DateFormatter(); formatter.dateStyle = .long; return formatter }
}
