import Foundation

/// One privacy-conscious action suitable for compact surfaces such as widgets and Watch.
/// It carries no food names, workout names, account identifiers, or health samples.
public struct DailyNextAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case preWorkoutFuel = "pre_workout_fuel"
        case recoveryMeal = "recovery_meal"
        case proteinCatchUp = "protein_catch_up"
        case trustReview = "trust_review"
        case steadyDay = "steady_day"
    }

    public let kind: Kind
    public let title: String
    public let detail: String
    public let deepLink: String
    public let proteinGrams: Int?
    public let carbGrams: Int?

    public init(
        kind: Kind,
        title: String,
        detail: String,
        deepLink: String,
        proteinGrams: Int? = nil,
        carbGrams: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.deepLink = deepLink
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
    }
}
