import Foundation
import WidgetKit

public class EcosystemSyncManager {
    static let shared = EcosystemSyncManager()
    private let calorieWidgetKind = "CalorieWidget"
    
    private init() {}
    
    /// Syncs logged nutrition macros to Apple HealthKit
    public func syncNutritionToHealthKit(item: FoodItem) {
        HealthKitManager.shared.saveNutrition(for: item)
    }

    public func syncWaterToHealthKit(ounces: Double, date: Date = Date()) {
        HealthKitManager.shared.saveWater(ounces: ounces, date: date)
    }

    public func replaceNutritionInHealthKit(oldItem: FoodItem, newItem: FoodItem) {
        HealthKitManager.shared.replaceNutrition(oldItem: oldItem, newItem: newItem)
    }

    public func deleteNutritionFromHealthKit(item: FoodItem) {
        HealthKitManager.shared.deleteNutrition(for: item)
    }
    
    /// Syncs the current daily totals to the home screen widgets via UserDefaults App Group
    public func updateWidgetData(log: DailyLog?, goals: GoalSettings?) {
        guard let log = log, let goals = goals else { return }
        let consistencyStatus = log.calorieConsistencyStatus()

        let widgetData = WidgetData(
            calories: log.totalCalories(),
            calorieGoal: goals.calories ?? 0,
            protein: log.totalMacros().protein,
            proteinGoal: goals.protein,
            carbs: log.totalMacros().carbs,
            carbsGoal: goals.carbs,
            fats: log.totalMacros().fats,
            fatGoal: goals.fats,
            lastUpdated: Date(),
            macroCalorieDelta: consistencyStatus.hasMeaningfulMismatch ? consistencyStatus.delta : nil
        )
        
        if SharedDataManager.shared.saveData(widgetData) {
            WidgetCenter.shared.reloadTimelines(ofKind: calorieWidgetKind)
        }
    }
}
