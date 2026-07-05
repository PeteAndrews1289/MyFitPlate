import Foundation

/// One finished buffet session, boiled down to what the scoreboard needs. Snapshot values
/// are computed at end-of-session (city multipliers applied), so later catalog or index
/// changes never rewrite history.
public struct AYCESessionRecord: Codable, Equatable, Identifiable {
    public let id: String
    public let cuisine: AYCECuisine
    public let date: Date
    public let buffetPrice: Double
    public let menuValue: Double
    public let kitchenSpend: Double
    public let calories: Double

    public init(session: AYCESession, endedAt: Date = Date()) {
        let totals = AYCERules.totals(for: session)
        self.id = session.id
        self.cuisine = session.cuisine
        self.date = endedAt
        self.buffetPrice = session.buffetPrice
        self.menuValue = totals.restaurantValue
        self.kitchenSpend = totals.restaurantFoodCost
        self.calories = totals.calories
    }

    public var beatSpot: Bool { buffetPrice > 0 && menuValue >= buffetPrice }
    public var beatKitchen: Bool { buffetPrice > 0 && kitchenSpend >= buffetPrice }
}

/// Lifetime record across sessions — the reason to come back next buffet.
public enum AYCEScoreboard {

    public static let maxRecords = 100

    /// Newest first, empty sessions ignored, capped so storage never grows unbounded.
    public static func appending(_ record: AYCESessionRecord, to records: [AYCESessionRecord]) -> [AYCESessionRecord] {
        guard record.menuValue > 0 else { return records }
        return Array(([record] + records).prefix(maxRecords))
    }

    public struct Summary: Equatable {
        public let sessions: Int
        public let wins: Int
        public let kitchenWins: Int
        /// Dollars of menu value eaten beyond the buffet price, summed over winning sessions.
        public let totalBeatenBy: Double

        public var losses: Int { sessions - wins }
    }

    public static func summary(of records: [AYCESessionRecord]) -> Summary {
        let wins = records.filter(\.beatSpot)
        return Summary(
            sessions: records.count,
            wins: wins.count,
            kitchenWins: records.filter(\.beatKitchen).count,
            totalBeatenBy: wins.reduce(0) { $0 + ($1.menuValue - $1.buffetPrice) }
        )
    }

    /// The start-screen record line; nil until there's a history worth bragging about.
    public static func recordLine(summary: Summary) -> String? {
        guard summary.sessions > 0 else { return nil }
        var parts: [String] = []
        parts.append(summary.wins == 1 ? "1 win" : "\(summary.wins) wins")
        parts.append(summary.losses == 1 ? "1 loss" : "\(summary.losses) losses")
        if summary.totalBeatenBy > 0 {
            parts.append("\(AYCERules.money(summary.totalBeatenBy)) beaten out of the spots")
        }
        if summary.kitchenWins > 0 {
            parts.append(summary.kitchenWins == 1 ? "1 kitchen defeated" : "\(summary.kitchenWins) kitchens defeated")
        }
        return parts.joined(separator: " · ")
    }
}
