import XCTest
@testable import MyFitPlateCore

final class DailyLogRulesTests: XCTestCase {

    func testDetermineMealType() {
        // Breakfast is 4-11
        var components = DateComponents()
        components.hour = 8
        let breakfastTime = Calendar.current.date(from: components)!
        XCTAssertEqual(DailyLogRules.determineMealType(for: breakfastTime), "Breakfast")

        // Lunch is 11-16
        components.hour = 12
        let lunchTime = Calendar.current.date(from: components)!
        XCTAssertEqual(DailyLogRules.determineMealType(for: lunchTime), "Lunch")

        // Dinner is 16-21
        components.hour = 18
        let dinnerTime = Calendar.current.date(from: components)!
        XCTAssertEqual(DailyLogRules.determineMealType(for: dinnerTime), "Dinner")

        // Snack is 21+ or < 4
        components.hour = 22
        let snackTime = Calendar.current.date(from: components)!
        XCTAssertEqual(DailyLogRules.determineMealType(for: snackTime), "Snack")
    }

    func testAddFoodToLog() {
        var log = DailyLog(date: Date(), meals: [])
        let food = FoodItem(id: "1", name: "Apple", calories: 95, protein: 0.5, carbs: 25, fats: 0.3)
        
        let added = DailyLogRules.addFoodToLog(log: &log, foodItem: food, mealName: "Snack")
        
        XCTAssertEqual(log.meals.count, 1)
        XCTAssertEqual(log.meals[0].name, "Snack")
        XCTAssertEqual(log.meals[0].foodItems.count, 1)
        XCTAssertEqual(log.meals[0].foodItems[0].name, "Apple")
        XCTAssertNotNil(added.timestamp)
        
        // Add to existing meal
        let food2 = FoodItem(id: "2", name: "Banana", calories: 105, protein: 1.3, carbs: 27, fats: 0.4)
        _ = DailyLogRules.addFoodToLog(log: &log, foodItem: food2, mealName: "Snack")
        
        XCTAssertEqual(log.meals.count, 1)
        XCTAssertEqual(log.meals[0].foodItems.count, 2)
        XCTAssertEqual(log.meals[0].foodItems[1].name, "Banana")
    }

    func testAddMealGroupsToLog() {
        var log = DailyLog(date: Date(), meals: [])
        let food1 = FoodItem(id: "1", name: "Apple", calories: 95, protein: 0.5, carbs: 25, fats: 0.3)
        let food2 = FoodItem(id: "2", name: "Banana", calories: 105, protein: 1.3, carbs: 27, fats: 0.4)
        
        let groups = [
            (mealName: "Breakfast", foodItems: [food1]),
            (mealName: "Lunch", foodItems: [food2])
        ]
        
        let (added, source) = DailyLogRules.addMealGroupsToLog(log: &log, mealGroups: groups, defaultSource: "test_source")
        
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(source, "test_source")
        XCTAssertEqual(log.meals.count, 2)
        XCTAssertEqual(log.meals[0].name, "Breakfast")
        XCTAssertEqual(log.meals[1].name, "Lunch")
        XCTAssertEqual(log.meals[0].foodItems[0].name, "Apple")
    }

    func testUpdateFoodInLog() {
        let food1 = FoodItem(id: "1", name: "Apple", calories: 95, protein: 0.5, carbs: 25, fats: 0.3)
        var log = DailyLog(date: Date(), meals: [Meal(name: "Breakfast", foodItems: [food1])])
        
        let updatedFood = FoodItem(id: "1", name: "Apple Updated", calories: 100, protein: 1.0, carbs: 25, fats: 0.3)
        let (updated, prev) = DailyLogRules.updateFoodInLog(log: &log, updatedFoodItem: updatedFood)
        
        XCTAssertTrue(updated)
        XCTAssertEqual(prev?.name, "Apple")
        XCTAssertEqual(log.meals[0].foodItems[0].name, "Apple Updated")
        XCTAssertEqual(log.meals[0].foodItems[0].calories, 100)
    }

    func testDeleteFoodFromLog() {
        let food1 = FoodItem(id: "1", name: "Apple", calories: 95, protein: 0.5, carbs: 25, fats: 0.3)
        let food2 = FoodItem(id: "2", name: "Banana", calories: 105, protein: 1.3, carbs: 27, fats: 0.4)
        var log = DailyLog(date: Date(), meals: [Meal(name: "Breakfast", foodItems: [food1, food2])])
        
        let (deleted, removed, name) = DailyLogRules.deleteFoodFromLog(log: &log, foodItemID: "1")
        
        XCTAssertTrue(deleted)
        XCTAssertEqual(name, "Apple")
        XCTAssertEqual(removed?.id, "1")
        XCTAssertEqual(log.meals[0].foodItems.count, 1)
        XCTAssertEqual(log.meals[0].foodItems[0].name, "Banana")
    }

    func testAddWaterToLog() {
        var log = DailyLog(date: Date(), meals: [])
        
        DailyLogRules.addWaterToLog(log: &log, amount: 8, goalOunces: 64, dateToLog: Date())
        
        XCTAssertNotNil(log.waterTracker)
        XCTAssertEqual(log.waterTracker?.totalOunces, 8)
        XCTAssertEqual(log.waterTracker?.goalOunces, 64)
        
        DailyLogRules.addWaterToLog(log: &log, amount: 16, goalOunces: 64, dateToLog: Date())
        XCTAssertEqual(log.waterTracker?.totalOunces, 24)
        
        // Test negative amount prevention (if it goes below 0)
        DailyLogRules.addWaterToLog(log: &log, amount: -30, goalOunces: 64, dateToLog: Date())
        XCTAssertEqual(log.waterTracker?.totalOunces, 0)
    }

    func testAddWorkoutToLog() {
        var log = DailyLog(date: Date(), meals: [])
        
        DailyLogRules.addWorkoutToLog(log: &log, exerciseName: "Running", durationMinutes: 30, caloriesBurned: 300)
        
        XCTAssertNotNil(log.exercises)
        XCTAssertEqual(log.exercises?.count, 1)
        XCTAssertEqual(log.exercises?[0].name, "Running")
        XCTAssertEqual(log.exercises?[0].durationMinutes, 30)
        XCTAssertEqual(log.exercises?[0].caloriesBurned, 300)
        XCTAssertEqual(log.exercises?[0].source, "ai_chat")
    }

    func testRepeatFoods() {
        let food1 = FoodItem(id: "1", name: "Apple", calories: 95, protein: 0.5, carbs: 25, fats: 0.3)
        let log = DailyLog(date: Date(), meals: [Meal(name: "Breakfast", foodItems: [food1])])
        
        let repeatedGroups = DailyLogRules.repeatFoods(from: log)
        
        XCTAssertEqual(repeatedGroups.count, 1)
        XCTAssertEqual(repeatedGroups[0].mealName, "Breakfast")
        XCTAssertEqual(repeatedGroups[0].foodItems.count, 1)
        
        let repeatedFood = repeatedGroups[0].foodItems[0]
        XCTAssertEqual(repeatedFood.name, "Apple")
        XCTAssertNotEqual(repeatedFood.id, "1") // ID should be new
        XCTAssertNotNil(repeatedFood.timestamp)
    }
}
