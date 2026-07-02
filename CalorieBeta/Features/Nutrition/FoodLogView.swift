import SwiftUI

struct FoodLogView: View {
    var meals: [Meal]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        List {
            ForEach(meals) { meal in
                Section(header: Text(meal.name)
                    .foregroundColor(colorScheme == .dark ? .white : .black)) {
                    ForEach(meal.foodItems, id: \.name) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text("\(formatted(item.calories)) cal")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("P \(formatted(item.protein)) g")
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Text("F \(formatted(item.fats)) g")
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Text("C \(formatted(item.carbs)) g")
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
    }

    private func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(rounded).formatted()
        }
        return rounded.formatted(.number.precision(.fractionLength(1)))
    }
}
