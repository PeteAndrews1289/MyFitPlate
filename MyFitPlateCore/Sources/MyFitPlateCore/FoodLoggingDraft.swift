import Foundation

public struct FoodLoggingDraft: Codable, Identifiable {
    public let id: UUID
    public var date: Date
    /// New manual destinations can freeze their civil day. Legacy/submitted drafts keep
    /// their original date and nil context; decoding never invents a new destination.
    public var dayContext: DiaryDayContext?
    public var trainingFuelTarget: TrainingFuelTarget?
    public var mealName: String
    public var entries: [Entry]
    /// Once a save begins, keep the exact payload for safe retry after interruption.
    public var isSubmitted: Bool

    public init(date: Date, mealName: String, dayContext: DiaryDayContext? = nil, trainingFuelTarget: TrainingFuelTarget? = nil) {
        id = UUID()
        self.date = dayContext?.originalDate ?? Calendar.current.startOfDay(for: date)
        self.dayContext = dayContext
        self.trainingFuelTarget = trainingFuelTarget
        self.mealName = mealName
        entries = []
        isSubmitted = false
    }

    public struct Entry: Codable, Identifiable {
        public let id: String
        public let sourceID: String
        public var food: FoodItem
        public var multiplier: Double
        /// A durable preview is checkpointed before asynchronous detail hydration begins.
        public var hydrationPending: Bool?

        public init(food: FoodItem, sourceID: String? = nil, now: Date = Date()) {
            id = UUID().uuidString
            self.sourceID = sourceID ?? food.id
            self.food = food
            self.food.timestamp = now
            multiplier = 1
        }

        public var preparedFood: FoodItem? {
            guard var result = FoodRepeatRules.adjusting(food, by: multiplier) else { return nil }
            result.id = id
            return result
        }
    }

    public var foods: [FoodItem] { entries.compactMap(\.preparedFood) }
    public var hasPendingHydration: Bool { entries.contains { $0.hydrationPending == true } }
    public var isReadyToSubmit: Bool { !entries.isEmpty && !hasPendingHydration && foods.count == entries.count }
    public var calories: Double { foods.reduce(0) { $0 + $1.calories } }
    public var protein: Double { foods.reduce(0) { $0 + $1.protein } }
}
