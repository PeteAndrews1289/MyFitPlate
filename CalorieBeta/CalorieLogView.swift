import SwiftUI
import FirebaseFirestore

struct CalorieLogView: View {
    @State private var dailyLog = DailyLog(
        date: Date(),
        meals: [],
        totalCaloriesOverride: nil
    )
    @State private var showAddFoodSheet = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    totalCaloriesSection
                    mealsSection
                    addFoodButton
                }
                .padding(.vertical)
            }
            .navigationTitle("Calorie Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("MyFitPlate")
                        .font(.headline)
                        .foregroundColor(.primary.opacity(0.5))
                        .padding(.leading, 5)
                }
            }
            .sheet(isPresented: $showAddFoodSheet) {
                AddFoodView { newFood in
                    addFoodToLog(newFood)
                }
            }
            .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        }
    }

    private var totalCaloriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Calories")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("\(dailyLog.totalCalories(), specifier: "%.0f") cal")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .padding()
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        .cornerRadius(15)
        .shadow(radius: 2)
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meals")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            List {
                ForEach(dailyLog.meals) { meal in
                    Section(header: Text(meal.name)
                        .foregroundColor(colorScheme == .dark ? .white : .black)) {
                        ForEach(meal.foodItems) { food in
                            foodItemRow(food: food)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .padding()
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        .cornerRadius(15)
        .shadow(radius: 2)
    }

    private func foodItemRow(food: FoodItem) -> some View {
        VStack(alignment: .leading) {
            Text(food.name)
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("\(food.calories, specifier: "%.1f") cal • Protein: \(food.protein, specifier: "%.1f")g • Carbs: \(food.carbs, specifier: "%.1f")g • Fats: \(food.fats, specifier: "%.1f")g")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    private var addFoodButton: some View {
        Button(action: {
            showAddFoodSheet = true
        }) {
            Text("Add Food")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(25)
        }
        .padding(.horizontal)
    }

    private func addFoodToLog(_ newFood: FoodItem) {
        if let firstMealIndex = dailyLog.meals.firstIndex(where: { !$0.foodItems.isEmpty }) {
            dailyLog.meals[firstMealIndex].foodItems.append(newFood)
        } else {
            let newMeal = Meal(id: UUID().uuidString, name: "All Meals", foodItems: [newFood])
            dailyLog.meals.append(newMeal)
        }
    }
}
