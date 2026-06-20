import Foundation

private enum SharedDataKeys {
    static let appGroup = "group.com.peterandrews.CalorieBeta"
    static let widgetData = "widgetData"
}

struct WidgetData: Codable {
    let calories: Double
    let calorieGoal: Double
    let protein: Double
    let proteinGoal: Double
    let carbs: Double
    let carbsGoal: Double
    let fats: Double
    let fatGoal: Double
    var lastUpdated: Date? = nil
    var macroCalorieDelta: Double? = nil

    static var previewData: WidgetData {
        .init(calories: 1250, calorieGoal: 2400, protein: 110, proteinGoal: 150, carbs: 180, carbsGoal: 250, fats: 25, fatGoal: 70, lastUpdated: Date(), macroCalorieDelta: nil)
    }
}

struct SharedDataManager {
    static let shared = SharedDataManager()
    private let userDefaults = UserDefaults(suiteName: SharedDataKeys.appGroup)

    func saveData(_ data: WidgetData) -> Bool {
        guard let userDefaults = userDefaults else { return false }

        do {
            let encodedData = try JSONEncoder().encode(data)
            userDefaults.set(encodedData, forKey: SharedDataKeys.widgetData)
            return true
        } catch {
            return false
        }
    }

    func loadData() -> WidgetData? {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: SharedDataKeys.widgetData) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }
}
