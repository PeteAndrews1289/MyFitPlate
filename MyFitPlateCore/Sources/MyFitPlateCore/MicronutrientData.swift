import Foundation

/// Nutrients whose presence can vary by food database. A `nil` value means the
/// source did not report the nutrient; an explicit zero remains reported data.
public enum MicronutrientKey: String, CaseIterable, Hashable, Sendable {
    case fiber
    case calcium
    case iron
    case potassium
    case sodium
    case vitaminA
    case vitaminC
    case vitaminD
    case vitaminB12
    case folate
    case magnesium
    case phosphorus
    case zinc
    case copper
    case manganese
    case selenium
    case vitaminB1
    case vitaminB2
    case vitaminB3
    case vitaminB5
    case vitaminB6
    case vitaminE
    case vitaminK

    public static let vitaminAndMineralKeys = allCases.filter { $0 != .fiber }

    public var displayName: String {
        switch self {
        case .fiber: return "Fiber"
        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .potassium: return "Potassium"
        case .sodium: return "Sodium"
        case .vitaminA: return "Vitamin A"
        case .vitaminC: return "Vitamin C"
        case .vitaminD: return "Vitamin D"
        case .vitaminB12: return "Vitamin B12"
        case .folate: return "Folate"
        case .magnesium: return "Magnesium"
        case .phosphorus: return "Phosphorus"
        case .zinc: return "Zinc"
        case .copper: return "Copper"
        case .manganese: return "Manganese"
        case .selenium: return "Selenium"
        case .vitaminB1: return "Vitamin B1"
        case .vitaminB2: return "Vitamin B2"
        case .vitaminB3: return "Vitamin B3"
        case .vitaminB5: return "Vitamin B5"
        case .vitaminB6: return "Vitamin B6"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        }
    }

    public var unit: String {
        switch self {
        case .fiber:
            return "g"
        case .vitaminA, .vitaminD, .vitaminB12, .folate, .copper, .selenium, .vitaminK:
            return "mcg"
        default:
            return "mg"
        }
    }
}

public struct MicronutrientCoverage: Equatable, Sendable {
    public let reportedFoodCount: Int
    public let totalFoodCount: Int

    public init(reportedFoodCount: Int, totalFoodCount: Int) {
        self.reportedFoodCount = max(0, reportedFoodCount)
        self.totalFoodCount = max(0, totalFoodCount)
    }

    public var hasReportedData: Bool { reportedFoodCount > 0 }
    public var isComplete: Bool { totalFoodCount > 0 && reportedFoodCount == totalFoodCount }
    public var fraction: Double {
        guard totalFoodCount > 0 else { return 0 }
        return Double(reportedFoodCount) / Double(totalFoodCount)
    }
}

public extension FoodItem {
    func micronutrientValue(for key: MicronutrientKey) -> Double? {
        switch key {
        case .fiber: return fiber
        case .calcium: return calcium
        case .iron: return iron
        case .potassium: return potassium
        case .sodium: return sodium
        case .vitaminA: return vitaminA
        case .vitaminC: return vitaminC
        case .vitaminD: return vitaminD
        case .vitaminB12: return vitaminB12
        case .folate: return folate
        case .magnesium: return magnesium
        case .phosphorus: return phosphorus
        case .zinc: return zinc
        case .copper: return copper
        case .manganese: return manganese
        case .selenium: return selenium
        case .vitaminB1: return vitaminB1
        case .vitaminB2: return vitaminB2
        case .vitaminB3: return vitaminB3
        case .vitaminB5: return vitaminB5
        case .vitaminB6: return vitaminB6
        case .vitaminE: return vitaminE
        case .vitaminK: return vitaminK
        }
    }

    var reportedMicronutrientCount: Int {
        MicronutrientKey.allCases.filter { micronutrientValue(for: $0) != nil }.count
    }

    var reportedVitaminMineralCount: Int {
        MicronutrientKey.vitaminAndMineralKeys.filter { micronutrientValue(for: $0) != nil }.count
    }

