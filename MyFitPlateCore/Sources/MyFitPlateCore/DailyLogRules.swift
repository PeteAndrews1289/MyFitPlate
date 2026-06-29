import Foundation

public struct DailyLogRules {
    
    public static func determineMealType(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<4: return "Snack"
        case 4..<11: return "Breakfast"
        case 11..<16: return "Lunch"
        case 16..<21: return "Dinner"
        default: return "Snack"
        }
    }
    
    public static func addFoodToLog(log: inout DailyLog, foodItem: FoodItem, mealName: String, source: String = "unknown") -> FoodItem {
        var itemToAdd = foodItem.normalizedForEstimatedSource(source)
        if itemToAdd.timestamp == nil { itemToAdd.timestamp = Date() }
        if let index = log.meals.firstIndex(where: { $0.name == mealName }) {
            log.meals[index].foodItems.append(itemToAdd)
        } else {
            log.meals.append(Meal(name: mealName, foodItems: [itemToAdd]))
        }
        return itemToAdd
    }
    
    public static func addMealGroupsToLog(log: inout DailyLog, mealGroups: [(mealName: String, foodItems: [FoodItem])], defaultSource: String = "recipe") -> (addedItems: [FoodItem], sourceUsed: String) {
        let nonEmptyGroups = mealGroups.filter { !$0.foodItems.isEmpty }
        guard !nonEmptyGroups.isEmpty else { return ([], defaultSource) }
        let itemSource = nonEmptyGroups.contains(where: { $0.mealName.lowercased().contains("ai") }) ? "ai_bulk" : defaultSource

        var allItemsWithTimestamp: [FoodItem] = []

        for group in nonEmptyGroups {
            let itemsWithTimestamp = group.foodItems.map { item -> FoodItem in
                var mutableItem = item.normalizedForEstimatedSource(itemSource)
                if mutableItem.timestamp == nil { mutableItem.timestamp = Date() }
                return mutableItem
            }
            allItemsWithTimestamp.append(contentsOf: itemsWithTimestamp)

            if let index = log.meals.firstIndex(where: { $0.name == group.mealName }) {
                log.meals[index].foodItems.append(contentsOf: itemsWithTimestamp)
            } else {
                let newMeal = Meal(name: group.mealName, foodItems: itemsWithTimestamp)
                log.meals.append(newMeal)
            }
        }
        return (allItemsWithTimestamp, itemSource)
    }
    
    public static func updateFoodInLog(log: inout DailyLog, updatedFoodItem: FoodItem) -> (updated: Bool, previousFoodItem: FoodItem?) {
        var itemUpdated = false
        var previousFoodItem: FoodItem?
        for i in 0..<log.meals.count {
            if let index = log.meals[i].foodItems.firstIndex(where: { $0.id == updatedFoodItem.id }) {
                previousFoodItem = log.meals[i].foodItems[index]
                log.meals[i].foodItems[index] = updatedFoodItem
                itemUpdated = true
                break
            }
        }
        return (itemUpdated, previousFoodItem)
    }
    
    public static func deleteFoodFromLog(log: inout DailyLog, foodItemID: String) -> (deleted: Bool, removedFoodItem: FoodItem?, foodName: String?) {
        var deleted = false
        var foodName: String?
        var removedFoodItem: FoodItem?
        for i in log.meals.indices {
            let initialCount = log.meals[i].foodItems.count
            if let itemToRemove = log.meals[i].foodItems.first(where: { $0.id == foodItemID }) {
                foodName = itemToRemove.name
                removedFoodItem = itemToRemove
            }
            log.meals[i].foodItems.removeAll { $0.id == foodItemID }
            if log.meals[i].foodItems.count < initialCount { deleted = true }
        }
        return (deleted, removedFoodItem, foodName)
    }
    
    public static func addWaterToLog(log: inout DailyLog, amount: Double, goalOunces: Double, dateToLog: Date) {
        if var waterTracker = log.waterTracker {
            waterTracker.totalOunces += amount
            if waterTracker.totalOunces < 0 {
                waterTracker.totalOunces = 0
            }
            waterTracker.goalOunces = goalOunces
            log.waterTracker = waterTracker
        } else {
            let initialAmount = max(0, amount)
            log.waterTracker = WaterTracker(totalOunces: initialAmount, goalOunces: goalOunces, date: Calendar.current.startOfDay(for: dateToLog))
        }
    }
    
    public static func addWorkoutToLog(log: inout DailyLog, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double, timestamp: Date = Date()) {
        let exercise = LoggedExercise(
            name: exerciseName,
            durationMinutes: durationMinutes,
            caloriesBurned: caloriesBurned,
            date: timestamp,
            source: "ai_chat"
        )
        
        if log.exercises == nil {
            log.exercises = []
        }
        log.exercises?.append(exercise)
    }
    
    public static func repeatFoods(from sourceLog: DailyLog) -> [(mealName: String, foodItems: [FoodItem])] {
        let mealGroups: [(mealName: String, foodItems: [FoodItem])] = sourceLog.meals.compactMap { meal in
            let repeatedItems = meal.foodItems.map { item -> FoodItem in
                var repeated = item
                repeated.id = UUID().uuidString
                repeated.timestamp = Date()
                return repeated
            }
            return repeatedItems.isEmpty ? nil : (mealName: meal.name, foodItems: repeatedItems)
        }
        return mealGroups
    }
}
