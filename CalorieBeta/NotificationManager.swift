import SwiftUI
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

/// Manages local notifications for the CalorieBeta app.
/// Schedules daily reminders to log food and displays remaining calories.
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private let db = Firestore.firestore()

    /// Schedules a daily reminder to log food at a specified time.
    /// The notification includes the remaining calories for the day.
    /// - Parameters:
    ///   - hour: The hour of the day to send the notification (24-hour format).
    ///   - minute: The minute of the hour to send the notification.
    func scheduleDailyReminder(atHour hour: Int, minute: Int) {
        // Remove any existing reminders to avoid duplicates
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyMealReminder"])

        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Time to Log Your Meal!"
        content.sound = .default
        content.badge = 1 // Update the app badge to 1

        // Fetch the user's calorie goal and daily log to calculate remaining calories
        if let userID = Auth.auth().currentUser?.uid {
            fetchUserData(userID: userID) { calorieGoal, caloriesConsumed in
                let remainingCalories = max(0, calorieGoal - caloriesConsumed)
                content.body = "Don't forget to log your meals! You have \(Int(remainingCalories)) calories left for today."
                
                // Set up the trigger for the notification
                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

                // Create and schedule the notification request
                let request = UNNotificationRequest(identifier: "dailyMealReminder", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Error scheduling reminder: \(error.localizedDescription)")
                    } else {
                        print("✅ Daily reminder scheduled for \(hour):\(minute)")
                    }
                }
            }
        } else {
            // If no user is logged in, schedule a generic reminder
            content.body = "Don't forget to log your meals today!"
            
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let request = UNNotificationRequest(identifier: "dailyMealReminder", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Error scheduling reminder: \(error.localizedDescription)")
                } else {
                    print("✅ Daily reminder scheduled for \(hour):\(minute) (generic)")
                }
            }
        }
    }

    /// Fetches the user's calorie goal and daily calorie consumption from Firestore.
    /// - Parameters:
    ///   - userID: The ID of the user to fetch data for.
    ///   - completion: A closure that returns the calorie goal and consumed calories.
    private func fetchUserData(userID: String, completion: @escaping (Double, Double) -> Void) {
        // Fetch the user's calorie goal from the 'goals' map in the user document
        db.collection("users").document(userID).getDocument { document, error in
            var calorieGoal: Double = 2000 // Default if not found
            if let document = document, document.exists,
               let data = document.data(),
               let goals = data["goals"] as? [String: Any],
               let goalCalories = goals["calories"] as? Double {
                calorieGoal = goalCalories
            } else {
                print("⚠️ Could not fetch calorie goal for user \(userID), using default: \(calorieGoal)")
            }

            // Fetch today's daily log
            let today = Calendar.current.startOfDay(for: Date())
            self.db.collection("users").document(userID).collection("dailyLogs")
                .whereField("date", isEqualTo: Timestamp(date: today))
                .getDocuments { snapshot, error in
                    var caloriesConsumed: Double = 0
                    if let error = error {
                        print("❌ Error fetching daily log: \(error.localizedDescription)")
                        completion(calorieGoal, caloriesConsumed)
                        return
                    }

                    guard let document = snapshot?.documents.first else {
                        print("ℹ️ No daily log found for today for user \(userID)")
                        completion(calorieGoal, caloriesConsumed)
                        return
                    }

                    let data = document.data()
                    // Check if the 'meals' field exists and cast it to an array of dictionaries
                    if let meals = data["meals"] as? [[String: Any]] {
                        for meal in meals {
                            // Check if the 'foodItems' field exists and cast it to an array of dictionaries
                            if let foodItems = meal["foodItems"] as? [[String: Any]] {
                                for item in foodItems {
                                    // Extract the 'calories' field as a Double
                                    if let calories = item["calories"] as? Double {
                                        caloriesConsumed += calories
                                    } else {
                                        print("⚠️ Could not parse calories for food item: \(item)")
                                    }
                                }
                            } else {
                                print("⚠️ No foodItems found in meal: \(meal)")
                            }
                        }
                    } else {
                        print("ℹ️ No meals found in daily log for user \(userID) on \(today)")
                    }

                    print("📊 Fetched for user \(userID): Calorie Goal = \(calorieGoal), Calories Consumed = \(caloriesConsumed)")
                    completion(calorieGoal, caloriesConsumed)
                }
        }
    }
}
