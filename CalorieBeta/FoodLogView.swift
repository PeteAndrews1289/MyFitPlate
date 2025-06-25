import SwiftUI
import FirebaseFirestore

// This view displays a log of meals and their associated food items, showing nutritional details.
// It is designed to be reusable and is typically used to present a summary of consumed food.
struct FoodLogView: View {
    var meals: [Meal]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        List {
            ForEach(meals) { meal in
                Section(header: Text(meal.name)
                    .foregroundColor(colorScheme == .dark ? .white : .black)) { // Dynamic text color.
                    ForEach(meal.foodItems, id: \.name) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundColor(colorScheme == .dark ? .white : .black) // Dynamic text color.
                                Text("\(item.calories, specifier: "%.1f") kcal")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("Protein: \(String(format: "%.1f", item.protein))g")
                                .foregroundColor(colorScheme == .dark ? .white : .black) // Dynamic text color.
                            Text("Fats: \(String(format: "%.1f", item.fats))g")
                                .foregroundColor(colorScheme == .dark ? .white : .black) // Dynamic text color.
                            Text("Carbs: \(String(format: "%.1f", item.carbs))g")
                                .foregroundColor(colorScheme == .dark ? .white : .black) // Dynamic text color.
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white) // Dynamic background.
    }
}
