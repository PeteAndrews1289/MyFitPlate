import Foundation

public extension Notification.Name {
    static let foodItemLogged = Notification.Name("FoodItemLogged")
    static let didUpdateExerciseLog = Notification.Name("didUpdateExerciseLog")
}

public enum DailyLogNotificationUserInfoKey {
    static let foodItem = "foodItem"
    static let userID = "userID"
}

public enum DailyLogNotifications {
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
}
