import Foundation

public extension Notification.Name {
    static let foodItemLogged = Notification.Name("FoodItemLogged")
    static let didUpdateExerciseLog = Notification.Name("didUpdateExerciseLog")
    static let openTrainingFuelPlanner = Notification.Name("OpenTrainingFuelPlanner")
    static let trainingFuelNotificationPreferencesChanged = Notification.Name("TrainingFuelNotificationPreferencesChanged")
    static let mealPlanChanged = Notification.Name("MealPlanChanged")
}

public enum DailyLogNotificationUserInfoKey {
    static let foodItem = "foodItem"
    static let userID = "userID"
}

public enum DailyLogNotifications {
    public struct FoodLoggedPayload: Equatable, Sendable {
        public let foodItem: FoodItem
        public let userID: String

        public init(foodItem: FoodItem, userID: String) {
            self.foodItem = foodItem
            self.userID = userID
        }
    }

    static func postFoodLogged(_ foodItem: FoodItem, userID: String, center: NotificationCenter = .default) {
        center.post(
            name: .foodItemLogged,
            object: nil,
            userInfo: [
                DailyLogNotificationUserInfoKey.foodItem: foodItem,
                DailyLogNotificationUserInfoKey.userID: userID
            ]
        )
    }

    public static func foodLoggedPayload(from notification: Notification) -> FoodLoggedPayload? {
        guard notification.name == .foodItemLogged,
              let foodItem = notification.userInfo?[DailyLogNotificationUserInfoKey.foodItem] as? FoodItem,
              let userID = notification.userInfo?[DailyLogNotificationUserInfoKey.userID] as? String,
              !userID.isEmpty else { return nil }
        return FoodLoggedPayload(foodItem: foodItem, userID: userID)
    }
}
