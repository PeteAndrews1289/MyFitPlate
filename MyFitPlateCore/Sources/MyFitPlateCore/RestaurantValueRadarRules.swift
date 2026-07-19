import Foundation

public enum RestaurantValueRadarRules {
    public enum Tier: String, Equatable, Sendable {
        case highProteinValue
        case balancedValue
        case lowerProteinValue

        public var label: String {
            switch self {
            case .highProteinValue: return "High protein value"
            case .balancedValue: return "Balanced value"
            case .lowerProteinValue: return "Lower protein value"
            }
        }
    }

    public struct Score: Equatable, Sendable {
        public let adjustedPrice: Double
        public let proteinPerDollar: Double
        public let proteinPer100Calories: Double
        public let tier: Tier

        public init(
            adjustedPrice: Double,
            proteinPerDollar: Double,
            proteinPer100Calories: Double,
            tier: Tier
        ) {
            self.adjustedPrice = adjustedPrice
            self.proteinPerDollar = proteinPerDollar
            self.proteinPer100Calories = proteinPer100Calories
            self.tier = tier
        }
    }

    public static func score(
        protein: Double,
        calories: Double,
        listedPrice: Double,
        priceMultiplier: Double = 1
    ) -> Score? {
        guard listedPrice.isFinite,
              listedPrice > 0,
              priceMultiplier.isFinite,
              priceMultiplier > 0 else {
            return nil
        }

        let safeProtein = protein.isFinite ? max(0, protein) : 0
        let safeCalories = calories.isFinite ? max(0, calories) : 0
        let adjustedPrice = listedPrice * priceMultiplier
        guard adjustedPrice.isFinite, adjustedPrice > 0 else { return nil }

        let proteinPerDollar = safeProtein / adjustedPrice
        let proteinPer100Calories = safeCalories > 0 ? safeProtein / safeCalories * 100 : 0
        let tier: Tier
        if proteinPerDollar >= 2.2 {
            tier = .highProteinValue
        } else if proteinPerDollar >= 1.5 {
            tier = .balancedValue
        } else {
            tier = .lowerProteinValue
        }

        return Score(
            adjustedPrice: adjustedPrice,
            proteinPerDollar: proteinPerDollar,
            proteinPer100Calories: proteinPer100Calories,
            tier: tier
        )
    }
}
