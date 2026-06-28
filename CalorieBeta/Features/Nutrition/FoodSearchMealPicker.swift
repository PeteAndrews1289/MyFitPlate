import SwiftUI

struct FoodSearchMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log to")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 7) {
                ForEach(foodTypes, id: \.self) { meal in
                    Button {
                        selectedMeal = meal
                    } label: {
                        Text(meal)
                            .appFont(size: 12, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedMeal == meal ? Color.brandPrimary.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .foregroundColor(selectedMeal == meal ? .brandPrimary : Color(UIColor.secondaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }
}

struct FoodSearchCompactMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]

    var body: some View {
        HStack(spacing: 10) {
            Text("Log to")
                .appFont(size: 12, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            Menu {
                ForEach(foodTypes, id: \.self) { meal in
                    Button(meal) {
                        selectedMeal = meal
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMeal)
                        .appFont(size: 13, weight: .bold)
                    Image(systemName: "chevron.up.chevron.down")
                        .appFont(size: 10, weight: .bold)
                }
                .foregroundColor(.brandPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.brandPrimary.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

