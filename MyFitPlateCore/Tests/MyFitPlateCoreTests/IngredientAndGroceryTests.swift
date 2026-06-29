import XCTest
@testable import MyFitPlateCore

final class IngredientLineParserTests: XCTestCase {
    func testParsesCommonQuantitiesAndUnits() {
        let oats = IngredientLineParser.normalizedIngredient(from: "1/2 cup oats")
        XCTAssertEqual(oats.quantity, 0.5, accuracy: 0.001)
        XCTAssertEqual(oats.unit, "cup")
        XCTAssertEqual(oats.name, "Oats")

        let chicken = IngredientLineParser.normalizedIngredient(from: "1 lbs chicken breast")
        XCTAssertEqual(chicken.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(chicken.unit, "lb")
        XCTAssertEqual(chicken.name, "Chicken Breast")

        let milk = IngredientLineParser.normalizedIngredient(from: "500 ml milk")
        XCTAssertEqual(milk.quantity, 500, accuracy: 0.001)
        XCTAssertEqual(milk.unit, "ml")
        XCTAssertEqual(milk.name, "Milk")
    }

    func testCleansBulletsParentheticalsAndUnicodeFractions() {
        let garlic = IngredientLineParser.normalizedIngredient(from: "- 2 cloves garlic (minced)")
        XCTAssertEqual(garlic.quantity, 2, accuracy: 0.001)
        XCTAssertEqual(garlic.unit, "clove")
        XCTAssertEqual(garlic.name, "Garlic")

        let chia = IngredientLineParser.normalizedIngredient(from: "½ cup chia seeds")
        XCTAssertEqual(chia.quantity, 0.5, accuracy: 0.001)
        XCTAssertEqual(chia.unit, "cup")
        XCTAssertEqual(chia.name, "Chia Seeds")
    }
}

final class IngredientMatchingAndCategoryTests: XCTestCase {
    func testNameMatcherIgnoresPrepWordsAndPluralization() {
        XCTAssertTrue(IngredientNameMatcher.matches("fresh chopped tomatoes", "tomato"))
        XCTAssertTrue(IngredientNameMatcher.matches("1 lb chicken breasts", "chicken breast"))
        XCTAssertTrue(IngredientNameMatcher.matches("diced red onions", "onion"))
    }

    func testCategoryMappingUsesSharedGroceryCategories() {
        XCTAssertEqual(IngredientCategoryMapper.groceryCategory(for: "salmon fillet"), "Meat & Seafood")
        XCTAssertEqual(IngredientCategoryMapper.groceryCategory(for: "Greek yogurt"), "Dairy & Eggs")
        XCTAssertEqual(IngredientCategoryMapper.groceryCategory(for: "brown rice"), "Carbohydrates")
        XCTAssertEqual(IngredientCategoryMapper.groceryCategory(for: "fresh garlic"), "Produce")
        XCTAssertEqual(IngredientCategoryMapper.groceryCategory(for: "olive oil"), "Pantry & Oils")
    }

    func testMealPrepCategoryCollapsesGroceryCategories() {
        XCTAssertEqual(IngredientCategoryMapper.mealPrepCategory(for: "eggs"), "Protein")
        XCTAssertEqual(IngredientCategoryMapper.mealPrepCategory(for: "Greek yogurt"), "Dairy")
        XCTAssertEqual(IngredientCategoryMapper.mealPrepCategory(for: "rice"), "Carbs")
    }
}

final class GroceryListBuilderTests: XCTestCase {
    func testBuildsMergedCategorizedGroceryList() {
        let day = makeDay(ingredients: [
            "1 cup rice",
            "2 cups cooked rice",
            "2 cloves garlic",
            "1 clove fresh garlic",
            "1 lb chicken breast",
            "1 cup Greek yogurt"
        ])

        let list = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .imperial)

        let rice = requireItem(named: "Rice", in: list)
        XCTAssertEqual(rice.quantity, 3, accuracy: 0.001)
        XCTAssertEqual(rice.unit, "cup")
        XCTAssertEqual(rice.category, "Carbohydrates")
        XCTAssertEqual(rice.source, "mealPlan")

        let garlic = requireItem(named: "Garlic", in: list)
        XCTAssertEqual(garlic.quantity, 3, accuracy: 0.001)
        XCTAssertEqual(garlic.unit, "clove")
        XCTAssertEqual(garlic.category, "Produce")

        let chicken = requireItem(named: "Chicken Breast", in: list)
        XCTAssertEqual(chicken.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(chicken.unit, "lb")
        XCTAssertEqual(chicken.category, "Meat & Seafood")

        let yogurt = requireItem(named: "Greek Yogurt", in: list)
        XCTAssertEqual(yogurt.category, "Dairy & Eggs")
    }

    func testMetricUnitConversion() {
        let day = makeDay(ingredients: [
            "16 oz almonds",
            "4 lbs chicken breast"
        ])

        let list = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric)

        let almonds = requireItem(named: "Almonds", in: list)
        XCTAssertEqual(almonds.quantity, 453.592, accuracy: 0.01)
        XCTAssertEqual(almonds.unit, "g")

        let chicken = requireItem(named: "Chicken Breast", in: list)
        XCTAssertEqual(chicken.quantity, 1.814, accuracy: 0.01)
        XCTAssertEqual(chicken.unit, "kg")
    }

    func testImperialUnitConversion() {
        let day = makeDay(ingredients: [
            "100 g spinach",
            "1000 ml milk"
        ])

        let list = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .imperial)

        let spinach = requireItem(named: "Spinach", in: list)
        XCTAssertEqual(spinach.quantity, 3.527, accuracy: 0.01)
        XCTAssertEqual(spinach.unit, "oz")

        let milk = requireItem(named: "Milk", in: list)
        XCTAssertEqual(milk.quantity, 33.814, accuracy: 0.01)
        XCTAssertEqual(milk.unit, "fl oz")
    }

    private func makeDay(ingredients: [String]) -> MealPlanDay {
        MealPlanDay(
            id: "plan1",
            date: Date(timeIntervalSince1970: 0),
            meals: [
                PlannedMeal(
                    id: UUID().uuidString,
                    mealType: "Dinner",
                    recipeID: nil,
                    foodItem: nil,
                    ingredients: ingredients,
                    instructions: nil
                )
            ]
        )
    }

    private func requireItem(named name: String, in list: [GroceryListItem], file: StaticString = #filePath, line: UInt = #line) -> GroceryListItem {
        guard let item = list.first(where: { $0.name == name }) else {
            XCTFail("Expected grocery item named \(name). Found: \(list.map(\.name))", file: file, line: line)
            return GroceryListItem(name: name, quantity: 0, unit: "", category: "", source: nil)
        }
        return item
    }
}

final class SmartSuggestionBuilderTests: XCTestCase {
    func testKeepsFirstUniqueRecentFoodsCaseInsensitively() {
        let items = [
            makeFood(id: "1", name: "Greek Yogurt"),
            makeFood(id: "2", name: "greek yogurt"),
            makeFood(id: "3", name: "Blueberries"),
            makeFood(id: "4", name: "Eggs")
        ]

        let suggestions = SmartSuggestionBuilder.uniqueRecentFoods(from: items, limit: 2)

        XCTAssertEqual(suggestions.map(\.name), ["Greek Yogurt", "Blueberries"])
    }

    private func makeFood(id: String, name: String) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            calories: 100,
            protein: 10,
            carbs: 5,
            fats: 3,
            servingSize: "1 serving",
            servingWeight: 100
        )
    }
}
