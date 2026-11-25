#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct AYCEActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var buffetPriceText: String
        public var currentValueText: String
        public var itemsCount: Double
        public var statusText: String
        public var isBeaten: Bool

        public init(buffetPriceText: String, currentValueText: String, itemsCount: Double, statusText: String, isBeaten: Bool) {
            self.buffetPriceText = buffetPriceText
            self.currentValueText = currentValueText
            self.itemsCount = itemsCount
            self.statusText = statusText
            self.isBeaten = isBeaten
        }
    }

    public var cuisineName: String // e.g. "Sushi Buffet"
    public var sessionID: String?
    public var accountKey: String?

    public init(cuisineName: String, sessionID: String? = nil, accountKey: String? = nil) {
        self.cuisineName = cuisineName
        self.sessionID = sessionID
        self.accountKey = accountKey
    }
}
#endif