    func scalingNutritionAndServing(by multiplier: Double) -> FoodItem {
        guard multiplier.isFinite, multiplier > 0 else { return self }
        var scaled = self
        scaled.calories *= multiplier
        scaled.protein *= multiplier
        scaled.carbs *= multiplier
        scaled.fats *= multiplier
        scaled.servingWeight *= multiplier
        scaled.saturatedFat = saturatedFat.map { $0 * multiplier }
        scaled.polyunsaturatedFat = polyunsaturatedFat.map { $0 * multiplier }
        scaled.monounsaturatedFat = monounsaturatedFat.map { $0 * multiplier }
        for key in MicronutrientKey.allCases {
            guard let value = micronutrientValue(for: key) else { continue }
            scaled.setMicronutrientValue(value * multiplier, for: key)
        }
        return scaled
    }

    fileprivate mutating func setMicronutrientValue(_ value: Double, for key: MicronutrientKey) {
        switch key {
        case .fiber: fiber = value
        case .calcium: calcium = value
        case .iron: iron = value
        case .potassium: potassium = value
        case .sodium: sodium = value
        case .vitaminA: vitaminA = value
        case .vitaminC: vitaminC = value
        case .vitaminD: vitaminD = value
        case .vitaminB12: vitaminB12 = value
        case .folate: folate = value
        case .magnesium: magnesium = value
        case .phosphorus: phosphorus = value
        case .zinc: zinc = value
        case .copper: copper = value
        case .manganese: manganese = value
        case .selenium: selenium = value
        case .vitaminB1: vitaminB1 = value
        case .vitaminB2: vitaminB2 = value
        case .vitaminB3: vitaminB3 = value
        case .vitaminB5: vitaminB5 = value
        case .vitaminB6: vitaminB6 = value
        case .vitaminE: vitaminE = value
        case .vitaminK: vitaminK = value
        }
    }
}

public extension AdjustedServingNutrition {
    func micronutrientValue(for key: MicronutrientKey) -> Double? {
        switch key {
        case .fiber: return fiber
        case .calcium: return calcium
        case .iron: return iron
        case .potassium: return potassium
        case .sodium: return sodium
        case .vitaminA: return vitaminA
        case .vitaminC: return vitaminC
        case .vitaminD: return vitaminD
        case .vitaminB12: return vitaminB12
        case .folate: return folate
        case .magnesium: return magnesium
        case .phosphorus: return phosphorus
        case .zinc: return zinc
        case .copper: return copper
        case .manganese: return manganese
        case .selenium: return selenium
        case .vitaminB1: return vitaminB1
        case .vitaminB2: return vitaminB2
        case .vitaminB3: return vitaminB3
        case .vitaminB5: return vitaminB5
        case .vitaminB6: return vitaminB6
        case .vitaminE: return vitaminE
        case .vitaminK: return vitaminK
        }
    }

    var reportedVitaminMineralCount: Int {
        MicronutrientKey.vitaminAndMineralKeys.filter { micronutrientValue(for: $0) != nil }.count
    }
}

public extension DailyLog {
    func totalMicronutrient(_ key: MicronutrientKey) -> Double {
        meals
            .flatMap(\.foodItems)
            .compactMap { $0.micronutrientValue(for: key) }
            .filter { $0.isFinite && $0 >= 0 }
            .reduce(0, +)
    }

    func micronutrientCoverage(for key: MicronutrientKey) -> MicronutrientCoverage {
        let foods = meals.flatMap(\.foodItems)
        let reportedCount = foods.filter { item in
            guard let value = item.micronutrientValue(for: key) else { return false }
            return value.isFinite && value >= 0
        }.count
        return MicronutrientCoverage(
            reportedFoodCount: reportedCount,
            totalFoodCount: foods.count
        )
    }
}

/// Adds only missing detail nutrients from independently agreeing exact-product records.
/// Calories, macros, identity, serving text, and existing values always remain primary-owned.
public enum FoodMicronutrientEnrichment {
    public static func enrichExactProduct(
        primary: FoodItem,
        with candidates: [FoodItem?]
    ) -> FoodItem {
        var enriched = primary

        for candidateValue in candidates {
            guard let candidate = candidateValue,
                  FoodSourceAgreement.agrees(primary, candidate),
                  candidate.servingWeight > 0 else {
                continue
            }

            let servingScale = primary.servingWeight / candidate.servingWeight
            for key in MicronutrientKey.allCases where enriched.micronutrientValue(for: key) == nil {
                guard let candidateValue = candidate.micronutrientValue(for: key) else { continue }
                let scaledValue = candidateValue * servingScale
                guard scaledValue.isFinite, scaledValue >= 0 else { continue }
                enriched.setMicronutrientValue(scaledValue, for: key)
            }
        }

        return enriched
    }
}
