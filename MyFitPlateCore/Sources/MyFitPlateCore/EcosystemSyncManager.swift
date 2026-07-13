import Foundation
import WidgetKit

public class EcosystemSyncManager {
    public static let shared = EcosystemSyncManager()
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
    public func updateWidgetData(
        log: DailyLog?,
        goals: GoalSettings?,
        trainingFuelPlan: TrainingFuelConfirmedPlan? = nil,
        now: Date = Date()
    ) {
        guard let log = log,
              let goals = goals,
              Calendar.current.isDate(log.date, inSameDayAs: now) else { return }
        let consistencyStatus = log.calorieConsistencyStatus()
        let fuelGoals = TodayFuelPlanGoals(
            calories: goals.calories ?? 0,
            protein: goals.protein,
            carbs: goals.carbs,
            fats: goals.fats
        )
        let nextAction = DailyNextActionRules.makeAction(
            plan: trainingFuelPlan,
            today: log,
            goals: fuelGoals,
            now: now
        )
        let previousData = SharedDataManager.shared.loadData()
        let shouldKeepPath = previousData?.pathDate.map {
            Calendar.current.isDate($0, inSameDayAs: now)
        } ?? false

        let widgetData = WidgetData(
            calories: log.totalCalories(),
            calorieGoal: goals.calories ?? 0,
            protein: log.totalMacros().protein,
            proteinGoal: goals.protein,
            carbs: log.totalMacros().carbs,
            carbsGoal: goals.carbs,
            fats: log.totalMacros().fats,
            fatGoal: goals.fats,
            lastUpdated: now,
            macroCalorieDelta: consistencyStatus.hasMeaningfulMismatch ? consistencyStatus.delta : nil,
            nextAction: nextAction,
            pathEvents: shouldKeepPath ? previousData?.pathEvents : nil,
            pathDate: shouldKeepPath ? previousData?.pathDate : nil
        )
        
        if SharedDataManager.shared.saveData(widgetData) {
            WidgetCenter.shared.reloadTimelines(ofKind: calorieWidgetKind)
        }
    }

    /// Adds the privacy-safe current Fuel Path segment to medium and large widgets. Passing nil
    /// removes only the path projection and preserves the existing nutrition/action payload.
    public func updateWidgetPath(snapshot: LivingDaySnapshot?) {
        let previous = SharedDataManager.shared.loadData()
        let isCurrentDay = snapshot.map { Calendar.current.isDateInToday($0.date) } ?? false

        guard previous != nil || (snapshot != nil && isCurrentDay) else { return }

        let calories = snapshot?.budget.calories.consumed ?? previous?.calories ?? 0
        let calorieGoal = snapshot?.budget.calories.target ?? previous?.calorieGoal ?? 0
        let protein = snapshot?.budget.protein.consumed ?? previous?.protein ?? 0
        let proteinGoal = snapshot?.budget.protein.target ?? previous?.proteinGoal ?? 0
        let carbs = snapshot?.budget.carbs.consumed ?? previous?.carbs ?? 0
        let carbsGoal = snapshot?.budget.carbs.target ?? previous?.carbsGoal ?? 0
        let fats = snapshot?.budget.fats.consumed ?? previous?.fats ?? 0
        let fatGoal = snapshot?.budget.fats.target ?? previous?.fatGoal ?? 0

        let widgetData = WidgetData(
            calories: calories,
            calorieGoal: calorieGoal,
            protein: protein,
            proteinGoal: proteinGoal,
            carbs: carbs,
            carbsGoal: carbsGoal,
            fats: fats,
            fatGoal: fatGoal,
            lastUpdated: snapshot?.generatedAt ?? previous?.lastUpdated,
            macroCalorieDelta: previous?.macroCalorieDelta,
            nextAction: snapshot?.nextAction ?? previous?.nextAction,
            pathEvents: isCurrentDay ? snapshot.map { WidgetPathProjection.make(from: $0) } : nil,
            pathDate: isCurrentDay ? snapshot?.date : nil
        )

        if SharedDataManager.shared.saveData(widgetData) {
            WidgetCenter.shared.reloadTimelines(ofKind: calorieWidgetKind)
        }
    }
}
