import SwiftUI
import MyFitPlateCore

struct FoodSearchMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                FoodSearchCompactMealPicker(selectedMeal: $selectedMeal, foodTypes: foodTypes)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Log to")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Log to", selection: $selectedMeal) {
                        ForEach(foodTypes, id: \.self) { meal in
                            Text(meal).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("food_search_meal_picker")
                }
            }
        }
    }
}

struct FoodSearchCompactMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]
    var date: Date?

    var body: some View {
        Menu {
            ForEach(foodTypes, id: \.self) { meal in
                Button(meal) { selectedMeal = meal }
            }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Text(selectedMeal).appTextRole(.control)
                    Image(systemName: "chevron.down").appTextRole(.caption)
                }
                if let date {
                    Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(date: .abbreviated, time: .omitted))
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("food_search_destination_date")
                }
            }.foregroundStyle(AppPalette.text).frame(minHeight: 44)
        }
        .accessibilityLabel(date.map { "Log to \(selectedMeal), \($0.formatted(date: .complete, time: .omitted))" } ?? "Log to \(selectedMeal)")
        .accessibilityIdentifier("food_search_meal_menu")
    }
}
