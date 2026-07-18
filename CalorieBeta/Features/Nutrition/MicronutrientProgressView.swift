import SwiftUI

struct MicronutrientProgressView: View {
    var dailyLog: DailyLog
    @ObservedObject var goalSettings: GoalSettings
    @Environment(\.colorScheme) var colorScheme

    private let micronutrients: [MicronutrientKey] = [
        .calcium,
        .iron,
        .potassium,
        .sodium,
        .fiber,
        .vitaminA,
        .vitaminC,
        .vitaminD,
        .vitaminB12,
        .magnesium,
        .zinc,
        .folate
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        if goalSettings.calciumGoal != nil {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(micronutrients, id: \.self) { nutrient in
                        let coverage = dailyLog.micronutrientCoverage(for: nutrient)
                        let intake = dailyLog.totalMicronutrient(nutrient)
                        let goal = getGoal(for: nutrient)
                        let progress = coverage.hasReportedData && goal > 0 ? intake / goal : 0
                        let percentage = coverage.hasReportedData ? Int(round(progress * 100)) : nil

                        MicronutrientRow(
                            name: nutrient.displayName,
                            percentage: percentage,
                            progress: progress,
                            coverage: coverage,
                            isSodium: nutrient == .sodium
                        )
                    }
                }

                Text("Totals include only foods whose source reports each nutrient. Missing values are unknown, not zero.")
                    .font(.caption)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding()

        } else {
            VStack {
                ProgressView()
                    .tint(AppPalette.effort)
                Text("Loading goals")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(minHeight: 180)
        }
    }

    private func getGoal(for key: MicronutrientKey) -> Double {
        switch key {
        case .calcium: return max(goalSettings.calciumGoal ?? 1000, 1)
        case .iron: return max(goalSettings.ironGoal ?? 18, 1)
        case .potassium: return max(goalSettings.potassiumGoal ?? 3500, 1)
        case .sodium: return goalSettings.sodiumGoal ?? 2300
        case .vitaminA: return max(goalSettings.vitaminAGoal ?? 900, 1)
        case .vitaminC: return max(goalSettings.vitaminCGoal ?? 90, 1)
        case .vitaminD: return max(goalSettings.vitaminDGoal ?? 20, 1)
        case .vitaminB12: return max(goalSettings.vitaminB12Goal ?? 2.4, 1)
        case .folate: return max(goalSettings.folateGoal ?? 400, 1)
        case .fiber: return 25
        case .magnesium: return 400
        case .phosphorus: return 700
        case .zinc: return 11
        case .copper: return 900
        case .manganese: return 2.3
        case .selenium: return 55
        case .vitaminB1: return 1.2
        case .vitaminB2: return 1.3
        case .vitaminB3: return 16
        case .vitaminB5: return 5
        case .vitaminB6: return 1.3
        case .vitaminE: return 15
        case .vitaminK: return 120
        }
    }
}

struct MicronutrientRow: View {
    let name: String
    let percentage: Int?
    let progress: Double
    let coverage: MicronutrientCoverage
    let isSodium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(percentage.map { "\($0)%" } ?? "N/A")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(getPercentageColor())
            }
            CustomProgressBar(value: min(progress, 1.0), isSodium: isSodium)
                .frame(height: 8)
            Text(coverageText)
                .font(.caption2)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }

    private var coverageText: String {
        if coverage.totalFoodCount == 0 { return "No foods logged" }
        if !coverage.hasReportedData { return "No reported data" }
        if coverage.isComplete { return "Complete data" }
        return "\(coverage.reportedFoodCount) of \(coverage.totalFoodCount) foods"
    }

    private func getPercentageColor() -> Color {
        guard percentage != nil else { return Color(UIColor.secondaryLabel) }
        if isSodium {
            return progress >= 1.0 ? AppPalette.critical : .primary
        } else {
            return progress >= 1.0 ? .accentPositive : .primary
        }
    }
}

struct CustomProgressBar: View {
    var value: Double
    var isSodium: Bool
    @Environment(\.colorScheme) var colorScheme

    private var fillColor: Color {
        if isSodium {
            return value >= 1.0 ? AppPalette.critical : AppPalette.caution
        } else {
            return value >= 1.0 ? .accentPositive : AppPalette.effort
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
