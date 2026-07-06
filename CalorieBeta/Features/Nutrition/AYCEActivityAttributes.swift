#if canImport(ActivityKit)
import ActivityKit
import Foundation

public struct AYCEActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var buffetPriceText: String
        public var currentValueText: String
        public var itemsCount: Int
        public var statusText: String
        public var isBeaten: Bool

        public init(buffetPriceText: String, currentValueText: String, itemsCount: Int, statusText: String, isBeaten: Bool) {
            self.buffetPriceText = buffetPriceText
            self.currentValueText = currentValueText
            self.itemsCount = itemsCount
            self.statusText = statusText
            self.isBeaten = isBeaten
        }
    }

    public var cuisineName: String // e.g. "Sushi Buffet"

    public init(cuisineName: String) {
        self.cuisineName = cuisineName
    }
}
#endif
