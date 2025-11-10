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
        .sheet(isPresented: $showingAddFoodView) {
            AddFoodView(
                isPresented: $showingAddFoodView,
                onFoodLogged: { foodItem, mealType in
                    Task {
                        await dailyLogService.logFoodItem(foodItem, mealType: mealType)
                    }
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
