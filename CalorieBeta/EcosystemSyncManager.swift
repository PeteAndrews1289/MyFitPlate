import Foundation
import WidgetKit

class EcosystemSyncManager {
    static let shared = EcosystemSyncManager()
    private let calorieWidgetKind = "CalorieWidget"
    
    private init() {}
    
    /// Syncs logged nutrition macros to Apple HealthKit
    func syncNutritionToHealthKit(item: FoodItem) {
        HealthKitManager.shared.saveNutrition(for: item)
    }

    func replaceNutritionInHealthKit(oldItem: FoodItem, newItem: FoodItem) {
        HealthKitManager.shared.replaceNutrition(oldItem: oldItem, newItem: newItem)
    }

    func deleteNutritionFromHealthKit(item: FoodItem) {
        HealthKitManager.shared.deleteNutrition(for: item)
    }
    
    /// Syncs the current daily totals to the home screen widgets via UserDefaults App Group
    func updateWidgetData(log: DailyLog?, goals: GoalSettings?) {
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
