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

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Text("Log to")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(foodTypes, id: \.self) { meal in
                    Button(meal) {
                        selectedMeal = meal
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMeal)
                        .appTextRole(.control)
                    Image(systemName: "chevron.up.chevron.down")
                        .appTextRole(.caption)
                }
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 44)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            }
            .accessibilityIdentifier("food_search_meal_menu")

            Spacer(minLength: 0)
        }
    }
}
