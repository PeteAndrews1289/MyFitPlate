import SwiftUI
import FirebaseAuth

struct CalorieLogView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @State private var showingAddFoodView = false
    @State private var foodToEdit: FoodItem?

    var body: some View {
        List {
            if let log = dailyLogService.currentDailyLog {
                ForEach(log.meals) { meal in
                    Section(header: Text(meal.name)) {
                        ForEach(meal.foodItems) { foodItem in
                            foodItemRow(foodItem)
                        }
                        .onDelete(perform: { indexSet in
                            deleteFood(in: meal, at: indexSet)
                        })
                    }
                }
            } else {
                Text("No log for this day yet.")
            }
        }
        .navigationTitle("Calorie Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddFoodView = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        // FIXED: Updated to use the new AddFoodView initializer
        .sheet(isPresented: $showingAddFoodView) {
            AddFoodView(
                initialFoodItem: FoodItem(
                    id: UUID().uuidString,
                    name: "",
                    calories: 0,
                    protein: 0,
                    carbs: 0,
                    fats: 0,
                    servingSize: "",
                    servingWeight: 0
                ),
                dailyLog: $dailyLogService.currentDailyLog,
                date: dailyLogService.activelyViewedDate,
                source: "manual_add",
                onLogUpdated: {
                    showingAddFoodView = false
                }
            )
        }
        // FIXED: Added sheet for editing existing items
        .sheet(item: $foodToEdit) { item in
            AddFoodView(
                initialFoodItem: item,
                dailyLog: $dailyLogService.currentDailyLog,
                date: dailyLogService.activelyViewedDate,
                source: "log_edit",
                onLogUpdated: {
                    foodToEdit = nil
                }
            )
        }
    }

    private func foodItemRow(_ foodItem: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(foodItem.name)
                Text("\(foodItem.calories, specifier: "%.0f") calories")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("P: \(foodItem.protein, specifier: "%.1f")g")
                Text("C: \(foodItem.carbs, specifier: "%.1f")g")
                Text("F: \(foodItem.fats, specifier: "%.1f")g")
            }
            .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            self.foodToEdit = foodItem
        }
    }

    private func deleteFood(in meal: Meal, at offsets: IndexSet) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let foodItemsToDelete = offsets.map { meal.foodItems[$0] }
        for foodItem in foodItemsToDelete {
            dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItem.id)
        }
    }
}
