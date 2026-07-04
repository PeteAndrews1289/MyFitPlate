import Foundation

/// Restaurant prices swing hard between metros; groceries much less. Each city carries a
/// restaurant multiplier over the national-baseline catalog, deliberately calibrated to
/// mid-range neighborhood spots — never the premium end. Home costs use a dampened
/// version of the same multiplier (grocery variance is roughly 40% of menu variance).
public struct AYCECity: Codable, Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    /// Multiplier over national-average mid-range menu prices.
    public let restaurantMultiplier: Double

    public var id: String { slug }

    public init(slug: String, name: String, restaurantMultiplier: Double) {
        self.slug = slug
        self.name = name
        self.restaurantMultiplier = restaurantMultiplier
    }

    /// Grocery prices track city cost far more weakly than menus do.
    public var homeMultiplier: Double {
        1 + (restaurantMultiplier - 1) * 0.4
    }
}

public enum AYCECityIndex {

    public static let national = AYCECity(slug: "us_average", name: "US average", restaurantMultiplier: 1.0)

    /// Mid-market calibration: the multiplier says what a typical neighborhood AYCE-adjacent
    /// menu runs in each metro, not what the famous places charge.
    public static let cities: [AYCECity] = [
        AYCECity(slug: "nyc", name: "New York", restaurantMultiplier: 1.30),
        AYCECity(slug: "sf", name: "San Francisco", restaurantMultiplier: 1.28),
        AYCECity(slug: "la", name: "Los Angeles", restaurantMultiplier: 1.18),
        AYCECity(slug: "seattle", name: "Seattle", restaurantMultiplier: 1.16),
        AYCECity(slug: "boston", name: "Boston", restaurantMultiplier: 1.16),
        AYCECity(slug: "dc", name: "Washington, DC", restaurantMultiplier: 1.14),
        AYCECity(slug: "san_diego", name: "San Diego", restaurantMultiplier: 1.10),
        AYCECity(slug: "miami", name: "Miami", restaurantMultiplier: 1.08),
        AYCECity(slug: "chicago", name: "Chicago", restaurantMultiplier: 1.06),
        AYCECity(slug: "philadelphia", name: "Philadelphia", restaurantMultiplier: 1.04),
        AYCECity(slug: "denver", name: "Denver", restaurantMultiplier: 1.04),
        AYCECity(slug: "austin", name: "Austin", restaurantMultiplier: 1.00),
        AYCECity(slug: "atlanta", name: "Atlanta", restaurantMultiplier: 0.98),
        AYCECity(slug: "dallas", name: "Dallas", restaurantMultiplier: 0.97),
        AYCECity(slug: "phoenix", name: "Phoenix", restaurantMultiplier: 0.96),
        AYCECity(slug: "houston", name: "Houston", restaurantMultiplier: 0.94)
    ]

    /// All picker options, national baseline first.
    public static var pickerOptions: [AYCECity] {
        [national] + cities
    }

    /// Unknown or nil slugs resolve to the national baseline — never a crash, never a
    /// surprise multiplier.
    public static func city(slug: String?) -> AYCECity {
        guard let slug else { return national }
        return pickerOptions.first { $0.slug == slug } ?? national
    }
}
