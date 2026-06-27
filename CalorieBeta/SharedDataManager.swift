import Foundation

private enum SharedDataKeys {
    static let appGroup = "group.com.peterandrews.CalorieBeta"
    static let widgetData = "widgetData"
    static let pendingWater = "pendingWaterOunces"
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
        guard let userDefaults = userDefaults else {
            AppLog.app.error("Unable to access shared app group defaults for widget data.")
            return false
        }

        do {
            let encodedData = try JSONEncoder().encode(data)
            userDefaults.set(encodedData, forKey: SharedDataKeys.widgetData)
            return true
        } catch {
            AppLog.app.error("Unable to encode widget data: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func loadData() -> WidgetData? {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: SharedDataKeys.widgetData) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(WidgetData.self, from: data)
        } catch {
            AppLog.app.error("Unable to decode widget data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func logPendingWater(ounces: Double) {
        guard let userDefaults = userDefaults else { return }
        let currentPending = userDefaults.double(forKey: SharedDataKeys.pendingWater)
        userDefaults.set(currentPending + ounces, forKey: SharedDataKeys.pendingWater)
    }

    func getAndClearPendingWater() -> Double {
        guard let userDefaults = userDefaults else { return 0 }
        let pending = userDefaults.double(forKey: SharedDataKeys.pendingWater)
        userDefaults.set(0.0, forKey: SharedDataKeys.pendingWater)
        return pending
    }

    /// Wipes the app-group data shared with the widget — used when an account is deleted.
    func clearWidgetData() {
        guard let userDefaults = userDefaults else { return }
        userDefaults.removeObject(forKey: SharedDataKeys.widgetData)
        userDefaults.removeObject(forKey: SharedDataKeys.pendingWater)
    }
}
