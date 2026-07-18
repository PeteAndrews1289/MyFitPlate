import Foundation

private enum SharedDataKeys {
    static let appGroup = "group.com.peterandrews.CalorieBeta"
    static let widgetData = "widgetData"
    static let pendingWater = "pendingWaterOunces"
}

public struct WidgetData: Codable, Equatable, Sendable {
    public let calories: Double
    public let calorieGoal: Double
    public let protein: Double
    public let proteinGoal: Double
    public let carbs: Double
    public let carbsGoal: Double
    public let fats: Double
    public let fatGoal: Double
    public var lastUpdated: Date? = nil
    public var macroCalorieDelta: Double? = nil
    public var nextAction: DailyNextAction? = nil
    public var pathEvents: [WidgetPathEvent]? = nil
    public var pathDate: Date? = nil

    public init(
        calories: Double,
        calorieGoal: Double,
        protein: Double,
        proteinGoal: Double,
        carbs: Double,
        carbsGoal: Double,
        fats: Double,
        fatGoal: Double,
        lastUpdated: Date? = nil,
        macroCalorieDelta: Double? = nil,
        nextAction: DailyNextAction? = nil,
        pathEvents: [WidgetPathEvent]? = nil,
        pathDate: Date? = nil
    ) {
        self.calories = calories
        self.calorieGoal = calorieGoal
        self.protein = protein
        self.proteinGoal = proteinGoal
        self.carbs = carbs
        self.carbsGoal = carbsGoal
        self.fats = fats
        self.fatGoal = fatGoal
        self.lastUpdated = lastUpdated
        self.macroCalorieDelta = macroCalorieDelta
        self.nextAction = nextAction
        self.pathEvents = pathEvents
        self.pathDate = pathDate
    }

    public static var previewData: WidgetData {
        .init(
            calories: 1_250,
            calorieGoal: 2_400,
            protein: 110,
            proteinGoal: 150,
            carbs: 180,
            carbsGoal: 250,
            fats: 25,
            fatGoal: 70,
            lastUpdated: Date(),
            macroCalorieDelta: nil,
            nextAction: DailyNextAction(
                kind: .preWorkoutFuel,
                title: "Fuel before training",
                detail: "15 g protein + 35 g carbs",
                deepLink: "myfitplate://training-fuel",
                proteinGrams: 15,
                carbGrams: 35
            ),
            pathEvents: [
                WidgetPathEvent(
                    kind: .meal,
                    state: .completed,
                    sequence: 0,
                    startDate: Date().addingTimeInterval(-3_600),
                    isApproximate: false,
                    needsTrustReview: false
                ),
                WidgetPathEvent(
                    kind: .strength,
                    state: .planned,
                    sequence: 1,
                    startDate: Date().addingTimeInterval(2_700),
                    isApproximate: false,
                    needsTrustReview: false
                ),
                WidgetPathEvent(
                    kind: .recovery,
                    state: .planned,
                    sequence: 2,
                    startDate: Date().addingTimeInterval(6_300),
                    isApproximate: false,
                    needsTrustReview: false
                )
            ],
            pathDate: Date()
        )
    }
}

public struct SharedDataManager {
    public static let shared = SharedDataManager()
    private let userDefaults = UserDefaults(suiteName: SharedDataKeys.appGroup)

    public func saveData(_ data: WidgetData) -> Bool {
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

    public func loadData() -> WidgetData? {
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

    public func logPendingWater(ounces: Double) {
        guard let userDefaults = userDefaults else { return }
        let currentPending = userDefaults.double(forKey: SharedDataKeys.pendingWater)
        userDefaults.set(currentPending + ounces, forKey: SharedDataKeys.pendingWater)
    }

    public func getAndClearPendingWater() -> Double {
        guard let userDefaults = userDefaults else { return 0 }
        let pending = userDefaults.double(forKey: SharedDataKeys.pendingWater)
        userDefaults.set(0.0, forKey: SharedDataKeys.pendingWater)
        return pending
    }

    /// Wipes the app-group data shared with the widget — used when an account is deleted.
    public func clearWidgetData() {
        guard let userDefaults = userDefaults else { return }
        userDefaults.removeObject(forKey: SharedDataKeys.widgetData)
        userDefaults.removeObject(forKey: SharedDataKeys.pendingWater)
    }
}
