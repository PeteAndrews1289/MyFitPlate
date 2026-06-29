import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlanAIGeneratorTests: XCTestCase {
    func testParseSingleMealMapsNutritionIngredientsAndInstructions() throws {
        let generator = MealPlanAIGenerator()
        let meal = try generator.parseSingleMealFromAIResponse("""
        {
          "mealType": "Lunch",
          "mealName": "Chicken Rice Bowl",
          "calories": 520,
          "protein": 42,
          "carbs": 55,
          "fats": 14,
          "ingredients": ["1 lb chicken breast", "1 bag frozen rice"],
          "instructions": ["Cook chicken", "Serve over rice"]
        }
        """)

        XCTAssertEqual(meal.mealType, "Lunch")
        XCTAssertEqual(meal.foodItem?.name, "Chicken Rice Bowl")
        XCTAssertEqual(meal.foodItem?.calories, 520)
        XCTAssertEqual(meal.foodItem?.protein, 42)
        XCTAssertEqual(meal.ingredients, ["1 lb chicken breast", "1 bag frozen rice"])
        XCTAssertEqual(meal.instructions, "Cook chicken\nServe over rice")
    }

    func testParseDayPlanReturnsMealsFromRootMealsArray() throws {
        let generator = MealPlanAIGenerator()
        let meals = try generator.parsePlanFromAIResponse("""
        {
          "meals": [
            {
              "mealType": "Breakfast",
              "mealName": "Greek Yogurt Bowl",
              "calories": 410,
              "protein": 35,
              "carbs": 45,
              "fats": 9,
              "ingredients": ["1 tub Greek yogurt"],
              "instructions": ["Mix and serve"]
            },
            {
              "mealType": "Snack",
              "mealName": "Protein Shake",
              "calories": 180,
              "protein": 28,
              "carbs": 8,
              "fats": 3,
              "ingredients": ["1 scoop protein"],
              "instructions": ["Shake with water"]
            }
          ]
        }
        """)

        XCTAssertEqual(meals.map(\.mealType), ["Breakfast", "Snack"])
        XCTAssertEqual(meals.map { $0.foodItem?.name }, ["Greek Yogurt Bowl", "Protein Shake"])
    }

    func testParseFullWeekPlanSortsOffsetsAndFiltersInvalidDays() throws {
        let generator = MealPlanAIGenerator()
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_767_225_600))

        let days = try generator.parseFullWeekPlanFromAIResponse("""
        {
          "days": [
            {
              "dayOffset": 2,
              "meals": [
                \(mealJSON(type: "Breakfast", name: "Day Two Breakfast")),
                \(mealJSON(type: "Lunch", name: "Day Two Lunch")),
                \(mealJSON(type: "Dinner", name: "Day Two Dinner"))
              ]
            },
            {
              "dayOffset": 8,
              "meals": [
                \(mealJSON(type: "Breakfast", name: "Invalid Offset Breakfast")),
                \(mealJSON(type: "Lunch", name: "Invalid Offset Lunch")),
                \(mealJSON(type: "Dinner", name: "Invalid Offset Dinner"))
              ]
            },
            {
              "dayOffset": 0,
              "meals": [
                \(mealJSON(type: "Breakfast", name: "Day Zero Breakfast")),
                \(mealJSON(type: "Lunch", name: "Day Zero Lunch")),
                \(mealJSON(type: "Dinner", name: "Day Zero Dinner"))
              ]
            },
            {
              "dayOffset": 1,
              "meals": [
                \(mealJSON(type: "Breakfast", name: "Too Few Breakfast")),
                \(mealJSON(type: "Lunch", name: "Too Few Lunch"))
              ]
            }
          ]
        }
        """, startDate: startDate)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.map(\.id), [
            dateString(for: startDate),
            dateString(for: calendar.date(byAdding: .day, value: 2, to: startDate)!)
        ])
        XCTAssertEqual(days[0].meals.first?.foodItem?.name, "Day Zero Breakfast")
        XCTAssertEqual(days[1].meals.first?.foodItem?.name, "Day Two Breakfast")
    }

    func testInvalidMealPlanJSONThrows() {
        let generator = MealPlanAIGenerator()

        XCTAssertThrowsError(try generator.parseSingleMealFromAIResponse("{ not json }"))
    }

    func testGenerateLocalFullWeekPlanUsesPreferencesAndMacroTargets() {
        let goals = GoalSettings()
        goals.calories = 2_400
        goals.protein = 180
        goals.carbs = 240
        goals.fats = 80

        let generator = MealPlanAIGenerator()
        let days = generator.generateLocalFullWeekPlan(
            goals: goals,
            preferredFoods: ["Salmon", "Quinoa"],
            preferredCuisines: ["Mediterranean"],
            preferredSnacks: ["Skyr"]
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { $0.meals.count == 4 })
        XCTAssertEqual(Set(days.map(\.id)).count, 7)

        let firstDay = days[0]
        XCTAssertEqual(firstDay.meals.map(\.mealType), ["Breakfast", "Lunch", "Dinner", "Snack"])
        XCTAssertEqual(firstDay.meals[0].foodItem?.name, "Skyr Protein Bowl")
        XCTAssertEqual(firstDay.meals[1].foodItem?.name, "Salmon Quinoa Bowl")
        XCTAssertEqual(firstDay.meals[2].foodItem?.name, "Salmon and Salmon Plate")
        XCTAssertEqual(firstDay.meals[3].foodItem?.name, "Skyr Snack")

        let calories = firstDay.meals.compactMap(\.foodItem?.calories).reduce(0, +)
        let protein = firstDay.meals.compactMap(\.foodItem?.protein).reduce(0, +)
        let carbs = firstDay.meals.compactMap(\.foodItem?.carbs).reduce(0, +)
        let fats = firstDay.meals.compactMap(\.foodItem?.fats).reduce(0, +)

        XCTAssertEqual(calories, 2_400, accuracy: 0.001)
        XCTAssertEqual(protein, 180, accuracy: 0.001)
        XCTAssertEqual(carbs, 240, accuracy: 0.001)
        XCTAssertEqual(fats, 80, accuracy: 0.001)
        XCTAssertEqual(firstDay.meals[1].ingredients, ["Salmon", "Quinoa", "Salmon", "Mediterranean seasoning"])
    }

    private func mealJSON(type: String, name: String) -> String {
        """
        {
          "mealType": "\(type)",
          "mealName": "\(name)",
          "calories": 400,
          "protein": 30,
          "carbs": 40,
          "fats": 10,
          "ingredients": ["1 item"],
          "instructions": ["Prep", "Serve"]
        }
        """
    }

    private func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
