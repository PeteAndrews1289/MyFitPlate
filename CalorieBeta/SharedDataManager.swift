import Foundation

// A simple struct to hold the data our widget needs.
struct WidgetData: Codable {
    let calories: Double
    let calorieGoal: Double
    let protein: Double
    let proteinGoal: Double
    let carbs: Double
    let carbsGoal: Double
    let fats: Double
    let fatGoal: Double

    // A static property for placeholder data used in previews.
    static var previewData: WidgetData {
        .init(calories: 1250, calorieGoal: 2400, protein: 110, proteinGoal: 150, carbs: 180, carbsGoal: 250, fats: 25, fatGoal: 70)
    }
}

// This manager handles saving and loading widget data to the shared space.
struct SharedDataManager {
    // The location of our shared data.
    static let shared = SharedDataManager()
    private let userDefaults = UserDefaults(suiteName: "group.com.peterandrews.CalorieBeta") // <-- IMPORTANT: Use your App Group name here

    // Saves the widget data.
    func saveData(_ data: WidgetData) {
        guard let userDefaults = userDefaults else { return }
        if let encodedData = try? JSONEncoder().encode(data) {
            userDefaults.set(encodedData, forKey: "widgetData")
        }
    }

    // Loads the widget data.
    func loadData() -> WidgetData? {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: "widgetData") else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }
}
