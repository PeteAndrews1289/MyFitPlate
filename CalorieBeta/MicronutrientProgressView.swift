import SwiftUI

struct MicronutrientProgressView: View {
    var dailyLog: DailyLog
    @ObservedObject var goalSettings: GoalSettings
    @Environment(\.colorScheme) var colorScheme

    private let micronutrients: [(key: String, name: String, unit: String)] = [
        ("calcium", "Calcium", "mg"),
        ("iron", "Iron", "mg"),
        ("potassium", "Potassium", "mg"),
        ("vitaminA", "Vitamin A", "mcg"),
        ("vitaminC", "Vitamin C", "mg"),
        ("vitaminD", "Vitamin D", "mcg"),
        ("vitaminB12", "Vitamin B12", "mcg"),
        ("folate", "Folate", "mcg"),
        ("fiber", "Fiber", "g"),
        ("sodium", "Sodium", "mg")
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        if goalSettings.calciumGoal != nil {
            let totals = dailyLog.totalMicronutrients()

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(micronutrients, id: \.key) { micro in
                    let intake = getIntake(for: micro.key, from: totals)
                    let goal = getGoal(for: micro.key)
                    let percentageValue = (goal > 0) ? (intake / goal) : 0.0
                    let displayPercentage = Int(round(percentageValue * 100))

                    MicronutrientRow(
                        name: micro.name,
                        percentage: displayPercentage,
                        progress: percentageValue,
                        isSodium: micro.key == "sodium"
                    )
                }
            }
            .padding()

        } else {
             VStack {
                 ProgressView()
                 Text("Loading Goals...")
                     .font(.caption)
                     .foregroundColor(.gray)
             }
             .frame(minHeight: 180)
         }
    }

    private func getIntake(for key: String, from totals: (calcium: Double, iron: Double, potassium: Double, sodium: Double, vitaminA: Double, vitaminC: Double, vitaminD: Double, vitaminB12: Double, folate: Double, fiber: Double)) -> Double {
         switch key {
             case "calcium": return totals.calcium
             case "iron": return totals.iron
             case "potassium": return totals.potassium
             case "sodium": return totals.sodium
             case "vitaminA": return totals.vitaminA
             case "vitaminC": return totals.vitaminC
             case "vitaminD": return totals.vitaminD
             case "vitaminB12": return totals.vitaminB12
             case "folate": return totals.folate
             case "fiber": return totals.fiber
             default: return 0
         }
    }

    private func getGoal(for key: String) -> Double {
        switch key {
            case "calcium": return max(goalSettings.calciumGoal ?? 1, 1)
            case "iron": return max(goalSettings.ironGoal ?? 1, 1)
            case "potassium": return max(goalSettings.potassiumGoal ?? 1, 1)
            case "sodium": return goalSettings.sodiumGoal ?? 2300
            case "vitaminA": return max(goalSettings.vitaminAGoal ?? 1, 1)
            case "vitaminC": return max(goalSettings.vitaminCGoal ?? 1, 1)
            case "vitaminD": return max(goalSettings.vitaminDGoal ?? 1, 1)
            case "vitaminB12": return max(goalSettings.vitaminB12Goal ?? 1, 1)
            case "folate": return max(goalSettings.folateGoal ?? 1, 1)
            case "fiber": return 25
            default: return 1
        }
    }
}

struct MicronutrientRow: View {
    let name: String
    let percentage: Int
    let progress: Double
    let isSodium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(percentage)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(getPercentageColor())
            }
            CustomProgressBar(value: progress, isSodium: isSodium)
                .frame(height: 8)
        }
    }

    private func getPercentageColor() -> Color {
        if isSodium {
            return progress >= 1.0 ? .red : .primary
        } else {
            return progress >= 1.0 ? .green : .primary
        }
    }
}

struct CustomProgressBar: View {
    var value: Double
    var isSodium: Bool
    @Environment(\.colorScheme) var colorScheme

    private var fillColor: Color {
        if isSodium {
            return value >= 1.0 ? .red : .orange
        } else {
            return value >= 1.0 ? .green : .accentColor
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.4) : .gray.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .frame(width: min(max(0, CGFloat(value) * geometry.size.width), geometry.size.width), height: geometry.size.height)
                    .foregroundColor(fillColor)
                    .animation(.easeInOut, value: value)
            }
        }
    }
}
